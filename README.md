# Null Harbor

Local KVM/libvirt-based cyber range for developing and testing red team exercises in an air-gapped environment.

---

## System Requirements

- **Host:** Ubuntu 20.04+ with KVM/libvirt
- **CPU:** 8+ cores (Intel VT-x / AMD-V required)
- **RAM:** 32 GB minimum
- **Disk:** 100+ GB free

---

## Quick Start

### 1. Start the GUI Service
```bash
./scripts/install-service.sh
```
This builds the GUI and installs it as a systemd service. Access at **http://localhost:8082**

Manage with:
```bash
sudo systemctl {start,stop,restart,status} null-harbor-gui
```

### 2. Start VMs
```bash
virsh net-start c2
virsh start attacker
virsh start user-ubuntu24
virsh start user-windows10
```

### 3. Access VM Consoles
```bash
virt-viewer attacker &
```

---

## Virtual Machines

| Name | OS | IP | Role |
|------|----|----|------|
| `attacker` | Kali Linux 2026.1 | 10.0.0.1 | Attacker |
| `user-ubuntu24` | Ubuntu 24.04 Server | 10.0.0.100 | Linux target |
| `user-windows10` | Windows 10 Enterprise | 10.0.0.101 | Windows target |

**Network:** `10.0.0.0/24` (c2 network, air-gapped)

---

## Project Structure

```
null-harbor/
├── c2.xml                 # Libvirt network definition
├── disks/                 # VM disk images (qcow2)
├── isos/                  # Installation ISOs
├── scripts/               # Utility scripts
└── gui/                   # Web-based GUI (Go + React)
```

---

## Essential Commands

```bash
# VM Management
virsh list --all
virsh start <vm> / virsh shutdown <vm>
virsh snapshot-list <vm>
virsh snapshot-revert <vm> <snapshot-name>

# Network
virsh net-list
virsh net-start c2
```

---

## Important Notes

- **Windows NIC:** Requires `virtio-win-gt-x64.msi` for Ethernet to appear
- **Ubuntu NIC:** `enp1s0` (not `eth0`)
- **Windows License:** Evaluation mode with 3 rearm cycles available
  ```bash
  slmgr /rearm  # Use sparingly
  ```

---

**Last Updated:** May 2026
