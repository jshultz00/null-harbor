# =============================================================================
# fileserver Setup Script — SMB File Server (intentionally vulnerable)
# Mounted as A:\setup.ps1 — runs locally, no network download from scenario
# =============================================================================

$ErrorActionPreference = "Continue"
Write-Host "[fileserver] Starting setup at $(Get-Date)"

# ── Domain join ───────────────────────────────────────────────────────────────
if (-not (Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain) {
    Write-Host "[fileserver] Joining domain secure.net..."
    $cred = New-Object System.Management.Automation.PSCredential(
        "SECURE\Administrator",
        (ConvertTo-SecureString "P@55w0rd!" -AsPlainText -Force)
    )
    for ($i = 1; $i -le 20; $i++) {
        try {
            Add-Computer -DomainName "secure.net" -Credential $cred -Force -ErrorAction Stop
            Write-Host "  Domain join successful"
            break
        } catch { Start-Sleep 60 }
    }
    # A:\setup.ps1 is always available — no download on reboot
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
        -Name "FileServerContinue" `
        -Value 'cmd.exe /c start /wait powershell -ExecutionPolicy Bypass -File A:\setup.ps1'
    Restart-Computer -Force
    exit
}

Write-Host "[fileserver] Domain joined. Configuring file server..."

# ── File Services role ────────────────────────────────────────────────────────
Install-WindowsFeature -Name FS-FileServer, FS-SMB1 -IncludeManagementTools

# ── Create shares with weak permissions ───────────────────────────────────────
$shares = @(
    @{Name="Finance";  Path="C:\Shares\Finance";  Desc="Finance Department Files"},
    @{Name="HR";       Path="C:\Shares\HR";       Desc="Human Resources"},
    @{Name="IT";       Path="C:\Shares\IT";       Desc="IT Department"},
    @{Name="Public";   Path="C:\Shares\Public";   Desc="Company Public Files"},
    @{Name="Scripts";  Path="C:\Shares\Scripts";  Desc="Login Scripts"}
)
foreach ($share in $shares) {
    New-Item -Path $share.Path -ItemType Directory -Force | Out-Null
    New-SmbShare -Name $share.Name -Path $share.Path `
        -Description $share.Desc -FullAccess "Everyone" -ErrorAction SilentlyContinue
}

# Realistic loot files
"Q4 2024 Projections - CONFIDENTIAL" | Out-File "C:\Shares\Finance\Q4-2024-projections.txt"
"Username,Password`njsmith,P@55w0rd!`nmjones,P@55w0rd!" | Out-File "C:\Shares\HR\employee-credentials-backup.csv"
"# Admin credentials`n# DC01: Administrator / P@55w0rd!" | Out-File "C:\Shares\IT\admin-notes.txt"
"net use Z: \\dc01\sysvol /persistent:yes" | Out-File "C:\Shares\Scripts\logon.bat"

# ── PrintNightmare (CVE-2021-34527) ───────────────────────────────────────────
Set-Service -Name Spooler -StartupType Automatic
Start-Service -Name Spooler
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers" `
    -Name "RegisterSpoolerRemoteRpcEndPoint" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

# ── Disable SMB signing (NTLM relay target) ───────────────────────────────────
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
    -Name "RequireSecuritySignature" -Value 0 -Type DWord -Force
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManWorkstation\Parameters" `
    -Name "RequireSecuritySignature" -Value 0 -Type DWord -Force

# ── OpenSSH Server ────────────────────────────────────────────────────────────
Write-Host "[fileserver] Enabling OpenSSH Server..."
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

# ── SMB protocol explicit enablement (feature installed above as FS-SMB1) ─────
Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue
Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue
Set-Service LanmanServer -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service LanmanServer -ErrorAction SilentlyContinue

# ── Wazuh agent ───────────────────────────────────────────────────────────────
try {
    Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.2-1.msi" `
        -OutFile "C:\wazuh-agent.msi" -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i C:\wazuh-agent.msi /quiet WAZUH_MANAGER=172.16.0.5 WAZUH_REGISTRATION_SERVER=172.16.0.5 WAZUH_REGISTRATION_PASSWORD=cyberrange-psk-2024 WAZUH_AGENT_NAME=fileserver" -Wait
} catch { Write-Host "[fileserver] Wazuh: $_" }

# ── Clear event logs for clean SIEM baseline ─────────────────────────────────
Write-Host "[fileserver] Clearing event logs..."
wevtutil el 2>$null | ForEach-Object { wevtutil cl "$_" 2>$null }
$wazuhBase = "C:\Program Files (x86)\ossec-agent"
Remove-Item "$wazuhBase\queue\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$wazuhBase\logs\*"  -Recurse -Force -ErrorAction SilentlyContinue
Start-Service WazuhSvc -ErrorAction SilentlyContinue

Remove-Item "C:\wazuh-agent.msi" -Force -ErrorAction SilentlyContinue
Write-Host "[fileserver] Setup complete at $(Get-Date)"
