# dockerfiles/ — Custom Docker Images

This directory contains Dockerfiles for all custom-built container images. Each subdirectory is a Docker build context.

---

## Images

| Directory | Base Image | Container(s) | Purpose |
|-----------|-----------|--------------|---------|
| `scenario/` | `kalilinux/kali-rolling` | scenario | Attacker platform, Saffron server, fake internet |
| `fw/` | `debian:bookworm-slim` | fw-dmz, fw-core | Shared nftables firewall base |
| `web-lin/` | `ubuntu:22.04` | web-lin | Apache + PHP web server + Wazuh agent |
| `wks-linux/` | `ubuntu:24.04` | wks-linux | Linux workstation + user accounts + Wazuh agent |
| `db01/` | `ubuntu:22.04` + MSSQL | db01 | MSSQL 2022 + domain-joined Ubuntu |

---

## Common Patterns Across All Linux Images

### Saffron Agent Installation

Every Linux image installs the Saffron agent binary and starts it as a background process in the container entrypoint. The binary is copied from `misc/saffron/bin/saffron-agent-linux-amd64` during the build:

```dockerfile
COPY --from=build /opt/saffron/saffron-agent /usr/local/bin/saffron-agent
RUN chmod +x /usr/local/bin/saffron-agent
```

The entrypoint starts Saffron before the primary service:
```bash
saffron-agent --server "${COMMANDLY_SERVER}" --hostname "$(hostname)" &
```

### Wazuh Agent Installation

Every Linux image installs the Wazuh agent at build time and registers it at container start:

```dockerfile
RUN curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add - && \
    echo "deb https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list && \
    apt-get update && \
    apt-get install -y wazuh-agent=${WAZUH_VERSION}-1
```

Registration at container start (in entrypoint):
```bash
/var/ossec/bin/agent-auth \
    -m "${WAZUH_MANAGER}" \
    -P "${WAZUH_ENROLLMENT_PSK}" \
    -A "$(hostname)"
/var/ossec/bin/wazuh-control start
```

### Syslog Forwarding

Linux images forward syslog to rsyslog (`10.50.50.8`) via `rsyslog` or the kernel logger:

```
*.* @10.50.50.8:514
```

---

## Build Order

Images have no inter-image dependencies (no multi-stage builds sharing layers across images). All images can be built in parallel: `docker compose build --parallel`.

See individual README files for detailed build specifications.
