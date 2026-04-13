# dockerfiles/fw/ — Shared nftables Firewall Base Image

This directory contains the shared Dockerfile for both firewall containers (`fw-dmz` and `fw-core`). Both containers use the same image; behavior is entirely determined by the `nftables.conf` bind-mounted from `config/fw-dmz/` or `config/fw-core/` at runtime.

---

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Minimal Debian image with nftables + rsyslog |
| `entrypoint.sh` | Loads nftables rules; starts rsyslog forwarding; keeps container alive |

---

## Dockerfile

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    nftables \
    iproute2 \
    rsyslog \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Saffron agent (receives nft rule changes from scenario phases)
COPY saffron-agent-linux-amd64 /usr/local/bin/saffron-agent
RUN chmod +x /usr/local/bin/saffron-agent

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
```

The image is intentionally minimal. No SSH, no shell history retention, no development tools. The attack surface of the firewall containers themselves should be as small as possible — they are managed exclusively via Saffron.

---

## entrypoint.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Load nftables ruleset from bind-mounted config
nft -f /etc/nftables.conf
echo "[fw] nftables rules loaded"

# 2. Forward kernel syslog (nftables log statements) to rsyslog → rsyslog container
# nftables log statements go to kernel ring buffer → rsyslog picks them up via imklog
cat >> /etc/rsyslog.conf <<'EOF'
# Forward all to central rsyslog
*.* @10.50.50.8:514
EOF
rsyslogd

# 3. Start Saffron agent (allows scenario phases to run `nft` commands remotely)
saffron-agent \
    --server "${COMMANDLY_SERVER:-http://10.0.0.1:8080}" \
    --hostname "$(hostname)" \
    &

# 4. Keep container alive (nftables runs in kernel, not as a process)
exec sleep infinity
```

### Why Saffron on Firewalls?

Scenario phases need to dynamically modify firewall rules — specifically, the SNAT chain on fw-dmz and potentially logging rules on fw-core. Rather than exec'ing into the container directly, phases use `cr_runcmd.bash fw-dmz "nft ..."` which goes through the Saffron REST API. This keeps the scenario scripting interface consistent across all machines (Linux containers, Windows VMs, and firewalls all respond to the same `cr_runcmd.bash` interface).

---

## Runtime Behavior

### nftables Rule Reloading

If a scenario phase needs to reload the full ruleset (e.g., after a `make reset`):

```bash
cr_runcmd.bash fw-dmz "nft flush ruleset && nft -f /etc/nftables.conf"
```

The `nftables.conf` is bind-mounted, so the container always has the latest version from the host.

### Verifying Rules

```bash
cr_runcmd.bash fw-dmz "nft list ruleset"
cr_runcmd.bash fw-dmz "nft list chain ip nat SCENARIO_SNAT"
```

### Log Volume

Both firewall containers log all forwarded traffic. Under load (e.g., a port scan scenario), this can generate thousands of log lines per second. rsyslog rate limiting (configured in the rsyslog container) prevents this from overwhelming the SIEM. The firewall container's local rsyslog also applies rate limiting before forwarding.
