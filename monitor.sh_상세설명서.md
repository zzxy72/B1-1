# monitor.sh 상세설명서

이 문서는 쉘 스크립트를 처음 보는 사람도 `monitor.sh`가 무엇을 확인하고, 어떤 순서로 동작하는지 이해할 수 있도록 작성한 설명서이다.

`monitor.sh`는 컨테이너 안에서 실행 중인 `agent-app`을 점검하는 관제 스크립트이다. 사람이 매번 직접 확인해야 하는 항목을 한 번에 확인하고, 결과를 로그 파일에 남긴다.

## 1. 한 줄 요약

```text
agent-app이 실행 중인지, 15034 포트가 열려 있는지, 방화벽과 서버 자원 상태가 괜찮은지 확인한 뒤 monitor.log에 기록한다.
```

## 2. 실행 위치

이 스크립트는 호스트 PC가 아니라 Docker 컨테이너 내부에서 실행한다.

컨테이너에 들어간 뒤 실행한다.

```bash
docker compose exec agent-lab bash
sudo -u agent-admin bash -lc 'source ~/.bashrc && "$AGENT_HOME/bin/monitor.sh"'
```

명령을 풀어서 보면 다음과 같다.

```text
sudo -u agent-admin
agent-admin 사용자 권한으로 실행한다.

bash -lc
bash 쉘을 새로 열고 명령을 실행한다.

source ~/.bashrc
AGENT_HOME, AGENT_PORT 같은 환경 변수를 불러온다.

"$AGENT_HOME/bin/monitor.sh"
monitor.sh 파일을 실행한다.
```

## 3. 스크립트가 성공하면 보이는 결과

정상 실행 예시는 다음과 비슷하다.

```text
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app'... [OK] (PID: 1234)
Checking port 15034... [OK]
Checking UFW firewall status... [OK]

[RESOURCE MONITORING]
CPU Usage : 3.2%
MEM Usage : 8.1%
DISK Used : 12%

[INFO] Log appended: /var/log/agent-app/monitor.log
```

중요한 부분은 `[OK]`와 `[INFO] Log appended`이다.

- `[OK]`: 해당 항목이 정상이라는 뜻이다.
- `[WARNING]`: 당장 실패는 아니지만 주의가 필요하다는 뜻이다.
- `[ERROR]`: 필수 항목이 실패했으므로 스크립트를 멈춘다는 뜻이다.
- `Log appended`: 로그 파일에 결과를 추가했다는 뜻이다.

## 4. 전체 동작 순서

`monitor.sh`는 크게 여섯 단계를 수행한다.

1. 로그 디렉토리가 있는지 확인한다.
2. 로그 파일이 너무 크면 오래된 로그를 밀어내고 새 로그를 준비한다.
3. `agent-app` 프로세스가 실행 중인지 확인한다.
4. `15034` 포트가 접속 대기 상태인지 확인한다.
5. 방화벽과 CPU, 메모리, 디스크 상태를 확인한다.
6. 확인 결과를 `/var/log/agent-app/monitor.log`에 한 줄로 기록한다.

프로세스와 포트는 필수 항목이다. 둘 중 하나라도 실패하면 `[ERROR]`를 출력하고 종료한다.

방화벽과 자원 사용률은 경고 항목이다. 문제가 있어도 로그 기록까지 계속 진행한다.

## 5. 맨 위 설정값 설명

스크립트 위쪽에는 기본 설정값이 모여 있다.

```bash
APP_PROCESS_NAME="${APP_PROCESS_NAME:-agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${LOG_FILE:-${AGENT_LOG_DIR}/monitor.log}"
```

`:-`는 “앞의 값이 없으면 뒤의 기본값을 사용한다”는 뜻이다.

예를 들어 `AGENT_PORT`가 이미 `15034`로 설정되어 있으면 그 값을 사용한다. 설정되어 있지 않으면 기본값 `15034`를 사용한다.

주요 설정값은 다음과 같다.

```text
APP_PROCESS_NAME
찾아야 할 앱 이름이다. 기본값은 agent-app이다.

AGENT_PORT
앱이 열어야 하는 TCP 포트이다. 기본값은 15034이다.

AGENT_LOG_DIR
로그 디렉토리이다. 기본값은 /var/log/agent-app이다.

LOG_FILE
실제 로그 파일이다. 기본값은 /var/log/agent-app/monitor.log이다.

MAX_LOG_SIZE_BYTES
로그 파일 최대 크기이다. 기본값은 10485760바이트, 즉 10MB이다.

MAX_LOG_BACKUPS
보관할 과거 로그 개수이다. 기본값은 10개이다.
```

