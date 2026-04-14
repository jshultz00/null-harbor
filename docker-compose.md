# docker-compose.yml — Implementation Specification

This document describes what `docker-compose.yml` will contain when implemented. All services are started with a single `make up` — no user-facing profiles to select.

---

## Global Configuration

```
version: "3.9"
name: local-cyber-range
```

All custom networks use `driver: bridge` with `com.docker.network.bridge.name` set to a named bridge for host-side visibility (`ip link show`). IP ranges are assigned as documented in the network topology.

`x-common-env` YAML anchor injects shared environment variables into all containers:
- `WAZUH_MANAGER=10.0.0.5`
- `COMMANDLY_SERVER=http://10.0.0.1:8080`

---

## Networks

| Docker Network Name | Subnet | Gateway | Bridge Name |
|--------------------|--------|---------|-------------|
| control | 10.0.0.0/24 | 10.0.0.254 | cr-control |
| vpn | 10.99.0.0/24 | 10.99.0.254 | cr-vpn |
| external | 5.79.99.0/24 | 5.79.99.254 | cr-external |
| dmz | 10.10.10.0/24 | 10.10.10.254 | cr-dmz |
| server | 10.20.20.0/24 | 10.20.20.254 | cr-server |
| users | 10.30.30.0/24 | 10.30.30.254 | cr-users |
| db | 10.40.40.0/24 | 10.40.40.254 | cr-db |
| siem | 10.50.50.0/24 | 10.50.50.254 | cr-siem |

All networks use `internal: false` except `external` which is host-accessible for WireGuard routing.

---

## Services

### scenario

```
build: dockerfiles/scenario
container_name: scenario
hostname: scenario
networks:
  control:    ipv4_address: 10.0.0.1
  external:   ipv4_address: 5.79.99.1
cap_add: [NET_ADMIN, NET_RAW, SYS_PTRACE]
volumes:
  - ./scenarios:/home/attacker/scenarios:ro
  - ./www:/srv/www:ro
  - ./webapps:/srv/webapps:ro
  - saffron-data:/opt/saffron/data
ports:
  - "8080:8080"   # Saffron server (host-accessible for scenario scripts)
```

The scenario container is the Kali-based attacker platform and Saffron server. It is also the setup file server (Caddy/Python HTTPS) from which Windows VMs download their `setup.ps1` on first boot. `NET_RAW` is required for packet crafting tools (hping3, Responder, etc.).

---

### fw-dmz

```
build: dockerfiles/fw
container_name: fw-dmz
hostname: fw-dmz
networks:
  control:    ipv4_address: 10.0.0.10
  external:   ipv4_address: 5.79.99.2
  dmz:        ipv4_address: 10.10.10.1
cap_add: [NET_ADMIN, NET_RAW]
sysctls:
  - net.ipv4.ip_forward=1
volumes:
  - ./config/fw-dmz/nftables.conf:/etc/nftables.conf:ro
```

DMZ perimeter firewall. Bridges the `external` and `dmz` segments. Hosts the SNAT chain for attacker IP diversity (scenario phases write transient rules via Saffron). All traffic is logged to syslog.

---

### fw-core

```
build: dockerfiles/fw
container_name: fw-core
hostname: fw-core
networks:
  control:    ipv4_address: 10.0.0.11
  dmz:        ipv4_address: 10.10.10.2
  server:     ipv4_address: 10.20.20.1
  users:      ipv4_address: 10.30.30.1
  db:         ipv4_address: 10.40.40.1
  siem:       ipv4_address: 10.50.50.1
cap_add: [NET_ADMIN]
sysctls:
  - net.ipv4.ip_forward=1
volumes:
  - ./config/fw-core/nftables.conf:/etc/nftables.conf:ro
```

Core/internal routing firewall. Routes between all internal segments. Permissive but fully logged — all inter-segment traffic generates Wazuh alerts via syslog forwarding.

---

### wireguard

