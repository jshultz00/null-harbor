# Makefile — Implementation Specification

This document describes what `Makefile` will contain when implemented. The Makefile is the primary operator interface for range lifecycle management.

---

## Variables

```makefile
COMPOSE     := docker compose
ENV_FILE    := .env
PEER        ?= participant    # Default WireGuard peer name for vpn-config target
SERVICE     ?=                # Service name for logs target

# Detect host LAN IP for WireGuard SERVERURL
HOST_IP     := $(shell ip route get 8.8.8.8 | awk '{print $$7; exit}')
```

---

## Targets

### `make build`

1. Check prerequisites: `/dev/kvm` exists; current user in `kvm` and `docker` groups; `openssl` available; `.env` exists (warn if missing and copy from `.env.example`)
2. Run `make certs` if `config/wazuh/certs/` does not already exist
3. Run `$(COMPOSE) build --pull` to build all custom images

```makefile
build: .env check-prereqs certs
	$(COMPOSE) build --pull
```

### `make up`

Start all services. Windows VMs take 10–30 min on first boot; print a reminder.

```makefile
up: .env
	$(COMPOSE) up -d
	@echo ""
	@echo "Range is starting. Windows VMs may take 10-30 min on first boot."
	@echo "Run 'make status' to monitor. Run 'make creds' to get credentials."
```

### `make down`

Stop all services gracefully. Volumes are preserved.

```makefile
down:
	$(COMPOSE) down --remove-orphans
```

### `make reset`

Stop services and wipe all data volumes. Use between exercises.

```makefile
reset:
	$(COMPOSE) down --volumes --remove-orphans
	@echo "All data volumes wiped. Run 'make up' to start fresh."
```

### `make clean`

Nuclear teardown: remove containers, volumes, and all locally-built images.

```makefile
clean:
	$(COMPOSE) down --volumes --remove-orphans --rmi local
	docker network prune -f
```

### `make status`

Print running containers with their assigned IPs across all networks.

```makefile
status:
	@echo "=== Running Containers ==="
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "=== Network Assignments ==="
	@docker network inspect cr-control --format '{{range .Containers}}  {{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}' 2>/dev/null | sort
```

### `make creds`

Print all machine hostnames, IPs, credentials, and connection commands.

```makefile
creds:
	@echo "========================================"
	@echo "  Local Cyber Range — Credentials"
	@echo "========================================"
	@echo ""
	@echo "LINUX (SSH)"
	@echo "  wks-linux  10.30.30.10  devuser / P@55w0rd!"
	@echo "  wks-linux  10.30.30.10  sysadmin / P@55w0rd!"
	@echo "  web-lin    10.10.10.10  www-admin / P@55w0rd!"
	@echo "  db01       10.40.40.10  (MSSQL SA: P@55w0rd!)"
	@echo ""
	@echo "WINDOWS (RDP)"
	@echo "  dc01       10.20.20.100  Administrator / P@55w0rd!"
	@echo "  exchange   10.20.20.10   Administrator / P@55w0rd!"
	@echo "  fileserver 10.20.20.20   Administrator / P@55w0rd!"
	@echo "  web-win    10.10.10.12   Administrator / P@55w0rd!"
	@echo "  wks-win11  10.30.30.20   SECURE\jsmith / P@55w0rd!"
	@echo ""
	@echo "SIEM"
	@echo "  Wazuh dashboard  https://10.0.0.7  (or https://localhost)"
	@echo ""
	@echo "AD Domain: secure.net / SECURE"
	@echo "AD Users: jsmith, mjones, bwilson, alee, cthompson, svc_mssql"
```

### `make map`

Open the interactive network topology viewer in the default browser.

```makefile
map:
	xdg-open network_map/index.html 2>/dev/null || open network_map/index.html
```

### `make vpn-config`

Generate a WireGuard peer config for a participant and print it as a QR code. The config file is written to `config/wireguard/peers/<PEER>.conf` and persists across `make down`.

```makefile
vpn-config:
	@test -n "$(PEER)" || (echo "Usage: make vpn-config PEER=alice" && exit 1)
	docker exec wireguard /app/show-peer $(PEER) || \
	  docker exec wireguard wg genkey | tee /tmp/peer-$(PEER)-privkey | \
	    wg pubkey > /tmp/peer-$(PEER)-pubkey
	# ... peer registration and qrencode output
	@echo "Peer config written to config/wireguard/peers/$(PEER).conf"
```

Full implementation uses `linuxserver/wireguard`'s built-in `/app/show-peer` if the peer was pre-declared, or generates a new keypair and registers the peer via `wg set` + `wg-quick save`.

### `make logs`

```makefile
logs:
	@test -n "$(SERVICE)" || (echo "Usage: make logs SERVICE=scenario" && exit 1)
	$(COMPOSE) logs -f $(SERVICE)
```

### `make certs`

Generate the Wazuh OpenSSL PKI chain. Only runs if `config/wazuh/certs/` does not exist (guarded by stamp file). Creates:
- `root-ca.pem` + `root-ca-key.pem` — self-signed root CA
- `wazuh.manager.pem` + key — server cert for manager
- `wazuh.indexer.pem` + key — server cert for indexer (SANs: `wazuh.indexer`, `10.0.0.6`)
- `wazuh.dashboard.pem` + key — server cert for dashboard
- `filebeat.pem` + key — client cert for Filebeat (manager → indexer)
- `admin.pem` + key — admin cert for OpenSearch security plugin

```makefile
certs: config/wazuh/certs/.stamp

config/wazuh/certs/.stamp:
	@mkdir -p config/wazuh/certs
	@echo "Generating Wazuh TLS certificate chain..."
	# openssl commands here (see config/wazuh/README.md for full procedure)
	@touch config/wazuh/certs/.stamp
```

### `make check-prereqs`

Internal target. Fails with a clear message if prerequisites are not met.

```makefile
check-prereqs:
	@test -e /dev/kvm || (echo "ERROR: /dev/kvm not found. KVM required for Windows VMs." && exit 1)
	@groups | grep -q kvm || (echo "ERROR: User not in kvm group. Run: sudo usermod -aG kvm $$USER" && exit 1)
	@groups | grep -q docker || (echo "ERROR: User not in docker group." && exit 1)
	@command -v openssl >/dev/null || (echo "ERROR: openssl not installed." && exit 1)
```

### `.env` auto-creation

```makefile
.env:
	@echo "WARNING: .env not found. Copying from .env.example."
	@echo "Edit .env before running 'make build' or 'make up'."
	@cp .env.example .env
```

---

## .PHONY Declaration

```makefile
.PHONY: build up down reset clean status creds map vpn-config logs certs check-prereqs
```
