# www/ — Fake Internet Static Files

This directory is served by Caddy (HTTPS) on the scenario container at `https://9.53.99.1/`. It represents static content for the fake internet — pages, files, and resources that participants or victim machines might fetch from "the internet" during a scenario.

---

## Purpose

During scenarios, the scenario container acts as a mini-internet. DNS resolves external domains to `9.53.99.1` (CoreDNS catch-all). Caddy serves content from `www/` over HTTPS.

Use cases:
- **Malware staging:** Payloads hosted at `https://updates.microsoft.com-cdn.net/patch.exe` (fake domain resolving to 9.53.99.1)
- **Phishing pages:** `https://login.microsoftonline-auth.com/` (fake credential harvesting page)
- **C2 callback verification:** A simple page at `https://c2.attackerco.com/beacon` that returns a 200 OK
- **Windows setup tools:** MSI installers, ZIP files referenced by `setup.ps1` scripts

---

## Structure

```
www/
├── index.html          # Default catch-all page (generic "Service Unavailable" page)
├── tools/              # Tooling binaries served to Windows VMs during setup
│   ├── wazuh-agent.msi                   # Wazuh agent Windows MSI
│   ├── saffron-agent-windows-amd64.exe   # Saffron Windows service
│   ├── vc_redist.x64.exe                 # Visual C++ Redistributable (Exchange prereq)
│   └── UcmaRuntimeSetup.exe              # UCMA 4.0 (Exchange prereq)
└── scenarios/          # Scenario-specific web content (created per scenario)
    └── .gitkeep
```

---

## Caddy HTTPS (Self-Signed)

Caddy uses `tls internal` to generate a self-signed certificate for all vhosts. Windows VMs must trust this CA for HTTPS downloads to succeed. The scenario container's `setup.ps1` bootstrap uses HTTP (port 8000, Python simple server) for initial downloads before the trust chain is established.

For Windows scenarios requiring trusted HTTPS: the Caddy CA cert is exported and imported via `setup.ps1` Stage 0 using HTTP first.

---

## Adding Scenario-Specific Content

Scenario phase scripts use Saffron to write files to the scenario container's `www/` volume:

```bash
# Phase script uploads a payload to the fake internet hosting
cr_copytoremote.bash scenario ./attacker_files/payload.py /srv/www/tools/update.py
```

Or directly via `docker exec`:
```bash
docker exec scenario cp /home/trainer/scenarios/<slug>/attacker_files/payload.py /srv/www/tools/update.py
```
