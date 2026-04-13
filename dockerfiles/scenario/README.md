# dockerfiles/scenario/ — Kali Attacker + Saffron Server + Fake Internet

The scenario container is the most complex image in the range. It serves four roles simultaneously:

1. **Attacker platform** — Kali Linux with a full red team toolset
2. **Saffron server** — REST API server that receives commands and dispatches to Saffron agents on target machines
3. **Fake internet** — Caddy HTTPS server + CoreDNS for simulated internet services (malware C2 callback endpoints, phishing pages, external IP hosting)
4. **Windows setup file server** — Python HTTP server on port 8000 serving `config/windows/<machine>/setup.ps1` and tooling binaries to Windows VMs during first boot

---

## Files in Build Context

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build |
| `entrypoint.sh` | Starts all services (Saffron, Caddy, CoreDNS, Python HTTPS, Postfix) |
| `Caddyfile` | HTTPS fake internet config with auto-cert (self-signed) |
| `Corefile` | CoreDNS zone configuration |
| `postfix-main.cf` | Postfix SMTP relay for phishing email injection |

---

## Dockerfile

```dockerfile
FROM kalilinux/kali-rolling AS base

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core tools
    nmap masscan netcat-openbsd curl wget python3 python3-pip \
    # AD / Windows attack
    impacket-scripts smbclient crackmapexec \
    evil-winrm bloodhound \
    # Web attack
    nikto sqlmap gobuster ffuf \
    # Password / cred tools
    hashcat john hydra \
    # Packet manipulation
    hping3 tcpdump wireshark-common \
    # C2 / post-exploitation
    metasploit-framework \
    # Email
    postfix swaks \
    # Utilities
    jq yq git vim tmux openssh-client qrencode \
    # Scenario runner dependencies
    python3-yaml \
    && rm -rf /var/lib/apt/lists/*

# Impacket (ensure latest version from pip, not Kali package)
RUN pip3 install --break-system-packages impacket

# Sliver C2 framework
RUN curl -s https://sliver.sh/install | bash

# Responder
RUN git clone --depth 1 https://github.com/lgandx/Responder.git /opt/Responder

# BloodHound CE collector
RUN curl -L https://github.com/SpecterOps/SharpHound/releases/latest/download/SharpHound.zip \
    -o /opt/SharpHound.zip && unzip /opt/SharpHound.zip -d /opt/SharpHound/

# Caddy (fake internet HTTPS)
RUN curl -s https://api.github.com/repos/caddyserver/caddy/releases/latest \
    | jq -r '.assets[] | select(.name | test("caddy_.*_linux_amd64.tar.gz")) | .browser_download_url' \
    | xargs curl -sL | tar xz -C /usr/local/bin caddy

# CoreDNS (range DNS)
RUN curl -s https://api.github.com/repos/coredns/coredns/releases/latest \
    | jq -r '.assets[] | select(.name == "coredns_.*_linux_amd64.tgz") | .browser_download_url' \
    | xargs curl -sL | tar xz -C /usr/local/bin coredns

# Saffron server binary
COPY --from=saffron-build /opt/saffron/server /usr/local/bin/saffron-server

# Range scripts
COPY entrypoint.sh /entrypoint.sh
COPY Caddyfile /etc/caddy/Caddyfile
COPY Corefile /etc/coredns/Corefile
COPY postfix-main.cf /etc/postfix/main.cf

RUN chmod +x /entrypoint.sh

WORKDIR /home/trainer
ENTRYPOINT ["/entrypoint.sh"]
```

---

## entrypoint.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Start Saffron server (OOB management REST API)
saffron-server \
    --bind 0.0.0.0:8080 \
    --data /opt/saffron/data \
    &

