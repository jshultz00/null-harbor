#!/bin/bash
# db01 entrypoint — runs as root; handles AD join, sshd, Wazuh before execing sqlservr

# ── SSH ────────────────────────────────────────────────────────────────────────
echo "root:${RANGE_PASSWORD:-Password1!}" | chpasswd
ssh-keygen -A -q
mkdir -p /run/sshd
/usr/sbin/sshd

# ── Active Directory join ──────────────────────────────────────────────────────
if [ -n "${AD_DOMAIN}" ] && [ -n "${AD_ADMIN_PASSWORD}" ]; then
    (
        export HOME=/root
        # Configure Kerberos
        cat > /etc/krb5.conf << KRB
[libdefaults]
    default_realm = ${AD_NETBIOS:-SECURE}
    dns_lookup_realm = true
    dns_lookup_kdc = true

[realms]
    ${AD_NETBIOS:-SECURE} = {
        kdc = dc01.${AD_DOMAIN}
        admin_server = dc01.${AD_DOMAIN}
    }

[domain_realm]
    .${AD_DOMAIN} = ${AD_NETBIOS:-SECURE}
    ${AD_DOMAIN} = ${AD_NETBIOS:-SECURE}
KRB

        # Join the domain if not already joined
        if ! realm list 2>/dev/null | grep -q "${AD_DOMAIN}"; then
            echo "Attempting to join ${AD_DOMAIN}..."
            for i in 1 2 3 4 5; do
                echo "${AD_ADMIN_PASSWORD}" | realm join \
                    --user=Administrator \
                    --computer-name="$(hostname)" \
                    "${AD_DOMAIN}" 2>/dev/null && break
                echo "Domain join attempt ${i} failed, retrying in 30s..."
                sleep 30
            done
        else
            echo "Already joined to ${AD_DOMAIN}"
        fi

        # Create MSSQL Kerberos keytab for Windows Authentication
        if realm list 2>/dev/null | grep -q "${AD_DOMAIN}"; then
            msktutil -c -b "CN=Computers" \
                -s "MSSQLSvc/$(hostname).${AD_DOMAIN}:1433" \
                -k /var/opt/mssql/mssql.keytab \
                --computer-name "$(hostname)" \
                --upn "MSSQLSvc/$(hostname).${AD_DOMAIN}" \
                --server "dc01.${AD_DOMAIN}" \
                --user-creds-only 2>/dev/null || true
        fi
    ) || true
fi

# ── Wazuh agent ────────────────────────────────────────────────────────────────
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
      <agent_name>${WAZUH_AGENT_NAME:-db01}</agent_name>
      <authorization_pass_path>/var/ossec/etc/enrollment-key</authorization_pass_path>
    </enrollment>
  </client>
</ossec_config>
XML

    /var/ossec/bin/wazuh-control start 2>/dev/null || true
fi

# ── Start MSSQL Server ────────────────────────────────────────────────────────
exec /opt/mssql/bin/sqlservr
