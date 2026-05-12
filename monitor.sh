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

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

print_ok() {
  printf '%s\n' "$1 [OK]${2:+ $2}"
}

print_warning() {
  printf '[WARNING] %s\n' "$1"
}

print_error() {
  printf '[ERROR] %s\n' "$1" >&2
}

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

find_app_pid() {
  pgrep -f "$APP_PROCESS_PATTERN" | head -n 1
}

check_process() {
  local pid
  pid="$(find_app_pid || true)"

  if [[ -z "$pid" ]]; then
    print_error "Process '$APP_PROCESS_NAME' is not running."
    exit 1
  fi

  print_ok "Checking process '$APP_PROCESS_NAME'..." "(PID: $pid)"
}

check_port() {
  if ss -ltn "( sport = :$AGENT_PORT )" 2>/dev/null | awk 'NR > 1 { found = 1 } END { exit !found }'; then
    print_ok "Checking port $AGENT_PORT..."
    return 0
  fi

  print_error "TCP port $AGENT_PORT is not in LISTEN state."
  exit 1
}

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

collect_disk_usage() {
  df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }'
}

warn_if_exceeded() {
  local label="$1"
  local value="$2"
  local threshold="$3"
  local unit="$4"

  if awk -v value="$value" -v threshold="$threshold" 'BEGIN { exit !(value > threshold) }'; then
    print_warning "$label threshold exceeded (${value}${unit} > ${threshold}${unit})"
  fi
}

append_log() {
  local pid="$1"
  local cpu="$2"
  local mem="$3"
  local disk="$4"

  printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%\n' \
    "$(timestamp)" "$pid" "$cpu" "$mem" "$disk" >> "$LOG_FILE"
}

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