# 2. Start CoreDNS (range DNS — participants use 10.0.0.1 as DNS)
# Generate zone file from embedded IP table
cat > /etc/coredns/range.db <<EOF
\$ORIGIN secure.net.
\$TTL 300
@  IN SOA ns1.secure.net. admin.secure.net. 1 3600 900 604800 300
@  IN NS  ns1.secure.net.
ns1             IN A  10.0.0.1
dc01            IN A  10.20.20.100
exchange        IN A  10.20.20.10
fileserver      IN A  10.20.20.20
mail-relay      IN A  10.10.10.20
web-lin         IN A  10.10.10.10
web-win         IN A  10.10.10.12
wks-linux       IN A  10.30.30.10
wks-win11       IN A  10.30.30.20
db01            IN A  10.40.40.10
wazuh           IN A  10.0.0.7
EOF
coredns -conf /etc/coredns/Corefile &

# 3. Start Caddy (fake internet HTTPS)
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &

# 4. Start Python setup file server (Windows VM first-boot scripts)
python3 -m http.server 8000 --directory /srv/setup &

# 5. Start Postfix (SMTP relay for phishing scenarios)
postfix start

# 6. Keep container alive
exec tail -f /dev/null
```

---

## Caddyfile (Fake Internet)

```caddyfile
# Self-signed TLS for all fake internet domains
{
    local_certs
}

# Generic catch-all for any domain — serves a "real-looking" page
:443 {
    tls internal
    root * /srv/www
    file_server
    log {
        output stdout
        format json
    }
}

# Scenario-specific vhosts (injected by scenario phase scripts via `docker exec scenario caddy reload`)
# Example: C2 callback endpoint
#   c2.attackerco.com {
#       tls internal
#       reverse_proxy localhost:4444
#   }
```

---

## Corefile (CoreDNS)

```
# range.secure.net — internal range DNS
secure.net:53 {
    file /etc/coredns/range.db
    log
    errors
}

# Fake external domains
attacker.com:53 {
    template IN A {
        answer "{{ .Name }} 300 IN A 9.53.99.1"
    }
}

# Forward everything else to 8.8.8.8 (or block, depending on exercise)
.:53 {
    forward . 8.8.8.8
    log
    errors
}
```

---

## Postfix (postfix-main.cf)

```
myhostname = mail.attacker.com
mydomain = attacker.com
myorigin = $mydomain
inet_interfaces = all
relayhost =

# Route secure.net mail through the DMZ mail relay (mail-relay container).
# Traffic goes: scenario → 5.79.99.25:25 → fw-dmz DNAT → mail-relay:25 → Exchange.
# This creates realistic SMTP log artifacts on both fw-dmz and mail-relay.
transport_maps = hash:/etc/postfix/transport
# transport file: secure.net  smtp:[5.79.99.25]:25
```

Scenario phase scripts send phishing emails via `swaks`, targeting the mail relay's external IP
so the flow traverses fw-dmz's DNAT and mail-relay's Postfix — generating log artifacts at each hop:

```bash
swaks \
    --to bwilson@secure.net \
    --from "it-support@attacker.com" \
    --server 5.79.99.25 \
    --body "Please click here to reset your password: http://9.53.99.1/reset" \
    --header "Subject: Urgent: Password Reset Required"
```

> **Mail flow:** scenario (5.79.99.1) → fw-dmz DNAT (5.79.99.25:25 → 10.10.10.20:25) → mail-relay → Exchange (10.20.20.10:25)
> Each hop produces SMTP log entries. Defenders see inbound SMTP from an external IP in fw-dmz and mail-relay logs before Exchange receives it.

---

## IP Aliases for Attacker Diversity

Phase scripts add/remove IP aliases on the external interface (`eth1`, `5.79.99.0/24`) to present different source IPs:

```bash
# Add alias for this phase's attacker persona
ip addr add 5.79.99.10/24 dev eth1 label eth1:phase2
# Later: ip addr del 5.79.99.10/24 dev eth1
```

For IPs outside `5.79.99.0/24`, the SNAT chain on fw-dmz is used instead (see [config/fw-dmz/README.md](../../config/fw-dmz/README.md)).
