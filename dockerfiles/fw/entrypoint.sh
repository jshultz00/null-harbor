#!/bin/bash
# No set -e — each section logs its own errors so the container never exits silently.

echo "[fw] Starting entrypoint..."

# ── SSH ────────────────────────────────────────────────────────────────────────
echo "root:${RANGE_PASSWORD:-P@55w0rd!}" | chpasswd
ssh-keygen -A -q
mkdir -p /run/sshd
if /usr/sbin/sshd; then
    echo "[fw] SSH daemon started"
else
    echo "ERROR: [fw] SSH daemon failed to start" >&2
fi

# ── Wazuh agent configuration ─────────────────────────────────────────────────
if [ -n "${WAZUH_ENROLLMENT_PSK}" ]; then
    MANAGER="${WAZUH_MANAGER:-172.16.0.5}"
    AGENT_NAME="${WAZUH_AGENT_NAME:-$(hostname)}"

    mkdir -p /var/ossec/etc

    if echo "${WAZUH_ENROLLMENT_PSK}" > /var/ossec/etc/enrollment-key; then
        chmod 640 /var/ossec/etc/enrollment-key
        echo "[fw] Wazuh enrollment key written"
    else
        echo "ERROR: [fw] Failed to write Wazuh enrollment key" >&2
    fi

    cat > /var/ossec/etc/ossec.conf << XML
<ossec_config>
  <client>
    <server>
      <address>${MANAGER}</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
    <enrollment>
      <enabled>yes</enabled>
      <agent_name>${AGENT_NAME}</agent_name>
      <authorization_pass_path>/var/ossec/etc/enrollment-key</authorization_pass_path>
    </enrollment>
  </client>
  <logging>
    <log_format>plain</log_format>
  </logging>
</ossec_config>
XML

    if /var/ossec/bin/wazuh-control start 2>/dev/null; then
        echo "[fw] Wazuh agent started"
    else
        echo "WARN: [fw] Wazuh agent failed to start — continuing without agent" >&2
    fi
fi

# ── Firewall container kernel settings ────────────────────────────────────────
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true
sysctl -w net.ipv4.conf.all.forwarding=1 2>/dev/null || true

# ── Load nftables rules ───────────────────────────────────────────────────────
if nft -f /etc/nftables.conf; then
    echo "[fw] nftables rules loaded successfully"
else
    echo "ERROR: [fw] nftables failed to load /etc/nftables.conf — container running without firewall rules" >&2
fi

echo "[fw] Entrypoint complete — entering sleep"
exec sleep infinity
