# dockerfiles/scenario/ — Kali Attacker + Saffron Server + Fake Internet

The scenario container is the most complex image in the range. It serves five roles simultaneously:

1. **Attacker platform** — Kali Linux with a full red team toolset
2. **Saffron server** — REST API server at `0.0.0.0:8080` that receives commands and dispatches to Saffron agents on target machines
3. **Fake internet** — Caddy HTTPS server + CoreDNS for simulated internet services (C2 callback endpoints, phishing pages, external IP hosting)
4. **Sliver C2 teamserver** — always-on daemon on port 31337
5. **Setup file server** — Python HTTP server on port 8000 serving `range-ca.crt` and other operator-provided files for participant download

---

## Files in Build Context

| File              | Purpose                                                                     |
| ----------------- | --------------------------------------------------------------------------- |
| `Dockerfile`      | Single-stage build from `kalilinux/kali-rolling`                            |
| `entrypoint.sh`   | Starts all services: CoreDNS, Caddy, Saffron, Sliver, Postfix, Python HTTPS |
| `Caddyfile`       | HTTPS fake internet — range CA PKI, on_demand TLS, per-domain file server   |
| `Corefile`        | CoreDNS static fallback (runtime generates `Corefile.dynamic` from this)    |
| `postfix-main.cf` | Postfix SMTP relay for phishing email injection                              |
| `transport`       | Postfix transport map — routes `secure.net` mail to `5.79.99.25:25`         |
| `server`          | Pre-compiled Saffron server binary (copied to `/usr/bin/saffron-server`)    |
| `crs/*.bash`      | CRS helper scripts (copied to `/usr/bin/`)                                  |
| `range-ca.crt`    | Range CA certificate — must be generated before `docker build` (gitignored) |
| `range-ca.key`    | Range CA private key — must be generated before `docker build` (gitignored) |

---

## Dockerfile

Single-stage build from `kalilinux/kali-rolling`. No multi-stage — all tools installed in one layer.

**APT packages:**

| Category         | Packages                                                   |
| ---------------- | ---------------------------------------------------------- |
| Network recon    | `nmap masscan hping3 tcpdump wireshark-common netcat-openbsd` |
| AD/Windows       | `impacket-scripts smbclient netexec evil-winrm`            |
| Web attacks      | `nikto sqlmap gobuster ffuf`                               |
| Credential       | `hashcat john hydra`                                       |
| Post-exploitation| `metasploit-framework`                                     |
| Email/phishing   | `postfix swaks`                                            |
| Utilities        | `curl wget python3 python3-pip python3-yaml git vim tmux openssh-client jq qrencode dnsutils iproute2` |

**Additional tools installed at build time:**

| Tool             | Method                                                        |
| ---------------- | ------------------------------------------------------------- |
| Responder        | `git clone https://github.com/lgandx/Responder.git /opt/Responder` |
| bloodhound       | `pip3 install --break-system-packages bloodhound`             |
| Sliver C2        | Pre-compiled binaries from GitHub releases (pinned: `v1.5.42`); `sliver-server` + `sliver` to `/usr/bin/` |
| Caddy            | Latest `linux_amd64.tar.gz` from GitHub releases API         |
| CoreDNS          | Latest `linux_amd64.tgz` from GitHub releases API            |
| yq               | `yq_linux_amd64` binary from `mikefarah/yq` GitHub releases  |

**Range CA:** `range-ca.crt` and `range-ca.key` are copied to `/etc/caddy/` and also placed at `/srv/setup/range-ca.crt` for participant download via the setup server.

---

## entrypoint.sh — Service Startup Sequence

The entrypoint runs as root inside the container. Steps in order:

### 1. Fix `resolv.conf`

Docker overwrites `/etc/resolv.conf` at container start. The entrypoint immediately captures the Docker-provided upstream DNS resolver, then replaces `/etc/resolv.conf` with `nameserver 127.0.0.1` so all container DNS queries go to CoreDNS.

```
DOCKER_DNS=$(grep -m1 '^nameserver' /etc/resolv.conf)  # captured before overwrite
echo "nameserver 127.0.0.1" > /etc/resolv.conf
```

