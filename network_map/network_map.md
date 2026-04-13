# Network Map — secure.net Local Cyber Range

Container-based attack/defense training environment. Linux services run as Docker containers. Windows targets run via `dockur/windows` with KVM. Segmented corporate network with DMZ, internal servers, user workstations, SIEM, and database zones. OOB management via Saffron (Go binary, REST API). Participant access via WireGuard VPN.

**Deployment:** docker-compose | **Map version:** 5.0

---

## Host Requirements


| Requirement | Detail                                                                    |
| ----------- | ------------------------------------------------------------------------- |
| KVM         | Required for Windows VMs — host user must be in `kvm` and `docker` groups |
| RAM         | ~50 GB                                                                    |


---

## Network Segments


| Segment  | Subnet        | Docker Network | Purpose                                                                               |
| -------- | ------------- | -------------- | ------------------------------------------------------------------------------------- |
| external | 5.79.99.0/24  | external       | Fake internet — scenario engine hosts C2 infra, fake domains, and attacker IP aliases |
| dmz      | 10.10.10.0/24 | dmz            | DMZ web server internal segment                                                       |
| server   | 10.20.20.0/24 | server         | Internal server segment — AD, Exchange, fileserver                                    |
| users    | 10.30.30.0/24 | users          | User workstation segment — mixed OS corporate endpoints                               |
| db       | 10.40.40.0/24 | db             | Database segment — MSSQL server                                                       |
| siem     | 10.50.50.0/24 | siem           | SIEM tooling segment — Wazuh stack + rsyslog                                          |
| vpn      | 10.99.0.0/24  | vpn            | WireGuard participant VPN — participants bring their own laptop as SOC workstation    |


---

## Machines

### scenario


| Field     | Value                                                          |
| --------- | -------------------------------------------------------------- |
| OS        | Kali (rolling)                                                 |
| CPUs      | 4                                                              |
| Memory    | 6 GB                                                           |
| Disk      | 80 GB                                                          |
| Type      | linux-container                                                |
| Image     | `cyber-range/scenario:local` (build: `./dockerfiles/scenario`) |
| mem_limit | 6g                                                             |
| cap_add   | NET_ADMIN, NET_RAW                                             |
| Volumes   | `./scenarios:/home/trainer/scenarios`, `./www:/var/www/html`   |


**Interfaces:**

- external: `5.79.99.1/24`

Scenario engine and fake internet node. Runs attack tools (Metasploit, nmap, Impacket, BloodHound, CrackMapExec, Responder, Sliver C2, Evil-WinRM) and fake internet services (Caddy HTTPS, CoreDNS). Saffron server. SSH access from host on port 2222. Scenarios mounted at `/home/trainer/scenarios`.

---

### fw-dmz


| Field     | Value                                                 |
| --------- | ----------------------------------------------------- |
| OS        | Linux (nftables)                                      |
| CPUs      | 1                                                     |
| Memory    | 0.25 GB                                               |
| Disk      | 1 GB                                                  |
| Type      | linux-firewall                                        |
| Image     | `debian:bookworm-slim`                                |
| mem_limit | 256m                                                  |
| cap_add   | NET_ADMIN, NET_RAW                                    |
| sysctls   | net.ipv4.ip_forward=1                                 |
| Volumes   | `./config/fw-dmz/nftables.conf:/etc/nftables.conf:ro` |


**Interfaces:**

- external: `5.79.99.2/24`
- dmz: `10.10.10.1/24`

DMZ perimeter firewall running nftables. Connects the fake internet (external) to the DMZ segment. SNAT rules support attacker IP diversity — phase scripts can present arbitrary source IPs to defenders.

---

### fw-core


| Field     | Value                                                  |
| --------- | ------------------------------------------------------ |
| OS        | Linux (nftables)                                       |
| CPUs      | 1                                                      |
| Memory    | 0.25 GB                                                |
| Disk      | 1 GB                                                   |
| Type      | linux-firewall                                         |
| Image     | `debian:bookworm-slim`                                 |
| mem_limit | 256m                                                   |
| cap_add   | NET_ADMIN, NET_RAW                                     |
| sysctls   | net.ipv4.ip_forward=1                                  |
| Volumes   | `./config/fw-core/nftables.conf:/etc/nftables.conf:ro` |


