# Local Cyber Range

A containerized, multi-segment enterprise network simulation for attack/defense security training. Built with Docker Compose, it emulates a realistic corporate environment ("Secure Corp" / `secure.net` domain) complete with Windows Active Directory, internal servers, DMZ services, a SOC, and a Wazuh SIEM stack.

---

## Prerequisites

- Docker + Docker Compose
- KVM/QEMU support (for Windows VMs — verify with `kvm-ok`)
- ~20 GB RAM minimum (`core` profile), up to 64 GB for `full`
- Linux host (nftables, nested virtualization)

---

## Quick Start

```bash
# 1. Copy and fill in secrets
cp .env.example .env
$EDITOR .env

# 2. Build custom images and generate Wazuh TLS certificates
make build

# 3. Start the range (choose a profile)
make up PROFILE=core        # ~20 GB RAM — core infrastructure only
make up PROFILE=web-attack  # ~28 GB RAM — adds web targets
make up PROFILE=full        # ~64 GB RAM — all machines including workstations

# 4. Watch status
make status
make logs

# 5. SSH into the attacker/scenario container
make scenario-ssh           # connects to Kali on port 2222

# 6. Shut down (preserves Windows disk images)
make down

# 7. Full teardown including Windows disks
make reset
```

> Windows VMs (DC, Exchange, workstations) take 15–90 minutes on first boot to install and configure themselves automatically via unattended setup scripts.

---

## Network Architecture

| Network | Subnet | Purpose |
|---|---|---|
| Main | 17.93.8.0/29 | Transit — border router to scenario engine |
| Router-DMZ | 130.2.2.0/24 | Blue border router to DMZ firewall |
| Firewall | 192.168.254.0/30 | Back-to-back link between DMZ and core firewalls |
| DMZ_Internal | 172.16.100.0/24 | Externally-reachable services (web, mail, DNS) |
| C2 | 172.16.0.0/24 | Out-of-band command & control (scenario engine, Wazuh) |
| Management | 172.31.202.0/24 | OOB management for firewalls and SOC workstations |
| Server | 192.168.200.0/24 | Internal servers (AD, Exchange, file, DB) |
| User | 192.168.100.0/24 | Corporate workstations |
| SOC | 192.168.110.0/24 | Security operations center workstations |
| SIEM | 192.168.66.0/24 | Wazuh manager, indexer, dashboard |
| DB | 192.168.214.0/24 | MSSQL database |
| Scenario | 9.53.99.0/24 | Scenario engine management segment |

---

## File Reference

### Root

| File | Purpose |
|---|---|
| `docker-compose.yml` | Main orchestration file defining all services, networks, volumes, and profiles |
| `Makefile` | Lifecycle automation — `build`, `up`, `down`, `reset`, `status`, `logs`, `shell`, `scenario-ssh` |
| `.env` | Runtime secrets (git-ignored). Copy from `.env.example` |
| `.env.example` | Template for required environment variables (`RANGE_PASSWORD`, `AD_DOMAIN`, `WAZUH_ENROLLMENT_PSK`, `WAZUH_VERSION`, `MSSQL_SA_PASSWORD`) |
| `.gitignore` | Excludes `.env`, Wazuh certificates, generated runtime data, and `remote_view.sh` |
| `network_map.html` | Interactive browser-based visualization of the network topology |
| `network_map.js` | Data source for the network map — defines all machine specs, IPs, and segment relationships |
| `remote_view.sh` | Stub script — placeholder for remote console access helpers |

---

### `dockerfiles/`

Custom Docker images built during `make build`. Each subdirectory has a `Dockerfile` and `entrypoint.sh`.

| Path | Purpose |
|---|---|
| `dockerfiles/scenario/Dockerfile` | Kali Linux rolling with full offensive toolset: Metasploit, CrackMapExec, Impacket, BloodHound, Sliver C2, Evil-WinRM, Responder, Caddy, CoreDNS, Postfix |
| `dockerfiles/scenario/entrypoint.sh` | Starts SSH (port 2222), Caddy HTTPS server, CoreDNS, Postfix, Sliver C2 listener, and enrolls with Wazuh |
| `dockerfiles/scenario/Caddyfile` | Caddy reverse proxy / HTTPS config for fake internet services |
| `dockerfiles/fw/Dockerfile` | Debian slim with nftables and Wazuh agent — shared base for both firewall containers |
| `dockerfiles/fw/entrypoint.sh` | Loads nftables rules from mounted config, enrolls with Wazuh agent |
| `dockerfiles/db01/Dockerfile` | MSSQL Server 2022 on Linux with `realmd`/`sssd` for Active Directory domain join |
| `dockerfiles/db01/entrypoint.sh` | Joins `secure.net` domain via Kerberos, starts MSSQL, enrolls Wazuh agent |
| `dockerfiles/web-lin/Dockerfile` | Ubuntu 22.04 with Apache 2.4, PHP, and MySQL clients |
| `dockerfiles/web-lin/entrypoint.sh` | Starts Apache, mounts web application, enrolls Wazuh agent |
| `dockerfiles/wks-linux/Dockerfile` | Ubuntu 24.04 developer workstation with Docker, Ansible, and intentionally seeded bash history |
| `dockerfiles/wks-linux/entrypoint.sh` | Creates `devuser` and `sysadmin` accounts, starts SSH, enrolls Wazuh agent |

---

### `config/`

Per-service configuration files and Windows provisioning scripts.

#### Wazuh

