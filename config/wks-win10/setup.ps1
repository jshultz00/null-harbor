# wks-win10 Setup Script — Windows 10 Domain Workstation
# Mounted as A:\setup.ps1 — no download from scenario

$ErrorActionPreference = "Continue"
Write-Host "[wks-win10] Starting setup at $(Get-Date)"

if (-not (Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain) {
    $cred = New-Object System.Management.Automation.PSCredential(
        "SECURE\Administrator", (ConvertTo-SecureString "Password1!" -AsPlainText -Force))
    for ($i = 1; $i -le 20; $i++) {
        try { Add-Computer -DomainName "secure.net" -Credential $cred -Force -ErrorAction Stop; break }
        catch { Write-Host "  Attempt $i failed — retrying in 60s..."; Start-Sleep 60 }
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
        -Name "WksWin10Continue" -Value 'cmd.exe /c start /wait powershell -ExecutionPolicy Bypass -File A:\setup.ps1'
    Restart-Computer -Force; exit
}

Write-Host "[wks-win10] Domain joined. Configuring workstation..."

# Enable RDP and add Domain Users to Remote Desktop Users
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" `
    -Name "fDenyTSConnections" -Value 0 -Type DWord -Force
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "SECURE\Domain Users" -ErrorAction SilentlyContinue

# Disable SMB signing
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManWorkstation\Parameters" `
    -Name "RequireSecuritySignature" -Value 0 -Type DWord -Force

# Enable LLMNR/NBNS (Responder target)
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "EnableMulticast" -Value 1 -Type DWord -Force

# Local admin account and credential loot (scenario targets)
net user localadmin Password1! /add /fullname:"Local Admin" /comment:"IT support account" 2>$null
net localgroup Administrators localadmin /add 2>$null
cmdkey /add:dc01.secure.net /user:SECURE\Administrator /pass:Password1!
cmdkey /add:fileserver.secure.net /user:SECURE\jsmith /pass:Password1!

# ── OpenSSH Server ────────────────────────────────────────────────────────────
Write-Host "[wks-win10] Enabling OpenSSH Server..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
Set-Service sshd -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service sshd -ErrorAction SilentlyContinue
$sshdConfig = "$env:ProgramData\ssh\sshd_config"
if (Test-Path $sshdConfig) {
    $cfg = Get-Content $sshdConfig
    $cfg = $cfg -replace 'PasswordAuthentication no', 'PasswordAuthentication yes'
    $cfg = $cfg -replace '#PasswordAuthentication yes', 'PasswordAuthentication yes'
    $cfg | Set-Content $sshdConfig
    Restart-Service sshd -ErrorAction SilentlyContinue
}

# ── SMB (v1 + v2 for lateral movement and relay scenarios) ────────────────────
Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue
Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue
Set-Service LanmanServer -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service LanmanServer -ErrorAction SilentlyContinue

try {
    Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.2-1.msi" `
        -OutFile "C:\wazuh-agent.msi" -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i C:\wazuh-agent.msi /quiet WAZUH_MANAGER=172.16.0.5 WAZUH_REGISTRATION_SERVER=172.16.0.5 WAZUH_REGISTRATION_PASSWORD=cyberrange-psk-2024 WAZUH_AGENT_NAME=wks-win10" -Wait
} catch { }

Write-Host "[wks-win10] Clearing event logs..."
wevtutil el 2>$null | ForEach-Object { wevtutil cl "$_" 2>$null }
$wazuhBase = "C:\Program Files (x86)\ossec-agent"
Remove-Item "$wazuhBase\queue\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$wazuhBase\logs\*"  -Recurse -Force -ErrorAction SilentlyContinue
Start-Service WazuhSvc -ErrorAction SilentlyContinue
Remove-Item "C:\wazuh-agent.msi" -Force -ErrorAction SilentlyContinue
Write-Host "[wks-win10] Setup complete at $(Get-Date)"
