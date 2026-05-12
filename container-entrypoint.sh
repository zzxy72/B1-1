#!/usr/bin/env bash

set -euo pipefail

mkdir -p /run/sshd

AGENT_HOME=/home/agent-admin/agent-app
AGENT_LOG_DIR=/var/log/agent-app

setfacl -m g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -m d:g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -m g:agent-core:rwx "$AGENT_HOME/api_keys"
setfacl -m d:g:agent-core:rwx "$AGENT_HOME/api_keys"
setfacl -m g:agent-core:rwx "$AGENT_LOG_DIR"
setfacl -m d:g:agent-core:rwx "$AGENT_LOG_DIR"

ufw default deny incoming >/dev/null || true
ufw default allow outgoing >/dev/null || true
ufw allow 20022/tcp >/dev/null || true
ufw allow 15034/tcp >/dev/null || true
ufw --force enable >/dev/null || true

service ssh start >/dev/null
service cron start >/dev/null

printf 'B1-1 container lab is ready.\n'
printf 'Enter with: docker compose exec agent-lab bash\n'

tail -f /dev/null
