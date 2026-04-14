# _template/ — Scenario Authoring Template

This directory is the structural reference for creating new scenarios. It contains blank files with inline comments explaining every field. Copy this entire directory to `scenarios/<your-slug>/` and fill in the blanks.

```bash
cp -r scenarios/_template scenarios/my-new-scenario
cd scenarios/my-new-scenario
$EDITOR manifest.yaml
```

---

## Files in This Directory

| File | Purpose |
|------|---------|
| `manifest.yaml` | Scenario metadata and phase list — schema reference with all fields documented |
| `env_vars.sh` | Shell variable template — all parameterized values |
| `phases/01_template.sh` | Single blank phase script showing conventions and helper functions |
| `attacker_files/.gitkeep` | Placeholder — add payloads, wordlists, helper scripts here |
| `README.md` | This file — also serves as the README template for new scenarios |

---

## Authoring Checklist

Before running a new scenario, verify:

- [ ] `manifest.yaml` has a unique `slug` matching the directory name
- [ ] All machines in `targets` are running (`listclients.bash` shows them connected)
- [ ] `env_vars.sh` exports all variables listed in `required_env`
- [ ] Each phase script exits 0 on success
- [ ] `bin/range-scenario --dry-run scenarios/<slug>` runs cleanly
- [ ] Phase 1 sets up the attacker IP alias or SNAT rule
- [ ] Last phase (or `--reset`) cleans up: removes IP aliases, flushes SNAT chain, removes persistence artifacts
- [ ] `README.md` has both a Trainer Guide and a Blue Team Brief section

---

## Scenario Design Principles

1. **Each phase is independent** — a phase script should be runnable in isolation if the environment is in the right state. Do not carry bash variables between phases; use `env_vars.sh` for all shared state.

2. **Realistic dwell time** — use `delay_after` in the manifest to simulate realistic attacker timing. Defenders should have time to detect each phase before the next begins.

3. **Vary attacker IPs** — use `ATTACKER_IP_PHASE1`, `ATTACKER_IP_PHASE2`, etc. in `env_vars.sh` and switch via IP alias or SNAT so defenders don't just blocklist a single IP.

4. **Trainers note fields** — use `trainer_note` in the manifest for guidance that should only appear in the runner output (not sent to the scenario container). Example: "Pause here — wait for blue team to acknowledge the Wazuh alert before proceeding."

5. **Always have a reset phase** — the last phase (or a dedicated `--reset` script) must clean up all artifacts: removed persistence, flushed nftables rules, deleted uploaded files. This ensures `make reset` alone isn't required between runs.
