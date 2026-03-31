# =============================================================================
# exchange Setup Script — Microsoft Exchange Server
# Mounted as A:\setup.ps1 via dockur/windows /oem — no network download needed
# =============================================================================

$ErrorActionPreference = "Continue"
Write-Host "[exchange] Starting setup at $(Get-Date)"

$stage = if (Test-Path "C:\setup-exchange-done.flag") { 3 }
         elseif (Test-Path "C:\setup-joined.flag") { 2 }
         else { 1 }

# =============================================================================
# STAGE 1 — Domain join (retry until DC is reachable)
# =============================================================================
if ($stage -eq 1) {
    Write-Host "[exchange] Stage 1: Domain join to secure.net..."
    $cred = New-Object System.Management.Automation.PSCredential(
        "SECURE\Administrator",
        (ConvertTo-SecureString "P@55w0rd!" -AsPlainText -Force)
    )

    $joined = $false
    for ($i = 1; $i -le 30; $i++) {
        try {
            Add-Computer -DomainName "secure.net" -Credential $cred `
                -OUPath "CN=Computers,DC=secure,DC=net" -Force -ErrorAction Stop
            $joined = $true
            Write-Host "  Domain join successful on attempt $i"
            break
        } catch {
            Write-Host "  Domain join attempt $i failed: $_ — retrying in 60s..."
            Start-Sleep -Seconds 60
        }
    }

    if ($joined) {
        New-Item -Path "C:\setup-joined.flag" -ItemType File -Force
        # A:\setup.ps1 is always available from the virtual floppy — no download needed
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
            -Name "ExchangeSetupStage2" `
            -Value 'cmd.exe /c start /wait powershell -ExecutionPolicy Bypass -File A:\setup.ps1'
        Write-Host "[exchange] Rebooting to complete domain join..."
        Restart-Computer -Force
    } else {
        Write-Host "[exchange] ERROR: Could not join domain after 30 attempts."
    }
}

# =============================================================================
# STAGE 2 — Install Exchange prerequisites and Exchange Server 2019
# =============================================================================
if ($stage -eq 2) {
    Write-Host "[exchange] Stage 2: Installing Exchange Server prerequisites..."

    Install-WindowsFeature `
        NET-Framework-45-Features, RPC-over-HTTP-proxy, `
        RSAT-Clustering, RSAT-Clustering-CmdInterface, RSAT-Clustering-Mgmt, `
        RSAT-Clustering-PowerShell, WAS-Process-Model, `
        Web-Asp-Net45, Web-Basic-Auth, Web-Client-Auth, Web-Digest-Auth, `
        Web-Dir-Browsing, Web-Dyn-Compression, Web-Http-Errors, `
        Web-Http-Logging, Web-Http-Redirect, Web-Http-Tracing, `
        Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Lgcy-Mgmt-Console, `
        Web-Metabase, Web-Mgmt-Console, Web-Mgmt-Service, `
        Web-Net-Ext45, Web-Request-Monitor, Web-Server, Web-Stat-Compression, `
        Web-Static-Content, Web-Windows-Auth, Web-WMI, `
        Windows-Identity-Foundation, RSAT-ADDS

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Download Visual C++ redistributable
    try {
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
            -OutFile "C:\vc_redist.x64.exe" -UseBasicParsing
        Start-Process "C:\vc_redist.x64.exe" -ArgumentList "/install /quiet /norestart" -Wait
    } catch { Write-Host "[exchange] VC++ redist: $_" }

    # Download Exchange Server 2019 CU15
    Write-Host "[exchange] Downloading Exchange Server 2019 (this takes time)..."
    $isoPath = "C:\ExchangeSetup.iso"
    $exchangeUrl = "https://download.microsoft.com/download/b/c/7/bc766694-8398-4258-8e1e-ce4ddb9b3f7d/ExchangeServer2019-x64-CU15.ISO"
    try {
        Invoke-WebRequest -Uri $exchangeUrl -OutFile $isoPath -UseBasicParsing
    } catch {
        Write-Host "[exchange] Could not download Exchange ISO: $_"
        exit 1
    }

    # Mount and install
    $mount = Mount-DiskImage -ImagePath $isoPath -PassThru
    $driveLetter = ($mount | Get-Volume).DriveLetter
    Write-Host "[exchange] Running Exchange setup (30-60 min)..."
    Start-Process "${driveLetter}:\Setup.exe" -ArgumentList @(
        "/mode:Install", "/role:Mailbox",
        "/OrganizationName:SecureCorp",
        "/IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF",
        "/CustomerFeedbackEnabled:False"
    ) -Wait -NoNewWindow
    Dismount-DiskImage -ImagePath $isoPath

    # Configure mail relay connector
    Start-Sleep -Seconds 60
    try {
        Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction SilentlyContinue
        New-ReceiveConnector -Name "Internal Relay" `
            -TransportRole FrontendTransport -Custom `
            -Bindings "0.0.0.0:25" `
            -RemoteIPRanges "172.16.100.0/24","172.16.0.0/24"
        Set-ReceiveConnector "EXCHANGE\Internal Relay" -PermissionGroups AnonymousUsers
    } catch { Write-Host "[exchange] Connector: $_" }

    # Enable mailboxes for domain users
    $users = @("jsmith","mjones","bwilson","alee","cthompson")
    foreach ($u in $users) {
        try {
            Enable-Mailbox -Identity "SECURE\$u" `
                -Database (Get-MailboxDatabase | Select-Object -First 1).Name
        } catch { }
    }

    # ── OpenSSH Server ────────────────────────────────────────────────────────────
    Write-Host "[exchange] Enabling OpenSSH Server..."
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

    # ── SMB (v1 + v2 for lateral movement scenarios) ──────────────────────────────
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue
    Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue
    Set-Service LanmanServer -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service LanmanServer -ErrorAction SilentlyContinue

    # Install Wazuh agent
    try {
        Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.2-1.msi" `
            -OutFile "C:\wazuh-agent.msi" -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList "/i C:\wazuh-agent.msi /quiet WAZUH_MANAGER=172.16.0.5 WAZUH_REGISTRATION_SERVER=172.16.0.5 WAZUH_REGISTRATION_PASSWORD=cyberrange-psk-2024 WAZUH_AGENT_NAME=exchange" -Wait
    } catch { Write-Host "[exchange] Wazuh: $_" }

    # ── Clear all event logs for a clean SIEM baseline ────────────────────────
    Write-Host "[exchange] Clearing event logs (clean SIEM baseline)..."
    wevtutil el 2>$null | ForEach-Object { wevtutil cl "$_" 2>$null }
    $wazuhBase = "C:\Program Files (x86)\ossec-agent"
    Remove-Item "$wazuhBase\queue\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$wazuhBase\logs\*"  -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service WazuhSvc -ErrorAction SilentlyContinue

    # Remove setup artifacts
    Remove-Item "C:\wazuh-agent.msi", "C:\vc_redist.x64.exe" -Force -ErrorAction SilentlyContinue

    New-Item -Path "C:\setup-exchange-done.flag" -ItemType File -Force
    Write-Host "[exchange] Setup complete at $(Get-Date)"
}
