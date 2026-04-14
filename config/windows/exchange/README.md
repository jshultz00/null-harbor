# config/windows/exchange/ — Exchange Server 2019 Setup

Exchange 2019 runs on Windows Server 2022 (the only officially supported combination as of Exchange 2019 CU13+). It is domain-joined to `secure.net` and provides a realistic email infrastructure for phishing simulation, email-based lateral movement, and email forensics training.

**Control IP:** 10.0.0.72  
**Server segment IP:** 10.20.20.10  
**Hostname:** exchange  
**FQDN:** exchange.secure.net

---

## Files

| File | Purpose |
|------|---------|
| `unattend.xml` | Unattended Windows installation |
| `setup.ps1` | Three-stage Exchange installation script |

---

## Hardware Requirements

Exchange 2019 is resource-intensive. Minimum allocation in `docker-compose.yml`:
- RAM: 8 GB (`RAM_SIZE=8G`)
- CPU: 4 cores (`CPU_CORES=4`)
- Disk: 128 GB (`DISK_SIZE=128G`) — Exchange databases grow quickly

First-boot setup takes **45–90 minutes** due to Exchange prerequisites and installation.

---

## setup.ps1 — Stage 0: Base Config + Domain Join

```powershell
Rename-Computer -NewName "exchange" -Force

# Static IPs
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.0.0.72 -PrefixLength 24 -DefaultGateway 10.0.0.254
New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress 10.20.20.10 -PrefixLength 24

# Point DNS at DC
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.20.20.100

# Domain join
$cred = New-Object System.Management.Automation.PSCredential(
    "SECURE\Administrator",
    (ConvertTo-SecureString $env:RANGE_PASSWORD -AsPlainText -Force)
)
Add-Computer -DomainName "secure.net" -Credential $cred -OUPath "OU=Servers,DC=secure,DC=net" -Restart -Force
```

---

## setup.ps1 — Stage 1: Exchange Prerequisites + Install

### Prerequisites

```powershell
# Required Windows features for Exchange 2019
Install-WindowsFeature `
    NET-Framework-45-Features, RPC-over-HTTP-proxy, RSAT-Clustering, `
    RSAT-Clustering-CmdInterface, RSAT-Clustering-Mgmt, RSAT-Clustering-PowerShell, `
    Web-Mgmt-Tools, WAS-Process-Model, Web-Asp-Net45, Web-Basic-Auth, Web-Client-Auth, `
    Web-Digest-Auth, Web-Dir-Browsing, Web-Dyn-Compression, Web-Http-Errors, `
    Web-Http-Logging, Web-Http-Redirect, Web-Http-Tracing, Web-ISAPI-Ext, `
    Web-ISAPI-Filter, Web-Lgcy-Mgmt-Console, Web-Metabase, Web-Mgmt-Console, `
    Web-Mgmt-Service, Web-Net-Ext45, Web-Request-Monitor, Web-Server, Web-Stat-Compression, `
    Web-Static-Content, Web-Windows-Auth, Web-WMI, Windows-Identity-Foundation, RSAT-ADDS

# Visual C++ Redistributable
Invoke-WebRequest "http://10.0.0.1:8000/tools/vc_redist.x64.exe" -OutFile "C:\vc_redist.exe"
Start-Process "C:\vc_redist.exe" -ArgumentList "/quiet /norestart" -Wait

# Unified Communications Managed API 4.0
Invoke-WebRequest "http://10.0.0.1:8000/tools/UcmaRuntimeSetup.exe" -OutFile "C:\UcmaRuntimeSetup.exe"
Start-Process "C:\UcmaRuntimeSetup.exe" -ArgumentList "/passive /norestart" -Wait
```

### Exchange Installation

```powershell
# Mount Exchange ISO (pre-downloaded to scenario container www/)
Invoke-WebRequest "http://10.0.0.1:8000/tools/ExchangeServer2019-x64.iso" -OutFile "C:\Exchange.iso"
Mount-DiskImage -ImagePath "C:\Exchange.iso"
$driveLetter = (Get-DiskImage "C:\Exchange.iso" | Get-Volume).DriveLetter

# Silent install — Mailbox role only
& "${driveLetter}:\Setup.exe" `
    /mode:Install `
    /role:Mailbox `
    /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF `
    /OrganizationName:"SECURE Corp" `
    /on:SECURE `
    /TargetDir:"C:\Program Files\Microsoft\Exchange Server\V15" `
    /MdbName:"Mailbox Database" /DbFilePath:"C:\ExchangeDB\Mailbox.edb" `
    /LogFolderPath:"C:\ExchangeDB\Logs"
```

---

## setup.ps1 — Stage 2: Mailboxes + Connectors + Finalization

### Create Mailboxes for All AD Users

```powershell
# All domain users get mailboxes
Enable-Mailbox -Identity "jsmith@secure.net"   -Database "Mailbox Database"
Enable-Mailbox -Identity "mjones@secure.net"   -Database "Mailbox Database"
Enable-Mailbox -Identity "bwilson@secure.net"  -Database "Mailbox Database"
Enable-Mailbox -Identity "alee@secure.net"     -Database "Mailbox Database"
Enable-Mailbox -Identity "cthompson@secure.net" -Database "Mailbox Database"
```

### SMTP Receive Connector (for inbound relay from scenario container)

```powershell
# Allow anonymous SMTP relay from scenario container (5.79.99.0/24)
# Used by phishing simulation phases to inject emails
New-ReceiveConnector -Name "Range-Relay" `
    -TransportRole FrontendTransport `
    -RemoteIPRanges "5.79.99.0/24" `
    -Bindings "0.0.0.0:25" `
    -PermissionGroups AnonymousUsers
Get-ReceiveConnector "exchange\Range-Relay" | `
    Add-ADPermission -User "NT AUTHORITY\ANONYMOUS LOGON" `
    -ExtendedRights ms-Exch-SMTP-Accept-Any-Recipient
```

### Disable SSL Certificate Warnings (self-signed scenario)

```powershell
# Exchange uses self-signed cert by default in lab; suppress OWA cert warnings
# Real exchange scenarios will use Outlook client, not OWA in most cases
```

### Wazuh + Saffron Install

Same as all other machines — see [windows/README.md](../README.md).
