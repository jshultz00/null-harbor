# web-win Setup Script — Windows IIS Web Server (DMZ, standalone workgroup)
# Mounted as A:\setup.ps1 — no download from scenario

$ErrorActionPreference = "Continue"
Write-Host "[web-win] Starting setup at $(Get-Date)"

Install-WindowsFeature -Name Web-Server, Web-Mgmt-Console, Web-ASP, Web-CGI, `
    Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Basic-Auth, Web-Windows-Auth, `
    Web-Digest-Auth, Web-Dir-Browsing, Web-Http-Errors, Web-Static-Content, `
    Web-Http-Logging, Web-Request-Monitor, Web-Http-Tracing `
    -IncludeManagementTools

# Intentionally weak IIS config — directory browsing, WebDAV
Set-WebConfigurationProperty -Filter /system.webServer/directoryBrowse `
    -Name enabled -Value True -PSPath "IIS:\"

Install-WindowsFeature Web-DAV-Publishing
Set-WebConfigurationProperty -Filter /system.webServer/webdav/authoring `
    -Name enabled -Value True -PSPath "IIS:\"

# Weak upload permissions
New-Item -Path "C:\inetpub\wwwroot\upload" -ItemType Directory -Force | Out-Null
icacls "C:\inetpub\wwwroot\upload" /grant "IUSR:(OI)(CI)F" /grant "IIS_IUSRS:(OI)(CI)F"

@"
<!DOCTYPE html><html><head><title>Secure Corp — Web Portal</title></head>
<body><h1>Secure Corp Internal Web Portal</h1>
<p>Server: web-win.secure.net</p></body></html>
"@ | Out-File "C:\inetpub\wwwroot\index.html" -Encoding UTF8

# ── OpenSSH Server ────────────────────────────────────────────────────────────
Write-Host "[web-win] Enabling OpenSSH Server..."
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

try {
    Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.2-1.msi" `
        -OutFile "C:\wazuh-agent.msi" -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i C:\wazuh-agent.msi /quiet WAZUH_MANAGER=172.16.0.5 WAZUH_REGISTRATION_SERVER=172.16.0.5 WAZUH_REGISTRATION_PASSWORD=cyberrange-psk-2024 WAZUH_AGENT_NAME=web-win" -Wait
} catch { }

Write-Host "[web-win] Clearing event logs..."
wevtutil el 2>$null | ForEach-Object { wevtutil cl "$_" 2>$null }
$wazuhBase = "C:\Program Files (x86)\ossec-agent"
Remove-Item "$wazuhBase\queue\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$wazuhBase\logs\*"  -Recurse -Force -ErrorAction SilentlyContinue
Start-Service WazuhSvc -ErrorAction SilentlyContinue
Remove-Item "C:\wazuh-agent.msi" -Force -ErrorAction SilentlyContinue
Write-Host "[web-win] Setup complete at $(Get-Date)"
