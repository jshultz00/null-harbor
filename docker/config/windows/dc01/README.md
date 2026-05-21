# config/windows/dc01/ — Domain Controller Setup

dc01 runs Windows Server 2022 and is promoted to a domain controller for `secure.net`. It hosts AD DS, AD CS (with intentional ESC misconfigurations), DNS, and LDAP/LDAPS.

**Control IP:** 10.0.0.70  
**Server segment IP:** 10.20.20.100  
**NetBIOS:** SECURE  
**Domain:** secure.net

---

## Files

| File | Purpose |
|------|---------|
| `unattend.xml` | Windows unattended installation answer file |
| `setup.ps1` | Three-stage PowerShell setup script |

---

## unattend.xml

Sets language, timezone (UTC), disables Windows Setup OOBE, sets initial local Administrator password. `dockur/windows` uses this file to automate the Windows installation phase before the first boot of the OS.

Key settings:
- `UILanguage`: `en-US`
- `TimeZone`: `UTC`
- `AutoLogon`: Enabled for Administrator (enables `setup.ps1` to run without interaction)
- `FirstLogonCommands`: Runs `setup.ps1` at first logon

---

## setup.ps1 — Stage 0: Promote to Domain Controller

```powershell
# 1. Set hostname
Rename-Computer -NewName "dc01" -Force

# 2. Set static IPs (two interfaces: control + server segment)
#    Interface 1 (control): 10.0.0.70/24 gw 10.0.0.254
#    Interface 2 (server):  10.20.20.100/24

# 3. Install AD DS role
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# 4. Promote to domain controller (creates new forest)
Import-Module ADDSDeployment
Install-ADDSForest `
    -DomainName "secure.net" `
    -DomainNetbiosName "SECURE" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString $env:RANGE_PASSWORD -AsPlainText -Force) `
    -InstallDns `
    -Force `
    -NoRebootOnCompletion:$false
# Reboots automatically after promotion
```

---

## setup.ps1 — Stage 1: AD CS + DNS + Users + GPOs

### Active Directory Certificate Services

```powershell
# Install AD CS (Enterprise CA)
Install-WindowsFeature ADCS-Cert-Authority, ADCS-Web-Enrollment `
    -IncludeManagementTools

Install-AdcsCertificationAuthority `
    -CAType EnterpriseRootCa `
    -CACommonName "SECURE-CA" `
    -CADistinguishedNameSuffix "DC=secure,DC=net" `
    -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
    -KeyLength 2048 `
    -HashAlgorithmName SHA256 `
    -ValidityPeriod Years `
    -ValidityPeriodUnits 10 `
    -Force
```

### ESC Misconfigurations

These are intentional attack-surface configurations for AD CS exploitation scenarios:

**ESC1 — Client authentication template with enrollee-supplied SAN:**
```powershell
# Duplicate the User template, enable SAN in request, grant Domain Users enrollment rights
$template = Get-CATemplate -TemplateName "User" | ...
# ENROLLEE_SUPPLIES_SUBJECT flag = 0x00000001 in msPKI-Certificate-Name-Flag
# This allows an attacker to request a cert with arbitrary SAN (any UPN including Administrator)
Set-ADObject -Identity "CN=ESC1Template,CN=Certificate Templates,..." `
    -Replace @{"msPKI-Certificate-Name-Flag"=1}
Add-CATemplate -TemplateName "ESC1Template"
```

**ESC4 — Write access to certificate template for Domain Users:**
```powershell
# Grant Domain Users "Write" on the template ACL
# This allows any domain user to modify the template to enable SAN supply (ESC1)
$acl = Get-ACL "AD:CN=ESC4Template,CN=Certificate Templates,..."
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    [System.Security.Principal.NTAccount]"Domain Users",
    [System.DirectoryServices.ActiveDirectoryRights]"WriteProperty",
    [System.Security.AccessControl.AccessControlType]"Allow"
)
$acl.AddAccessRule($ace)
Set-ACL "AD:CN=ESC4Template,..." $acl
```

**ESC8 — NTLM relay to AD CS web enrollment:**
```powershell
# Install IIS-based web enrollment endpoint
Install-AdcsWebEnrollment -Force
# Leave HTTP (not HTTPS-only) enabled on /certsrv
# NTLM auth enabled (default) — allows relay attacks (PetitPotam, etc.)
```

### DNS Forward Zones

```powershell
# Internal zones auto-created by AD DS promotion
# Add fake external domain for scenario realism
Add-DnsServerPrimaryZone -Name "contoso.com" -ZoneFile "contoso.com.dns"
Add-DnsServerResourceRecordA -ZoneName "contoso.com" -Name "mail" -IPv4Address "5.79.99.10"
```

### AD Users and Groups

```powershell
$password = ConvertTo-SecureString $env:RANGE_PASSWORD -AsPlainText -Force

