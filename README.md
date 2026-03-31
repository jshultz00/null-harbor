# Local Cyber Range

A containerized, multi-segment enterprise network simulation for attack/defense security training. Built with Docker Compose, it emulates a realistic corporate environment ("Secure Corp" / `secure.net` domain) complete with Windows Active Directory, internal servers, DMZ services, a SOC, and a Wazuh SIEM stack.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Variables](#environment-variables)
- [Quick Start](#quick-start)
- [Make Targets](#make-targets)
- [Service Profiles](#service-profiles)
- [First-Boot Sequence](#first-boot-sequence)
- [Network Architecture](#network-architecture)
- [Service IP Reference](#service-ip-reference)
- [Accessing Services](#accessing-services)
- [Day-to-Day Workflows](#day-to-day-workflows)
- [Scenario Development](#scenario-development)
- [Firewall Manipulation](#firewall-manipulation)
- [Intentional Vulnerabilities](#intentional-vulnerabilities)
- [File Reference](#file-reference)
- [Architecture Notes](#architecture-notes)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Docker Engine ≥ 24 + Docker Compose v2 | `docker compose version` to verify |
| KVM/QEMU | Required for Windows/macOS VMs — run `kvm-ok` to verify |
| Linux host with nested virtualization | Check with `cat /sys/module/kvm_intel/parameters/nested` (should be `Y`) or `kvm_amd` |
| `openssl` in PATH | Used by `make certs` to generate Wazuh PKI — usually pre-installed |
| RAM | ~20 GB (`core`), ~28 GB (`web-attack`), ~64 GB (`full`) |
| Disk | ~50 GB free minimum; Windows VM images grow to 20–80 GB each on first boot |

Verify KVM availability before starting:

```bash
kvm-ok            # confirms hardware virtualisation is enabled
ls -l /dev/kvm    # should be crw-rw---- owned by root:kvm
groups            # your user must be in the 'kvm' and 'docker' groups
```

---

## Environment Variables

Copy `.env.example` to `.env` and fill in every value before running `make build` or `make up`.

```bash
cp .env.example .env
$EDITOR .env
```

| Variable | Purpose | Example |
|---|---|---|
| `RANGE_PASSWORD` | Shared password seeded on all Linux containers and the Windows Administrator account | `Training!23` |
| `AD_DOMAIN` | Active Directory FQDN | `secure.net` |
| `AD_NETBIOS` | NetBIOS domain name | `SECURE` |
| `AD_ADMIN_PASSWORD` | Domain Administrator password — must match `RANGE_PASSWORD` | `Training!23` |
| `WAZUH_VERSION` | Wazuh image tag for manager, indexer, and dashboard | `4.9.0` |
| `WAZUH_MANAGER` | C2-network IP of the Wazuh manager (agents auto-enroll here) | `172.16.0.5` |
| `WAZUH_ENROLLMENT_PSK` | Pre-shared key for agentless auto-enrollment | `changeme-psk` |
| `WAZUH_INDEXER_PASSWORD` | OpenSearch admin password (used by manager and dashboard) | `SecurePass!1` |
| `WAZUH_API_PASSWORD` | Wazuh REST API password for the `wazuh-wui` user | `SecurePass!1` |
| `MSSQL_SA_PASSWORD` | MSSQL `sa` account password (must meet SQL Server complexity rules) | `Str0ngPass!` |
| `ACCEPT_EULA` | Must be `Y` to accept the MSSQL Server EULA | `Y` |

> **Security note:** `.env` is git-ignored. Never commit it. The `authd.pass` file (Wazuh enrollment PSK) is also excluded.

---

## Quick Start

```bash
# 1. Copy and fill in secrets
cp .env.example .env
$EDITOR .env

# 2. Build custom images and generate Wazuh TLS certificates (once)
make build

# 3. Start the range — choose a profile
make up PROFILE=core        # ~20 GB RAM — core infrastructure only
make up PROFILE=web-attack  # ~28 GB RAM — adds DMZ web targets + DB
make up PROFILE=full        # ~64 GB RAM — everything including workstations

# 4. Monitor startup
make status                 # container health and state
make logs                   # tail all logs
make logs SVC=dc01          # tail a specific service

# 5. Access the range
make scenario-ssh           # SSH into the Kali attacker container (port 2222)
# Wazuh dashboard: https://localhost
# SOC workstation: http://localhost:8006  (noVNC)

# 6. Stop (Windows disk images are preserved)
make down

# 7. Full teardown including all Windows disk images
make reset
```

> **Windows VMs** (DC, Exchange, workstations) take **15–90 minutes on first boot** to install Windows and run the unattended provisioning scripts. Subsequent starts from preserved disk images take 1–3 minutes.

---

## Make Targets

Run `make help` to see all targets. Full reference:

| Target | Variables | Description |
|---|---|---|
| `make help` | — | Print all targets and descriptions |
| `make build` | — | Generate Wazuh PKI certificates, then build all custom Docker images |
| `make certs` | — | Generate Wazuh TLS certificates only (skipped if already present) |
| `make up` | `PROFILE=core\|web-attack\|full` | Start the range with the specified profile (default: `core`) |
| `make down` | — | Stop all containers; Windows disk volumes are **preserved** |
| `make reset` | — | Full teardown — destroys all containers, networks, **and disk volumes** (prompts for confirmation) |
| `make status` | — | `docker compose ps` — show container status and health |
| `make logs` | `SVC=<service-name>` | Tail logs; omit `SVC` to follow all services |
| `make shell` | `SVC=<service-name>` | Open a bash shell inside a running container |
| `make scenario-ssh` | — | SSH into the Kali scenario container on `localhost:2222` |

**Examples:**

```bash
make up PROFILE=web-attack          # start with DMZ web servers
make logs SVC=wazuh.manager         # tail Wazuh manager logs
make shell SVC=fw-core              # open shell on core firewall
make shell SVC=db01                 # open shell on MSSQL container
make logs SVC=dc01                  # watch DC01 Windows provisioning progress
```

---

## Service Profiles

Profiles control which containers start. Each higher profile is a superset of the previous.

| Profile | Included Services | Approx. RAM |
|---|---|---|
| `core` | `scenario`, `fw-dmz`, `fw-core`, `dc01`, `wks-win10`, `wazuh.manager`, `wazuh.indexer`, `wazuh.dashboard`, `soc-ws` | ~20 GB |
| `web-attack` | `core` + `router`, `web-lin`, `web-win`, `dns-dmz`, `mail-relay`, `db01`, `exchange` | ~28 GB |
| `full` | `web-attack` + `fileserver`, `wks-linux`, `wks-win11`, `wks-macos` | ~64 GB |

**Profile selection guidance:**

- Use `core` for AD attacks, Kerberoasting, AD CS abuse, and SIEM/detection exercises.
- Use `web-attack` to add web application targets, phishing simulation (mail relay), and SQL injection / database pivoting scenarios.
- Use `full` for complete kill-chain exercises: initial access via web → lateral movement → workstation compromise → exfiltration.

---

## First-Boot Sequence

Windows VMs are provisioned via `unattend.xml` + `setup.ps1`. The process is:

1. **OS install** — Windows installs from the dockur/windows base image (~10–30 min).
2. **`setup.ps1` stage 1** — Machine-specific configuration runs (AD DS install, domain join, IIS config, etc.). Machine reboots.
3. **`setup.ps1` stage 2** — Post-reboot tasks complete (AD CS install, user creation, GPOs, SMB shares, etc.). Machine reboots again.

**Domain join sequencing** is enforced by a Docker healthcheck on `dc01` that polls TCP port 389 (LDAP) every 60 seconds with a 25-minute start period. Services that depend on AD (`exchange`, `fileserver`, `db01`, `wks-win10`, `wks-win11`) will not start until `dc01` reports healthy.

Monitor DC01 provisioning progress:

```bash
make logs SVC=dc01                          # watch the KVM/QEMU console output
docker inspect DC01 --format '{{.State.Health.Status}}'   # check health status
```

**Subsequent restarts** from preserved disk volumes skip OS installation and complete in ~1–3 minutes.

---

## Network Architecture

| Network | Subnet | Gateway | Purpose |
|---|---|---|---|
| Main | 17.93.8.0/29 | 17.93.8.6 | Transit — scenario engine to border router |
| Router-DMZ | 130.2.2.0/24 | 130.2.2.254 | Border router to DMZ firewall |
| Firewall Link | 192.168.254.0/30 | — | Back-to-back link between DMZ and core firewalls |
| DMZ Internal | 172.16.100.0/24 | — | Externally-reachable services (web, mail, DNS) |
| C2 | 172.16.0.0/24 | 172.16.0.254 | Out-of-band control plane — scenario engine and Wazuh reach every host without routing |
| Management | 172.31.202.0/24 | — | OOB management for firewalls and SOC workstation |
| Server | 192.168.200.0/24 | 192.168.200.254 | Internal servers (AD, Exchange, file server, DB) |
| User | 192.168.100.0/24 | — | Corporate workstations |
| SOC | 192.168.110.0/24 | — | Security operations center workstations |
| SIEM | 192.168.66.0/24 | — | Wazuh manager, indexer, dashboard |
| DB | 192.168.214.0/24 | — | MSSQL database |
| Scenario | 9.53.99.0/24 | — | Scenario engine management segment |

> The **C2 network** is an intentional out-of-band bypass — every container has a `172.16.0.x` interface connected to it. This lets Wazuh agents enroll and the scenario engine reach any host without traversing the firewalls, enabling clean scenario setup/teardown independent of firewall state.

---

## Service IP Reference

### C2 Network (172.16.0.0/24) — all containers

| Container | C2 IP |
|---|---|
| `scenario` (Kali) | 172.16.0.1 |
| `wazuh.manager` | 172.16.0.5 |
| `db01` | 172.16.0.30 |
| `web-lin` | 172.16.0.40 |
| `web-win` | 172.16.0.42 |
| `dns-dmz` | 172.16.0.44 |
| `mail-relay` | 172.16.0.45 |
| `dc01` | 172.16.0.70 |
| `exchange` | 172.16.0.72 |
| `fileserver` | 172.16.0.74 |
| `soc-ws` | 172.16.0.80 |
| `wks-linux` | 172.16.0.100 |
| `wks-win10` | 172.16.0.101 |
| `wks-win11` | 172.16.0.102 |
| `wks-macos` | 172.16.0.103 |

### Per-Segment IPs

| Container | Segment IP | Segment |
|---|---|---|
| `fw-dmz` | 172.16.100.254 | DMZ Internal gateway |
| `web-lin` | 172.16.100.10 | DMZ Internal |
| `web-win` | 172.16.100.12 | DMZ Internal |
| `dns-dmz` | 172.16.100.6 | DMZ Internal |
| `mail-relay` | 172.16.100.8 | DMZ Internal |
| `fw-core` | 192.168.200.254 | Server gateway |
| `dc01` | 192.168.200.1 | Server |
| `exchange` | 192.168.200.10 | Server |
| `fileserver` | 192.168.200.6 | Server |
| `wks-linux` | 192.168.100.10 | User |
| `wks-win10` | 192.168.100.11 | User |
| `wks-win11` | 192.168.100.12 | User |
| `wks-macos` | 192.168.100.13 | User |
| `soc-ws` | 192.168.110.11 | SOC |
| `wazuh.manager` | 192.168.66.50 | SIEM |
| `wazuh.indexer` | 192.168.66.20 | SIEM |
| `wazuh.dashboard` | 192.168.66.10 | SIEM |
| `db01` | 192.168.214.10 | DB |

---

## Accessing Services

### From the host machine

| Service | URL / Command | Notes |
|---|---|---|
| Wazuh Dashboard | https://localhost | Log in as `admin` / `<WAZUH_INDEXER_PASSWORD>` from `.env` |
| SOC Workstation | http://localhost:8006 | noVNC browser console — use for initial access before RDP |
| Kali scenario container | `make scenario-ssh` | SSH as `root` on port 2222 |
| Wazuh REST API | https://localhost:55000 | Username `wazuh-wui` / `<WAZUH_API_PASSWORD>` from `.env` |
| Wazuh agent events | port 1514 | Agent UDP/TCP syslog forwarding |
| Wazuh enrollment | port 1515 | Automatic agent registration |

### From the SOC workstation (noVNC → RDP)

Once the SOC workstation is accessible via noVNC (`http://localhost:8006`):

1. Open the Remote Desktop Connection application inside the Windows VM.
2. RDP to internal server/workstation IPs using domain credentials:
   - Domain admin: `SECURE\Administrator` / `<RANGE_PASSWORD>`
   - Domain users: `SECURE\jsmith`, `SECURE\mjones`, `SECURE\bwilson`, `SECURE\alee`, `SECURE\cthompson` — all use password `P@55w0rd!`

### From the scenario (Kali) container

```bash
make scenario-ssh                         # or: ssh root@localhost -p 2222

# Reach any host via C2 network (bypasses firewalls)
ping 172.16.0.70                          # dc01
ssh sysadmin@172.16.0.100                 # wks-linux

# Reach DMZ services via their DMZ IPs
curl http://172.16.100.10                 # web-lin employee portal
nmap -sV 172.16.100.0/24                  # scan DMZ segment

# Reach internal services (routes through fw-core)
crackmapexec smb 192.168.200.0/24         # enumerate internal servers
```

### Wazuh Dashboard login

Default credentials for the Wazuh Dashboard:

- **Username:** `admin`
- **Password:** value of `WAZUH_INDEXER_PASSWORD` in `.env`

> The self-signed TLS certificate will trigger a browser warning — this is expected. Add a security exception to proceed.

---

## Day-to-Day Workflows

### Rebuild after code/config changes

```bash
# Rebuild a specific image and restart its container
docker compose build scenario && docker compose up -d scenario

# Rebuild all images (does not regenerate certificates if already present)
make build && make up PROFILE=core
```

### Inspect a running container

```bash
make shell SVC=fw-core                    # bash shell on core firewall
make shell SVC=scenario                   # bash shell on Kali
make shell SVC=db01                       # bash shell on MSSQL container
docker exec -it DC01 bash                 # equivalent direct docker command
```

### Check Wazuh agent status

```bash
# From scenario container or any enrolled host:
make scenario-ssh
curl -k -u wazuh-wui:<API_PASSWORD> https://172.16.0.5:55000/agents | python3 -m json.tool

# From the Wazuh dashboard:
# Agents → Agent list → filter by status
```

### Wipe and rebuild Windows disk images

Windows disk volumes persist across `make down` restarts. To force a full re-provision:

```bash
make reset            # destroys ALL volumes (Wazuh data too) — prompts for confirmation

# To reset only specific Windows VMs:
docker compose stop dc01
docker volume rm cyber-range_dc01-disk
docker compose up -d dc01                 # triggers fresh OS install
```

### Update Wazuh version

```bash
# Edit WAZUH_VERSION in .env, then:
make down
make build            # regenerates certs if needed
make up PROFILE=core
```

---

## Scenario Development

Attack scripts and playbooks are placed in `./scenarios/` on the host. This directory is live-mounted into the Kali container at `/home/trainer/scenarios` — no rebuild required.

```bash
# Add a new scenario script
echo '#!/bin/bash\nnmap -sC -sV 192.168.200.0/24' > scenarios/recon-internal.sh
chmod +x scenarios/recon-internal.sh

# Run it from Kali immediately (no rebuild needed)
make scenario-ssh
bash /home/trainer/scenarios/recon-internal.sh
```

The scenario container includes a full offensive toolset:

| Tool | Purpose |
|---|---|
| Metasploit Framework | Exploitation and post-exploitation |
| CrackMapExec | SMB/LDAP/WinRM enumeration and credential attacks |
| Impacket | Kerberos attacks (Kerberoasting, AS-REP, Pass-the-Hash, DCSync) |
| BloodHound + neo4j | AD attack path analysis |
| Sliver C2 | Command and control framework |
| Evil-WinRM | WinRM shell for post-exploitation |
| Responder | LLMNR/NBT-NS/MDNS poisoning |
| Caddy | Reverse proxy / HTTPS server for phishing infrastructure |
| CoreDNS | Custom DNS for fake domain resolution |
| Postfix | SMTP mail relay for phishing campaigns |

**Common attack chains to practice:**

```bash
# Kerberoasting
GetUserSPNs.py secure.net/jsmith:P@55w0rd! -dc-ip 192.168.200.1 -request

# AS-REP Roasting (requires accounts with pre-auth disabled)
GetNPUsers.py secure.net/ -dc-ip 192.168.200.1 -usersfile /usr/share/wordlists/users.txt

# AD CS ESC8 — HTTP enrollment relay attack
certipy relay -target http://192.168.200.1/certsrv/ -template Machine

# BloodHound collection
bloodhound-python -u jsmith -p 'P@55w0rd!' -d secure.net -ns 192.168.200.1 -c All

# SMB enumeration
crackmapexec smb 192.168.200.0/24 -u jsmith -p 'P@55w0rd!'
```

---

## Firewall Manipulation

Both firewalls (`fw-dmz`, `fw-core`) run nftables with a **permissive default posture** and logging enabled. This design allows all traffic through by default so scenarios can selectively tighten rules to test detection.

### View current rules

```bash
make shell SVC=fw-core
nft list ruleset

make shell SVC=fw-dmz
nft list ruleset
```

### Inject rules at runtime (no restart)

```bash
make shell SVC=fw-core

# Block user workstations from directly reaching the database segment
nft add rule inet filter forward ip saddr @users ip daddr @db drop

# Allow only SOC to reach servers on RDP
nft add rule inet filter forward ip saddr @soc ip daddr @servers tcp dport 3389 accept
nft add rule inet filter forward ip daddr @servers drop

# Block all outbound from a compromised workstation
nft add rule inet filter forward ip saddr 192.168.100.11 drop
```

### View firewall logs

Firewall logs are forwarded to Wazuh. You can also read them directly:

```bash
make shell SVC=fw-core
journalctl -f -k | grep fw-core          # kernel netfilter log
```

### Reset firewall to baseline

```bash
make shell SVC=fw-core
nft flush ruleset && nft -f /etc/nftables.conf
```

---

## Intentional Vulnerabilities

This range is built for training. All weaknesses are deliberate:

| Vulnerability | Location | Technique |
|---|---|---|
| Weak passwords (`P@55w0rd!`) | All domain accounts | Credential spraying, brute force |
| AD CS ESC8 misconfiguration | `dc01` — HTTP certificate enrollment endpoint | Certificate-based privilege escalation via relay |
| Kerberoastable service accounts | `dc01` — SPNs registered in AD | Kerberoasting / offline hash cracking |
| Plaintext credentials in bash history | `wks-linux` (`devuser`, `sysadmin`) | Post-exploitation credential harvesting |
| Hardcoded credentials in HTML comments | `webapps/web01/index.html` (`admin / P@55w0rd!`) | Web application reconnaissance / information disclosure |
| Permissive firewall rules | `fw-dmz`, `fw-core` | Unrestricted lateral movement; detection gap identification |
| Unpatched macOS (Sonoma 14) | `wks-macos` | CVE exploitation scenarios |
| Open SMTP relay | `mail-relay` — accepts any sender for `secure.net` | Phishing campaign simulation |

---

## File Reference

### Root

| File | Purpose |
|---|---|
| `docker-compose.yml` | Main orchestration file — all services, networks, volumes, and profiles |
| `Makefile` | Lifecycle automation — `build`, `up`, `down`, `reset`, `status`, `logs`, `shell`, `scenario-ssh` |
| `.env` | Runtime secrets (git-ignored) — copy from `.env.example` |
| `.env.example` | Template with all required variable names and descriptions |
| `.gitignore` | Excludes `.env`, Wazuh certificates, generated runtime data, and `remote_view.sh` |
| `network_map.html` | Interactive browser-based visualization of the network topology |
| `network_map.js` | Data source for the network map — machine specs, IPs, and segment relationships |
| `remote_view.sh` | Stub placeholder for remote console access helpers |

---

### `dockerfiles/`

Custom Docker images built during `make build`.

| Path | Purpose |
|---|---|
| `dockerfiles/scenario/` | Kali Linux rolling with full offensive toolset: Metasploit, CrackMapExec, Impacket, BloodHound, Sliver C2, Evil-WinRM, Responder, Caddy, CoreDNS, Postfix |
| `dockerfiles/scenario/entrypoint.sh` | Starts SSH (port 2222), Caddy HTTPS server, CoreDNS, Postfix, Sliver C2 listener, enrolls Wazuh agent |
| `dockerfiles/scenario/Caddyfile` | Caddy reverse proxy / HTTPS config for fake internet services |
| `dockerfiles/fw/` | Debian slim with nftables and Wazuh agent — shared base for both firewall containers |
| `dockerfiles/fw/entrypoint.sh` | Loads nftables rules from mounted config, enrolls Wazuh agent |
| `dockerfiles/db01/` | MSSQL Server 2022 on Linux with `realmd`/`sssd` for AD domain join |
| `dockerfiles/db01/entrypoint.sh` | Joins `secure.net` domain via Kerberos, starts MSSQL, enrolls Wazuh agent |
| `dockerfiles/web-lin/` | Ubuntu 22.04 with Apache 2.4, PHP, and MySQL clients |
| `dockerfiles/web-lin/entrypoint.sh` | Starts Apache, mounts web application, enrolls Wazuh agent |
| `dockerfiles/wks-linux/` | Ubuntu 24.04 developer workstation with Docker, Ansible, and intentionally seeded bash history |
| `dockerfiles/wks-linux/entrypoint.sh` | Creates `devuser` and `sysadmin` accounts, starts SSH, enrolls Wazuh agent |

---

### `config/`

Per-service configuration files and Windows provisioning scripts.

#### Wazuh

| Path | Purpose |
|---|---|
| `config/wazuh/ossec.conf` | Wazuh manager rules — FIM paths, syscheck intervals, alert thresholds |
| `config/wazuh/wazuh.indexer.yml` | OpenSearch node/cluster config for the Wazuh indexer |
| `config/wazuh/opensearch_dashboards.yml` | Dashboard connection config (Kibana-compatible) |
| `config/wazuh/authd.pass` | Wazuh enrollment PSK — must match `WAZUH_ENROLLMENT_PSK` in `.env` (git-ignored) |
| `config/wazuh/certs/` | TLS certificate directory — populated by `make build` (root CA, manager, indexer, dashboard, admin certs) |

#### Windows Machines

Each Windows machine directory contains two files:

| File | Purpose |
|---|---|
| `unattend.xml` | Windows unattended installation answer file — sets locale, disables firewall, enables RDP, sets Administrator password, queues `setup.ps1` |
| `setup.ps1` | PowerShell provisioning script — runs after first boot (sometimes in multiple staged reboots) |

| Machine | Notable `setup.ps1` behavior |
|---|---|
| `config/dc01/` | Stage 1: Install AD DS + promote to DC. Stage 2: Install AD CS (ESC8 misconfiguration), create domain users (`jsmith`, `mjones`, `bwilson`, `alee`, `cthompson` — all `P@55w0rd!`), create Kerberoastable service accounts, apply GPOs |
| `config/exchange/` | Joins domain, installs Exchange Server |
| `config/fileserver/` | Joins domain, configures SMB shares |
| `config/web-win/` | Configures IIS — standalone, not domain-joined |
| `config/dns-dmz/` | Standalone Windows DNS server in DMZ |
| `config/wks-win10/` | Joins `secure.net`, configures user profile |
| `config/wks-win11/` | Joins `secure.net`, configures user profile |
| `config/soc-ws/` | SOC analyst workstation — OOB management network, not domain-joined |

#### Firewalls

| Path | Purpose |
|---|---|
| `config/fw-dmz/nftables.conf` | DMZ perimeter firewall — permissive with logging; controls traffic from `router_dmz` into `dmz_internal` |
| `config/fw-central/nftables.conf` | Core firewall — controls inter-segment traffic (Server / User / SOC / SIEM / DB); defines named sets for scenario rule injection |

#### Routing

| Path | Purpose |
|---|---|
| `config/brdr-router/frr.conf` | FRRouting config — BGP/OSPF peering between `main` and `router_dmz` segments |
| `config/brdr-router/daemons` | FRR daemon enable flags |

#### Other

| Path | Purpose |
|---|---|
| `config/rsyslog/rsyslog.conf` | Centralized syslog forwarding config (supplemental to Wazuh agents) |

---

### `webapps/`

| Path | Purpose |
|---|---|
| `webapps/web01/index.html` | DMZ employee portal — intentionally contains hardcoded credentials in HTML comments (`admin / P@55w0rd!`) for information disclosure training scenarios |

---

### `www/`

| Path | Purpose |
|---|---|
| `www/index.html` | Fake "Secure Corp" public website served by Caddy on the scenario engine — simulates an internet-facing presence for phishing and OSINT scenarios |

---

### `scenarios/`

Empty directory (`.gitkeep`) bind-mounted into the Kali container at `/home/trainer/scenarios`. Place attack scripts and scenario playbooks here — changes are immediately visible inside the container without a rebuild.

---

### `data/`

Runtime data directory for Wazuh (logs, agent data). Populated at runtime; not committed to git.

---

## Architecture Notes

- **Wazuh agent enrollment** is automatic via PSK (`WAZUH_ENROLLMENT_PSK`). Every Linux container self-enrolls on startup using the PSK in `config/wazuh/authd.pass`. Windows VMs do not auto-enroll — agents must be installed manually if desired.
- **Windows VMs** use KVM via `dockur/windows`. Disk images are stored in named Docker volumes and persist across `make down`. Use `make reset` to destroy them and trigger a fresh OS install on next `make up`.
- **Domain join sequencing** is enforced by a Docker healthcheck on `dc01` (polls LDAP port 389 every 60 seconds, 40 retries, 25-minute start period). Exchange, file server, DB, and workstations only start once the DC is healthy.
- **Scenario scripts** in `./scenarios/` are live-mounted into the Kali container — no rebuild required to add new attack scripts.
- **Dynamic firewall rules** can be injected at runtime via `nft add rule` inside the firewall containers to test detection and response without a full restart. Rules revert to the baseline config on container restart.
- **C2 network bypass** — the `172.16.0.0/24` network connects every container out-of-band, bypassing both firewalls. This is intentional — it allows the scenario engine and Wazuh to reach all hosts regardless of firewall state, enabling clean scenario setup without affecting the training environment.

---

## Troubleshooting

### `make build` fails — certificate errors

```bash
# Check openssl is installed
openssl version

# Manually wipe and regenerate certs
rm -rf config/wazuh/certs/
make certs
```

### Windows VM won't start — KVM not available

```bash
kvm-ok                          # check hardware support
ls -la /dev/kvm                 # check device exists
sudo adduser $USER kvm          # add yourself to kvm group
newgrp kvm                      # apply group change without logout
```

### DC01 stuck in `starting` / never becomes healthy

- Windows OS installation can take 20–45 minutes on first boot.
- Monitor progress: `make logs SVC=dc01`
- If the container exits unexpectedly: `docker inspect DC01 --format '{{.State.ExitCode}}'`
- Verify KVM is available — Windows VMs will fail silently without `/dev/kvm`.

### Wazuh Dashboard shows no agents

1. Verify the manager is running: `make status`
2. Check `WAZUH_MANAGER` in `.env` matches the C2 IP (`172.16.0.5`).
3. Check `WAZUH_ENROLLMENT_PSK` in `.env` matches `config/wazuh/authd.pass`.
4. Inspect agent enrollment logs: `make logs SVC=wazuh.manager`

### Wazuh Dashboard login fails

- Password is `WAZUH_INDEXER_PASSWORD` from `.env` (username: `admin`).
- If you changed the password after initial startup, the indexer may need to be reset: `make reset` and rebuild.

### Container exits immediately after `make up`

```bash
make logs SVC=<service>         # inspect exit reason
docker inspect <CONTAINER>      # check exit code and OOMKilled flag
```

- **OOMKilled** — reduce `mem_limit` in `docker-compose.yml` or free host RAM.
- **Missing `.env` variables** — re-check `.env` has all values from `.env.example`.

### Scenario SSH connection refused

```bash
make status | grep SCENARIO     # confirm container is running
ssh -o StrictHostKeyChecking=no -p 2222 root@localhost
# Password is RANGE_PASSWORD from .env
```

### Reset a single Windows VM without full teardown

```bash
docker compose stop <service>
docker volume rm cyber-range_<service>-disk
docker compose up -d <service>
```
