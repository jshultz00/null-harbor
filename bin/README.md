# bin/ — Control Scripts

This directory contains the two primary operator-facing scripts. Neither script requires a web server or daemon — they are self-contained bash programs that wrap Makefile targets and Docker commands.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `range` | Interactive TUI shell menu — the primary human interface for the range |
| `range-scenario` | Scenario runner — reads `manifest.yaml`, executes phases on the scenario container |

---

## Usage

### Starting the range (TUI)

```bash
./bin/range
```

Presents an interactive menu. Fzf is used if available; falls back to bash `select`.

### Running a scenario directly

```bash
# Dry run — print all phases without executing
./bin/range-scenario --dry-run scenarios/apache-mass-defacement

# Execute a specific phase only
./bin/range-scenario --phase 02_lateral_movement scenarios/apache-mass-defacement

# Full execution
./bin/range-scenario scenarios/apache-mass-defacement

# Reset scenario artifacts
./bin/range-scenario --reset scenarios/apache-mass-defacement
```

---

## Dependencies

Both scripts require:
- `bash` 4.0+
- `docker` CLI available on PATH
- `make` available on PATH
- The range to be running (`make up` completed)

`range` additionally uses `fzf` for the scenario picker if installed. Falls back to `bash select` if not.

`range-scenario` requires either `python3` with `pyyaml` or `yq` (Go binary) to parse `manifest.yaml`. Checks for both at startup and errors clearly if neither is present.

See [range.md](range.md) and [range-scenario.md](range-scenario.md) for full implementation specs.
