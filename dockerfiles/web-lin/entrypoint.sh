#!/bin/bash
set -e

# ── SSH ────────────────────────────────────────────────────────────────────────
echo "root:${RANGE_PASSWORD:-P@55w0rd!}" | chpasswd
ssh-keygen -A -q
mkdir -p /run/sshd
/usr/sbin/sshd

# ── Wazuh agent configuration ─────────────────────────────────────────────────
if [ -n "${WAZUH_ENROLLMENT_PSK}" ]; then
    MANAGER="${WAZUH_MANAGER:-172.16.0.5}"
    AGENT_NAME="${WAZUH_AGENT_NAME:-$(hostname)}"

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
      <agent_name>${AGENT_NAME}</agent_name>
      <authorization_pass_path>/var/ossec/etc/enrollment-key</authorization_pass_path>
    </enrollment>
  </client>
  <syscheck>
    <frequency>300</frequency>
    <directories check_all="yes">/var/www/html</directories>
  </syscheck>
</ossec_config>
XML

    /var/ossec/bin/wazuh-control start 2>/dev/null || true
fi

# ── Start Apache in the foreground ────────────────────────────────────────────
exec apache2ctl -D FOREGROUND