| Path | Purpose |
|---|---|
| `config/wazuh/ossec.conf` | Wazuh manager rules — file integrity monitoring (FIM) paths, syscheck intervals, alert thresholds |
| `config/wazuh/wazuh.indexer.yml` | OpenSearch node/cluster config for the Wazuh indexer |
| `config/wazuh/opensearch_dashboards.yml` | Kibana-compatible dashboard connection config |
| `config/wazuh/certs/` | TLS certificate directory — populated by `make build` (root CA, manager, indexer, dashboard, admin certs) |

#### Windows Machines

Each Windows machine has two files:

| File | Purpose |
|---|---|
| `unattend.xml` | Windows unattended installation answer file — sets locale, disables firewall, enables RDP, sets Administrator password, queues `setup.ps1` to run post-install |
| `setup.ps1` | PowerShell provisioning script run after first boot |

| Machine | Notable `setup.ps1` behavior |
|---|---|
| `config/dc01/` | 3-stage setup: (1) install AD DS + promote to DC, (2) install AD CS with intentional ESC8 misconfiguration, create domain users (`jsmith`, `mjones`, `bwilson`, `alee`, `cthompson`, all `Password!`), create Kerberoastable service accounts, apply GPOs |
| `config/exchange/` | Installs Exchange Server and joins the domain |
| `config/fileserver/` | Joins domain, configures SMB shares |
| `config/web-win/` | Configures IIS, standalone (not domain-joined) |
| `config/dns-dmz/` | Standalone Windows DNS server in DMZ |
| `config/wks-win10/` | Joins `secure.net`, configures user profile |
| `config/wks-win11/` | Joins `secure.net`, configures user profile |
| `config/soc-ws/` | SOC analyst workstation — OOB management network, not domain-joined |

#### Firewalls

| Path | Purpose |
|---|---|
| `config/fw-dmz/nftables.conf` | DMZ perimeter firewall rules — permissive by default with logging enabled for detection training |
| `config/fw-central/nftables.conf` | Core firewall rules — controls inter-segment traffic (Server/User/SIEM/DMZ), permissive with logging |

#### Routing

| Path | Purpose |
|---|---|
| `config/brdr-router/frr.conf` | FRRouting configuration for the border router — BGP/OSPF peering between external and DMZ segments |
| `config/brdr-router/daemons` | FRR daemon enable flags |

#### Other

| Path | Purpose |
|---|---|
| `config/rsyslog/rsyslog.conf` | Centralized syslog forwarding config (supplemental to Wazuh) |

---

### `webapps/`

| Path | Purpose |
|---|---|
| `webapps/web01/index.html` | DMZ employee portal — intentionally contains hardcoded credentials in HTML comments (`admin / Password!`) for information disclosure training scenarios |

---

### `www/`

| Path | Purpose |
|---|---|
| `www/index.html` | Fake "Secure Corp" public website served by Caddy on the scenario engine — simulates an internet-facing presence for phishing and OSINT scenarios |

---

### `scenarios/`

Empty directory (`.gitkeep`) that is bind-mounted into the scenario/Kali container at `/home/trainer/scenarios`. Place attack scripts and scenario playbooks here — they are accessible to the trainer without rebuilding the container.

---

### `data/`

Runtime data directory for Wazuh (logs, agent data). Populated at runtime; not committed.

---

## Service Profiles

| Profile | Included Services | Approx. RAM |
|---|---|---|
| `core` | Router, firewalls, DC, Wazuh SIEM, scenario engine, Linux workstation | ~20 GB |
| `web-attack` | `core` + DMZ web servers (Linux + Windows), mail relay, DNS | ~28 GB |
| `full` | `web-attack` + Exchange, file server, Windows workstations, macOS workstation, SOC workstation, MSSQL | ~64 GB |

---

## Intentional Vulnerabilities

This range is built for training. Weaknesses are deliberate:

| Vulnerability | Location | Technique |
|---|---|---|
| Weak passwords (`Password!`) | All accounts | Credential spraying, brute force |
| AD CS ESC8 misconfiguration | `dc01` — HTTP enrollment endpoint | Certificate-based privilege escalation |
| Kerberoastable service accounts | `dc01` — SPNs registered | Kerberoasting |
| Plaintext credentials in bash history | `wks-linux` | Post-exploitation credential harvest |
| Hardcoded credentials in HTML comments | `webapps/web01/index.html` | Web application reconnaissance |
| Permissive firewall rules | `fw-dmz`, `fw-core` | Lateral movement, detection gap identification |
| Unpatched macOS | `wks-macos` (macOS 14) | CVE exploitation scenarios |
| Open SMTP relay | `mail-relay` | Phishing campaign simulation |

---

## Accessing Services

| Service | Access Method |
|---|---|
| Kali scenario container | `make scenario-ssh` (SSH, port 2222) |
| Wazuh Dashboard | https://localhost (from host, port 443) |
| SOC Workstation console | http://localhost:8006 (noVNC) |
| Windows VMs (after boot) | RDP from SOC workstation to internal IPs |
| Wazuh REST API | https://172.16.0.5:55000 |

---

## Architecture Notes

- **Wazuh agent enrollment** is automatic via PSK (`WAZUH_ENROLLMENT_PSK` in `.env`). Every Linux container self-enrolls on startup.
- **Windows VMs** use KVM via `dockur/windows`. Disk images are stored in named Docker volumes and persist across `make down`. Use `make reset` to destroy them.
- **Domain join sequencing** is enforced by a Docker healthcheck on `dc01` (polls LDAP port 389). Exchange, file server, and workstations only start once the DC is healthy.
- **Scenario scripts** at `./scenarios/` are live-mounted into the Kali container — no rebuild required to add new attack scripts.
- **Dynamic firewall rules** can be injected at runtime via `nft add rule` inside the firewall containers to test detection and response without a full restart.