CoreDNS's dynamic Corefile then forwards unmatched queries to `$DOCKER_DNS` (not hardcoded `8.8.8.8`), ensuring Docker's internal DNS is always reachable even if host firewall blocks UDP 53 to the internet.

### 2. IP aliases on `eth1`

Eight fake internet domains are aliased as `/32` host routes on `eth1`. Traffic routed here by `fw-dmz` is accepted because the IP is locally aliased. Errors are suppressed with `|| true` so the container starts normally in local test runs where `eth1` may not exist.

| Domain          | Fake Public IP     |
| --------------- | ------------------ |
| `google.com`    | `142.250.80.46`    |
| `microsoft.com` | `20.112.52.29`     |
| `github.com`    | `140.82.121.4`     |
| `linkedin.com`  | `108.174.10.10`    |
| `pastebin.com`  | `104.23.98.190`    |
| `dropbox.com`   | `162.125.6.6`      |
| `slack.com`     | `54.192.151.10`    |
| `attacker.com`  | `3.89.100.42`      |

IPs are realistic public addresses from real ASN ranges for believability. Wildcard zone entries resolve all subdomains to the same IP.

**Scenario-injectable DNS:** If `/home/attacker/dns-additions.conf` exists, additional `domain ip` entries are processed — IP aliases are added and zone files are generated for those domains as well.

### 3. CoreDNS zone files and dynamic Corefile

For each domain (built-in + dns-additions.conf), `entrypoint.sh` generates a zone file at `/etc/coredns/zones/<domain>.db` with wildcard A record, then writes `/etc/coredns/Corefile.dynamic` — one `file` stanza per domain plus a catch-all `forward` stanza using the captured Docker DNS upstream.

The static `Corefile` in the image is a fallback only; CoreDNS is always invoked as:

```bash
coredns -conf /etc/coredns/Corefile.dynamic
```

### 4–9. Background services started in order

| Step | Service                                  | Port  | Notes                                              |
| ---- | ---------------------------------------- | ----- | -------------------------------------------------- |
| 4    | Saffron server                           | 8080  | `saffron-server -host 0.0.0.0 -port 8080`; data dir `/opt/saffron/data` |
| 5    | CoreDNS                                  | 53    | Uses `/etc/coredns/Corefile.dynamic`               |
| 6    | Caddy on_demand TLS permission server    | 9090  | Tiny Python `HTTPServer` — always returns HTTP 200 to approve cert issuance |
| 7    | Caddy                                    | 80/443| `caddy run --config /etc/caddy/Caddyfile`          |
| 8    | Sliver teamserver                        | 31337 | `sliver-server daemon --lhost 0.0.0.0 --lport 31337`; creds stored in `/root/.sliver/configs/` on first start |
| 9    | Postfix                                  | 25    | `myhostname`/`mydomain` set from `$SMTP_HOSTNAME`/`$SMTP_DOMAIN` env vars (defaults: `mail.attacker.com` / `attacker.com`) |
| 10   | Python setup file server                 | 8000  | Serves `/srv/setup/` — contains `range-ca.crt` for participant download |

---

## Caddyfile

Caddy acts as the HTTPS server for all fake internet domains. Key design:

- **Range CA as PKI root** — Caddy mints per-domain certificates on first connection, signed by the range CA. Participants install `range-ca.crt` once; all fake internet domains then present valid TLS with no browser warnings.
- **On-demand TLS** — Caddy issues certs lazily on first connection. The `ask` directive points to the permission server at `localhost:9090`, which always approves.
- **Per-domain file server** — Requests to `:443` are served from `/srv/www/{host}/` if `index.html` exists there; otherwise falls back to `/srv/www/_default`.
- **HTTP redirect** — `:80` redirects permanently to HTTPS.

```
{
    pki { ca range-ca { root { cert /etc/caddy/range-ca.crt; key /etc/caddy/range-ca.key } } }
    on_demand_tls { ask http://localhost:9090/ }
}

:80  { redir https://{host}{uri} permanent }

:443 {
    tls { ca range-ca; on_demand }
    @has_dir file /srv/www/{host}/index.html
    handle @has_dir { root * /srv/www/{host}; file_server }
    handle          { root * /srv/www/_default; file_server }
}
```