**Interfaces:**

- dmz: `10.10.10.2/24`
- server: `10.20.20.1/24`
- users: `10.30.30.1/24`
- db: `10.40.40.1/24`
- siem: `10.50.50.1/24`

Central firewall and core router running nftables. Connects the DMZ to all internal segments (server, users, db, siem). Policy-based routing between zones.

---

### wireguard


| Field     | Value                        |
| --------- | ---------------------------- |
| OS        | Linux (WireGuard)            |
| CPUs      | 1                            |
| Memory    | 0.25 GB                      |
| Disk      | 1 GB                         |
| Type      | linux-container              |
| Image     | `linuxserver/wireguard`      |
| mem_limit | 256m                         |
| cap_add   | NET_ADMIN, SYS_MODULE        |
| sysctls   | net.ipv4.ip_forward=1        |
| Volumes   | `./config/wireguard:/config` |


**Interfaces:**

- vpn: `10.99.0.1/24`

WireGuard VPN server. Participants connect from their own laptops to act as SOC workstations with visibility into the range. Generate a peer config with: `make vpn-config PEER=alice`

---

### wazuh.manager


| Field     | Value                                             |
| --------- | ------------------------------------------------- |
| OS        | Linux (Wazuh 4.9.x)                               |
| CPUs      | 2                                                 |
| Memory    | 2 GB                                              |
| Disk      | 20 GB                                             |
| Type      | linux-container                                   |
| Image     | `wazuh/wazuh-manager:4.9.2`                       |
| mem_limit | 2g                                                |
| Ports     | 1514, 1515, 55000                                 |
| Certs     | `config/wazuh/certs/` — generated by `make certs` |


**Interfaces:**

- siem: `10.50.50.5/24`

Wazuh manager: agent enrollment (PSK), OSSEC rules, and alert processing. Run `make build` to generate TLS certs before first `make up`.

---

### wazuh.indexer


| Field     | Value                       |
| --------- | --------------------------- |
| OS        | Linux (OpenSearch)          |
| CPUs      | 2                           |
| Memory    | 2 GB                        |
| Disk      | 20 GB                       |
| Type      | linux-container             |
| Image     | `wazuh/wazuh-indexer:4.9.2` |
| mem_limit | 2g                          |


**Interfaces:**

- siem: `10.50.50.6/24`

Wazuh indexer: OpenSearch data store for SIEM alerts and event history.

---

### wazuh.dashboard


| Field     | Value                         |
| --------- | ----------------------------- |
| OS        | Linux (Wazuh Dashboard)       |
| CPUs      | 1                             |
| Memory    | 1 GB                          |
| Disk      | 5 GB                          |
| Type      | linux-container               |
| Image     | `wazuh/wazuh-dashboard:4.9.2` |
| mem_limit | 1g                            |
| Ports     | 443→5601                      |


**Interfaces:**

- siem: `10.50.50.7/24`

Wazuh dashboard: HTTPS UI served on host :443. Analyst-facing interface for alert triage, rule browsing, and agent status.

---

### rsyslog


| Field     | Value                                |
| --------- | ------------------------------------ |
| OS        | Linux (rsyslog)                      |
| CPUs      | 1                                    |
| Memory    | 0.25 GB                              |
| Disk      | 5 GB                                 |
| Type      | linux-container                      |
| Image     | `cyber-range/rsyslog:local`          |
| mem_limit | 256m                                 |
| Volumes   | `./config/rsyslog:/etc/rsyslog.d:ro` |


**Interfaces:**

- siem: `10.50.50.8/24`

Centralized syslog collector. Receives UDP/TCP 514 from all Linux containers and forwards structured logs to Wazuh manager.

---

### mail-relay


