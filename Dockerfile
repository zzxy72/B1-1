FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    acl \
    cron \
    iproute2 \
    openssh-server \
    procps \
    sudo \
    ufw \
  && rm -rf /var/lib/apt/lists/*

COPY agent-app /tmp/agent-build/agent-app
COPY monitor.sh /tmp/agent-build/monitor.sh
COPY container-init.sh /usr/local/bin/container-init.sh
COPY container-entrypoint.sh /usr/local/bin/container-entrypoint.sh

RUN chmod 755 /usr/local/bin/container-init.sh /usr/local/bin/container-entrypoint.sh \
  && chmod 755 /tmp/agent-build/agent-app /tmp/agent-build/monitor.sh \
  && /usr/local/bin/container-init.sh \
  && rm -rf /tmp/agent-build

EXPOSE 20022 15034

ENTRYPOINT ["/usr/local/bin/container-entrypoint.sh"]
