# soc-ws Setup Script — SOC Analyst Workstation (standalone, NOT domain joined)
# Mounted as A:\setup.ps1 — no download from scenario

$ErrorActionPreference = "Continue"
Write-Host "[soc-ws] Starting setup at $(Get-Date)"

# Enable RDP
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" `
    -Name "fDenyTSConnections" -Value 0 -Type DWord -Force
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "analyst" -ErrorAction SilentlyContinue

# Point DNS at dc01 for internal name resolution during investigations
$adapters = Get-NetAdapter -Physical | Where-Object Status -eq Up
foreach ($a in $adapters) {
    Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex `
        -ServerAddresses "192.168.200.1","9.53.99.47" -ErrorAction SilentlyContinue
}

# Download investigation tools
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$toolsDir = "C:\Tools"
New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null

try {
    Invoke-WebRequest -Uri "https://download.sysinternals.com/files/SysinternalsSuite.zip" `
        -OutFile "$toolsDir\Sysinternals.zip" -UseBasicParsing
    Expand-Archive "$toolsDir\Sysinternals.zip" -DestinationPath "$toolsDir\Sysinternals" -Force
    Remove-Item "$toolsDir\Sysinternals.zip" -Force
} catch { Write-Host "  Sysinternals: $_" }

try {
    Invoke-WebRequest -Uri "https://nmap.org/dist/nmap-7.95-setup.exe" `
        -OutFile "$toolsDir\nmap-setup.exe" -UseBasicParsing
    Start-Process "$toolsDir\nmap-setup.exe" -ArgumentList "/S" -Wait
    Remove-Item "$toolsDir\nmap-setup.exe" -Force
} catch { Write-Host "  Nmap: $_" }

# Desktop RDP shortcuts for each internal server
$desktopPath = "C:\Users\analyst\Desktop"
New-Item -Path $desktopPath -ItemType Directory -Force | Out-Null

$rdpTargets = @(
    @{Name="DC01";        IP="192.168.200.1"},
    @{Name="EXCHANGE";    IP="192.168.200.10"},
    @{Name="FILESERVER";  IP="192.168.200.6"},
    @{Name="WKS-WIN10";   IP="192.168.100.11"},
    @{Name="WKS-WIN11";   IP="192.168.100.12"}
)
foreach ($t in $rdpTargets) {
    @"
full address:s:$($t.IP)
username:s:SECURE\Administrator
prompt for credentials:i:1
"@ | Out-File "$desktopPath\$($t.Name)-RDP.rdp" -Encoding ASCII
}

# ── OpenSSH Server ────────────────────────────────────────────────────────────
Write-Host "[soc-ws] Enabling OpenSSH Server..."
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

# Wazuh agent
try {
    Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.2-1.msi" `
        -OutFile "C:\wazuh-agent.msi" -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i C:\wazuh-agent.msi /quiet WAZUH_MANAGER=172.16.0.5 WAZUH_REGISTRATION_SERVER=172.16.0.5 WAZUH_REGISTRATION_PASSWORD=cyberrange-psk-2024 WAZUH_AGENT_NAME=soc-ws" -Wait
} catch { Write-Host "[soc-ws] Wazuh: $_" }

Write-Host "[soc-ws] Clearing event logs..."
wevtutil el 2>$null | ForEach-Object { wevtutil cl "$_" 2>$null }
$wazuhBase = "C:\Program Files (x86)\ossec-agent"
Remove-Item "$wazuhBase\queue\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$wazuhBase\logs\*"  -Recurse -Force -ErrorAction SilentlyContinue
Start-Service WazuhSvc -ErrorAction SilentlyContinue
Remove-Item "C:\wazuh-agent.msi" -Force -ErrorAction SilentlyContinue
Write-Host "[soc-ws] Setup complete at $(Get-Date)"
