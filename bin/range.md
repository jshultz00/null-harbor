# bin/range — TUI Control Script Specification

`range` is the primary human interface for the cyber range. It is a bash script that presents an interactive menu wrapping Makefile targets. No daemon, no web server.

---

## Behavior

On launch, the script:
1. Checks that Docker is running (`docker info` exit code 0)
2. Checks that `.env` exists; warns if not
3. Prints range banner and current container status summary (running / total)
4. Presents the main menu

---

## Main Menu

```
╔══════════════════════════════════════╗
║       LOCAL CYBER RANGE              ║
╚══════════════════════════════════════╝

  Range status: 14/17 containers running

  [1] Start Range
  [2] Stop Range
  [3] Reset Range (wipe volumes)
  [4] Run Scenario
  [5] Show Status
  [6] Show Credentials
  [7] Open Network Map
  [8] Generate VPN Config
  [9] Exit

Select:
```

---

## Menu Actions

### [1] Start Range

Calls `make up`. Prints Docker Compose output. After start, prints a reminder about Windows VM first-boot time and suggests running option 5 (status) to monitor.

### [2] Stop Range

Confirms with the user ("Stop the range? Volumes will be preserved. [y/N]") before calling `make down`.

### [3] Reset Range

Prompts with a warning: "WARNING: This will wipe all data volumes. All Windows VM progress will be lost. Type 'reset' to confirm: ". Only proceeds if user types the word `reset` exactly. Calls `make reset`.

### [4] Run Scenario

1. Scans `scenarios/` for directories containing `manifest.yaml`
2. Presents scenario picker:
   - With fzf: `ls scenarios/*/manifest.yaml | xargs ... | fzf --preview ...` showing scenario name, description, difficulty, estimated duration
   - Without fzf: numbered `bash select` list of scenario slugs
3. Once selected, presents sub-menu:
   - `[1] Run full scenario`
   - `[2] Run single phase`
   - `[3] Dry run (print phases only)`
   - `[4] Reset scenario`
   - `[5] Back`
4. Delegates to `bin/range-scenario` with appropriate flags

### [5] Show Status

Calls `make status` and additionally shows:
- Windows VM boot progress (polls `dockur/windows` health endpoint if available)
- Saffron client count: `docker exec scenario cr_listclients.bash 2>/dev/null | wc -l` enrolled agents

### [6] Show Credentials

Calls `make creds`. Output is paged through `less` if terminal height is insufficient.

### [7] Open Network Map

Calls `make map`. On headless hosts, prints the file path instead.

### [8] Generate VPN Config

Prompts: "Participant name: " then calls `make vpn-config PEER=<name>`. Prints the resulting `.conf` file path and QR code.

### [9] Exit

Exits with code 0. Does not stop the range.

---

## Implementation Notes

- Uses `tput` for color output; falls back to plain text if `TERM` is unset
- All Makefile calls use `$(dirname "$0")/../Makefile` resolved via `SCRIPT_DIR` so the script works from any working directory
- Ctrl+C is trapped and presents "Range is still running. Exit anyway? [y/N]"
- Menu re-renders after each action (loop, not one-shot)