```
image: linuxserver/wireguard
container_name: wireguard
hostname: wireguard
networks:
  control:    ipv4_address: 10.0.0.20
  vpn:        ipv4_address: 10.99.0.1
cap_add: [NET_ADMIN, SYS_MODULE]
sysctls:
  - net.ipv4.ip_forward=1
  - net.ipv4.conf.all.src_valid_mark=1
volumes:
  - ./config/wireguard:/config
  - /lib/modules:/lib/modules:ro
ports:
  - "51820:51820/udp"   # WireGuard UDP port — exposed to host LAN
environment:
  - PUID=1000
  - PGID=1000
  - TZ=UTC
  - SERVERURL=auto        # Uses host LAN IP for peer config generation
  - SERVERPORT=51820
  - PEERS=0               # Peers added dynamically via make vpn-config
  - PEERDNS=10.0.0.1      # Scenario container runs CoreDNS for range DNS
  - INTERNAL_SUBNET=10.99.0.0/24
  - ALLOWEDIPS=10.0.0.0/24,10.10.10.0/24,10.20.20.0/24,10.30.30.0/24,10.40.40.0/24,10.50.50.0/24,5.79.99.0/24
```

---

### wazuh.manager

```
image: wazuh/wazuh-manager:${WAZUH_VERSION}
container_name: wazuh.manager
hostname: wazuh.manager
networks:
  control:    ipv4_address: 10.0.0.5
  siem:       ipv4_address: 10.50.50.5
volumes:
  - ./config/wazuh/ossec.conf:/wazuh-config-mount/etc/ossec.conf:ro
  - ./config/wazuh/authd.pass:/wazuh-config-mount/etc/authd.pass:ro
  - wazuh-manager-data:/var/ossec/data
  - wazuh-logs:/var/ossec/logs
environment:
  - WAZUH_API_USERNAME=wazuh-wui
  - WAZUH_API_PASSWORD=${WAZUH_API_PASSWORD}
  - FILEBEAT_SSL_VERIFICATION_MODE=full
  - SSL_CERTIFICATE_AUTHORITIES=/etc/ssl/root-ca.pem
  - SSL_CERTIFICATE=/etc/ssl/filebeat.pem
  - SSL_KEY=/etc/ssl/filebeat.key
```

---

### wazuh.indexer

```
image: wazuh/wazuh-indexer:${WAZUH_VERSION}
container_name: wazuh.indexer
hostname: wazuh.indexer
networks:
  control:    ipv4_address: 10.0.0.6
  siem:       ipv4_address: 10.50.50.6
volumes:
  - ./config/wazuh/wazuh.indexer.yml:/usr/share/wazuh-indexer/opensearch.yml:ro
  - wazuh-indexer-data:/var/lib/wazuh-indexer
environment:
  - "OPENSEARCH_JAVA_OPTS=-Xms2g -Xmx2g"
  - OPENSEARCH_INITIAL_ADMIN_PASSWORD=${WAZUH_INDEXER_PASSWORD}
ulimits:
  memlock: { soft: -1, hard: -1 }
  nofile:  { soft: 65536, hard: 65536 }
```

---

### wazuh.dashboard

```
image: wazuh/wazuh-dashboard:${WAZUH_VERSION}
container_name: wazuh.dashboard
hostname: wazuh.dashboard
networks:
  control:    ipv4_address: 10.0.0.7
  siem:       ipv4_address: 10.50.50.7
volumes:
  - ./config/wazuh/opensearch_dashboards.yml:/usr/share/wazuh-dashboard/config/opensearch_dashboards.yml:ro
ports:
  - "443:5601"   # Dashboard accessible from host at https://localhost
depends_on: [wazuh.indexer, wazuh.manager]
```

---

### rsyslog

```
image: rsyslog/syslog_appliance_alpine
container_name: rsyslog
hostname: rsyslog
networks:
  control:    ipv4_address: 10.0.0.8
  siem:       ipv4_address: 10.50.50.8
volumes:
  - ./config/rsyslog/rsyslog.conf:/etc/rsyslog.conf:ro
  - rsyslog-data:/var/log/remote
ports:
  - "514:514/udp"
  - "514:514/tcp"
```

---

### mail-relay

```
build: dockerfiles/mail-relay
container_name: mail-relay
hostname: mail-relay
networks:
  control:    ipv4_address: 10.0.0.45
  dmz:        ipv4_address: 10.10.10.20
volumes:
  - ./config/mail-relay/main.cf:/etc/postfix/main.cf:ro
environment:
  - WAZUH_MANAGER=10.0.0.5
  - COMMANDLY_SERVER=http://10.0.0.1:8080
```

