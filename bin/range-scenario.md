# bin/range-scenario — Scenario Runner Specification

`range-scenario` reads a scenario's `manifest.yaml`, sources `env_vars.sh`, and executes phase scripts sequentially via `docker exec` on the scenario (Kali) container. It is the execution engine for all scenario automation.

---

## Usage

```
Usage: range-scenario [OPTIONS] <scenario-dir>

Options:
  --dry-run            Print phases without executing. Exit 0.
  --phase <name>       Execute only the named phase (exact match on phase slug).
  --reset              Run the scenario's cleanup/reset phase if defined in manifest.
  --no-delays          Skip inter-phase delays (useful for testing).
  --verbose            Print each command before executing.

Arguments:
  scenario-dir         Path to scenario directory containing manifest.yaml
                       (e.g., scenarios/apache-mass-defacement)
```

---

## Execution Flow

1. **Validate** `<scenario-dir>/manifest.yaml` exists and is parseable
2. **Parse** manifest: extract phases list, target IPs, required env vars
3. **Source** `<scenario-dir>/env_vars.sh` — exports all scenario-specific variables into current shell
4. **Verify** Saffron connectivity: call `cr_listclients.bash` and check that all machines listed in `manifest.yaml` under `targets` are connected. Warn (not fail) if a target is missing.
5. **Execute** phases in order:
   - Print phase header: `[PHASE 1/5] 01_initial_access — Exploit Apache mod_cgi`
   - Copy phase script to scenario container: `docker cp <scenario-dir>/phases/<script> scenario:/tmp/<script>`
   - Execute: `docker exec scenario bash /tmp/<script>`
   - Check exit code; on non-zero: print error, ask "Continue to next phase? [y/N]"
   - Apply post-phase delay if defined in manifest (skipped with `--no-delays`)
6. **Print** "Scenario complete." on success

---

## manifest.yaml Parsing

`range-scenario` supports two parsers, checked in order:
1. `python3 -c "import yaml; ..."` — uses PyYAML if available
2. `yq` — Go-based YAML processor

If neither is available, the script exits with a clear error message and installation instructions.

Parsed fields used during execution:

```
manifest.name          — displayed in phase headers
manifest.phases[]      — ordered list of phases to execute
  .slug                — identifier for --phase flag matching
  .name                — human-readable phase name
  .description         — printed before execution
  .script              — path relative to scenario dir (e.g., phases/01_access.sh)
  .delay_after         — seconds to wait after phase completes (int, default 0)
  .trainer_note        — printed to terminal only (not sent to scenario container)
manifest.targets       — map of machine-name → IP, checked against Saffron clients
manifest.required_env  — list of env var names that must be non-empty after sourcing env_vars.sh
```

---

## Environment Variable Injection

After sourcing `env_vars.sh`, the following variables are always available to phase scripts (injected by `range-scenario` itself if not already in `env_vars.sh`):

| Variable | Value | Source |
|----------|-------|--------|
| `COMMANDLY_SERVER` | `http://10.0.0.1:8080` | `.env` / environment |
| `SCENARIO_DIR` | Absolute path to scenario directory | Set by runner |
| `SCENARIO_SLUG` | Scenario slug from manifest | Set by runner |
| `PHASE_NUM` | Current phase number (1-indexed) | Set per-phase |
| `PHASE_SLUG` | Current phase slug | Set per-phase |

Phase scripts must not rely on any global state outside of what is in `env_vars.sh` and the above injected variables. Each phase is an independent bash script — it must be executable in isolation.

---

## Error Handling

- Phase script exits non-zero → print exit code, print last 20 lines of output, ask to continue
- `docker exec` fails (container not running) → fatal error, exit 1
- Saffron target not connected → warning only, execution continues
- Missing `required_env` variable → fatal error before any execution begins

---

## Dry Run Output Format

```
Scenario: Apache Mass Defacement
Slug:     apache-mass-defacement
Phases:   5

  [1] 01_recon            — OSINT and port scanning against web-lin
  [2] 02_initial_access   — Exploit CVE-XXXX-XXXX mod_cgi RCE on web-lin
  [3] 03_persistence      — Install reverse shell cron job as www-data
  [4] 04_defacement       — Replace web content with attacker page
  [5] 05_cleanup          — Remove artifacts (trainer use after debrief)

Targets:
  web-lin    → 10.10.10.10
  scenario   → 10.0.0.1

Dry run complete. No commands executed.
```
