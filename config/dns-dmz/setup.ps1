# dns-dmz Setup Script — DMZ DNS Server (standalone workgroup)
# Mounted as A:\setup.ps1 — no download from scenario

$ErrorActionPreference = "Continue"
Write-Host "[dns-dmz] Starting setup at $(Get-Date)"

Install-WindowsFeature -Name DNS, RSAT-DNS-Server -IncludeManagementTools
Set-DnsServerForwarder -IPAddress "9.53.99.47" -PassThru

Add-DnsServerStubZone -Name "secure.net" `
    -MasterServers "192.168.200.1" -PassThru -ErrorAction SilentlyContinue
Add-DnsServerResourceRecordA -Name "www" -ZoneName "secure.net" `
    -IPv4Address "172.16.100.10" -ErrorAction SilentlyContinue
Add-DnsServerResourceRecordA -Name "mail" -ZoneName "secure.net" `
    -IPv4Address "172.16.100.8" -ErrorAction SilentlyContinue

# ── OpenSSH Server ────────────────────────────────────────────────────────────
Write-Host "[dns-dmz] Enabling OpenSSH Server..."
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

# dns-dmz doesn't get a Wazuh agent (DMZ standalone, not monitored)
Write-Host "[dns-dmz] Clearing event logs..."
wevtutil el 2>$null | ForEach-Object { wevtutil cl "$_" 2>$null }

Write-Host "[dns-dmz] Setup complete at $(Get-Date)"
