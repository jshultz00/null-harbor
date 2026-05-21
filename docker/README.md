# Local Cyber Range

A portable, sandboxed cyber range for incident response and red team training. Runs on a single Linux host with KVM and Docker. Inspired by Cloud Range but designed to be deployed locally, from scratch, in under an hour.

---

## Architecture Overview


| Layer              | Technology                | Notes                                          |
| ------------------ | ------------------------- | ---------------------------------------------- |
| Linux services     | Docker containers         | Firewalls, SIEM, web servers, workstations, DB |
| Windows machines   | `dockur/windows` KVM VMs  | DC, Exchange, fileserver, workstations         |
| OOB management     | Saffron agent/server      | Replaces SaltStack; Go binary, REST API        |
| Participant access | WireGuard VPN             | Participants bring their own laptop as SOC WS  |
| Attacker platform  | Kali (scenario container) | Full toolset + fake internet + Saffron server  |


### Network Segments


| Segment  | Subnet        | Purpose                                                                 |
| -------- | ------------- | ----------------------------------------------------------------------- |
| management | 10.0.0.0/24 | Saffron OOB — every machine has an interface here; **hidden from participants** (not in WireGuard routes, not logged by firewalls, not indexed by SIEM) |
| vpn      | 10.99.0.0/24  | WireGuard participants                                                  |
| external | 5.79.99.0/24  | Fake internet (scenario owns subnet; IP aliases for attacker diversity) |
| dmz      | 10.10.10.0/24 | DMZ web servers                                                         |
| server   | 10.20.20.0/24 | AD, Exchange, fileserver                                                |
| users    | 10.30.30.0/24 | Workstations                                                            |
| db       | 10.40.40.0/24 | Database servers                                                        |
| siem     | 10.50.50.0/24 | Wazuh stack + rsyslog                                                   |


### Machine IPs


| Machine         | Control IP | Segment IP(s)                                              |
| --------------- | ---------- | ---------------------------------------------------------- |
| scenario        | 10.0.0.1   | 5.79.99.1 (external)                                       |
| fw-dmz          | 10.0.0.10  | 5.79.99.2, 10.10.10.1                                      |
| fw-core         | 10.0.0.11  | 10.10.10.2, 10.20.20.1, 10.30.30.1, 10.40.40.1, 10.50.50.1 |
| wireguard       | 10.0.0.20  | 10.99.0.1                                                  |
| wazuh.manager   | 10.0.0.5   | 10.50.50.5                                                 |
| wazuh.indexer   | 10.0.0.6   | 10.50.50.6                                                 |
| wazuh.dashboard | 10.0.0.7   | 10.50.50.7                                                 |
| rsyslog         | 10.0.0.8   | 10.50.50.8                                                 |
| mail-relay      | 10.0.0.45  | 10.10.10.20                                                |
| web-lin         | 10.0.0.40  | 10.10.10.10                                                |
| web-win         | 10.0.0.42  | 10.10.10.12                                                |
| dc01            | 10.0.0.70  | 10.20.20.100                                               |
| exchange        | 10.0.0.72  | 10.20.20.10                                                |
| fileserver      | 10.0.0.74  | 10.20.20.20                                                |
| db01            | 10.0.0.30  | 10.40.40.10                                                |
| wks-linux       | 10.0.0.100 | 10.30.30.10                                                |
| wks-win11       | 10.0.0.101 | 10.30.30.20                                                |


---

## Quick Start

### Prerequisites

- Linux host with KVM enabled (`/dev/kvm` present)
- Host user in `kvm` and `docker` groups
- Docker + Docker Compose v2
- `make`, `openssl`, `wireguard-tools` installed on host
- ~200 GB free disk space for Windows VM volumes (first boot)

### First Run

```bash
# 1. Copy secrets template and fill in values
cp .env.example .env
$EDITOR .env

# 2. Build all Docker images and generate Wazuh TLS certs
make build

# 3. Start the full range
make up

# 4. Print all machine IPs and credentials
make creds

# 5. Generate a WireGuard peer config for a participant
make vpn-config PEER=alice
```

Windows VMs (dc01, exchange, fileserver, workstations) take **10–30 minutes** on first boot to complete domain join and service installation. `make status` shows current container state.

### Stopping the Range

```bash
# Stop gracefully, keep volumes (fastest resume)
make down

# Stop and wipe all data volumes (clean slate for next exercise)
make reset

# Nuclear: remove volumes + images
make clean
```

---

## Directory Structure

