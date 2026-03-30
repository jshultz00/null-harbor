#!/bin/bash
set -e

# ── Root password (for SSH access) ────────────────────────────────────────────
echo "root:${RANGE_PASSWORD:-Password!}" | chpasswd

# ── IP forwarding (scenario is the fake internet gateway) ────────────────────
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true

# ── SSH host keys ─────────────────────────────────────────────────────────────
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A -q
fi
/usr/sbin/sshd

# ── Caddy (serves setup scripts on :80, fake HTTPS on :443) ──────────────────
caddy start --config /etc/caddy/Caddyfile --adapter caddyfile 2>/dev/null || \
    (cd /var/www/html && python3 -m http.server 80 &)

# ── Wazuh agent ───────────────────────────────────────────────────────────────
if [ -n "${WAZUH_ENROLLMENT_PSK}" ]; then
    MANAGER="${WAZUH_MANAGER:-172.16.0.5}"
    echo "${WAZUH_ENROLLMENT_PSK}" > /var/ossec/etc/enrollment-key
    chmod 640 /var/ossec/etc/enrollment-key

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
      <agent_name>${WAZUH_AGENT_NAME:-scenario}</agent_name>
      <authorization_pass_path>/var/ossec/etc/enrollment-key</authorization_pass_path>
    </enrollment>
  </client>
</ossec_config>
XML
    /var/ossec/bin/wazuh-control start 2>/dev/null || true
fi

exec sleep infinity
