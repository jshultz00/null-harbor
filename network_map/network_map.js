// Edit this file to add, remove, or modify machines and networks.
// The HTML loads this directly via <script src>, so it works with file:// (no server needed).
const NETWORK_MAP_DATA = {
  "_meta": {
    "version": "5.0",
    "description": "secure.net Local Cyber Range — container-based attack/defense training environment. Linux services run as Docker containers. Windows targets run via dockur/windows with KVM. Segmented corporate network with DMZ, internal servers, user workstations, SIEM, and database zones. OOB management via Saffron (Go binary, REST API). Participant access via WireGuard VPN.",
    "deployment": "docker-compose",
    "host_requirements": {
      "note": "dockur/windows requires KVM (/dev/kvm). Host user must be in kvm and docker groups. All Linux containers run on any Docker host.",
      "min_ram_all_up": "~50 GB"
    }
  },
  "networks": {
    "external": {
      "subnet": "5.79.99.0/24",
      "docker_name": "external",
      "description": "Fake internet — scenario engine hosts C2 infra, fake domains, and attacker IP aliases"
    },
    "dmz": {
      "subnet": "10.10.10.0/24",
      "docker_name": "dmz",
      "description": "DMZ web server segment"
    },
    "server": {
      "subnet": "10.20.20.0/24",
      "docker_name": "server",
      "description": "Internal server segment — AD, Exchange, fileserver"
    },
    "users": {
      "subnet": "10.30.30.0/24",
      "docker_name": "users",
      "description": "User workstation segment — mixed OS corporate endpoints"
    },
    "db": {
      "subnet": "10.40.40.0/24",
      "docker_name": "db",
      "description": "Database segment — MSSQL server"
    },
    "siem": {
      "subnet": "10.50.50.0/24",
      "docker_name": "siem",
      "description": "SIEM tooling segment — Wazuh stack + rsyslog"
    },
    "vpn": {
      "subnet": "10.99.0.0/24",
      "docker_name": "vpn",
      "description": "WireGuard participant VPN — participants bring their own laptop as SOC workstation"
    }
  },
  "machines": {
    "scenario": {
      "OS": "Kali (rolling)",
      "CPUs": "4",
      "Memory (GB)": "6",
      "HDD Size (GB)": "80",
      "description": "Scenario engine and fake internet node. Runs attack tools (Metasploit, nmap, Impacket, BloodHound, CrackMapExec, Responder, Sliver C2, Evil-WinRM) and fake internet services (Caddy HTTPS, CoreDNS). Saffron server. SSH access from host on port 2222. Scenarios mounted at /home/trainer/scenarios.",
      "deploy": {
        "type": "linux-container",
        "image": "cyber-range/scenario:local (build: ./dockerfiles/scenario)",
        "mem_limit": "6g",
        "cap_add": ["NET_ADMIN", "NET_RAW"],
        "privileged": false,
        "volumes": ["./scenarios:/home/trainer/scenarios", "./www:/var/www/html"]
      },
      "interfaces": [
        {"network": "external", "ip": "5.79.99.1/24"}
      ]
    },
    "fw-dmz": {
      "OS": "Linux (nftables)",
      "CPUs": "1",
      "Memory (GB)": "0.25",
      "HDD Size (GB)": "1",
      "description": "DMZ perimeter firewall running nftables. Connects the fake internet (external) to the DMZ segment. SNAT rules support attacker IP diversity — phase scripts can present arbitrary source IPs to defenders.",
      "deploy": {
        "type": "linux-firewall",
        "image": "debian:bookworm-slim",
        "mem_limit": "256m",
        "cap_add": ["NET_ADMIN", "NET_RAW"],
        "sysctls": ["net.ipv4.ip_forward=1"],
        "volumes": ["./config/fw-dmz/nftables.conf:/etc/nftables.conf:ro"]
      },
      "interfaces": [
        {"network": "external", "ip": "5.79.99.2/24"},
        {"network": "dmz",      "ip": "10.10.10.1/24"}
      ]
    },
    "fw-core": {
      "OS": "Linux (nftables)",
      "CPUs": "1",
      "Memory (GB)": "0.25",
      "HDD Size (GB)": "1",
      "description": "Central firewall and core router running nftables. Connects the DMZ to all internal segments (server, users, db, siem). Policy-based routing between zones.",
      "deploy": {
        "type": "linux-firewall",
        "image": "debian:bookworm-slim",
        "mem_limit": "256m",
        "cap_add": ["NET_ADMIN", "NET_RAW"],
        "sysctls": ["net.ipv4.ip_forward=1"],
        "volumes": ["./config/fw-core/nftables.conf:/etc/nftables.conf:ro"]
      },
      "interfaces": [
        {"network": "dmz",     "ip": "10.10.10.2/24"},
        {"network": "server",  "ip": "10.20.20.1/24"},
        {"network": "users",   "ip": "10.30.30.1/24"},
        {"network": "db",      "ip": "10.40.40.1/24"},
        {"network": "siem",    "ip": "10.50.50.1/24"}
      ]
    },
    "wireguard": {
      "OS": "Linux (WireGuard)",
      "CPUs": "1",
      "Memory (GB)": "0.25",
      "HDD Size (GB)": "1",
      "description": "WireGuard VPN server. Participants connect from their own laptops to act as SOC workstations with visibility into the range. Generate a peer config with: make vpn-config PEER=alice",
      "deploy": {
        "type": "linux-container",
        "image": "linuxserver/wireguard",
        "mem_limit": "256m",
        "cap_add": ["NET_ADMIN", "SYS_MODULE"],
        "sysctls": ["net.ipv4.ip_forward=1"],
        "volumes": ["./config/wireguard:/config"]
      },
      "interfaces": [
        {"network": "vpn",     "ip": "10.99.0.1/24"}
      ]
    },
    "wazuh.manager": {
      "OS": "Linux (Wazuh 4.9.x)",
      "CPUs": "2",
      "Memory (GB)": "2",
      "HDD Size (GB)": "20",
      "description": "Wazuh manager: agent enrollment (PSK), OSSEC rules, and alert processing. Run 'make build' to generate TLS certs before first 'make up'.",
      "deploy": {
        "type": "linux-container",
        "image": "wazuh/wazuh-manager:4.9.2",
        "mem_limit": "2g",
        "ports": ["1514:1514", "1515:1515", "55000:55000"],
        "certs": "config/wazuh/certs/ — generated by 'make certs'"
      },
      "interfaces": [
        {"network": "siem",    "ip": "10.50.50.5/24"}
      ]
    },
    "wazuh.indexer": {
      "OS": "Linux (OpenSearch)",
      "CPUs": "2",
      "Memory (GB)": "2",
      "HDD Size (GB)": "20",
      "description": "Wazuh indexer: OpenSearch data store for SIEM alerts and event history.",
      "deploy": {
        "type": "linux-container",
        "image": "wazuh/wazuh-indexer:4.9.2",
        "mem_limit": "2g"
      },
      "interfaces": [
        {"network": "siem",    "ip": "10.50.50.6/24"}
      ]
    },
    "wazuh.dashboard": {
      "OS": "Linux (Wazuh Dashboard)",
      "CPUs": "1",
      "Memory (GB)": "1",
      "HDD Size (GB)": "5",
      "description": "Wazuh dashboard: HTTPS UI served on host :443. Analyst-facing interface for alert triage, rule browsing, and agent status.",
      "deploy": {
        "type": "linux-container",
        "image": "wazuh/wazuh-dashboard:4.9.2",
        "mem_limit": "1g",
        "ports": ["443:5601"]
      },
      "interfaces": [
        {"network": "siem",    "ip": "10.50.50.7/24"}
      ]
    },
    "rsyslog": {
      "OS": "Linux (rsyslog)",
      "CPUs": "1",
      "Memory (GB)": "0.25",
      "HDD Size (GB)": "5",
      "description": "Centralized syslog collector. Receives UDP/TCP 514 from all Linux containers and forwards structured logs to Wazuh manager.",
      "deploy": {
        "type": "linux-container",
        "image": "cyber-range/rsyslog:local",
        "mem_limit": "256m",
        "volumes": ["./config/rsyslog:/etc/rsyslog.d:ro"]
      },
      "interfaces": [
        {"network": "siem",    "ip": "10.50.50.8/24"}
      ]
    },
    "web-lin": {
      "OS": "Ubuntu 22.04",
      "CPUs": "1",
      "Memory (GB)": "0.5",
      "HDD Size (GB)": "5",
      "description": "Linux DMZ web server running Apache + PHP. Hosts web01 (employee portal). Content swapped per scenario via ./webapps/web01/ volume mount. Wazuh agent pre-baked.",
      "deploy": {
        "type": "linux-container",
        "image": "cyber-range/web-lin:local (build: ./dockerfiles/web-lin)",
        "mem_limit": "512m",
        "volumes": ["./webapps/web01:/var/www/html:ro"]
      },
      "interfaces": [
        {"network": "dmz",     "ip": "10.10.10.10/24"}
      ],
      "nat": {"external_ip": "5.79.99.10", "via": "fw-dmz", "note": "DNAT through fw-dmz — reachable from scenario/external as 5.79.99.10"}
    },
    "mail-relay": {
      "OS": "Debian 12 (Postfix)",
      "CPUs": "1",
      "Memory (GB)": "0.25",
      "HDD Size (GB)": "5",
      "description": "DMZ mail relay (Postfix). Accepts inbound SMTP from the fake internet (5.79.99.25 via DNAT at fw-dmz) and relays to Exchange (10.20.20.10) for internal delivery. Provides realistic SMTP traffic artifacts — Received headers, relay logs — for phishing and email-based attack scenarios. Wazuh agent pre-baked.",
      "deploy": {
        "type": "linux-container",
        "image": "cyber-range/mail-relay:local (build: ./dockerfiles/mail-relay)",
        "mem_limit": "256m",
        "volumes": ["./config/mail-relay/main.cf:/etc/postfix/main.cf:ro"]
      },
      "interfaces": [
        {"network": "dmz",     "ip": "10.10.10.20/24"}
      ],
      "nat": {"external_ip": "5.79.99.25", "via": "fw-dmz", "note": "DNAT through fw-dmz — inbound SMTP (:25) from scenario/external reaches mail-relay as 5.79.99.25"}
    },
    "web-win": {
      "OS": "Windows Server 2025 Core",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "60",
      "description": "Windows DMZ web server running IIS. Primary Windows target for web exploitation, WebShell deployment, and lateral movement pivot into internal segments.",
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
        "devices": ["/dev/kvm"]
      },
      "interfaces": [
        {"network": "dmz",     "ip": "10.10.10.12/24"}
      ],
      "nat": {"external_ip": "5.79.99.12", "via": "fw-dmz", "note": "DNAT through fw-dmz — reachable from scenario/external as 5.79.99.12"}
    },
    "dc01": {
      "OS": "Windows Server 2025 Core",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "60",
      "description": "Primary Active Directory DC for secure.net. Runs AD DS, DNS, AD CS (PKI co-hosted). High-value target for DCSync, Golden Ticket, Kerberoasting, and ADCS scenarios (ESC1/ESC4/ESC8 misconfigs baked in).",
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
        "devices": ["/dev/kvm"]
      },
      "interfaces": [
        {"network": "server",  "ip": "10.20.20.100/24"}
      ]
    },
    "exchange": {
      "OS": "Windows Server 2022 Core",
      "CPUs": "2",
      "Memory (GB)": "6",
      "HDD Size (GB)": "60",
      "description": "Microsoft Exchange 2019 mail server for secure.net. Used in phishing, email exfiltration, and credential harvesting scenarios. Fully functional mail flow (60-90 min first-boot). Exchange 2019 runs on Windows Server 2022 (the only officially supported combination as of Exchange 2019 CU13+).",
      "deploy": {
        "type": "windows-container",
        "image": "ghcr.io/dockur/windows",
        "mem_limit": "6g",
        "requires_kvm": true,
        "environment": {
          "VERSION": "2022",
          "RAM_SIZE": "6G",
          "CPU_CORES": "2",
          "DISK_SIZE": "60G"
        },
        "devices": ["/dev/kvm"]
      },
      "interfaces": [
        {"network": "server",  "ip": "10.20.20.10/24"}
      ]
    },
    "fileserver": {
      "OS": "Windows Server 2025 Core",
      "CPUs": "1",
      "Memory (GB)": "2",
      "HDD Size (GB)": "60",
      "description": "File server with SMB shares accessible to domain users. Print Spooler enabled (intentionally vulnerable — PrintNightmare). Used for lateral movement, UNC path abuse, data staging, and ransomware simulation.",
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
        "devices": ["/dev/kvm"]
      },
      "interfaces": [
        {"network": "server",  "ip": "10.20.20.20/24"}
      ]
    },
    "db01": {
      "OS": "Ubuntu 22.04",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "40",
      "description": "Microsoft SQL Server 2022 on Linux. Domain joined to secure.net via realmd/sssd. SPN registered for Kerberoasting (svc_mssql). Used in SQL injection, xp_cmdshell RCE, credential dumping, and Kerberoasting scenarios.",
      "deploy": {
        "type": "linux-container",
        "image": "cyber-range/db01:local (build: ./dockerfiles/db01)",
        "mem_limit": "4g",
        "environment": {
          "ACCEPT_EULA": "${ACCEPT_EULA}",
          "MSSQL_SA_PASSWORD": "${MSSQL_SA_PASSWORD}",
          "AD_DOMAIN": "${AD_DOMAIN}",
          "AD_ADMIN_PASSWORD": "${AD_ADMIN_PASSWORD}"
        }
      },
      "interfaces": [
        {"network": "db",      "ip": "10.40.40.10/24"}
      ]
    },
    "wks-linux": {
      "OS": "Ubuntu 24.04",
      "CPUs": "1",
      "Memory (GB)": "1",
      "HDD Size (GB)": "10",
      "description": "Linux developer workstation. devuser (developer, docker, git) and sysadmin (elevated, sudo, bash history with admin creds). Used in Linux persistence, LD_PRELOAD rootkit, SSH key harvesting, and credential reuse scenarios.",
      "deploy": {
        "type": "linux-container",
        "image": "cyber-range/wks-linux:local (build: ./dockerfiles/wks-linux)",
        "mem_limit": "1g"
      },
      "interfaces": [
        {"network": "users",   "ip": "10.30.30.10/24"}
      ]
    },
    "wks-win11": {
      "OS": "Windows 11",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "60",
      "description": "Windows 11 workstation joined to secure.net. User: SECURE\\bwilson. Modern endpoint for testing detection against current-generation OS defenses (SmartScreen, Credential Guard, AMSI).",
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
        "devices": ["/dev/kvm"]
      },
      "interfaces": [
        {"network": "users",   "ip": "10.30.30.20/24"}
      ]
    }
  },
  "nat_rules": [
    {
      "type": "DNAT",
      "firewall": "fw-dmz",
      "external_ip": "5.79.99.10",
      "proto": "tcp",
      "ports": "80,443",
      "internal_ip": "10.10.10.10",
      "machine": "web-lin",
      "note": "Inbound HTTP/HTTPS from fake internet to Linux DMZ web server"
    },
    {
      "type": "DNAT",
      "firewall": "fw-dmz",
      "external_ip": "5.79.99.12",
      "proto": "tcp",
      "ports": "80,443",
      "internal_ip": "10.10.10.12",
      "machine": "web-win",
      "note": "Inbound HTTP/HTTPS from fake internet to Windows IIS web server"
    },
    {
      "type": "DNAT",
      "firewall": "fw-dmz",
      "external_ip": "5.79.99.25",
      "proto": "tcp",
      "ports": "25",
      "internal_ip": "10.10.10.20",
      "machine": "mail-relay",
      "note": "Inbound SMTP from fake internet to DMZ mail relay"
    },
    {
      "type": "SNAT",
      "firewall": "fw-dmz",
      "source": "10.10.10.0/24",
      "masquerade_pool": "5.79.99.2–5.79.99.254",
      "note": "Outbound masquerade for DMZ → external. Phase scripts alias additional 5.79.99.x IPs on scenario and toggle SNAT rules to present diverse attacker source IPs to defenders."
    }
  ],
  "layout": {
    "_note": "Controls the visual layout of the network map. Edit zone positions, colors, and dimensions here. Add a new zone entry to make a new segment appear on the diagram.",
    "chain": {
      "y":          270,
      "startX":     28,
      "nodeW":      130,
      "nodeH":      48,
      "gap":        60,
      "zonePad":    10,
      "zoneLabelH": 18,
      "nodeGap":    6
    },
    "colors": {
      "nodeType": {
        "linux":   "#2a9a51",
        "windows": "#2a6dd2",
        "macos":   "#7e57a0",
        "fw":      "#c46d1c"
      },
      "attackZone": {
        "bgColor":     "#341870",
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
        "bgColor":       "#143060",
        "x":             0,
        "y":             500,
        "cols":          2,
        "nodeW":         140,
        "nodeH":         38,
        "segment":       "dmz",
        "connectorSide": "top"
      },
      {
        "id":            "Server",
        "label":         "SERVER",
        "bgColor":       "#10381c",
        "x":             100,
        "y":             60,
        "cols":          3,
        "nodeW":         114,
        "nodeH":         38,
        "segment":       "server",
        "connectorSide": "bottom"
      },
      {
        "id":            "VPN",
        "label":         "VPN/SOC",
        "bgColor":       "#0e2a3a",
        "x":             700,
        "y":             60,
        "cols":          1,
        "nodeW":         200,
        "nodeH":         38,
        "segment":       "vpn",
        "connectorSide": "left"
      },
      {
        "id":            "Users",
        "label":         "USERS",
        "bgColor":       "#34240c",
        "x":             730,
        "y":             240,
        "cols":          1,
        "nodeW":         200,
        "nodeH":         38,
        "segment":       "users",
        "connectorSide": "left"
      },
      {
        "id":            "SIEM",
        "label":         "SIEM",
        "bgColor":       "#101c3c",
        "x":             350,
        "y":             500,
        "cols":          2,
        "nodeW":         112,
        "nodeH":         38,
        "segment":       "siem",
        "connectorSide": "top"
      },
      {
        "id":            "DB",
        "label":         "DB",
        "bgColor":       "#380c1c",
        "x":             750,
        "y":             500,
        "cols":          1,
        "nodeW":         200,
        "nodeH":         38,
        "segment":       "db",
        "connectorSide": "left"
      },
      {
        "id":            "External",
        "label":         "EXTERNAL / SCENARIO",
        "bgColor":       "#341870",
        "segment":       "external",
        "renderMode":    "attackZone",
        "connectorSide": "right"
      }
    ],
    "autoLayout": {
      "zoneStartX":  28,
      "zoneStartY":  420,
      "colStride":   280,
      "rowStride":   160,
      "defaultCols": 2,
      "defaultNodeW": 120,
      "defaultNodeH": 38
    }
  },
};