Static website content for each fake domain lives in `www/<domain>/` (project root) and is bind-mounted into `/srv/www/` at runtime.

---

## Corefile (CoreDNS)

The `Corefile` in the image is a static fallback and is **not used at runtime**. It documents the structure used:

```
.:53 {
    forward . 8.8.8.8
    log
    errors
    cache 30
}
```

The actual runtime config is `/etc/coredns/Corefile.dynamic`, generated by `entrypoint.sh` with one `file` block per fake internet domain and a catch-all forwarder pointing to the Docker-provided upstream DNS resolver.

---

## Postfix (postfix-main.cf + transport)

Postfix is configured for outbound phishing email. `myhostname` and `mydomain` are set at container start from environment variables:

- `SMTP_HOSTNAME` → `myhostname` (default: `mail.attacker.com`)
- `SMTP_DOMAIN` → `mydomain` (default: `attacker.com`)

Phase scripts can change these mid-scenario without rebuild:

```bash
postconf -e "myhostname=notifications.linkedin.com"
postfix reload
```

**Transport map** routes `secure.net` mail via the DMZ mail relay's external IP:

```
secure.net    smtp:[5.79.99.25]:25
```

**Mail flow:** scenario → `5.79.99.25:25` → fw-dmz DNAT → `mail-relay:25` → Exchange. Each hop produces SMTP log artifacts for defenders to investigate.

Phase scripts send phishing email via `swaks`:

```bash
swaks \
    --to bwilson@secure.net \
    --from "it-support@attacker.com" \
    --server 5.79.99.25 \
    --body "Please reset your password: https://microsoft.com/reset" \
    --header "Subject: Urgent: Password Reset Required"
```

---

## Fake Internet IP Aliases

Unlike the attacker diversity aliases used by phase scripts, the eight fake internet domain IPs are permanently aliased by `entrypoint.sh` on container start. These are `/32` host routes — fw-dmz routes traffic destined for those IPs to the scenario container's `eth1`.

For scenario-specific attacker diversity (different source IPs per phase), phase scripts add additional aliases:

```bash
ip addr add 5.79.99.10/32 dev eth1 label eth1:phase2
# Later:
ip addr del 5.79.99.10/32 dev eth1
```

For IPs outside the `5.79.99.0/24` range, use SNAT rules on fw-dmz instead. See [config/fw-dmz/README.md](../../config/fw-dmz/README.md).

---

## Prerequisites (before `docker build`)

The range CA must exist before building — Caddy needs the cert/key baked into the image:

```bash
# Generate a range CA (one-time, operator only)
openssl genrsa -out dockerfiles/scenario/range-ca.key 4096
openssl req -new -x509 -days 3650 \
    -key dockerfiles/scenario/range-ca.key \
    -out dockerfiles/scenario/range-ca.crt \
    -subj "/CN=Local Cyber Range CA/O=Range/C=US"
```

Both files are gitignored. The Saffron `server` binary and `crs/*.bash` scripts must also be present in `dockerfiles/scenario/` before building (see `misc/saffron/`).

---

## Building

Build via the top-level Makefile (preferred — builds all images together):

```bash
make build
```

Or standalone:

```bash
docker build -t scenario dockerfiles/scenario/
```

The image takes several minutes on first build due to Kali apt, Metasploit, and the GitHub release API downloads for Caddy/CoreDNS/Sliver/yq.

---

## Running

Always start via docker-compose — the container needs `eth1` on the external network and `eth0` on the control network for IP aliasing and routing to work:

```bash
make up
# or
docker compose up -d scenario
```

Tail logs:

```bash
make logs SERVICE=scenario
# or
docker compose logs -f scenario
```

---

## Service Access

| Service              | Address                        | Notes                                          |
| -------------------- | ------------------------------ | ---------------------------------------------- |
| Saffron REST API     | `http://10.0.0.1:8080`         | OOB management — operator/trainer only         |
| Sliver teamserver    | `10.0.0.1:31337`               | Connect with `sliver` client (see below)       |
| Caddy fake internet  | `https://<fake-domain>/`       | Reachable from participant WireGuard subnet    |
| CoreDNS              | `10.0.0.1:53`                  | Participants use this as their DNS resolver    |
| Setup file server    | `http://10.0.0.1:8000`         | Range CA cert + operator files; HTTP only      |

