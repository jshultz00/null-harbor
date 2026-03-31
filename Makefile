# =============================================================================
# Local Cyber Range — Makefile
# =============================================================================
# First-time setup:
#   make build      ← builds custom Docker images + generates Wazuh certs
#   make up         ← starts everything (~64 GB RAM)
#
# Subsequent runs (Windows disk volumes are preserved on 'make down'):
#   make up         ← fast restart (~1–2 min for Windows VMs)
#   make down       ← stop gracefully, keep all volumes
#   make reset      ← wipe volumes + prune stale networks (prompts for confirmation)
#   make clean      ← nuclear option: volumes + images + force-remove stranded resources
# =============================================================================

COMPOSE   = docker compose
WAZUH_VER = $(shell grep WAZUH_VERSION .env 2>/dev/null | cut -d= -f2 | tr -d ' ')

.PHONY: build up down reset clean status watch events logs certs help

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

up: ## Start the range
	$(COMPOSE) up -d
	@echo ""
	@echo "Waiting 5 s for containers to settle..."
	@sleep 5
	@echo ""
	@$(COMPOSE) ps -a
	@echo ""
	@echo "  Access points:"
	@echo "    Wazuh dashboard : https://localhost"
	@echo "    SOC workstation : http://localhost:8006  (noVNC, then use RDP)"
	@echo "    Scenario SSH    : ssh attacker@localhost -p 2222"
	@echo ""
	@echo "  NOTE: db01, fileserver, exchange, wks-win10, wks-win11 are held"
	@echo "        until DC01 passes its health check (~25 min on first boot)."
	@echo "  Windows VMs take 15-90 min on first boot (OS install)."
	@echo "  Run 'make watch' to stream infrastructure logs."

down: ## Stop the range gracefully (Windows disk volumes are preserved)
	$(COMPOSE) down --remove-orphans
	@echo "Range stopped. Windows disk images preserved. Run 'make up' to restart."

reset: ## Teardown + wipe all volumes (Windows disks, Wazuh data) + prune stale networks
	@echo "WARNING: This will destroy all Windows disk images and Wazuh data."
	@read -p "Are you sure you want to wipe all volumes? [y/N] " confirm && [ "$$confirm" = "y" ]
	-$(COMPOSE) down -v --remove-orphans
	@echo "Pruning stale Docker networks..."
	-docker network ls --filter "name=cyber-range" --format "{{.ID}}" | xargs -r docker network rm
	-docker network prune -f
	@echo "Reset complete. Run 'make build && make up' to rebuild from scratch."

clean: ## Nuclear cleanup — wipe volumes, images, AND force-remove any stranded resources
	@echo "WARNING: This destroys all containers, volumes, networks, AND built images."
	@echo "         You will need to run 'make build && make up' afterwards."
	@read -p "Are you sure you want to destroy everything? [y/N] " confirm && [ "$$confirm" = "y" ]
	@echo "--- Stopping compose stack ---"
	-$(COMPOSE) down -v --remove-orphans 2>/dev/null || true
	@echo "--- Force-removing any stray cyber-range containers ---"
	-docker ps -aq --filter "label=com.docker.compose.project=cyber-range" | xargs -r docker rm -f
	@echo "--- Removing cyber-range networks ---"
	-docker network ls --filter "name=cyber-range" --format "{{.ID}}" | xargs -r docker network rm
	-docker network prune -f
	@echo "--- Removing cyber-range volumes ---"
	-docker volume ls --filter "name=cyber-range" --format "{{.Name}}" | xargs -r docker volume rm
	@echo "--- Removing locally built images ---"
	-docker images --filter "reference=cyber-range/*:local" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi -f
	@echo ""
	@echo "Clean complete. Run 'make build && make up' to rebuild from scratch."

# ── Observability ─────────────────────────────────────────────────────────────

status: ## Show all container statuses including exited/crashed
	$(COMPOSE) ps -a

watch: ## Stream logs from core infrastructure containers (Ctrl-C to stop)
	$(COMPOSE) logs -f fw-core fw-dmz router scenario wazuh.manager

events: ## Stream low-level Docker events for this project (start/die/restart)
	docker events --filter "label=com.docker.compose.project=cyber-range"

logs: ## Tail logs for a specific service  [SVC=service-name]
	$(COMPOSE) logs -f $(SVC)

# ── Utilities ─────────────────────────────────────────────────────────────────

shell: ## Open a shell in a running service  [SVC=service-name]
	$(COMPOSE) exec $(SVC) bash

scenario-ssh: ## SSH into the scenario (Kali) container as attacker
	ssh -o StrictHostKeyChecking=no -p 2222 attacker@localhost