| Field     | Value                                                                    |
| --------- | ------------------------------------------------------------------------ |
| OS        | Debian 12 (Postfix)                                                      |
| CPUs      | 1                                                                        |
| Memory    | 0.25 GB                                                                  |
| Disk      | 5 GB                                                                     |
| Type      | linux-container                                                          |
| Image     | `cyber-range/mail-relay:local` (build: `./dockerfiles/mail-relay`)       |
| mem_limit | 256m                                                                     |
| Volumes   | `./config/mail-relay/main.cf:/etc/postfix/main.cf:ro`                    |


**Interfaces:**

- dmz: `10.10.10.20/24`
- external (NAT via fw-dmz): `5.79.99.25:25` → `10.10.10.20:25`

DMZ mail relay (Postfix). Accepts inbound SMTP from the fake internet and relays to Exchange (`10.20.20.10`) for internal delivery. Provides realistic SMTP traffic artifacts — Received headers, relay logs — for phishing and email-based attack scenarios. Wazuh agent pre-baked.

---

### web-lin


| Field     | Value                                                        |
| --------- | ------------------------------------------------------------ |
| OS        | Ubuntu 22.04                                                 |
| CPUs      | 1                                                            |
| Memory    | 0.5 GB                                                       |
| Disk      | 5 GB                                                         |
| Type      | linux-container                                              |
| Image     | `cyber-range/web-lin:local` (build: `./dockerfiles/web-lin`) |
| mem_limit | 512m                                                         |
| Volumes   | `./webapps/web01:/var/www/html:ro`                           |


**Interfaces:**

- dmz: `10.10.10.10/24`
- external (NAT via fw-dmz): `5.79.99.10` → `10.10.10.10`

Linux DMZ web server running Apache + PHP. Hosts web01 (employee portal). Content swapped per scenario via `./webapps/web01/` volume mount. Wazuh agent pre-baked.

---

### web-win


| Field     | Value                    |
| --------- | ------------------------ |
| OS        | Windows Server 2025 Core |
| CPUs      | 2                        |
| Memory    | 4 GB                     |
| Disk      | 60 GB                    |
| Type      | windows-container (KVM)  |
| Image     | `ghcr.io/dockur/windows` |
| mem_limit | 4g                       |
| Devices   | /dev/kvm                 |


**Interfaces:**

- dmz: `10.10.10.12/24`
- external (NAT via fw-dmz): `5.79.99.12` → `10.10.10.12`

Windows DMZ web server running IIS. Primary Windows target for web exploitation, WebShell deployment, and lateral movement pivot into internal segments.

---

### dc01


| Field     | Value                    |
| --------- | ------------------------ |
| OS        | Windows Server 2025 Core |
| CPUs      | 2                        |
| Memory    | 4 GB                     |
| Disk      | 60 GB                    |
| Type      | windows-container (KVM)  |
| Image     | `ghcr.io/dockur/windows` |
| mem_limit | 4g                       |
| Devices   | /dev/kvm                 |


**Interfaces:**

- server: `10.20.20.100/24`

Primary Active Directory DC for secure.net. Runs AD DS, DNS, AD CS (PKI co-hosted). High-value target for DCSync, Golden Ticket, Kerberoasting, and ADCS scenarios (ESC1/ESC4/ESC8 misconfigs baked in).

---

### exchange


| Field     | Value                    |
| --------- | ------------------------ |
| OS        | Windows Server 2022 Core |
| CPUs      | 2                        |
| Memory    | 6 GB                     |
| Disk      | 60 GB                    |
| Type      | windows-container (KVM)  |
| Image     | `ghcr.io/dockur/windows` |
| mem_limit | 6g                       |
| Devices   | /dev/kvm                 |


**Interfaces:**

- server: `10.20.20.10/24`

Microsoft Exchange 2019 mail server for secure.net. Used in phishing, email exfiltration, and credential harvesting scenarios. Fully functional mail flow (60–90 min first-boot). Exchange 2019 runs on Windows Server 2022 (the only officially supported combination as of Exchange 2019 CU13+).

---

### fileserver


| Field     | Value                    |
| --------- | ------------------------ |
| OS        | Windows Server 2025 Core |
| CPUs      | 1                        |
| Memory    | 2 GB                     |
| Disk      | 60 GB                    |
| Type      | windows-container (KVM)  |
| Image     | `ghcr.io/dockur/windows` |
| mem_limit | 2g                       |
| Devices   | /dev/kvm                 |


