#!/usr/bin/env bash

set -euo pipefail

AGENT_HOME=/home/agent-admin/agent-app
AGENT_LOG_DIR=/var/log/agent-app

groupadd agent-common
groupadd agent-core

useradd -m -s /bin/bash agent-admin
useradd -m -s /bin/bash agent-dev
useradd -m -s /bin/bash agent-test

usermod -aG agent-common,agent-core agent-admin
usermod -aG agent-common,agent-core agent-dev
usermod -aG agent-common agent-test

printf 'agent-admin:agentpass\nagent-dev:agentpass\nagent-test:agentpass\n' | chpasswd

install -d -o agent-admin -g agent-core -m 0750 "$AGENT_HOME"
install -d -o agent-admin -g agent-core -m 0750 "$AGENT_HOME/bin"
install -d -o agent-admin -g agent-common -m 2770 "$AGENT_HOME/upload_files"
install -d -o agent-admin -g agent-core -m 2770 "$AGENT_HOME/api_keys"
install -d -o agent-admin -g agent-core -m 2770 "$AGENT_LOG_DIR"

install -o agent-admin -g agent-core -m 0750 /tmp/agent-build/agent-app "$AGENT_HOME/agent-app"
install -o agent-dev -g agent-core -m 0750 /tmp/agent-build/monitor.sh "$AGENT_HOME/bin/monitor.sh"

printf 'agent_api_key_test\n' > "$AGENT_HOME/api_keys/t_secret.key"
chown agent-admin:agent-core "$AGENT_HOME/api_keys/t_secret.key"
chmod 0660 "$AGENT_HOME/api_keys/t_secret.key"

printf 'agent-admin ALL=(root) NOPASSWD: /usr/sbin/ufw status\n' > /etc/sudoers.d/agent-admin-ufw-status
chmod 0440 /etc/sudoers.d/agent-admin-ufw-status

setfacl -m g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -m d:g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -m g:agent-core:rwx "$AGENT_HOME/api_keys"
setfacl -m d:g:agent-core:rwx "$AGENT_HOME/api_keys"
setfacl -m g:agent-core:rwx "$AGENT_LOG_DIR"
setfacl -m d:g:agent-core:rwx "$AGENT_LOG_DIR"

cat > /etc/profile.d/agent-app.sh <<'EOF'
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key
export AGENT_LOG_DIR=/var/log/agent-app
EOF

for user_name in agent-admin agent-dev agent-test; do
  printf '\nsource /etc/profile.d/agent-app.sh\n' >> "/home/$user_name/.bashrc"
  chown "$user_name:$user_name" "/home/$user_name/.bashrc"
done

mkdir -p /run/sshd

sed -i 's/^#\?Port .*/Port 20022/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config

grep -q '^Port 20022' /etc/ssh/sshd_config || printf '\nPort 20022\n' >> /etc/ssh/sshd_config
grep -q '^PermitRootLogin no' /etc/ssh/sshd_config || printf '\nPermitRootLogin no\n' >> /etc/ssh/sshd_config
grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config || printf '\nPasswordAuthentication yes\n' >> /etc/ssh/sshd_config

printf '* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/monitor.cron.out 2>&1\n' \
  | crontab -u agent-admin -