### Shell access (attacker tools)

```bash
docker exec -it scenario bash
# Working directory: /home/attacker
# Tools: nmap, netexec, evil-winrm, impacket, sliver, metasploit, etc.
```

### Sliver C2

Connect to the teamserver from the operator host:

```bash
# First run — import operator config generated on container first start
docker cp scenario:/root/.sliver/configs/ ./sliver-configs/
sliver import ./sliver-configs/<operator>.cfg

# Subsequent connections
sliver
[sliver] > version          # confirm connection
[sliver] > sessions          # list active implants
```

Sliver operator configs are stored at `/root/.sliver/configs/` inside the container and persist across restarts via the Docker volume.

### Saffron API

```bash
# List connected agents
curl http://10.0.0.1:8080/api/clients

# Run a command on a specific agent
curl -X POST http://10.0.0.1:8080/api/run \
    -H "Content-Type: application/json" \
    -d '{"client": "dc01", "command": "whoami"}'
```

Helper scripts wrapping common API calls are available inside the container at `/usr/bin/*.bash`.

---

## Participant Onboarding

Participants must install the range CA certificate once so that fake internet domains present valid TLS. After connecting to WireGuard:

**Linux / macOS:**

```bash
# Download from the setup server
curl -o range-ca.crt http://10.0.0.1:8000/range-ca.crt

# Linux (Ubuntu/Debian)
sudo cp range-ca.crt /usr/local/share/ca-certificates/range-ca.crt
sudo update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain range-ca.crt
```

**Windows (PowerShell, as Administrator):**

```powershell
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
$cert.Import("range-ca.crt")
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
$store.Open("ReadWrite")
$store.Add($cert)
$store.Close()
```

**Browser only (Firefox):** Firefox maintains its own CA store. Import via `about:preferences#privacy` → Certificates → View Certificates → Authorities → Import.

After installing the CA, `https://google.com` (and all other fake internet domains) will show a valid cert in the participant's browser.

---

## Running Scenarios

Scenarios are executed from the operator host using `bin/range-scenario`:

```bash
# Full run
bin/range-scenario scenarios/apache-mass-defacement

# Dry run — print phases without executing
bin/range-scenario --dry-run scenarios/apache-mass-defacement

# Single phase only
bin/range-scenario --phase 02_initial_access scenarios/apache-mass-defacement

# Skip inter-phase delays (testing)
bin/range-scenario --no-delays scenarios/apache-mass-defacement
```

Phase scripts execute inside the scenario container via `docker exec`. Each script must be idempotent and source only from `env_vars.sh`. See [scenarios/_template/README.md](../../scenarios/_template/README.md) for the full schema.

---

## Environment Variables

Set in `.env` or `docker-compose.yml`. All have defaults but should be overridden for production exercises.

| Variable        | Default              | Purpose                                               |
| --------------- | -------------------- | ----------------------------------------------------- |
| `SMTP_HOSTNAME` | `mail.attacker.com`  | Postfix `myhostname` — appears in email `Received:` headers |
| `SMTP_DOMAIN`   | `attacker.com`       | Postfix `mydomain` — used as `myorigin`               |

Phase scripts can override mid-scenario without rebuilding:

```bash
docker exec scenario postconf -e "myhostname=notifications.linkedin.com"
docker exec scenario postfix reload
```

---

## Injecting Custom DNS (dns-additions.conf)

To add domains beyond the eight built-in fake internet entries — for example, a scenario-specific C2 domain — mount or copy a `dns-additions.conf` file into the container before or at start:

```
# /home/attacker/dns-additions.conf
# Format: <domain> <ip>
# Lines starting with # are ignored.
c2.evil-corp.net    5.79.99.50
cdn.updates-cdn.com 5.79.99.51
```

The entrypoint processes this file during startup: IP aliases are added on `eth1`, zone files are generated, and the domain is included in `Corefile.dynamic`. To apply changes after the container is running, restart the container — entrypoint re-runs from scratch each time.
