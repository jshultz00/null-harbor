# config/windows/wks-win10/ — Windows 10 Workstation Setup

wks-win10 is a Windows 10 Pro workstation (22H2) domain-joined to `secure.net`. It represents a standard corporate endpoint and is the primary blue team access point for Windows forensics, EDR analysis, and credential harvesting scenarios.

**Control IP:** 10.0.0.101  
**Users segment IP:** 10.30.30.20  
**Hostname:** wks-win10  
**Primary user:** SECURE\jsmith (domain admin — high-value credential target)

---

## Files

| File | Purpose |
|------|---------|
| `unattend.xml` | Unattended Windows 10 installation |
| `setup.ps1` | Three-stage workstation setup |

---

## setup.ps1 — Stage 0: Base Config + Domain Join

```powershell
Rename-Computer -NewName "wks-win10" -Force
# Static IPs (control + users segments)
# DNS: 10.20.20.100 (dc01)
# Domain join to secure.net
# Create OU: OU=Workstations,DC=secure,DC=net (if not exists)
# Join OU=Workstations
```

---

## setup.ps1 — Stage 1: User Profiles + Software + Attack Surface

### Create Local User Profiles

Windows does not create roaming profile directories until the user logs in. Stage 1 forces profile creation for domain users by running a logon via `runas` or WMI:

```powershell
# Force profile creation for domain users (so their AppData, Documents exist for scenarios)
$users = @("jsmith", "mjones")
foreach ($user in $users) {
    # Use WMI Win32_Process to run a command as the domain user
    # This creates the profile directory structure under C:\Users\<user>
    Start-Process -FilePath "cmd.exe" `
        -Credential (New-Object PSCredential "SECURE\$user", (ConvertTo-SecureString $env:RANGE_PASSWORD -AsPlainText -Force)) `
        -ArgumentList "/c echo profile created" `
        -NoNewWindow -Wait
}
```

### Windows Defender Exclusions (Training-Only)

Windows Defender is disabled via GPO from dc01. Ensure the Defender GPO has been applied before proceeding. Stage 1 waits and polls:

```powershell
# Wait for GPO to apply Defender disable
$timeout = 300
$elapsed = 0
while ((Get-MpPreference).DisableRealtimeMonitoring -eq $false -and $elapsed -lt $timeout) {
    Start-Sleep 10; $elapsed += 10
}
```

### Credential Artifacts (Intentional — For Scenario Realism)

```powershell
# Place a credentials file in jsmith's Documents (data exfiltration target)
$jsmithDocs = "C:\Users\jsmith\Documents"
Set-Content "$jsmithDocs\server-creds.txt" "db01 SA password: $env:RANGE_PASSWORD`nOLD admin: admin:admin123"

# PowerShell history with interesting commands (DFIR artifact)
$histPath = "C:\Users\jsmith\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
@(
    "net use \\fileserver\Finance$ /user:SECURE\jsmith $env:RANGE_PASSWORD",
    "Invoke-WebRequest http://internal-tools/deploy.ps1 | iex",
    "Get-ADUser -Filter * -Properties *",
    "Set-MpPreference -DisableRealtimeMonitoring \$true"
) | Set-Content $histPath
```

### Mapped Network Drives

```powershell
# Map shares at logon via GPP (Group Policy Preference)
# This is done via the dc01 GPO, not directly here
# Drives mapped:
#   Z: → \\fileserver\Finance$ (for Finance users)
#   Y: → \\fileserver\IT (for IT users)
```

### RDP Configuration

```powershell
# Enable RDP (for participant access)
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
# Allow Domain Users RDP access
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "SECURE\Domain Users"
```

---

## setup.ps1 — Stage 2: Wazuh + Saffron

Wazuh agent on wks-win10 is configured to forward:
- Security event log (logon events 4624/4625/4634, process creation 4688)
- Sysmon events (if Sysmon is installed — optional, adds richer process telemetry)
- PowerShell script block logging events (Event ID 4104)

Saffron service runs as SYSTEM and accepts commands from the scenario container for scenario automation (e.g., running attacker payloads, triggering user actions).
