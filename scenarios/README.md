# scenarios/ — Attack/Defense Training Scenarios

Each subdirectory is a self-contained scenario. Scenarios are executed by `bin/range-scenario` which reads the `manifest.yaml` and runs phase scripts sequentially on the scenario container.

---

## Directory Structure per Scenario

```
scenarios/<slug>/
├── manifest.yaml        # Scenario metadata, phases list, target IPs, MITRE tags
├── env_vars.sh          # Shell variable exports for all parameterized values
├── phases/              # One bash script per phase
│   ├── 01_<name>.sh
│   ├── 02_<name>.sh
│   └── ...
├── attacker_files/      # Payloads, wordlists, helper scripts
│   ├── payload.py
│   └── passwords.txt
└── README.md            # Trainer guide + blue team brief
```

---

## Available Scenarios

| Slug | Status | Difficulty | MITRE Techniques |
|------|--------|-----------|-----------------|
| `_template` | Structural reference | — | — |

> Actual attack scenarios are deferred post-v1 infrastructure build. The `_template/` directory defines the schema and authoring conventions.

---

## manifest.yaml Schema

```yaml
name:        "Human-Readable Scenario Name"
slug:        "scenario-slug"              # Must match directory name
version:     "1.0.0"
description: "One paragraph scenario summary"
difficulty:  easy | medium | hard | expert
duration:    "45 minutes"                 # Estimated exercise time

mitre:
  - technique: "T1190"                   # Exploit Public-Facing Application
    name:       "Initial Access"
  - technique: "T1059.001"
    name:       "PowerShell"

targets:
  scenario:    "10.0.0.1"                # Must match machine control IPs
  web-lin:     "10.10.10.10"
  wks-win10:   "10.30.30.20"

required_env:
  - ATTACKER_IP
  - TARGET_WEB_LIN
  - TARGET_WKS_WIN10

phases:
  - slug:        "01_recon"
    name:        "Reconnaissance"
    description: "OSINT and external port scanning"
    script:      "phases/01_recon.sh"
    delay_after: 30                      # Seconds to wait after phase completes
    trainer_note: "Wait until defenders acknowledge port scan in Wazuh before continuing"

  - slug:        "02_initial_access"
    name:        "Initial Access"
    description: "Exploit CVE-XXXX-XXXX mod_cgi RCE on web-lin"
    script:      "phases/02_initial_access.sh"
    delay_after: 60

  # ... additional phases
```

---

## env_vars.sh Convention

```bash
#!/usr/bin/env bash
# env_vars.sh — All scenario-specific variables
# Sourced by range-scenario before phase execution

# Saffron server (inherited from environment; override if needed)
export COMMANDLY_SERVER="${COMMANDLY_SERVER:-http://10.0.0.1:8080}"

# Attacker source IPs (for SNAT toggling)
export ATTACKER_IP_PHASE1="9.53.99.10"
export ATTACKER_IP_PHASE2="185.220.101.47"   # Tor exit node IP for realism
export ATTACKER_IP_PHASE3="45.33.32.156"     # Known offensive infrastructure IP

# Target IPs (from network map — never hardcode in phase scripts)
export TARGET_WEB_LIN="10.10.10.10"
export TARGET_WKS_WIN10="10.30.30.20"
export TARGET_DC01="10.20.20.100"

# Payload names
export PAYLOAD_NAME="update.py"
export WEBSHELL_NAME="health.php"

# Credentials (for scenarios that use known creds)
export TARGET_USER="jsmith"
export TARGET_PASS="${RANGE_PASSWORD:-P@55w0rd!}"
```

---

## Phase Script Convention

```bash
#!/usr/bin/env bash
# phases/01_recon.sh
# Phase 1: External reconnaissance
# Depends on: env_vars.sh (sourced by range-scenario before exec)

set -euo pipefail

echo "[Phase 1] Starting external reconnaissance of ${TARGET_WEB_LIN}"

# Set attacker IP alias for this phase
ip addr add "${ATTACKER_IP_PHASE1}/24" dev eth1 label eth1:phase1 2>/dev/null || true

# Port scan
nmap -sS -sV -p 22,80,443,8080,8443 "${TARGET_WEB_LIN}" -oN /tmp/recon-nmap.txt

# Report
echo "[Phase 1] Recon complete. Results at /tmp/recon-nmap.txt"
```

Phase scripts must be:
- **Self-contained:** All dependencies come from `env_vars.sh` or the Kali image
- **Idempotent:** Running the same phase twice should not break the scenario state
- **Fast-fail:** Use `set -euo pipefail`; a failed tool exits the phase with non-zero

---

## Scenario README Format

Each `scenarios/<slug>/README.md` has two sections:

### Trainer Guide (full attack path — keep confidential from participants)

Describes what each phase does from the attacker's perspective. Includes expected Wazuh alerts, expected SIEM signatures, and what defensive actions the trainer should watch for.

### Blue Team Brief (what participants receive at exercise start)

Describes the scenario from the defender's perspective — what they're told happened, what systems are in scope, what their job is. Does not reveal the attack path or IOCs.