DMZ mail relay (Postfix). Accepts inbound SMTP from the fake internet (DNAT: `5.79.99.25:25` → `10.10.10.20:25` at fw-dmz) and relays to Exchange (`10.20.20.10`) for internal delivery. Provides realistic SMTP traffic artifacts for phishing and email-based attack scenarios. Wazuh agent pre-baked.

---

### web-lin

```
build: dockerfiles/web-lin
container_name: web-lin
hostname: web-lin
networks:
  control:    ipv4_address: 10.0.0.40
  dmz:        ipv4_address: 10.10.10.10
volumes:
  - ./webapps/web01:/var/www/html:rw   # Scenario-swappable content
environment:
  - WAZUH_MANAGER=10.0.0.5
  - COMMANDLY_SERVER=http://10.0.0.1:8080
```

---

### db01

```
build: dockerfiles/db01
container_name: db01
hostname: db01
networks:
  control:    ipv4_address: 10.0.0.30
  db:         ipv4_address: 10.40.40.10
environment:
  - ACCEPT_EULA=${ACCEPT_EULA}
  - MSSQL_SA_PASSWORD=${MSSQL_SA_PASSWORD}
  - AD_DOMAIN=${AD_DOMAIN}
  - AD_DOMAIN_CONTROLLER=10.20.20.100
  - WAZUH_MANAGER=10.0.0.5
  - COMMANDLY_SERVER=http://10.0.0.1:8080
volumes:
  - db01-data:/var/opt/mssql
```

---

### wks-linux

```
build: dockerfiles/wks-linux
container_name: wks-linux
hostname: wks-linux
networks:
  control:    ipv4_address: 10.0.0.100
  users:      ipv4_address: 10.30.30.10
environment:
  - WAZUH_MANAGER=10.0.0.5
  - COMMANDLY_SERVER=http://10.0.0.1:8080
  - AD_DOMAIN=${AD_DOMAIN}
  - AD_DOMAIN_CONTROLLER=10.20.20.100
```

---

### Windows VMs (dockur/windows)

All Windows VMs follow the same pattern. Example for dc01:

```
image: dockur/windows
container_name: dc01
hostname: dc01
networks:
  control:    ipv4_address: 10.0.0.70
  server:     ipv4_address: 10.20.20.100
devices:
  - /dev/kvm
  - /dev/net/tun
cap_add: [NET_ADMIN]
environment:
  - VERSION=2022          # Windows Server 2022
  - RAM_SIZE=4G
  - CPU_CORES=2
  - DISK_SIZE=64G
  - USERNAME=Administrator
  - PASSWORD=${RANGE_PASSWORD}
  - SETUP_SERVER=http://10.0.0.1:8000/windows/dc01/setup.ps1
volumes:
  - dc01-data:/storage
stop_grace_period: 2m    # Windows needs time to shut down cleanly
```

Windows VMs use KVM acceleration and require `/dev/kvm`. `SETUP_SERVER` points to the scenario container which serves the per-machine `setup.ps1` on first boot. RAM/CPU allocations:

| VM | RAM | CPU | Disk |
|----|-----|-----|------|
| dc01 | 4G | 2 | 64G |
| exchange | 8G | 4 | 128G |
| fileserver | 2G | 2 | 64G |
| web-win | 2G | 2 | 64G |
| wks-win11 | 4G | 2 | 64G |

---

## Volumes

All persistent data lives under `./data/` on the host (gitignored):

```
volumes:
  wazuh-manager-data:   driver: local, device: ./data/wazuh/manager
  wazuh-indexer-data:   driver: local, device: ./data/wazuh/indexer
  wazuh-logs:           driver: local, device: ./data/wazuh/logs
  rsyslog-data:         driver: local, device: ./data/rsyslog
  db01-data:            driver: local, device: ./data/db01
  saffron-data:         driver: local, device: ./data/saffron
  dc01-data:            driver: local, device: ./data/windows/dc01
  exchange-data:        driver: local, device: ./data/windows/exchange
  fileserver-data:      driver: local, device: ./data/windows/fileserver
  web-win-data:         driver: local, device: ./data/windows/web-win
  wks-win11-data:       driver: local, device: ./data/windows/wks-win11
```

`make reset` prunes all volumes. `make down` preserves them.
