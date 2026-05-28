#!/usr/bin/env bash

set -u
set -o pipefail

APP_PROCESS_NAME="${APP_PROCESS_NAME:-agent-app}"
APP_PROCESS_PATTERN="${APP_PROCESS_PATTERN:-(^|/|[[:space:]])${APP_PROCESS_NAME}($|[[:space:]])}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${LOG_FILE:-${AGENT_LOG_DIR}/monitor.log}"
MAX_LOG_SIZE_BYTES="${MAX_LOG_SIZE_BYTES:-10485760}"
MAX_LOG_BACKUPS="${MAX_LOG_BACKUPS:-10}"

CPU_THRESHOLD="${CPU_THRESHOLD:-20}"
MEM_THRESHOLD="${MEM_THRESHOLD:-10}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"

# 현재 시각을 로그 형식에 맞는 문자열로 만든다.
timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

# 점검 성공 메시지를 [OK] 형식으로 출력한다.
print_ok() {
  printf '%s\n' "$1 [OK]${2:+ $2}"
}

# 경고 상황을 [WARNING] 형식으로 출력한다.
print_warning() {
  printf '[WARNING] %s\n' "$1"
}

# 치명적인 오류를 [ERROR] 형식으로 표준 오류에 출력한다.
print_error() {
  printf '[ERROR] %s\n' "$1" >&2
}

# 로그 디렉토리가 존재하고 현재 사용자에게 쓰기 권한이 있는지 확인한다.
ensure_log_dir() {
  if [[ ! -d "$AGENT_LOG_DIR" ]]; then
    print_error "Log directory does not exist: $AGENT_LOG_DIR"
    exit 1
  fi

  if [[ ! -w "$AGENT_LOG_DIR" ]]; then
    print_error "Log directory is not writable: $AGENT_LOG_DIR"
    exit 1
  fi
}

# monitor.log가 최대 크기를 넘으면 백업 파일로 회전시켜 로그가 무한히 커지지 않게 한다.
rotate_log_if_needed() {
  [[ -f "$LOG_FILE" ]] || return 0

  local size
  size="$(stat -c '%s' "$LOG_FILE" 2>/dev/null || echo 0)"
  [[ "$size" =~ ^[0-9]+$ ]] || size=0

  if (( size < MAX_LOG_SIZE_BYTES )); then
    return 0
  fi

  local i
  for (( i = MAX_LOG_BACKUPS - 1; i >= 1; i-- )); do
    if [[ -f "${LOG_FILE}.${i}" ]]; then
      mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
    fi
  done

  mv "$LOG_FILE" "${LOG_FILE}.1"
  : > "$LOG_FILE"

  if [[ -f "${LOG_FILE}.$((MAX_LOG_BACKUPS + 1))" ]]; then
    rm -f "${LOG_FILE}.$((MAX_LOG_BACKUPS + 1))"
  fi
}

# 실행 중인 agent-app 프로세스의 PID를 찾는다.
find_app_pid() {
  pgrep -f "$APP_PROCESS_PATTERN" | head -n 1
}

# agent-app 프로세스가 실행 중인지 확인하고, 없으면 모니터링을 실패로 종료한다.
check_process() {
  local pid
  pid="$(find_app_pid || true)"

  if [[ -z "$pid" ]]; then
    print_error "Process '$APP_PROCESS_NAME' is not running."
    exit 1
  fi

  print_ok "Checking process '$APP_PROCESS_NAME'..." "(PID: $pid)"
}

# 지정된 AGENT_PORT가 LISTEN 상태인지 확인하고, 아니면 실패로 종료한다.
check_port() {
  if ss -ltn "( sport = :$AGENT_PORT )" 2>/dev/null | awk 'NR > 1 { found = 1 } END { exit !found }'; then
    print_ok "Checking port $AGENT_PORT..."
    return 0
  fi

  print_error "TCP port $AGENT_PORT is not in LISTEN state."
  exit 1
}

