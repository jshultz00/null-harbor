// KVM/libvirt Null Harbor Network Map
// Edit this file to modify the network topology for the local KVM environment
const NETWORK_MAP_DATA = {
  "_meta": {
    "version": "1.0",
    "description": "Null Harbor KVM/libvirt cyber range — local attack/defense training environment",
    "deployment": "libvirt/kvm",
    "host_requirements": {
      "note": "KVM hypervisor with libvirt. Network: c2 (10.0.0.0/24)",
      "min_ram_all_up": "~16 GB"
    }
  },
  "networks": {
    "c2": {
      "subnet": "10.0.0.0/24",
      "libvirt_name": "c2",
      "description": "Internal isolated network — no internet routing"
    }
  },
  "machines": {
    "attacker": {
      "OS": "Kali Linux 2026.1",
      "CPUs": "4",
      "Memory (GB)": "6",
      "HDD Size (GB)": "80",
      "description": "Attacker VM running Kali Linux. Primary system for launching attacks against targets. Pre-installed with Metasploit, nmap, Impacket, BloodHound, CrackMapExec, and other pentesting tools. Baseline snapshot: initialsnap",
      "deploy": {
        "type": "kvm-vm",
        "image": "disks/kali-linux-2026.1-qemu-amd64.qcow2",
        "mem_limit": "6g",
        "cpus": 4,
        "disk_size": "80g"
      },
      "interfaces": [
        {"network": "c2", "ip": "10.0.0.1/24"}
      ]
    },
    "user-ubuntu24": {
      "OS": "Ubuntu 24.04 Server",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "40",
      "description": "Linux target VM running Ubuntu 24.04. Primary target for Linux exploitation, privilege escalation, and persistence exercises. Baseline snapshot: initialsnap",
      "deploy": {
        "type": "kvm-vm",
        "image": "disks/ubuntu-target.qcow2",
        "mem_limit": "4g",
        "cpus": 2,
        "disk_size": "40g"
      },
      "interfaces": [
        {"network": "c2", "ip": "10.0.0.100/24"}
      ]
    },
    "user-windows10": {
      "OS": "Windows 10 Enterprise 22H2",
      "CPUs": "2",
      "Memory (GB)": "4",
      "HDD Size (GB)": "60",
      "description": "Windows target VM. Primary Windows target for malware analysis, lateral movement, and Windows exploitation. Domain isolation by design. Baseline snapshot: initialsnap. Evaluation activated via slmgr /rearm (3 rearms available)",
      "deploy": {
        "type": "kvm-vm",
        "image": "disks/windows-target.qcow2",
        "mem_limit": "4g",
        "cpus": 2,
        "disk_size": "60g"
      },
      "interfaces": [
        {"network": "c2", "ip": "10.0.0.101/24"}
      ]
    }
  },
  "layout": {
    "_note": "Visual layout configuration for network map diagram",
    "chain": {
      "y":          180,
      "startX":     60,
      "nodeW":      140,
      "nodeH":      50,
      "gap":        80,
      "zonePad":    20,
      "zoneLabelH": 20,
      "nodeGap":    8
    },
    "colors": {
      "nodeType": {
        "linux":   "#2a9a51",
        "windows": "#2a6dd2",
        "attacker": "#ff3333"
      },
      "networkZone": {
        "bgColor":     "#0a1a2e",
        "strokeColor": "#16c784",
        "labelColor":  "#00ff41"
      }
    },
    "zones": [
      {
        "id":            "Attackers",
        "label":         "ATTACKERS",
        "bgColor":       "#1a0a0a",
        "x":             20,
        "y":             40,
        "cols":          1,
        "nodeW":         160,
        "nodeH":         48,
        "segment":       "attacker",
        "connectorSide": "bottom"
      },
      {
        "id":            "Users",
        "label":         "USERS",
        "bgColor":       "#0a1a2e",
        "x":             220,
        "y":             40,
        "cols":          2,
        "nodeW":         140,
        "nodeH":         48,
        "segment":       "c2",
        "connectorSide": "top"
      }
    ]
  }
};

// ============================================================================
// RENDER NETWORK MAP
// ============================================================================

const SVG_NS = "http://www.w3.org/2000/svg";
let currentSelectedNode = null;

function initNetworkMap() {
  const canvas = document.getElementById('diagram');
  if (!canvas) return;
  
  canvas.innerHTML = '';
  renderNetwork();
  setupDetailPanel();
}

function renderNetwork() {
  const canvas = document.getElementById('diagram');
  const layout = NETWORK_MAP_DATA.layout;
  const zones = layout.zones;
  
  let maxX = 0, maxY = 0;
  
  // Render zones and machines
  zones.forEach(zone => {
    const machines = getMachinesBySegment(zone.segment);
    const zoneW = zone.cols * (zone.nodeW + 20) + 40;
    const zoneH = Math.ceil(machines.length / zone.cols) * (zone.nodeH + 20) + 60;
    
    maxX = Math.max(maxX, zone.x + zoneW);
    maxY = Math.max(maxY, zone.y + zoneH);
    
    // Zone background
    const zoneRect = document.createElementNS(SVG_NS, 'rect');
    zoneRect.setAttribute('x', zone.x);
    zoneRect.setAttribute('y', zone.y);
    zoneRect.setAttribute('width', zoneW);
    zoneRect.setAttribute('height', zoneH);
    zoneRect.setAttribute('fill', zone.bgColor);
    zoneRect.setAttribute('stroke', layout.colors.networkZone.strokeColor);
    zoneRect.setAttribute('stroke-width', '2');
    zoneRect.setAttribute('rx', '4');
    canvas.appendChild(zoneRect);
    
    // Zone label
    const zoneLabel = document.createElementNS(SVG_NS, 'text');
    zoneLabel.setAttribute('x', zone.x + 12);
    zoneLabel.setAttribute('y', zone.y + 24);
    zoneLabel.setAttribute('font-size', '11px');
    zoneLabel.setAttribute('font-weight', 'bold');
    zoneLabel.setAttribute('fill', layout.colors.networkZone.labelColor);
    zoneLabel.setAttribute('letter-spacing', '2');
    zoneLabel.textContent = zone.label;
    canvas.appendChild(zoneLabel);
    
    // Machines in zone
    let machineIdx = 0;
    machines.forEach((mName, idx) => {
      const machine = NETWORK_MAP_DATA.machines[mName];
      const col = idx % zone.cols;
      const row = Math.floor(idx / zone.cols);
      const nodeX = zone.x + 20 + col * (zone.nodeW + 20);
      const nodeY = zone.y + 50 + row * (zone.nodeH + 20);
      
      renderMachineNode(canvas, mName, machine, nodeX, nodeY, zone.nodeW, zone.nodeH);
    });
  });
  
  // Set canvas size
  canvas.setAttribute('width', maxX + 40);
  canvas.setAttribute('height', maxY + 40);
}

