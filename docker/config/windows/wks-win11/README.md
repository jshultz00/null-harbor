# config/windows/wks-win11/ — Windows 11 Workstation Setup

wks-win11 is a Windows 11 Pro workstation (23H2) domain-joined to `secure.net`. It provides a second user-segment endpoint for multi-machine lateral movement scenarios. Primary user is `bwilson` (Finance department).

**Control IP:** 10.0.0.102  
**Users segment IP:** 10.30.30.30  
**Hostname:** wks-win11  
**Primary user:** SECURE\bwilson (Finance user — lower privilege, credential phishing target)

---

## Files

| File | Purpose |
|------|---------|
| `unattend.xml` | Unattended Windows 11 installation |
| `setup.ps1` | Three-stage workstation setup |

---

## Key Differences from wks-win10

| Aspect | wks-win10 | wks-win11 |
|--------|-----------|-----------|
| OS | Windows 10 22H2 | Windows 11 23H2 |
| Primary user | jsmith (Domain Admin) | bwilson (Finance, low-priv) |
| Primary purpose | High-value credential target | Phishing/initial access endpoint |
| Credential artifacts | Admin password files, PS history | Browser-saved passwords (simulated), Outlook cached creds |

---

## setup.ps1 — Stage 1: Windows 11 Specifics

```powershell
# Windows 11 requires TPM 2.0 bypass for virtualized environments
# dockur/windows handles this via registry workarounds in the base image

# Disable Windows 11 "first run" experience
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" `
    -Name "ScoobeSystemSettingEnabled" -Value 0

# Taskbar customization (minor — makes the desktop look more "corporate")
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "TaskbarAl" -Value 0  # Left-align taskbar
```

### Simulated Browser Credential Store

```powershell
# Place a JSON file simulating Chrome's Login Data (SQLite) format with saved passwords
# Actual Chrome credential extraction scenarios will target this artifact
# In a real scenario: attacker runs SharpChrome or similar against bwilson's profile
$chromePath = "C:\Users\bwilson\AppData\Local\Google\Chrome\User Data\Default"
New-Item -ItemType Directory -Path $chromePath -Force
# Placeholder Login Data SQLite file with encrypted credentials baked in
# (pre-encrypted with bwilson's DPAPI key — requires DPAPI decryption to read)
Invoke-WebRequest "http://10.0.0.1:8000/tools/chrome-login-data-sample" `
    -OutFile "$chromePath\Login Data"
```

### Finance Share Access Artifacts

```powershell
# bwilson's recent documents point to Finance share (creates MRU registry artifacts)
$recentDocs = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs"
# Registry entries pointing to \\fileserver\Finance$\Reports\Q4-2024-Financial-Report.xlsx
```

---

## setup.ps1 — Stage 2: Wazuh + Saffron

Same as wks-win10. Wazuh on wks-win11 captures:
- Security event log
- Microsoft-Windows-Sysmon/Operational (if deployed)
- PowerShell/Operational log (script block logging)