임계값 설정도 있다.

```bash
CPU_THRESHOLD="${CPU_THRESHOLD:-20}"
MEM_THRESHOLD="${MEM_THRESHOLD:-10}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
```

뜻은 다음과 같다.

```text
CPU 사용률이 20%를 넘으면 WARNING
메모리 사용률이 10%를 넘으면 WARNING
디스크 사용률이 80%를 넘으면 WARNING
```

이 값들은 실행할 때 바꿀 수도 있다.

```bash
CPU_THRESHOLD=50 MEM_THRESHOLD=70 "$AGENT_HOME/bin/monitor.sh"
```

## 6. 출력 함수 설명

스크립트에는 결과를 보기 좋게 출력하는 함수가 있다.

```bash
print_ok() {
  printf '%s\n' "$1 [OK]${2:+ $2}"
}
```

이 함수는 정상 메시지를 출력한다.

예를 들어 다음처럼 호출하면:

```bash
print_ok "Checking port 15034..."
```

화면에는 이렇게 보인다.

```text
Checking port 15034... [OK]
```

경고와 오류는 다음 함수가 담당한다.

```bash
print_warning() {
  printf '[WARNING] %s\n' "$1"
}

print_error() {
  printf '[ERROR] %s\n' "$1" >&2
}
```

`>&2`는 오류 메시지를 일반 출력이 아니라 오류 출력으로 보낸다는 뜻이다. 초보자는 “오류 전용 통로로 보낸다” 정도로 이해하면 된다.

## 7. 로그 디렉토리 확인

```bash
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
```

이 함수는 로그를 쓸 수 있는 상태인지 먼저 확인한다.

- `-d`: 디렉토리인지 확인한다.
- `-w`: 쓰기 권한이 있는지 확인한다.
- `!`: 아니다라는 뜻이다.
- `exit 1`: 실패로 종료한다는 뜻이다.

로그 디렉토리가 없거나 쓸 수 없으면 이후 점검 결과를 기록할 수 없으므로 바로 멈춘다.

## 8. 로그 순환 보관

```bash
rotate_log_if_needed
```

이 단계는 `monitor.log`가 너무 커졌을 때 오래된 로그를 번호 붙은 파일로 보관한다.

예를 들어 현재 로그가 10MB를 넘으면 다음처럼 바뀐다.

```text
monitor.log      -> monitor.log.1
monitor.log.1    -> monitor.log.2
monitor.log.2    -> monitor.log.3
```

최대 10개까지만 보관한다. `monitor.log.11`이 생기면 삭제한다.

이렇게 하는 이유는 로그 파일이 계속 커져서 디스크를 가득 채우는 일을 막기 위해서이다.

## 9. agent-app 프로세스 확인

```bash
find_app_pid() {
  pgrep -f "$APP_PROCESS_PATTERN" | head -n 1
}
```

`pgrep`은 실행 중인 프로세스 목록에서 특정 이름을 찾는 명령이다.

```text
pgrep -f
프로세스 이름뿐 아니라 실행 명령 전체에서 찾는다.

head -n 1
여러 개가 찾아지면 첫 번째 하나만 사용한다.
```

프로세스를 찾지 못하면 `check_process` 함수가 오류를 내고 종료한다.

```text
[ERROR] Process 'agent-app' is not running.
```

이 오류가 나오면 먼저 `agent-app`을 실행해야 한다.

```bash
sudo -u agent-admin bash -lc 'source ~/.bashrc && cd "$AGENT_HOME" && ./agent-app'
```

## 10. 15034 포트 확인

```bash
check_port() {
  if ss -ltn "( sport = :$AGENT_PORT )" 2>/dev/null | awk 'NR > 1 { found = 1 } END { exit !found }'; then
    print_ok "Checking port $AGENT_PORT..."
    return 0
  fi

  print_error "TCP port $AGENT_PORT is not in LISTEN state."
  exit 1
}
```

이 함수는 앱이 `15034` 포트에서 접속을 기다리는지 확인한다.

명령의 의미는 다음과 같다.

```text
ss
네트워크 포트 상태를 보는 명령이다.

-l
LISTEN 상태, 즉 접속 대기 중인 포트만 본다.

-t
TCP 포트만 본다.

-n
포트 번호를 이름으로 바꾸지 않고 숫자로 보여준다.

sport = :15034
로컬 포트가 15034인 항목을 찾는다.
```

