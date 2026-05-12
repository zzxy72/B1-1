# B1-1 컨테이너 기반 시스템 관제 자동화 실습

이 저장소는 `요구사항/b1-1.md`를 기준으로, Linux 컨테이너 안에 Agent 서비스를 구축하고 관리하는 실습 파일입니다.

요구사항은 `Ubuntu 22.04 LTS 또는 동등 리눅스 환경`을 제시하지만, 제공된 `agent-app` 바이너리가 `GLIBC_2.38` 이상을 요구합니다. 그래서 앱 실행까지 검증 가능한 상위 LTS 환경인 `ubuntu:24.04` 컨테이너를 사용합니다.

호스트 PC의 SSH, 방화벽, 계정을 직접 변경하지 않습니다. 모든 실습은 Docker 컨테이너 `b1-1-agent-lab` 내부에서 진행합니다.

## 파일 구성

```text
.
├── Dockerfile
├── docker-compose.yml
├── container-init.sh
├── container-entrypoint.sh
├── agent-app
├── monitor.sh
├── README.md
├── 요구사항/
│   └── b1-1.md
├── 요구사항_수행내역서.md
├── 상세설명서.md
└── 컨테이너_활용_작업계획서.md
```

## 컨테이너 시작

```bash
docker compose up -d --build
docker compose ps
```

컨테이너 접속:

```bash
docker compose exec agent-lab bash
```

컨테이너 중지:

```bash
docker compose down
```

## 컨테이너 내부 실습 서버 정보

```text
OS: Ubuntu 24.04 LTS container
SSH Port: 20022
APP Port: 15034
AGENT_HOME: /home/agent-admin/agent-app
AGENT_LOG_DIR: /var/log/agent-app
```

생성 계정:

```text
agent-admin / agentpass
agent-dev   / agentpass
agent-test  / agentpass
```

호스트에서 SSH 접속을 시험하려면:

```bash
ssh -p 20022 agent-admin@localhost
```

## 앱 실행

첫 번째 터미널:

```bash
docker compose exec agent-lab bash
sudo -u agent-admin bash -lc 'source ~/.bashrc && cd "$AGENT_HOME" && ./agent-app'
```

정상 기준:

```text
[1/5] ... [OK]
[2/5] ... [OK]
[3/5] ... [OK]
[4/5] ... [OK]
[5/5] ... [OK]
Agent READY
```

## 모니터링 실행

두 번째 터미널:

```bash
docker compose exec agent-lab bash
sudo -u agent-admin bash -lc 'source ~/.bashrc && "$AGENT_HOME/bin/monitor.sh"'
tail -n 5 /var/log/agent-app/monitor.log
```

cron 확인:

```bash
crontab -u agent-admin -l
sleep 70
tail -n 5 /var/log/agent-app/monitor.log
```

## 문서

- `컨테이너_활용_작업계획서.md`: 컨테이너 기반으로 작업하는 전체 계획
- `요구사항_수행내역서.md`: 제출용 수행 내역과 증거 기록 위치
- `상세설명서.md`: 초보자용 개념 설명과 체크리스트별 확인 방법
