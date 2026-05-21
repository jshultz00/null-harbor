# config/windows/web-win/ — Windows Web Server Setup

web-win runs Windows Server 2022 with IIS and an ASP.NET application. It provides a Windows-based web surface for scenarios involving IIS exploitation, ASPX webshell deployment, and Windows web server forensics.

**Control IP:** 10.0.0.42  
**DMZ segment IP:** 10.10.10.12  
**Hostname:** web-win  
**FQDN:** web-win.secure.net

---

## Files

| File | Purpose |
|------|---------|
| `unattend.xml` | Unattended Windows installation |
| `setup.ps1` | Three-stage setup script |

---

## setup.ps1 — Stage 1: IIS + ASP.NET Setup

```powershell
# Install IIS with ASP.NET 4.5 and management tools
Install-WindowsFeature Web-Server, Web-Asp-Net45, Web-Net-Ext45, `
    Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Mgmt-Console, Web-Scripting-Tools

# Create application pool
New-WebAppPool -Name "RangeAppPool"
Set-ItemProperty IIS:\AppPools\RangeAppPool -Name processModel.userName -Value "SECURE\svc_webapp"
Set-ItemProperty IIS:\AppPools\RangeAppPool -Name processModel.password -Value $env:RANGE_PASSWORD
Set-ItemProperty IIS:\AppPools\RangeAppPool -Name processModel.identityType -Value 3

# Create web application
New-Website -Name "RangeWeb" -Port 80 -PhysicalPath "C:\inetpub\rangeweb" -ApplicationPool "RangeAppPool"
```

### Service Account

```powershell
# svc_webapp service account — has SeImpersonatePrivilege (token impersonation attack surface)
# This allows PrintSpoofer/JuicyPotato-style privilege escalation in exploitation scenarios
New-ADUser -Name "WebApp Service" -SamAccountName "svc_webapp" `
    -UserPrincipalName "svc_webapp@secure.net" `
    -AccountPassword (ConvertTo-SecureString $env:RANGE_PASSWORD -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true

# Grant local IIS_IUSRS membership
Add-LocalGroupMember -Group "IIS_IUSRS" -Member "SECURE\svc_webapp"
```

### Web Application Content

The web application content is served from `webapps/web-win/` — scenario-swappable. Default content is a simple corporate intranet page. Scenarios replace this content with vulnerable applications (e.g., a file upload vulnerability, a SQL injection endpoint).

### Upload Directory (Writable by App Pool — Intentional Vulnerability)

```powershell
# Create upload directory writable by app pool identity
# This is an intentional vulnerability — allows ASPX webshell upload in exploitation scenarios
New-Item -ItemType Directory -Path "C:\inetpub\rangeweb\uploads" -Force
$acl = Get-Acl "C:\inetpub\rangeweb\uploads"
$ace = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "IIS AppPool\RangeAppPool", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
)
$acl.AddAccessRule($ace)
Set-Acl "C:\inetpub\rangeweb\uploads" $acl

# Enable script execution in uploads directory (allows .aspx files to execute)
Add-WebConfigurationProperty -pspath "IIS:\Sites\RangeWeb\uploads" `
    -filter "system.webServer/handlers" -name "." `
    -value @{name="ASPX";path="*.aspx";verb="*";type="System.Web.UI.PageHandlerFactory"}
```

---

## setup.ps1 — Stage 2: Wazuh + Saffron + Completion

Standard install. The Wazuh agent on web-win should be configured to monitor:
- IIS access logs (`C:\inetpub\logs\LogFiles\W3SVC1\`)
- Windows Security logs (event IDs 4688 process creation, 4689 process exit)
- The uploads directory (file creation events)
