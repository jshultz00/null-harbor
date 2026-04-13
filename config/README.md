# config/ — Service Configuration Files

This directory contains all configuration files that are bind-mounted into containers at runtime. No configuration is baked into Docker images — images are generic; all environment-specific config lives here.

---

## Structure

| Directory | Container | Purpose |
|-----------|-----------|---------|
| `fw-dmz/` | fw-dmz | nftables ruleset for DMZ perimeter firewall + SNAT chain |
| `fw-core/` | fw-core | nftables ruleset for internal routing/segmentation |
| `wazuh/` | wazuh.manager, wazuh.indexer, wazuh.dashboard | Wazuh stack configuration + TLS certificates |
| `wireguard/` | wireguard | WireGuard server config + generated peer configs |
| `rsyslog/` | rsyslog | Centralized syslog receiver configuration |
| `windows/` | (served by scenario container) | Per-machine `unattend.xml` + `setup.ps1` scripts |

---

## Mount Strategy

All config files are mounted **read-only** (`:ro`) except:
- `config/wireguard/` — mounted read-write because `linuxserver/wireguard` writes generated peer configs back to the mount
- `config/wazuh/certs/` — written by `make certs` on the host, read-only inside containers

Windows config files are not bind-mounted into any container. They are served over HTTP by the scenario container from `./config/windows/<machine>/` on port 8000 and downloaded by Windows VMs during first-boot setup.

---

## Deeper Documentation

- [fw-dmz/README.md](fw-dmz/README.md) — nftables ruleset with SNAT chain details
- [fw-core/README.md](fw-core/README.md) — internal routing and segmentation rules
- [wazuh/README.md](wazuh/README.md) — ossec.conf, TLS cert generation, enrollment PSK
- [wireguard/README.md](wireguard/README.md) — server config and peer management
- [rsyslog/README.md](rsyslog/README.md) — syslog receiver and forwarding rules
- [windows/README.md](windows/README.md) — Windows unattended setup procedure
