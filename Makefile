# =============================================================================
# Local Cyber Range — Makefile
# =============================================================================
# First-time setup:
#   make build      ← builds custom Docker images + generates Wazuh certs
#   make up         ← starts the core profile (~20 GB RAM)
#
# Subsequent runs (Windows disk volumes are preserved on 'make down'):
#   make up         ← fast restart (~1–2 min for Windows VMs)
#   make down       ← stop, keep volumes
#   make reset      ← full teardown including Windows disk images
# =============================================================================

PROFILE  ?= core
COMPOSE   = docker compose
WAZUH_VER = $(shell grep WAZUH_VERSION .env 2>/dev/null | cut -d= -f2 | tr -d ' ')

.PHONY: build up down reset status logs certs help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# ── Build ─────────────────────────────────────────────────────────────────────

build: certs ## Build all custom images and generate Wazuh certificates
	$(COMPOSE) build
	@echo ""
	@echo "Build complete. Run 'make up' to start the range."

certs: ## Generate Wazuh TLS certificates (skipped if already present)
	@mkdir -p config/wazuh/certs
	@if [ ! -f config/wazuh/certs/root-ca.pem ]; then \
		echo "Generating Wazuh PKI certificates (requires openssl)..."; \
		openssl genrsa -out config/wazuh/certs/root-ca-key.pem 4096 2>/dev/null; \
		openssl req -new -x509 -days 3650 \
			-subj "/O=CyberRange/CN=Wazuh-CA" \
			-key config/wazuh/certs/root-ca-key.pem \
			-out config/wazuh/certs/root-ca.pem 2>/dev/null; \
		for node in wazuh.indexer wazuh.manager wazuh.dashboard admin; do \
			openssl genrsa -out config/wazuh/certs/$${node}-key.pem 4096 2>/dev/null; \
			openssl req -new \
				-subj "/O=CyberRange/CN=$${node}" \
				-key config/wazuh/certs/$${node}-key.pem \
				-out config/wazuh/certs/$${node}.csr 2>/dev/null; \
			openssl x509 -req -days 3650 \
				-CA config/wazuh/certs/root-ca.pem \
				-CAkey config/wazuh/certs/root-ca-key.pem \
				-CAcreateserial \
				-in config/wazuh/certs/$${node}.csr \
				-out config/wazuh/certs/$${node}.pem 2>/dev/null; \
			rm -f config/wazuh/certs/$${node}.csr; \
			chmod 600 config/wazuh/certs/$${node}-key.pem; \
		done; \
		echo "Certificates generated in config/wazuh/certs/"; \
	else \
		echo "Wazuh certificates already present, skipping."; \
	fi

# ── Lifecycle ─────────────────────────────────────────────────────────────────

up: ## Start the range  [PROFILE=core|web-attack|full]
	$(COMPOSE) --profile $(PROFILE) up -d
	@echo ""
	@echo "Range starting with profile: $(PROFILE)"
	@echo "  Wazuh dashboard : https://localhost"
	@echo "  SOC workstation : http://localhost:8006  (noVNC, then use RDP)"
	@echo "  Scenario SSH    : ssh root@localhost -p 2222"
	@echo ""
	@echo "Windows VMs take 15–90 min on first boot (OS install)."
	@echo "Run 'make status' to monitor container health."

down: ## Stop the range (Windows disk volumes are preserved)
	$(COMPOSE) down
	@echo "Range stopped. Windows disk images preserved. Run 'make up' to restart."

reset: ## Full teardown — destroys all containers, networks, and disk volumes
	@echo "WARNING: This will destroy all Windows disk images and Wazuh data."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	$(COMPOSE) down -v
	@echo "Reset complete. Run 'make build && make up' to rebuild from scratch."

# ── Observability ─────────────────────────────────────────────────────────────

status: ## Show container status and health
	$(COMPOSE) ps

logs: ## Tail logs for a service  [SVC=service-name]
	$(COMPOSE) logs -f $(SVC)

# ── Utilities ─────────────────────────────────────────────────────────────────

shell: ## Open a shell in a running service  [SVC=service-name]
	$(COMPOSE) exec $(SVC) bash

scenario-ssh: ## SSH into the scenario (Kali) container
	ssh -o StrictHostKeyChecking=no -p 2222 root@localhost
