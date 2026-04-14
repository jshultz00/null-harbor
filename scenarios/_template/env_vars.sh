#!/usr/bin/env bash
# env_vars.sh — Scenario Environment Variables Template
# This file is sourced by bin/range-scenario before any phase is executed.
# All variables exported here are available inside phase scripts.
#
# CONVENTION: Never hardcode IPs or passwords directly in phase scripts.
#             Define them here and reference them as $VARIABLE_NAME.

# ---------------------------------------------------------------------------
# Saffron (OOB management)
# ---------------------------------------------------------------------------
# Inherited from container environment; override here only if needed
export COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.0.0.1:8080}"

# ---------------------------------------------------------------------------
# Attacker source IPs (per phase — use SNAT at fw-dmz or IP aliases)
# ---------------------------------------------------------------------------
# Define one per phase that needs a distinct attacker identity.
# range-scenario does not automatically set these — phase scripts must
# configure ip aliases or SNAT rules themselves using these values.
export ATTACKER_IP_PHASE1="5.79.99.10"
# export ATTACKER_IP_PHASE2="185.220.101.47"   # Example: Tor exit node
# export ATTACKER_IP_PHASE3="45.33.32.156"     # Example: known offensive infra

# ---------------------------------------------------------------------------
# Target machine IPs
# ---------------------------------------------------------------------------
# Use these variables in phase scripts instead of hardcoded IPs.
# These must match the values in manifest.yaml targets section.
# export TARGET_WEB_LIN="10.10.10.10"
# export TARGET_WEB_WIN="10.10.10.12"
# export TARGET_DC01="10.20.20.100"
# export TARGET_EXCHANGE="10.20.20.10"
# export TARGET_FILESERVER="10.20.20.20"
# export TARGET_DB01="10.40.40.10"
# export TARGET_WKS_LINUX="10.30.30.10"
# export TARGET_WKS_WIN10="10.30.30.20"
# export TARGET_WKS_WIN11="10.30.30.30"

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
# Inherit default range password from environment; scenarios can override
export RANGE_PASSWORD="${RANGE_PASSWORD:-P@55w0rd!}"
# export TARGET_USER="jsmith"
# export TARGET_DOMAIN="secure.net"

# ---------------------------------------------------------------------------
# Payload / file names
# ---------------------------------------------------------------------------
# Consistent names across phases (upload, check, cleanup all use same name)
# export PAYLOAD_NAME="update.py"
# export WEBSHELL_NAME="health.php"
# export PERSISTENCE_NAME="systemd-timesyncd-helper"
