#!/bin/bash
set -euo pipefail

# Stage 1: Load nftables ruleset into kernel
# nftables runs entirely in kernel space — this is not a background process
nft -f /etc/nftables.conf
echo "[fw] nftables rules loaded"

# Stage 2: Configure rsyslog to forward all syslog to the central collector (SIEM segment)
# nftables FW-DMZ-FWD log lines flow through the kernel ring buffer -> rsyslog via imklog
echo '*.* @10.50.50.8:514' >> /etc/rsyslog.conf
rsyslogd
echo "[fw] rsyslog started, forwarding to 10.50.50.8:514"

# Stage 3: Start Saffron agent
# Allows scenario phases to run nft commands remotely via the Saffron REST API
saffron-agent \
  -server "${COMMANDLY_SERVER:-10.0.0.1:8080}" \
  -client-id "$(hostname)" &
echo "[fw] saffron-agent started"

# Stage 4: Keep-alive
# nftables has no foreground process to exec into; sleep infinity holds the container
exec sleep infinity
