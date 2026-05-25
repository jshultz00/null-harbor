# ISO Images

This directory is for local installer and driver ISO files used by the range.

The ISO/archive files themselves are intentionally not committed to Git. Most are
larger than GitHub's normal file limit, and several are too large for practical
Git LFS usage on typical plans.

Expected local files:

| File | Purpose |
| --- | --- |
| `ubuntu-24.04.2-live-server-amd64.iso` | Ubuntu Server installer |
| `windows10-enterprise-eval.iso` | Windows 10 Enterprise evaluation installer |
| `kali-linux-2026.1-qemu-amd64.7z` | Kali prebuilt QEMU image archive |
| `virtio-win.iso` | Windows virtio driver ISO |

Recommended storage pattern:

1. Keep download sources, checksums, and build notes in this repository.
2. Store bulky ISO/archive files in external artifact storage or local backup
   storage.
3. Rehydrate this directory from those artifacts when rebuilding the range.

