FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      nftables \
      iproute2 \
      rsyslog \
      netcat-openbsd \
      procps \
    && rm -rf /var/lib/apt/lists/*

COPY client /usr/bin/saffron-agent
RUN chmod +x /usr/bin/saffron-agent

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
