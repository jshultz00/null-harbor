# data/ — Persistent Docker Volumes

This directory holds all Docker volume data. It is **gitignored** — never commit anything from this directory.

---

## Structure

```
data/
├── wazuh/
│   ├── manager/      # wazuh.manager volume (/var/ossec/data)
│   ├── indexer/      # wazuh.indexer volume (/var/lib/wazuh-indexer)
│   └── logs/         # Wazuh alert logs and archives
├── rsyslog/          # rsyslog volume (/var/log/remote)
├── db01/             # MSSQL data volume (/var/opt/mssql)
├── saffron/          # Saffron server data (job history, client registry)
└── windows/
    ├── dc01/         # KVM disk image — ~20 GB after first boot
    ├── exchange/     # KVM disk image — ~60 GB after Exchange install
    ├── fileserver/   # KVM disk image — ~15 GB
    ├── web-win/      # KVM disk image — ~15 GB
    ├── wks-win10/    # KVM disk image — ~20 GB
    └── wks-win11/    # KVM disk image — ~20 GB
```

---

## Expected Disk Usage

| Volume | Size (steady state) | Notes |
|--------|---------------------|-------|
| windows/dc01 | ~20 GB | Grows slowly after initial setup |
| windows/exchange | ~60 GB | Exchange databases grow with email activity |
| windows/fileserver | ~15 GB | Small — mostly file share content |
| windows/web-win | ~15 GB | Small — IIS + app |
| windows/wks-win10 | ~20 GB | Windows 10 + user profiles |
| windows/wks-win11 | ~20 GB | Windows 11 + user profiles |
| wazuh/indexer | 5–20 GB | Grows with log volume; configure index lifecycle |
| wazuh/logs | 1–5 GB | Prunable; contains alert archives |
| rsyslog | 1–5 GB | Rotated by rsyslog |
| **Total** | **~170–200 GB** | Plan for 250+ GB free before first run |

---

## Lifecycle

| Command | Effect on data/ |
|---------|----------------|
| `make down` | Containers stop; data/ untouched; volumes preserved |
| `make reset` | All volumes wiped; data/ cleared; Windows VMs must re-run setup (10–30 min) |
| `make clean` | Same as reset, plus images removed |
| `make up` (after `down`) | Containers restart with existing data; Windows VMs resume in minutes |

---

## Windows VM Snapshot Strategy (Future)

After first-boot Windows setup completes, the KVM disk images under `data/windows/` can be snapshotted so that `make reset` restores from snapshot instead of re-running the 10–30 minute setup. Snapshot management is not implemented in v1 but is an open question tracked in the spec.
