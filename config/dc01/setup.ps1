# =============================================================================
# dc01 Setup Script — Primary Domain Controller + AD CS
# Mounted by dockur/windows from /oem/setup.ps1 → available in Windows as A:\setup.ps1
# Runs as: Administrator (FirstLogonCommands / RunOnce)
# =============================================================================

$ErrorActionPreference = "Continue"
$VerbosePreference = "Continue"

Write-Host "[dc01] Starting setup at $(Get-Date)"

# ── Stage detection ────────────────────────────────────────────────────────────
$stage = if (Test-Path "C:\setup-stage2-done.flag") { 3 }
         elseif (Test-Path "C:\setup-stage1-done.flag") { 2 }
         else { 1 }

Write-Host "[dc01] Detected stage: $stage"

# =============================================================================
# STAGE 1 — Install AD DS and promote to Domain Controller
# =============================================================================
if ($stage -eq 1) {
    Write-Host "[dc01] Stage 1: Installing AD DS role..."

    Install-WindowsFeature -Name AD-Domain-Services, RSAT-AD-Tools, RSAT-AD-PowerShell `
        -IncludeManagementTools -IncludeAllSubFeature

    Write-Host "[dc01] Promoting to Domain Controller (creates secure.net)..."
    Import-Module ADDSDeployment

    # Set RunOnce key BEFORE reboot so Stage 2 continues automatically.
    # A:\setup.ps1 is always available (virtual floppy — no network needed).
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
        -Name "CyberRangeStage2" `
        -Value 'cmd.exe /c start /wait powershell -ExecutionPolicy Bypass -File A:\setup.ps1'

    New-Item -Path "C:\setup-stage1-done.flag" -ItemType File -Force

    Install-ADDSForest `
        -DomainName "secure.net" `
        -DomainNetbiosName "SECURE" `
        -DomainMode "WinThreshold" `
        -ForestMode "WinThreshold" `
        -InstallDns:$true `
        -SafeModeAdministratorPassword (ConvertTo-SecureString "Password!" -AsPlainText -Force) `
        -Force:$true `
        -NoRebootOnCompletion:$false
}

# =============================================================================
# STAGE 2 — Post-DC-promotion: AD CS, users, GPOs, vulnerabilities
# =============================================================================
if ($stage -eq 2) {
    Write-Host "[dc01] Stage 2: Post-DC setup (AD CS, users, GPOs)..."
    Start-Sleep -Seconds 30
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    # ── Install AD CS (Certificate Authority) ─────────────────────────────────
    Write-Host "[dc01] Installing AD Certificate Services..."
    Install-WindowsFeature -Name ADCS-Cert-Authority, RSAT-ADCS-Mgmt -IncludeManagementTools
    Install-WindowsFeature -Name ADCS-Web-Enrollment -IncludeManagementTools

    Install-AdcsCertificationAuthority `
        -CAType EnterpriseRootCa `
        -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
        -KeyLength 2048 `
        -HashAlgorithmName SHA256 `
        -CACommonName "Secure-Net-CA" `
        -CADistinguishedNameSuffix "DC=secure,DC=net" `
        -ValidityPeriod Years `
        -ValidityPeriodUnits 10 `
        -Force

    Install-AdcsWebEnrollment -Force   # ESC8 — HTTP web enrollment endpoint

    # ── Create Domain Users ────────────────────────────────────────────────────
    Write-Host "[dc01] Creating domain users..."
    $secPass = ConvertTo-SecureString "Password!" -AsPlainText -Force

    $users = @(
        @{Name="jsmith";    Full="John Smith";     Title="Developer"},
        @{Name="mjones";    Full="Mary Jones";     Title="HR Manager"},
        @{Name="bwilson";   Full="Bob Wilson";     Title="Sysadmin"},
        @{Name="alee";      Full="Alice Lee";      Title="Finance"},
        @{Name="cthompson"; Full="Chris Thompson"; Title="IT Support"}
    )
    foreach ($u in $users) {
        try {
            New-ADUser -Name $u.Name -GivenName ($u.Full.Split()[0]) `
                -Surname ($u.Full.Split()[1]) -SamAccountName $u.Name `
                -UserPrincipalName "$($u.Name)@secure.net" `
                -AccountPassword $secPass -Enabled $true `
                -Title $u.Title -Company "Secure Corp" `
                -PasswordNeverExpires $true
        } catch { }
    }

    # Service account — Kerberoasting target (SPN registered)
    try {
        New-ADUser -Name "svc_mssql" -SamAccountName "svc_mssql" `
            -UserPrincipalName "svc_mssql@secure.net" `
            -AccountPassword $secPass -Enabled $true `
            -Description "MSSQL Service Account" -PasswordNeverExpires $true
        setspn -A "MSSQLSvc/db01.secure.net:1433" "svc_mssql"
    } catch { }

    # ── Weak GPO settings ──────────────────────────────────────────────────────
    # Disable SMB signing (enables NTLM relay)
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
        -Name "RequireSecuritySignature" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManWorkstation\Parameters" `
        -Name "RequireSecuritySignature" -Value 0 -Type DWord -Force

    # Enable LLMNR (enables Responder)
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name "EnableMulticast" -Value 1 -Type DWord -Force

    # ── OpenSSH Server ────────────────────────────────────────────────────────────
    Write-Host "[dc01] Enabling OpenSSH Server..."
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

    # ── SMB (v1 + v2 for lateral movement and relay scenarios) ───────────────────
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue
    Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue
    Set-Service LanmanServer -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service LanmanServer -ErrorAction SilentlyContinue

    # ── Install Wazuh agent ────────────────────────────────────────────────────
    Write-Host "[dc01] Installing Wazuh agent..."
    try {
        Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.2-1.msi" `
            -OutFile "C:\wazuh-agent.msi" -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList "/i C:\wazuh-agent.msi /quiet WAZUH_MANAGER=172.16.0.5 WAZUH_REGISTRATION_SERVER=172.16.0.5 WAZUH_REGISTRATION_PASSWORD=cyberrange-psk-2024 WAZUH_AGENT_NAME=dc01" -Wait
    } catch { Write-Host "  Wazuh install error: $_" }

    # ── Clear all event logs for a clean SIEM baseline ────────────────────────
    Write-Host "[dc01] Clearing event logs (clean SIEM baseline)..."
    wevtutil el 2>$null | ForEach-Object { wevtutil cl "$_" 2>$null }

    # Clear Wazuh agent queue so setup noise is never forwarded to the SIEM
    $wazuhBase = "C:\Program Files (x86)\ossec-agent"
    Remove-Item "$wazuhBase\queue\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$wazuhBase\logs\*"  -Recurse -Force -ErrorAction SilentlyContinue

    # Start Wazuh — first event it ever sends will be post-setup
    Start-Service WazuhSvc -ErrorAction SilentlyContinue

    # Remove setup artifacts
    Remove-Item "C:\wazuh-agent.msi" -Force -ErrorAction SilentlyContinue

    New-Item -Path "C:\setup-stage2-done.flag" -ItemType File -Force
    Write-Host "[dc01] Setup complete at $(Get-Date). Domain secure.net is ready."
}

if ($stage -eq 3) {
    Write-Host "[dc01] All stages complete. Nothing to do."
}
