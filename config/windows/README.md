# config/windows/ — Windows VM Unattended Setup

This directory contains per-machine `unattend.xml` and `setup.ps1` files for all Windows VMs. These files are served over HTTP by the scenario container on port 8000 and downloaded by each VM during first boot.

---

## How It Works

`dockur/windows` supports a `SETUP_URL` or `SETUP_SERVER` environment variable that points to a PowerShell script. On first boot, after Windows completes GUI setup, `dockur/windows` downloads and runs this script. For this range:

```
SETUP_SERVER=http://10.0.0.1:8000
```

Each VM downloads:
```
http://10.0.0.1:8000/windows/<machine>/setup.ps1
```

The scenario container (10.0.0.1) serves the `config/windows/` directory on port 8000 using a simple Python HTTP server or Caddy.

---

## Three-Stage Setup Pattern

All Windows VMs follow the same three-stage pattern. Each stage is separated by a reboot. `setup.ps1` uses a stage marker file (`C:\range-setup-stage.txt`) to determine which stage to run:

```
Stage 0 (first run):  Base configuration, rename computer, join domain (or promote to DC for dc01)
                      → Reboot → Stage 1
Stage 1:              Install roles/features, configure services (IIS, Exchange, etc.)
                      → Reboot → Stage 2
Stage 2:              Finalize, install Wazuh agent, install Saffron service, signal completion
                      → Done
```

The `setup.ps1` checks `$env:COMPUTERNAME` to confirm it ran on the correct machine as a sanity check.

---

## Common setup.ps1 Sections (All VMs)

### Stage 0 — Base Config

```powershell
# Set static IP (machines start with DHCP from dockur/windows, then switch to static)
New-NetIPAddress -InterfaceAlias "Ethernet" `
    -IPAddress <machine-control-ip> -PrefixLength 24 `
    -DefaultGateway 10.0.0.254
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.20.20.100,8.8.8.8

# Domain join (non-DC machines only)
$cred = New-Object System.Management.Automation.PSCredential(
    "SECURE\Administrator",
    (ConvertTo-SecureString $env:RANGE_PASSWORD -AsPlainText -Force)
)
Add-Computer -DomainName "secure.net" -Credential $cred -Restart -Force
```

### Stage 2 — Wazuh Agent Install

```powershell
# Download Wazuh agent MSI from scenario container (http://10.0.0.1:8000/tools/wazuh-agent.msi)
Invoke-WebRequest -Uri "http://10.0.0.1:8000/tools/wazuh-agent.msi" -OutFile "C:\wazuh-agent.msi"
msiexec /i C:\wazuh-agent.msi WAZUH_MANAGER="10.0.0.5" WAZUH_REGISTRATION_PASSWORD="<PSK>" /qn /norestart
Start-Service -Name "WazuhSvc"
```

### Stage 2 — Saffron Service Install

```powershell
# Download Saffron Windows agent from scenario container
Invoke-WebRequest -Uri "http://10.0.0.1:8000/tools/saffron-agent-windows-amd64.exe" `
    -OutFile "C:\saffron\saffron.exe"

# Install as Windows service
New-Service -Name "SaffronAgent" `
    -BinaryPathName "C:\saffron\saffron.exe --server http://10.0.0.1:8080 --hostname $env:COMPUTERNAME" `
    -StartupType Automatic `
    -Description "Saffron range management agent"
Start-Service SaffronAgent
```

---

## Per-Machine Subdirectories

| Directory | VM | Key Setup Tasks |
|-----------|----|----|
| `dc01/` | Domain Controller | AD DS install + promotion, AD CS ESC1/4/8, users, GPOs |
| `exchange/` | Exchange 2019 | Exchange install on WS2022, mailboxes, connectors |
| `fileserver/` | File Server | DFS shares, permissions, ransomware-bait files |
| `web-win/` | Windows Web Server | IIS + ASPX app, service account |
| `wks-win10/` | Windows 10 WS | Domain join, user profiles, Office-like apps |
| `wks-win11/` | Windows 11 WS | Domain join, user profiles |

See each machine's README for detailed stage-by-stage setup instructions.