포트가 열려 있지 않으면 다음 오류가 나온다.

```text
[ERROR] TCP port 15034 is not in LISTEN state.
```

이 경우 `agent-app`이 실행 중이어도 포트를 열지 못한 상태일 수 있다.

## 11. 방화벽 확인

```bash
check_firewall
```

이 함수는 컨테이너 안에 방화벽 도구가 있는지 확인한다.

먼저 `ufw`가 있으면 `ufw status`로 상태를 확인한다. `ufw`가 없고 `firewall-cmd`가 있으면 firewalld 상태를 확인한다.

둘 다 없으면 다음 경고를 출력한다.

```text
[WARNING] Neither ufw nor firewalld was found.
```

방화벽은 중요하지만, 이 스크립트에서는 방화벽 상태 때문에 바로 종료하지 않는다. 앱 프로세스와 포트 확인이 더 직접적인 생존 확인이기 때문이다.

## 12. CPU 사용률 계산

```bash
collect_cpu_usage
```

이 함수는 `/proc/stat` 파일을 두 번 읽는다. 두 번 읽는 사이에 `sleep 1`로 1초 기다린다.

```text
첫 번째 CPU 상태 읽기
1초 대기
두 번째 CPU 상태 읽기
두 값의 차이로 1초 동안 CPU가 얼마나 바빴는지 계산
```

`/proc/stat`은 Linux가 제공하는 시스템 상태 파일이다. 사람이 직접 수정하는 파일이 아니라, 커널이 현재 상태를 보여주는 파일이다.

계산 결과는 소수점 한 자리로 출력된다.

```text
3.2
15.7
```

화면에 출력할 때는 뒤에 `%`가 붙는다.

## 13. 메모리 사용률 계산

```bash
collect_mem_usage
```

이 함수는 `/proc/meminfo` 파일에서 메모리 정보를 읽는다.

사용하는 값은 두 가지이다.

```text
MemTotal
전체 메모리 크기

MemAvailable
지금 사용할 수 있는 메모리 크기
```

계산식은 다음과 같다.

```text
(전체 메모리 - 사용 가능한 메모리) / 전체 메모리 * 100
```

즉, 전체 중 몇 퍼센트를 사용 중인지 계산한다.

## 14. 디스크 사용률 확인

```bash
collect_disk_usage() {
  df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }'
}
```

`df`는 디스크 사용량을 보여주는 명령이다.

```text
df -P /
루트 파일시스템 / 의 디스크 사용량을 표준 형식으로 보여준다.

awk 'NR == 2 ...'
두 번째 줄, 즉 실제 디스크 정보 줄만 읽는다.

gsub(/%/, "", $5)
사용률 값에서 % 기호를 제거한다.
```

예를 들어 `12%`가 나오면 숫자 `12`만 가져온다.

## 15. 임계값 경고

```bash
warn_if_exceeded "CPU" "$cpu" "$CPU_THRESHOLD" "%"
warn_if_exceeded "MEM" "$mem" "$MEM_THRESHOLD" "%"
warn_if_exceeded "DISK_USED" "$disk" "$DISK_THRESHOLD" "%"
```

임계값은 “이 숫자를 넘으면 주의하라”는 기준이다.

예를 들어 CPU 기준이 `20%`인데 실제 CPU 사용률이 `25.3%`이면 다음처럼 출력된다.

```text
[WARNING] CPU threshold exceeded (25.3% > 20%)
```

경고는 실패가 아니다. 스크립트는 계속 진행해서 로그를 남긴다.

## 16. 로그 기록

```bash
append_log "$pid" "$cpu" "$mem" "$disk"
```

이 함수는 점검 결과를 로그 파일에 한 줄 추가한다.

로그 예시는 다음과 같다.

```text
[2026-05-12 16:30:00] PID:1234 CPU:3.2% MEM:8.1% DISK_USED:12%
```

각 항목의 의미는 다음과 같다.

```text
2026-05-12 16:30:00
점검한 시간이다.

PID:1234
agent-app 프로세스 번호이다.

CPU:3.2%
CPU 사용률이다.

MEM:8.1%
메모리 사용률이다.

DISK_USED:12%
루트 파일시스템의 디스크 사용률이다.
```

로그를 확인하려면 다음 명령을 사용한다.

```bash
tail -n 5 /var/log/agent-app/monitor.log
```

