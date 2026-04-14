#!/usr/bin/env bash
# phases/01_template.sh — Template Phase Script
#
# This script is executed inside the scenario container by bin/range-scenario via:
#   docker exec scenario bash /tmp/01_template.sh
#
# All variables from env_vars.sh are available because range-scenario sources
# env_vars.sh and passes the environment when calling docker exec.
#
# CONVENTIONS:
#   - Use set -euo pipefail for fail-fast behavior
#   - Echo progress markers so range-scenario can log phase output
#   - Clean up temporary files at the end of each phase
#   - Set/remove IP aliases at start/end of phase if using per-phase attacker IPs
#   - Use * scripts (from COMMANDLY_SERVER) for all remote machine interactions
#   - Do not use docker exec directly from inside a phase script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Phase Setup
# ---------------------------------------------------------------------------
echo "[01_template] Phase starting"
echo "[01_template] Attacker IP: ${ATTACKER_IP_PHASE1}"

# Set attacker IP alias for this phase (within 5.79.99.0/24)
# For IPs outside this range, use SNAT at fw-dmz instead:
#   runcmd.bash fw-dmz "nft flush chain ip nat SCENARIO_SNAT"
#   runcmd.bash fw-dmz "nft add rule ip nat SCENARIO_SNAT ip saddr 5.79.99.1 oifname eth2 snat to ${ATTACKER_IP_PHASE1}"
ip addr add "${ATTACKER_IP_PHASE1}/24" dev eth1 label eth1:phase1 2>/dev/null || true

# ---------------------------------------------------------------------------
# Phase Actions — Replace this section with actual attack steps
# ---------------------------------------------------------------------------
echo "[01_template] Running phase actions..."

# Example: run a command on a remote machine via Saffron
# source /usr/bin/runcmd.bash  (or use full path)
# runcmd.bash "${TARGET_WEB_LIN}" "id"

# Example: copy a file to a remote machine
# copytoremote.bash "${TARGET_WEB_LIN}" "${SCRIPT_DIR}/../attacker_files/payload.py" /tmp/payload.py

# Example: check if a file exists on a remote machine (returns 0/1)
# checkfile.bash "${TARGET_WEB_LIN}" /tmp/payload.py 10

echo "[01_template] Phase actions complete"

# ---------------------------------------------------------------------------
# Phase Teardown
# ---------------------------------------------------------------------------
# Remove IP alias (next phase sets its own alias)
ip addr del "${ATTACKER_IP_PHASE1}/24" dev eth1 label eth1:phase1 2>/dev/null || true

echo "[01_template] Phase complete"
exit 0