**Interfaces:**

- server: `10.20.20.20/24`

File server with SMB shares accessible to domain users. Print Spooler enabled (intentionally vulnerable — PrintNightmare). Used for lateral movement, UNC path abuse, data staging, and ransomware simulation.

---

### db01


| Field     | Value                                                  |
| --------- | ------------------------------------------------------ |
| OS        | Ubuntu 22.04                                           |
| CPUs      | 2                                                      |
| Memory    | 4 GB                                                   |
| Disk      | 40 GB                                                  |
| Type      | linux-container                                        |
| Image     | `cyber-range/db01:local` (build: `./dockerfiles/db01`) |
| mem_limit | 4g                                                     |


**Interfaces:**

- db: `10.40.40.10/24`

Microsoft SQL Server 2022 on Linux. Domain joined to secure.net via realmd/sssd. SPN registered for Kerberoasting (svc_mssql). Used in SQL injection, xp_cmdshell RCE, credential dumping, and Kerberoasting scenarios.

---

### wks-linux


| Field     | Value                                                            |
| --------- | ---------------------------------------------------------------- |
| OS        | Ubuntu 24.04                                                     |
| CPUs      | 1                                                                |
| Memory    | 1 GB                                                             |
| Disk      | 10 GB                                                            |
| Type      | linux-container                                                  |
| Image     | `cyber-range/wks-linux:local` (build: `./dockerfiles/wks-linux`) |
| mem_limit | 1g                                                               |


**Interfaces:**

- users: `10.30.30.10/24`

Linux developer workstation. `devuser` (developer, docker, git) and `sysadmin` (elevated, sudo, bash history with admin creds). Used in Linux persistence, LD_PRELOAD rootkit, SSH key harvesting, and credential reuse scenarios.

---

### wks-win11


| Field     | Value                    |
| --------- | ------------------------ |
| OS        | Windows 11               |
| CPUs      | 2                        |
| Memory    | 4 GB                     |
| Disk      | 60 GB                    |
| Type      | windows-container (KVM)  |
| Image     | `ghcr.io/dockur/windows` |
| mem_limit | 4g                       |
| Devices   | /dev/kvm                 |


**Interfaces:**

- users: `10.30.30.20/24`

Windows 11 workstation joined to secure.net. User: `SECURE\bwilson`. Modern endpoint for testing detection against current-generation OS defenses (SmartScreen, Credential Guard, AMSI).

---

## IP Summary


| Machine         | Segment IPs                                                                               |
| --------------- | ----------------------------------------------------------------------------------------- |
| scenario        | external: 5.79.99.1                                                                       |
| fw-dmz          | external: 5.79.99.2, dmz: 10.10.10.1                                                     |
| fw-core         | dmz: 10.10.10.2, server: 10.20.20.1, users: 10.30.30.1, db: 10.40.40.1, siem: 10.50.50.1 |
| wireguard       | vpn: 10.99.0.1                                                                            |
| db01            | db: 10.40.40.10                                                                           |
| mail-relay      | dmz: 10.10.10.20, external (DNAT): 5.79.99.25 (SMTP :25)                                 |
| web-lin         | dmz: 10.10.10.10, external (DNAT): 5.79.99.10                                            |
| web-win         | dmz: 10.10.10.12, external (DNAT): 5.79.99.12                                            |
| wazuh.manager   | siem: 10.50.50.5                                                                          |
| wazuh.indexer   | siem: 10.50.50.6                                                                          |
| wazuh.dashboard | siem: 10.50.50.7                                                                          |
| rsyslog         | siem: 10.50.50.8                                                                          |
| dc01            | server: 10.20.20.100                                                                      |
| exchange        | server: 10.20.20.10                                                                       |
| fileserver      | server: 10.20.20.20                                                                       |
| wks-linux       | users: 10.30.30.10                                                                        |
| wks-win11       | users: 10.30.30.20                                                                        |