```
local_cyber_range/
├── README.md                   # This file
├── docker-compose.yml          # All services — see docker-compose.md
├── Makefile                    # Range lifecycle — see Makefile.md
├── .env.example                # Secrets template — see .env.example.md
├── bin/
│   ├── range                   # Interactive TUI control script
│   └── range-scenario          # Scenario runner (reads manifest, executes phases)
├── config/
│   ├── fw-dmz/                 # DMZ firewall nftables config
│   ├── fw-core/                # Core/internal firewall nftables config
│   ├── wazuh/                  # Wazuh manager + indexer + dashboard configs
│   ├── wireguard/              # WireGuard server config + generated peer configs
│   ├── rsyslog/                # Centralized syslog config
│   └── windows/                # Per-machine unattend.xml + setup.ps1
│       ├── dc01/
│       ├── exchange/
│       ├── fileserver/
│       ├── web-win/
│       └── wks-win11/
├── dockerfiles/
│   ├── scenario/               # Kali attacker + Saffron server + fake internet
│   ├── fw/                     # Shared nftables firewall base image
│   ├── web-lin/                # Ubuntu + Apache + PHP + Wazuh agent
│   ├── wks-linux/              # Ubuntu workstation + user accounts
│   └── db01/                   # MSSQL 2022 on Ubuntu + domain join
├── scenarios/
│   └── _template/              # Blank scenario template (schema reference)
├── webapps/
│   └── web01/                  # Scenario-swappable web content for web-lin
├── www/                        # Static files served by scenario container (HTTPS)
├── data/                       # Docker volume mounts — gitignored
├── misc/
│   ├── crs/                    # * helper scripts (Saffron wrappers)
│   └── saffron/                # Saffron server + agent binaries and source
├── network_map/                # Interactive topology viewer (HTML)
└── _specs/                     # Feature specs
```

---

## Credentials


| Machine    | Username             | Password  | Protocol  |
| ---------- | -------------------- | --------- | --------- |
| wks-linux  | devuser              | P@55w0rd! | SSH :22   |
| wks-linux  | jsmith               | P@55w0rd! | SSH :22   |
| wks-linux  | administrator        | P@55w0rd! | SSH :22   |
| web-lin    | administrator        | P@55w0rd! | SSH :22   |
| db01       | sa (MSSQL)           | P@55w0rd! | TCP :1433 |
| dc01       | SECURE\Administrator | P@55w0rd! | RDP :3389 |
| dc01       | Administrator        | P@55w0rd! | RDP :3389 |
| wks-win11  | Administrator        | P@55w0rd! | RDP :3389 |
| wks-win11  | SECURE\jsmith        | P@55w0rd! | RDP :3389 |
| wks-win11  | SECURE\mjones        | P@55w0rd! | RDP :3389 |
| wks-win11  | SECURE\bwilson       | P@55w0rd! | RDP :3389 |
| wks-win11  | SECURE\Administrator | P@55w0rd! | RDP :3389 |
| exchange   | Administrator        | P@55w0rd! | RDP :3389 |
| exchange   | SECURE\Administrator | P@55w0rd! | RDP :3389 |
| fileserver | Administrator        | P@55w0rd! | RDP :3389 |
| fileserver | SECURE\Administrator | P@55w0rd! | RDP :3389 |


AD domain: `secure.net` / NetBIOS: `SECURE`

---

## Scenario Engine

Scenarios live under `scenarios/<slug>/`. Each is a self-contained directory with a `manifest.yaml`, `env_vars.sh`, and a `phases/` directory of bash scripts. The scenario runner (`bin/range-scenario`) reads the manifest and executes phases sequentially via `docker exec` on the scenario container.

See [scenarios/README.md](scenarios/README.md) and [bin/README.md](bin/README.md) for details.

---

## Attacker IP Diversity

Scenario phases can present arbitrary source IPs to defenders to prevent memorization of a single attacker address in SIEM logs. Two mechanisms are available:

1. **IP aliases** on the scenario container's `5.79.99.0/24` external interface — any IP in that range, fully bidirectional, no NAT
2. **SNAT at fw-dmz** — for completely arbitrary IPs (e.g., `3.3.3.3`), a Source NAT rule in fw-dmz's nftables translates the scenario container's real source IP before traffic enters the internal network; stateful so responses route back correctly

Phase scripts toggle these rules between phases. See [config/fw-dmz/README.md](config/fw-dmz/README.md) for implementation details.

---

## Hardware Requirements


| Component | Minimum                | Recommended             |
| --------- | ---------------------- | ----------------------- |
| CPU       | 8-core with VT-x/AMD-V | i9-14900K or equivalent |
| RAM       | 32 GB                  | 64 GB                   |
| Disk      | 300 GB NVMe            | 500 GB+ NVMe            |
| KVM       | Required               | Required                |


This range was designed for a single host: Intel i9-14900K, 62 GB RAM, 915 GB NVMe.