# IT Department
New-ADUser -Name "John Smith"      -SamAccountName "jsmith"     -UserPrincipalName "jsmith@secure.net"     -AccountPassword $password -Enabled $true -Department "IT"
New-ADUser -Name "Mary Jones"      -SamAccountName "mjones"     -UserPrincipalName "mjones@secure.net"     -AccountPassword $password -Enabled $true -Department "IT"

# Finance Department
New-ADUser -Name "Bob Wilson"      -SamAccountName "bwilson"    -UserPrincipalName "bwilson@secure.net"    -AccountPassword $password -Enabled $true -Department "Finance"
New-ADUser -Name "Alice Lee"       -SamAccountName "alee"       -UserPrincipalName "alee@secure.net"       -AccountPassword $password -Enabled $true -Department "Finance"

# Operations
New-ADUser -Name "Chris Thompson"  -SamAccountName "cthompson"  -UserPrincipalName "cthompson@secure.net"  -AccountPassword $password -Enabled $true -Department "Operations"

# Service account (Kerberoastable — SPN registered, password = range password)
New-ADUser -Name "MSSQL Service"   -SamAccountName "svc_mssql"  -UserPrincipalName "svc_mssql@secure.net"  -AccountPassword $password -Enabled $true
Set-ADUser "svc_mssql" -ServicePrincipalNames @{Add="MSSQLSvc/db01.secure.net:1433"}

# Groups
New-ADGroup -Name "IT-Admins"     -GroupScope Global -GroupCategory Security
New-ADGroup -Name "Finance-Users" -GroupScope Global -GroupCategory Security
Add-ADGroupMember "IT-Admins"     -Members jsmith, mjones
Add-ADGroupMember "Finance-Users" -Members bwilson, alee
Add-ADGroupMember "Domain Admins" -Members jsmith    # jsmith is domain admin — privilege escalation target
```

### Group Policy Objects

```powershell
# GPO: Disable Windows Defender on workstations (training environment — allows payloads to run)
$gpo = New-GPO -Name "Disable-Defender-WKS"
Set-GPRegistryValue -Name "Disable-Defender-WKS" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" `
    -ValueName "DisableAntiSpyware" `
    -Type DWord -Value 1
New-GPLink -Name "Disable-Defender-WKS" -Target "OU=Workstations,DC=secure,DC=net"

# GPO: Enable WinRM on all machines (allows PSRemoting for lateral movement scenarios)
$gpo2 = New-GPO -Name "Enable-WinRM"
# ... WinRM service startup, firewall rules via GP
New-GPLink -Name "Enable-WinRM" -Target "DC=secure,DC=net"

# GPO: Audit policy — enable detailed process creation, logon, object access logging
# Critical for Wazuh to generate meaningful security event alerts
$gpo3 = New-GPO -Name "Audit-Policy"
# auditpol settings via GP registry keys
```

---

## setup.ps1 — Stage 2: Finalization

1. Install Wazuh agent MSI (downloads from `http://10.0.0.1:8000/tools/wazuh-agent.msi`)
2. Install Saffron Windows service (downloads `saffron-agent-windows-amd64.exe`)
3. Write `C:\range-setup-complete.txt` as a completion marker (polled by `make status`)
4. Log completion to Windows Event Log: `Write-EventLog -LogName Application -Source "RangeSetup" -EventId 9999 -Message "Stage 2 complete"`
