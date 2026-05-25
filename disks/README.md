# VM Disks

This directory is for local VM disk images used by the range.

The disk images themselves are intentionally not committed to Git. They are too
large for normal GitHub repository storage and change frequently enough to make
Git history painful.

Expected local files:

| File | Purpose |
| --- | --- |
| `kali-linux-2026.1-qemu-amd64.qcow2` | Kali attacker VM disk |
| `ubuntu-target.qcow2` | Ubuntu target VM disk |
| `windows-target.qcow2` | Windows target VM disk |

Recommended storage pattern:

1. Keep source-controlled libvirt XML, scripts, topology files, and setup docs in
   this repository.
2. Store disk images in external artifact storage or local backup storage.
3. Document artifact versions, checksums, and restore instructions in the repo.

