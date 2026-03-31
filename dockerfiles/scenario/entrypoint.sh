#!/bin/bash
set -e

# ── Root password (for SSH access) ────────────────────────────────────────────
echo "root:${RANGE_PASSWORD:-P@55w0rd!}" | chpasswd

# ── Attacker user password (primary trainer/student account) ──────────────────
echo "attacker:NewPassWhoDis?" | chpasswd

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


exec sleep infinity