function getMachinesBySegment(segment) {
  const machines = NETWORK_MAP_DATA.machines;
  if (segment === 'attacker') {
    return ['attacker'];
  } else if (segment === 'c2') {
    return ['user-ubuntu24', 'user-windows10'];
  }
  return [];
}

function renderMachineNode(canvas, machineName, machine, x, y, w, h) {
  const osType = machine.OS.toLowerCase().includes('windows') 
    ? 'windows' 
    : machine.OS.toLowerCase().includes('kali')
    ? 'attacker'
    : 'linux';
  const color = NETWORK_MAP_DATA.layout.colors.nodeType[osType] || '#666';
  
  // Create group
  const group = document.createElementNS(SVG_NS, 'g');
  group.setAttribute('class', 'node-group');
  group.addEventListener('click', () => selectNode(machineName, machine));
  
  // Node rect
  const rect = document.createElementNS(SVG_NS, 'rect');
  rect.setAttribute('class', 'node-rect');
  rect.setAttribute('x', x);
  rect.setAttribute('y', y);
  rect.setAttribute('width', w);
  rect.setAttribute('height', h);
  rect.setAttribute('fill', color);
  rect.setAttribute('stroke', '#444');
  rect.setAttribute('stroke-width', '1');
  rect.setAttribute('rx', '3');
  group.appendChild(rect);
  
  // Machine name
  const nameText = document.createElementNS(SVG_NS, 'text');
  nameText.setAttribute('class', 'node-label');
  nameText.setAttribute('x', x + w / 2);
  nameText.setAttribute('y', y + 16);
  nameText.setAttribute('text-anchor', 'middle');
  nameText.textContent = machineName;
  group.appendChild(nameText);
  
  // IP address
  const ip = machine.interfaces[0]?.ip || 'N/A';
  const ipText = document.createElementNS(SVG_NS, 'text');
  ipText.setAttribute('class', 'node-sub');
  ipText.setAttribute('x', x + w / 2);
  ipText.setAttribute('y', y + 32);
  ipText.setAttribute('text-anchor', 'middle');
  ipText.textContent = ip;
  group.appendChild(ipText);
  
  canvas.appendChild(group);
}

function selectNode(machineName, machine) {
  // Update selection styling
  document.querySelectorAll('.node-group').forEach(g => g.classList.remove('selected'));
  const nodes = document.querySelectorAll('.node-group');
  nodes.forEach(n => {
    if (n.querySelector('.node-label').textContent === machineName) {
      n.classList.add('selected');
    }
  });
  
  currentSelectedNode = { name: machineName, data: machine };
  updateDetailPanel(machineName, machine);
}

function setupDetailPanel() {
  const detailTabs = document.querySelectorAll('[data-tab]');
  detailTabs.forEach(btn => {
    btn.addEventListener('click', (e) => {
      const tabName = e.target.dataset.tab;
      detailTabs.forEach(b => b.classList.remove('active'));
      e.target.classList.add('active');
      document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
      document.getElementById(`tab-${tabName}`)?.classList.add('active');
    });
  });
}

function updateDetailPanel(machineName, machine) {
  const detailDiv = document.getElementById('detail');
  const placeholder = document.getElementById('detail-placeholder');
  
  if (!detailDiv) return;
  
  let html = `
    <h2>${machineName}</h2>
    <div class="os">${machine.OS}</div>
    <div class="detail-row">
      <span class="detail-label">CPUS</span>
      <span class="detail-val">${machine.CPUs}</span>
    </div>
    <div class="detail-row">
      <span class="detail-label">MEMORY</span>
      <span class="detail-val">${machine['Memory (GB)']} GB</span>
    </div>
    <div class="detail-row">
      <span class="detail-label">DISK</span>
      <span class="detail-val">${machine['HDD Size (GB)']} GB</span>
    </div>
    <div class="detail-row">
      <span class="detail-label">DESCRIPTION</span>
    </div>
    <div style="font-size:0.75rem; color:#c9d1d9; margin-bottom:12px; line-height:1.5;">
      ${machine.description}
    </div>
  `;
  
  if (machine.interfaces && machine.interfaces.length > 0) {
    html += '<div style="margin-top:12px;">';
    machine.interfaces.forEach(iface => {
      html += `<div class="iface-item"><span>${iface.network}</span> ${iface.ip}</div>`;
    });
    html += '</div>';
  }
  
  detailDiv.innerHTML = html;
  detailDiv.style.display = 'block';
  if (placeholder) placeholder.style.display = 'none';
}

// Init on load
document.addEventListener('DOMContentLoaded', initNetworkMap);
