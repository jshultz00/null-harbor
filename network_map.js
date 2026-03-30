// Edit this file to add, remove, or modify machines and networks.
// The HTML loads this directly via <script src>, so it works with file:// (no server needed).
const NETWORK_MAP_DATA = {
  "_meta": {
    "version": "4.0",
    "description": "holey.net Local Cyber Range — container-based attack/defense training environment. Linux services run as Docker containers. Windows targets run via dockur/windows with KVM. Segmented corporate network with DMZ, internal servers, user workstations, SOC, SIEM, and database zones.",
    "deployment": "docker-compose",
    "host_requirements": {
      "note": "dockur/windows requires KVM. On macOS use Docker Desktop + Rosetta, or deploy to the Beelink SER5 Pro (Linux host with KVM support). All Linux containers run on any Docker host.",
      "min_ram_all_up": "~64 GB",
      "min_ram_core_scenario": "~28 GB (subset — see profiles in docker-compose.yml)"
    }
  },
  "networks": {
    "Router-DMZ": {
      "subnet": "130.2.2.0/24",
      "docker_name": "router_dmz",
      "description": "Connects the Blue border router to the DMZ firewall"
    },
    "Firewall": {
      "subnet": "192.168.254.0/30",
      "docker_name": "fw_link",
      "description": "Back-to-back link between DMZ firewall (.242) and Central firewall (.241)"
    },
    "DMZ_Internal": {
      "subnet": "172.16.100.0/24",
      "docker_name": "dmz_internal",
      "description": "DMZ internal segment — web servers, mail relay, DNS"
    },
    "DMZ_External": {
      "subnet": "130.2.2.0/24",
      "docker_name": "dmz_external",
      "description": "DMZ external segment — public-facing IPs reachable from Router-DMZ"
    },
    "C2": {
      "subnet": "172.16.0.0/24",
      "docker_name": "c2",
      "description": "Command and Control — scenario engine communicates with all blue hosts via this segment"
    },
    "Management": {
      "subnet": "172.31.202.0/24",
      "docker_name": "management",
      "description": "Out-of-band management for firewalls and SOC workstations"
    },
    "Server": {
      "subnet": "192.168.200.0/24",
      "docker_name": "server",
      "description": "Internal server segment — AD, DNS, Exchange, file servers"
    },
    "User": {
      "subnet": "192.168.100.0/24",
      "docker_name": "user",
      "description": "User workstation segment — mixed OS corporate endpoints"
    },
    "SOC": {
      "subnet": "192.168.110.0/24",
      "docker_name": "soc",
      "description": "Security Operations Center — analyst workstations"
    },
    "SIEM": {
      "subnet": "192.168.66.0/24",
      "docker_name": "siem",
      "description": "SIEM tooling segment — Wazuh manager and dashboard"
    },
    "DB": {
      "subnet": "192.168.214.0/24",
      "docker_name": "db",
      "description": "Database segment — MSSQL server"
    },
    "Scenario": {
      "subnet": "9.53.99.0/24",
      "docker_name": "scenario",
      "description": "Scenario/management segment — attacker scenario engine"
    },
    "Main": {
      "subnet": "17.93.8.0/29",
      "docker_name": "main",
      "description": "Transit segment connecting the Blue border router to the scenario/internet node"
    },
    "External": {
      "subnet": "any",
      "docker_name": "external",
      "description": "Simulates the internet — attacker hosts fake domains, C2 infra, and traffic generation"
    }
  },
  "machines": {
    "attacker": {
      "OS": "Kali (rolling)",
      "CPUs": "4",
      "Memory (GB)": "6",
      "HDD Size (GB)": "80",
      "description": "Scenario engine and fake internet node. Runs attack orchestration (Salt Master, Metasploit, CRAM) alongside simulated internet services (CoreDNS, Caddy HTTPS, SMTP, traffic generators). Scenarios stored at /home/trainer/scenarios.",
      "deploy": {
        "type": "linux-container",
        "image": "kalilinux/kali-rolling",
        "mem_limit": "6g",
        "cap_add": ["NET_ADMIN", "NET_RAW"],
        "privileged": false,
        "volumes": ["./scenarios:/home/trainer/scenarios", "./www:/var/www/html"],
      },
      "interfaces": [
        {"network": "Scenario", "ip": "9.53.99.47/24"},
        {"network": "Main",     "ip": "17.93.8.4/29"},
        {"network": "External", "ip": "any"},
        {"network": "C2",       "ip": "172.16.0.1/24"}
      ]
    },
    "router": {
      "OS": "Linux (FRRouting)",
      "CPUs": "1",
      "Memory (GB)": "0.25",
      "HDD Size (GB)": "1",
      "description": "Blue-side border router running FRRouting. Routes traffic between the Main segment and the DMZ via the Router-DMZ transit link.",
      "deploy": {
        "type": "linux-router",
        "image": "frrouting/frr:latest",
        "mem_limit": "256m",
        "cap_add": ["NET_ADMIN", "NET_RAW", "SYS_ADMIN"],
        "sysctls": ["net.ipv4.ip_forward=1"],
      },
      "interfaces": [
        {"network": "Router-DMZ", "ip": "130.2.2.1/24"},
        {"network": "Main",       "ip": "17.93.8.1/29"}
      ]
    },
    "fw-dmz": {
      "OS": "Linux (iptables/nftables)",
      "CPUs": "1",
      "Memory (GB)": "0.25",
      "HDD Size (GB)": "1",
      "description": "DMZ perimeter firewall running nftables. Connects the border router to the DMZ internal segment and passes traffic toward the central firewall.",
      "deploy": {
        "type": "linux-firewall",
        "image": "debian:bookworm-slim",
        "mem_limit": "256m",
        "cap_add": ["NET_ADMIN", "NET_RAW"],
        "sysctls": ["net.ipv4.ip_forward=1"],
        "volumes": ["./config/fw-dmz/nftables.conf:/etc/nftables.conf:ro"],
      },
      "interfaces": [
        {"network": "Management",   "ip": "172.31.202.140/24"},
        {"network": "Firewall",     "ip": "192.168.254.242/30"},
        {"network": "DMZ_Internal", "ip": "172.16.100.254/24"},
        {"network": "Router-DMZ",   "ip": "130.2.2.2/24"}
      ]
    },
    "fw-core": {
      "OS": "Linux (iptables/nftables)",
      "CPUs": "1",
      "Memory (GB)": "0.25",
      "HDD Size (GB)": "1",
      "description": "Central firewall and core router running nftables. Connects and segments the Server, User, SOC, SIEM, and DB zones.",
      "deploy": {
        "type": "linux-firewall",
        "image": "debian:bookworm-slim",
        "mem_limit": "256m",
        "cap_add": ["NET_ADMIN", "NET_RAW"],
        "sysctls": ["net.ipv4.ip_forward=1"],
        "volumes": ["./config/fw-central/nftables.conf:/etc/nftables.conf:ro"],
      },
      "interfaces": [
        {"network": "Management", "ip": "172.31.202.139/24"},
        {"network": "Firewall",   "ip": "192.168.254.241/30"},
        {"network": "Server",     "ip": "192.168.200.254/24"},
        {"network": "User",       "ip": "192.168.100.254/24"},
        {"network": "SOC",        "ip": "192.168.110.254/24"},
        {"network": "SIEM",       "ip": "192.168.66.254/24"},
        {"network": "DB",         "ip": "192.168.214.254/24"}
      ]
    },
    "web-lin": {
      "OS": "Ubuntu 22.04",
      "CPUs": "1",
      "Memory (GB)": "0.5",
      "HDD Size (GB)": "5",
      "description": "Linux DMZ web server running Apache. Hosts a lifestyle/magazine website. Vulnerable web application surface for initial access scenarios.",
      "deploy": {
        "type": "linux-container",
        "image": "ubuntu:22.04",
        "mem_limit": "512m",
        "volumes": ["./webapps/web01:/var/www/html:ro"],
      },
      "interfaces": [
        {"network": "C2",           "ip": "172.16.0.40/24"},
        {"network": "DMZ_Internal", "ip": "172.16.100.10/24"},
        {"network": "DMZ_External", "ip": "130.2.2.4/24"}
      ]
    },
    "web-win": {
      "OS": "Windows Server 2025 Core",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "60",
      "description": "Windows DMZ web server running IIS. Hosts a corporate services website. Primary Windows target for web exploitation, WebShell deployment, and lateral movement pivot into internal segments.",
      "deploy": {
        "type": "windows-container",
        "image": "ghcr.io/dockur/windows",
        "mem_limit": "4g",
        "requires_kvm": true,
        "environment": {
          "VERSION": "2025",
          "RAM_SIZE": "4G",
          "CPU_CORES": "2",
          "DISK_SIZE": "60G"
        },
        "devices": ["/dev/kvm"],
      },
      "interfaces": [
        {"network": "C2",           "ip": "172.16.0.42/24"},
        {"network": "DMZ_Internal", "ip": "172.16.100.12/24"},
        {"network": "DMZ_External", "ip": "130.2.2.12/24"}
      ]
    },
    "dns-dmz": {
      "OS": "Ubuntu 22.04",
      "CPUs": "1",
      "Memory (GB)": "0.5",
      "HDD Size (GB)": "5",
      "description": "DMZ DNS server. Provides name resolution within the DMZ. Used in DNS tunneling and C2-over-DNS scenarios as a pivot point.",
      "deploy": {
        "type": "linux-container",
        "image": "ubuntu:22.04",
        "mem_limit": "512m",
      },
      "interfaces": [
        {"network": "C2",           "ip": "172.16.0.44/24"},
        {"network": "DMZ_Internal", "ip": "172.16.100.6/24"},
        {"network": "DMZ_External", "ip": "130.2.2.6/24"}
      ]
    },
    "mail-relay": {
      "OS": "Ubuntu 22.04",
      "CPUs": "1",
      "Memory (GB)": "0.25",
      "HDD Size (GB)": "2",
      "description": "Postfix mail relay in the DMZ. Accepts inbound SMTP from the External segment and relays to exchange internally. Used in phishing delivery and SMTP exfiltration scenarios.",
      "deploy": {
        "type": "linux-container",
        "image": "boky/postfix",
        "mem_limit": "256m",
        "environment": {
          "RELAYHOST": "192.168.200.10",
          "ALLOWED_SENDER_DOMAINS": "holey.net"
        },
      },
      "interfaces": [
        {"network": "C2",           "ip": "172.16.0.45/24"},
        {"network": "DMZ_Internal", "ip": "172.16.100.8/24"},
        {"network": "DMZ_External", "ip": "130.2.2.20/24"}
      ]
    },
    "dc01": {
      "OS": "Windows Server 2025 Core",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "60",
      "description": "Primary Active Directory Domain Controller for the holey.net domain. Runs AD DS, DNS, AD CS (PKI), and Kerberos. High-value target for credential attacks, DCSync, Golden Ticket, and ADCS scenarios (ESC1, ESC4, ESC8).",
      "deploy": {
        "type": "windows-container",
        "image": "ghcr.io/dockur/windows",
        "mem_limit": "4g",
        "requires_kvm": true,
        "environment": {
          "VERSION": "2025",
          "RAM_SIZE": "4G",
          "CPU_CORES": "2",
          "DISK_SIZE": "60G"
        },
        "devices": ["/dev/kvm"],
      },
      "interfaces": [
        {"network": "C2",    "ip": "172.16.0.70/24"},
        {"network": "Server","ip": "192.168.200.1/24"}
      ]
    },
    "exchange": {
      "OS": "Windows Server 2025 Core",
      "CPUs": "2",
      "Memory (GB)": "6",
      "HDD Size (GB)": "60",
      "description": "Microsoft Exchange mail server for the holey.net domain. Receives mail relayed from mail-relay. Used in phishing, email exfiltration, and credential harvesting scenarios.",
      "deploy": {
        "type": "windows-container",
        "image": "ghcr.io/dockur/windows",
        "mem_limit": "6g",
        "requires_kvm": true,
        "environment": {
          "VERSION": "2025",
          "RAM_SIZE": "6G",
          "CPU_CORES": "2",
          "DISK_SIZE": "60G"
        },
        "devices": ["/dev/kvm"],
      },
      "interfaces": [
        {"network": "C2",    "ip": "172.16.0.72/24"},
        {"network": "Server","ip": "192.168.200.10/24"}
      ]
    },
    "fileserver": {
      "OS": "Windows Server 2025 Core",
      "CPUs": "1",
      "Memory (GB)": "2",
      "HDD Size (GB)": "60",
      "description": "File server with SMB shares accessible to domain users. Also runs Print Spooler service (enabled, intentionally vulnerable). Used for lateral movement via UNC paths, PrintNightmare exploitation, data staging, ransomware simulation, and exfiltration scenarios.",
      "deploy": {
        "type": "windows-container",
        "image": "ghcr.io/dockur/windows",
        "mem_limit": "2g",
        "requires_kvm": true,
        "environment": {
          "VERSION": "2025",
          "RAM_SIZE": "2G",
          "CPU_CORES": "1",
          "DISK_SIZE": "60G"
        },
        "devices": ["/dev/kvm"],
      },
      "interfaces": [
        {"network": "C2",    "ip": "172.16.0.74/24"},
        {"network": "Server","ip": "192.168.200.6/24"}
      ]
    },
    "db01": {
      "OS": "Ubuntu 22.04",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "40",
      "description": "Microsoft SQL Server database host (Linux). Stores application databases for web servers and internal services. Used in SQL injection, credential dumping via xp_cmdshell, and data exfiltration scenarios.",
      "deploy": {
        "type": "linux-container",
        "image": "mcr.microsoft.com/mssql/server:2022-latest",
        "mem_limit": "4g",
        "environment": {
          "ACCEPT_EULA": "Y",
          "MSSQL_SA_PASSWORD": "P@ssw0rd123!"
        },
      },
      "interfaces": [
        {"network": "C2","ip": "172.16.0.30/24"},
        {"network": "DB", "ip": "192.168.214.10/24"}
      ]
    },
    "wks-linux": {
      "OS": "Ubuntu 24.04",
      "CPUs": "1",
      "Memory (GB)": "1",
      "HDD Size (GB)": "10",
      "description": "Linux developer workstation. Simulates a developer or engineering endpoint on the corporate network. Used in Linux persistence, LD_PRELOAD rootkit, and SSH key harvesting scenarios.",
      "deploy": {
        "type": "linux-container",
        "image": "ubuntu:24.04",
        "mem_limit": "1g",
      },
      "interfaces": [
        {"network": "C2",  "ip": "172.16.0.100/24"},
        {"network": "User","ip": "192.168.100.10/24"}
      ]
    },
    "wks-win10": {
      "OS": "Windows 10",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "60",
      "description": "Windows 10 user workstation joined to holey.net domain. Standard corporate endpoint. Primary target for phishing payload delivery, credential harvesting, and lateral movement.",
      "deploy": {
        "type": "windows-container",
        "image": "ghcr.io/dockur/windows",
        "mem_limit": "4g",
        "requires_kvm": true,
        "environment": {
          "VERSION": "win10",
          "RAM_SIZE": "4G",
          "CPU_CORES": "2",
          "DISK_SIZE": "60G"
        },
        "devices": ["/dev/kvm"]
      },
      "interfaces": [
        {"network": "C2",  "ip": "172.16.0.101/24"},
        {"network": "User","ip": "192.168.100.11/24"}
      ]
    },
    "wks-win11": {
      "OS": "Windows 11",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "60",
      "description": "Windows 11 user workstation joined to holey.net domain. Modern endpoint for testing detection of attacks against current-generation OS defenses (SmartScreen, Credential Guard, AMSI).",
      "deploy": {
        "type": "windows-container",
        "image": "ghcr.io/dockur/windows",
        "mem_limit": "4g",
        "requires_kvm": true,
        "environment": {
          "VERSION": "win11",
          "RAM_SIZE": "4G",
          "CPU_CORES": "2",
          "DISK_SIZE": "60G"
        },
        "devices": ["/dev/kvm"],
      },
      "interfaces": [
        {"network": "C2",  "ip": "172.16.0.102/24"},
        {"network": "User","ip": "192.168.100.12/24"}
      ]
    },
    "wks-win7": {
      "OS": "Windows 7 SP1",
      "CPUs": "1",
      "Memory (GB)": "2",
      "HDD Size (GB)": "20",
      "description": "Legacy Windows 7 user workstation joined to holey.net domain. Intentionally unpatched to support EternalBlue (MS17-010) and other legacy exploit scenarios.",
      "deploy": {
        "type": "windows-container",
        "image": "ghcr.io/dockur/windows",
        "mem_limit": "2g",
        "requires_kvm": true,
        "environment": {
          "VERSION": "win7",
          "RAM_SIZE": "2G",
          "CPU_CORES": "1",
          "DISK_SIZE": "20G"
        },
        "devices": ["/dev/kvm"],
      },
      "interfaces": [
        {"network": "C2",  "ip": "172.16.0.103/24"},
        {"network": "User","ip": "192.168.100.13/24"}
      ]
    },
    "wazuh": {
      "OS": "Ubuntu 22.04",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "50",
      "description": "Wazuh all-in-one SIEM — manager, indexer, and dashboard. Receives logs and events from Wazuh agents on all hosts. Provides MITRE ATT&CK-mapped alerting, file integrity monitoring, vulnerability detection, and active response.",
      "deploy": {
        "type": "linux-container",
        "image": "wazuh/wazuh-odfe:latest",
        "mem_limit": "4g",
        "environment": {
          "WAZUH_MANAGER": "0.0.0.0",
          "WAZUH_API_USER": "wazuh",
          "WAZUH_API_PASSWORD": "changeme123!"
        },
        "volumes": [
          "./data/wazuh/data:/var/ossec/data",
          "./data/wazuh/logs:/var/ossec/logs",
          "./config/wazuh/ossec.conf:/var/ossec/etc/ossec.conf:ro"
        ],
        "ports": ["1514:1514/udp", "1515:1515", "55000:55000", "443:443"],
      },
      "interfaces": [
        {"network": "SIEM","ip": "192.168.66.50/24"}
      ]
    },
    "soc-ws": {
      "OS": "Windows 10",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "60",
      "description": "SOC analyst workstation. Pre-loaded with investigation tools (Zenmap, Ghidra, browser shortcuts to SIEMs). Accessible via Guacamole from the access/training portal.",
      "deploy": {
        "type": "windows-container",
        "image": "ghcr.io/dockur/windows",
        "mem_limit": "4g",
        "requires_kvm": true,
        "environment": {
          "VERSION": "win10",
          "RAM_SIZE": "4G",
          "CPU_CORES": "2",
          "DISK_SIZE": "60G"
        },
        "devices": ["/dev/kvm"],
      },
      "interfaces": [
        {"network": "Management","ip": "172.31.202.11/24"},
        {"network": "C2",        "ip": "172.16.0.80/24"},
        {"network": "SOC",       "ip": "192.168.110.11/24"}
      ]
    }
  },
  "layout": {
    "_note": "Controls the visual layout of the network map. Edit zone positions, colors, and dimensions here. Add a new zone entry to make a new segment appear on the diagram.",
    "chain": {
      "y":          270,
      "startX":     28,
      "nodeW":      130,
      "nodeH":      48,
      "gap":        16,
      "zonePad":    10,
      "zoneLabelH": 18,
      "nodeGap":    6
    },
    "colors": {
      "nodeType": {
        "linux":   "#1e6e3a",
        "windows": "#1e4e96",
        "fw":      "#8c4e14"
      },
      "attackZone": {
        "bgColor":     "#1a0c38",
        "strokeColor": "#6e3fd4",
        "labelColor":  "#bc8cff"
      },
      "typeBorder": {
        "linux":   "#2d3748",
        "windows": "#2d3748",
        "fw":      "#2d3748"
      }
    },
    "zones": [
      {
        "id":            "DMZ",
        "label":         "DMZ",
        "bgColor":       "#0a1830",
        "x":             18,
        "y":             390,
        "cols":          3,
        "nodeW":         117,
        "nodeH":         38,
        "segment":       "DMZ_Internal",
        "connectorSide": "top"
      },
      {
        "id":            "Server",
        "label":         "SERVER",
        "bgColor":       "#081c0e",
        "x":             530,
        "y":             60,
        "cols":          3,
        "nodeW":         120,
        "nodeH":         38,
        "segment":       "Server",
        "connectorSide": "bottom"
      },
      {
        "id":            "SOC",
        "label":         "SOC",
        "bgColor":       "#0c0a24",
        "x":             848,
        "y":             248,
        "cols":          1,
        "nodeW":         196,
        "nodeH":         38,
        "segment":       "SOC",
        "connectorSide": "left"
      },
      {
        "id":            "User",
        "label":         "USERS",
        "bgColor":       "#1a1206",
        "x":             848,
        "y":             390,
        "cols":          2,
        "nodeW":         102,
        "nodeH":         38,
        "segment":       "User",
        "connectorSide": "left"
      },
      {
        "id":            "SIEM",
        "label":         "SIEM",
        "bgColor":       "#080e1e",
        "x":             530,
        "y":             600,
        "cols":          2,
        "nodeW":         112,
        "nodeH":         38,
        "segment":       "SIEM",
        "connectorSide": "top"
      },
      {
        "id":            "DB",
        "label":         "DB",
        "bgColor":       "#1c060e",
        "x":             848,
        "y":             600,
        "cols":          1,
        "nodeW":         196,
        "nodeH":         38,
        "segment":       "DB",
        "connectorSide": "left"
      }
    ]
  },
  "profiles": {
    "_note": "Use Docker Compose profiles to run scenario-specific subsets and stay within 32 GB RAM.",
    "core": {
      "description": "Minimum viable range — covers lateral movement, AD attacks, credential dumping. ~20 GB RAM.",
      "services": ["attacker","fw-dmz","fw-core","dc01","wks-win10","wazuh"]
    },
    "web-attack": {
      "description": "Adds DMZ web servers and DB for initial access → pivot scenarios. ~28 GB RAM.",
      "services": ["core", "router","web-lin","web-win","dns-dmz","mail-relay","exchange","db01"]
    },
    "full": {
      "description": "All services. Requires ~64 GB RAM — suitable for cloud or future hardware upgrade.",
      "services": ["all"]
    }
  }
};
