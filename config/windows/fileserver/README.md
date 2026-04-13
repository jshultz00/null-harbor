# config/windows/fileserver/ — Windows File Server Setup

fileserver runs Windows Server 2022 and provides SMB file shares for the `secure.net` domain. It is the primary target for ransomware simulation scenarios (mass file encryption across network shares) and data exfiltration training.

**Control IP:** 10.0.0.74  
**Server segment IP:** 10.20.20.20  
**Hostname:** fileserver  
**FQDN:** fileserver.secure.net

---

## Files

| File | Purpose |
|------|---------|
| `unattend.xml` | Unattended Windows installation |
| `setup.ps1` | Three-stage setup script |

---

## setup.ps1 — Stage 0: Base Config + Domain Join

Standard rename, static IP assignment, DNS configuration, domain join. See [windows/README.md](../README.md) for the common pattern.

Control IP: `10.0.0.74/24`  
Server IP: `10.20.20.20/24`

---

## setup.ps1 — Stage 1: File Server Role + Share Structure

### Install File Server Role

```powershell
Install-WindowsFeature FS-FileServer, FS-DFS-Namespace, FS-DFS-Replication, `
    FS-Resource-Manager, RSAT-DFS-Mgmt-Con -IncludeManagementTools
```

### Share Directory Structure

```powershell
# Create directory tree to simulate a realistic corporate file server
$dirs = @(
    "C:\Shares\Finance\Reports",
    "C:\Shares\Finance\Invoices",
    "C:\Shares\Finance\Payroll",
    "C:\Shares\IT\Scripts",
    "C:\Shares\IT\Documentation",
    "C:\Shares\IT\Backups",
    "C:\Shares\HR\Policies",
    "C:\Shares\HR\Employee Records",
    "C:\Shares\Operations\Projects",
    "C:\Shares\Operations\Contracts",
    "C:\Shares\NETLOGON",
    "C:\Shares\SYSVOL"
)
$dirs | ForEach-Object { New-Item -ItemType Directory -Path $_ -Force }
```

### SMB Shares

```powershell
# Department shares with realistic permissions
New-SmbShare -Name "Finance$" -Path "C:\Shares\Finance" -FullAccess "SECURE\IT-Admins" -ReadAccess "SECURE\Finance-Users"
New-SmbShare -Name "IT"       -Path "C:\Shares\IT"      -FullAccess "SECURE\IT-Admins"
New-SmbShare -Name "HR$"      -Path "C:\Shares\HR"       -FullAccess "SECURE\IT-Admins", "SECURE\Domain Admins"
New-SmbShare -Name "Ops"      -Path "C:\Shares\Operations" -FullAccess "SECURE\IT-Admins" -ChangeAccess "SECURE\Domain Users"

# Hidden admin share (C$, ADMIN$ created automatically)
```

### Populate Shares with Bait Files

```powershell
# Create realistic-looking documents that act as ransomware bait
# These files have meaningful names so that when a ransomware scenario encrypts them,
# the impact is clearly visible to defenders reviewing file access logs

$financeFiles = @(
    "Q4-2024-Financial-Report.xlsx",
    "2024-Employee-Salaries.xlsx",
    "Invoice-00447-Acme-Corp.pdf",
    "Budget-FY2025-Draft.xlsx"
)
$financeFiles | ForEach-Object {
    $content = "CONFIDENTIAL - SECURE Corp Finance Document - $_"
    Set-Content -Path "C:\Shares\Finance\Reports\$_" -Value $content
}

# IT documentation
@("Network-Diagram.vsdx", "AD-Schema-Notes.docx", "Server-Passwords-OLD.txt") | ForEach-Object {
    Set-Content -Path "C:\Shares\IT\Documentation\$_" -Value "SECURE Corp IT - $_"
}
```

### NTFS Audit Policy (for Wazuh file access alerts)

```powershell
# Enable object access auditing on Finance share (generates Security event 4663 on read/write/delete)
$acl = Get-Acl "C:\Shares\Finance"
$auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule(
    "Everyone",
    "ReadData,WriteData,Delete",
    "ContainerInherit,ObjectInherit",
    "None",
    "Success,Failure"
)
$acl.AddAuditRule($auditRule)
Set-Acl "C:\Shares\Finance" $acl
```

This generates Windows Security Event 4663 (object access) whenever files in the Finance share are read or modified. Wazuh picks up these events via the agent and generates alerts.

---

## setup.ps1 — Stage 2: Wazuh + Saffron + Completion

Standard Wazuh MSI + Saffron service install. See [windows/README.md](../README.md).

Wazuh agent on fileserver is particularly important — it must forward Security event logs (especially Event ID 4663 — file access, 4656 — handle request) to the manager so ransomware scenarios generate visible SIEM activity.