`tail -n 5`는 파일의 마지막 5줄만 보여준다.

## 17. main 함수

스크립트 마지막에는 `main` 함수가 있다.

```bash
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
```

`main`은 지금까지 만든 함수들을 순서대로 실행하는 지휘자 역할을 한다.

마지막 줄 `main "$@"` 때문에 스크립트를 실행하면 `main` 함수가 시작된다.

`"$@"`는 스크립트에 전달된 추가 입력값 전체를 의미한다. 현재 `monitor.sh`는 별도 입력값을 사용하지 않지만, Bash 스크립트에서 흔히 쓰는 안전한 실행 방식이다.

## 18. 실패 상황별 해결 방법

프로세스 오류:

```text
[ERROR] Process 'agent-app' is not running.
```

해결:

```bash
sudo -u agent-admin bash -lc 'source ~/.bashrc && cd "$AGENT_HOME" && ./agent-app'
```

포트 오류:

```text
[ERROR] TCP port 15034 is not in LISTEN state.
```

확인:

```bash
ss -ltnp | grep ':15034'
```

앱이 이미 다른 오류로 종료되었거나, 다른 프로세스가 포트를 사용 중일 수 있다.

로그 디렉토리 오류:

```text
[ERROR] Log directory does not exist: /var/log/agent-app
```

확인:

```bash
ls -ld /var/log/agent-app
```

쓰기 권한 오류:

```text
[ERROR] Log directory is not writable: /var/log/agent-app
```

확인:

```bash
id agent-admin
ls -ld /var/log/agent-app
getfacl /var/log/agent-app
```

방화벽 경고:

```text
[WARNING] UFW firewall is not active.
```

확인:

```bash
ufw status
```

## 19. cron으로 자동 실행될 때

`monitor.sh`는 사람이 직접 실행할 수도 있고, cron이 자동으로 실행할 수도 있다.

cron 등록 예시는 다음과 같다.

```text
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/monitor.cron.out 2>&1
```

뜻은 다음과 같다.

```text
* * * * *
매분 실행한다.

/home/agent-admin/agent-app/bin/monitor.sh
실행할 스크립트 경로이다.

>>
출력 내용을 파일 뒤에 추가한다.

2>&1
오류 출력도 일반 출력과 같은 파일에 저장한다.
```

cron이 실제로 동작하는지 확인하려면 1분 이상 기다린 뒤 로그 줄이 늘어나는지 보면 된다.

```bash
tail -n 5 /var/log/agent-app/monitor.log
sleep 70
tail -n 5 /var/log/agent-app/monitor.log
```

## 20. 이 스크립트를 이해하기 위한 Bash 기호 사전

```text
#!/usr/bin/env bash
이 파일을 bash로 실행하라는 의미이다.

set -u
정의되지 않은 변수를 사용하면 오류로 처리한다.

set -o pipefail
파이프 중간 명령이 실패해도 전체 실패로 알 수 있게 한다.

$
변수 값을 꺼낼 때 사용한다.

"$변수"
변수 값에 공백이 있어도 하나의 값으로 안전하게 다룬다.

if ... then ... fi
조건문이다. 조건이 맞으면 안쪽 명령을 실행한다.

[[ ... ]]
Bash에서 조건을 검사할 때 자주 쓰는 문법이다.

local
함수 안에서만 쓰는 변수를 만든다.

return 0
함수를 성공으로 끝낸다.

exit 1
스크립트 전체를 실패로 끝낸다.

|
앞 명령의 결과를 뒤 명령으로 넘긴다.

>>
파일 끝에 내용을 추가한다.

2>/dev/null
오류 메시지를 화면에 보이지 않게 버린다.
```

## 21. 최종 확인 체크리스트

`monitor.sh`를 제출 전에 확인할 때는 아래 순서로 보면 된다.

1. `agent-app`을 먼저 실행한다.
2. 다른 터미널에서 컨테이너에 접속한다.
3. `sudo -u agent-admin bash -lc 'source ~/.bashrc && "$AGENT_HOME/bin/monitor.sh"'`를 실행한다.
4. 화면에 프로세스와 포트 `[OK]`가 나오는지 확인한다.
5. CPU, 메모리, 디스크 사용률이 출력되는지 확인한다.
6. `/var/log/agent-app/monitor.log`에 새 줄이 추가되는지 확인한다.
7. cron으로 1분 뒤에도 로그가 늘어나는지 확인한다.