# UFW 또는 firewalld 방화벽이 활성 상태인지 확인하고, 비활성 상태는 경고만 출력한다.
check_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    local ufw_status
    if [[ "$(id -u)" -eq 0 ]]; then
      ufw_status="$(ufw status 2>/dev/null || true)"
    elif command -v sudo >/dev/null 2>&1; then
      ufw_status="$(sudo -n ufw status 2>/dev/null || true)"
    else
      ufw_status=""
    fi

    if printf '%s\n' "$ufw_status" | grep -qi '^Status: active'; then
      print_ok "Checking UFW firewall status..."
    else
      print_warning "UFW firewall is not active."
    fi
    return 0
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --state 2>/dev/null | grep -q '^running$'; then
      print_ok "Checking firewalld status..."
    else
      print_warning "firewalld is not running."
    fi
    return 0
  fi

  print_warning "Neither ufw nor firewalld was found."
}

# /proc/stat 값을 1초 간격으로 비교해 전체 CPU 사용률을 계산한다.
collect_cpu_usage() {
  local first second idle1 total1 idle2 total2 diff_idle diff_total

  first="$(awk '/^cpu / { print $2, $3, $4, $5, $6, $7, $8, $9, $10, $11 }' /proc/stat)"
  sleep 1
  second="$(awk '/^cpu / { print $2, $3, $4, $5, $6, $7, $8, $9, $10, $11 }' /proc/stat)"

  read -r -a cpu1 <<< "$first"
  read -r -a cpu2 <<< "$second"

  idle1=$((cpu1[3] + cpu1[4]))
  idle2=$((cpu2[3] + cpu2[4]))
  total1=0
  total2=0

  local value
  for value in "${cpu1[@]}"; do
    total1=$((total1 + value))
  done
  for value in "${cpu2[@]}"; do
    total2=$((total2 + value))
  done

  diff_idle=$((idle2 - idle1))
  diff_total=$((total2 - total1))

  if (( diff_total <= 0 )); then
    printf '0.0'
  else
    awk -v idle="$diff_idle" -v total="$diff_total" 'BEGIN { printf "%.1f", (100 * (total - idle) / total) }'
  fi
}

# /proc/meminfo의 전체 메모리와 사용 가능한 메모리를 이용해 메모리 사용률을 계산한다.
collect_mem_usage() {
  awk '
    /^MemTotal:/ { total = $2 }
    /^MemAvailable:/ { available = $2 }
    END {
      if (total > 0) {
        printf "%.1f", ((total - available) / total) * 100
      } else {
        printf "0.0"
      }
    }
  ' /proc/meminfo
}

# 루트 파티션(/)의 디스크 사용률을 퍼센트 숫자로 수집한다.
collect_disk_usage() {
  df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }'
}

# 수집한 자원 사용률이 임계값을 넘으면 경고 메시지를 출력한다.
warn_if_exceeded() {
  local label="$1"
  local value="$2"
  local threshold="$3"
  local unit="$4"

  if awk -v value="$value" -v threshold="$threshold" 'BEGIN { exit !(value > threshold) }'; then
    print_warning "$label threshold exceeded (${value}${unit} > ${threshold}${unit})"
  fi
}

# 현재 점검 결과를 monitor.log에 한 줄로 누적 기록한다.
append_log() {
  local pid="$1"
  local cpu="$2"
  local mem="$3"
  local disk="$4"

  printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%\n' \
    "$(timestamp)" "$pid" "$cpu" "$mem" "$disk" >> "$LOG_FILE"
}

# 전체 모니터링 흐름을 순서대로 실행한다.
main() {
  local pid cpu mem disk

  ensure_log_dir
  rotate_log_if_needed

  printf '====== SYSTEM MONITOR RESULT ======\n\n'
  printf '[HEALTH CHECK]\n'

  pid="$(find_app_pid || true)"
  check_process
  check_port
  check_firewall

  printf '\n[RESOURCE MONITORING]\n'
  cpu="$(collect_cpu_usage)"
  mem="$(collect_mem_usage)"
  disk="$(collect_disk_usage)"

  printf 'CPU Usage : %s%%\n' "$cpu"
  printf 'MEM Usage : %s%%\n' "$mem"
  printf 'DISK Used : %s%%\n\n' "$disk"

  warn_if_exceeded "CPU" "$cpu" "$CPU_THRESHOLD" "%"
  warn_if_exceeded "MEM" "$mem" "$MEM_THRESHOLD" "%"
  warn_if_exceeded "DISK_USED" "$disk" "$DISK_THRESHOLD" "%"

  append_log "$pid" "$cpu" "$mem" "$disk"
  printf '\n[INFO] Log appended: %s\n' "$LOG_FILE"
}

main "$@"
