#!/usr/bin/env bash
set -euo pipefail

log() { echo "[entrypoint] $*"; }

# ── resolv.conf — must be first, Docker overwrites it at container start ───────
# Save Docker-provided upstream DNS before overwriting — UDP :53 to 8.8.8.8 may
# be blocked by the host firewall; Docker's own resolver is always reachable.
DOCKER_DNS=$(grep -m1 '^nameserver' /etc/resolv.conf | awk '{print $2}' || echo "8.8.8.8")
log "Captured Docker DNS upstream: ${DOCKER_DNS}"
echo "nameserver 127.0.0.1" > /etc/resolv.conf
log "resolv.conf set to nameserver 127.0.0.1"

# ── Static domain-to-IP table ──────────────────────────────────────────────────
# IPs are realistic public addresses matching real ASN ranges for believability.
# All subdomains resolve to the same IP via wildcard zone entries.
FAKE_INTERNET_DOMAINS=(
  "google.com      142.250.80.46"
  "microsoft.com   20.112.52.29"
  "github.com      140.82.121.4"
  "linkedin.com    108.174.10.10"
  "pastebin.com    104.23.98.190"
  "dropbox.com     162.125.6.6"
  "slack.com       54.192.151.10"
  "attacker.com    3.89.100.42"
)

# ── 1. IP aliases on eth1 ──────────────────────────────────────────────────────
# /32 host routes — traffic routed here by fw-dmz, accepted because IP is aliased.
# eth1 won't exist in local test runs; || true makes it non-fatal.
log "Adding fake internet IP aliases on eth1..."
for entry in "${FAKE_INTERNET_DOMAINS[@]}"; do
  domain=$(awk '{print $1}' <<< "$entry")
  ip=$(awk '{print $2}' <<< "$entry")
  ip addr add "${ip}/32" dev eth1 label "eth1:${domain%%.*}" 2>/dev/null || true
  log "  aliased ${ip} (${domain})"
done

# Process dns-additions.conf if present (scenario-injectable entries)
if [[ -f /home/attacker/dns-additions.conf ]]; then
  log "Processing dns-additions.conf..."
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
    domain=$(awk '{print $1}' <<< "$line")
    ip=$(awk '{print $2}' <<< "$line")
    if [[ -n "$domain" && -n "$ip" ]]; then
      ip addr add "${ip}/32" dev eth1 2>/dev/null || true
      log "  aliased ${ip} (${domain}) [dns-additions.conf]"
    fi
  done < /home/attacker/dns-additions.conf
fi

# ── 2. CoreDNS zone files and dynamic Corefile ────────────────────────────────
log "Generating CoreDNS zone files..."
mkdir -p /etc/coredns/zones

write_zone() {
  local domain="$1" ip="$2" serial
  serial=$(date +%s)
  cat > "/etc/coredns/zones/${domain}.db" <<EOF
\$ORIGIN ${domain}.
\$TTL 300
@  IN SOA ns1.${domain}. admin.${domain}. ${serial} 3600 900 604800 300
@  IN NS  ns1.${domain}.
@  IN A   ${ip}
*  IN A   ${ip}
EOF
}

for entry in "${FAKE_INTERNET_DOMAINS[@]}"; do
  domain=$(awk '{print $1}' <<< "$entry")
  ip=$(awk '{print $2}' <<< "$entry")
  write_zone "$domain" "$ip"
done

if [[ -f /home/attacker/dns-additions.conf ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
    domain=$(awk '{print $1}' <<< "$line")
    ip=$(awk '{print $2}' <<< "$line")
    [[ -n "$domain" && -n "$ip" ]] && write_zone "$domain" "$ip"
  done < /home/attacker/dns-additions.conf
fi

# Generate dynamic Corefile (one 'file' block per domain + catch-all forwarder)
log "Generating /etc/coredns/Corefile.dynamic..."

collect_domains() {
  for entry in "${FAKE_INTERNET_DOMAINS[@]}"; do awk '{print $1}' <<< "$entry"; done
  if [[ -f /home/attacker/dns-additions.conf ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
      awk '{print $1}' <<< "$line"
    done < /home/attacker/dns-additions.conf
  fi
}

{
  while IFS= read -r domain; do
    printf '%s:53 {\n    file /etc/coredns/zones/%s.db\n    log\n    errors\n}\n\n' \
      "$domain" "$domain"
  done < <(collect_domains)
  printf '.:53 {\n    forward . %s\n    log\n    errors\n    cache 30\n}\n' "$DOCKER_DNS"
} > /etc/coredns/Corefile.dynamic

# ── 3. Saffron server ──────────────────────────────────────────────────────────
log "Starting Saffron server on 0.0.0.0:8080..."
mkdir -p /opt/saffron/data
cd /opt/saffron/data
/usr/bin/saffron-server -host 0.0.0.0 -port 8080 &
cd /home/attacker

# ── 4. CoreDNS ────────────────────────────────────────────────────────────────
log "Starting CoreDNS..."
/usr/bin/coredns -conf /etc/coredns/Corefile.dynamic &

# ── 5. Caddy on_demand TLS permission server (port 9090) ─────────────────────
# Caddy v2.9+ requires an 'ask' endpoint for on_demand TLS. This tiny server
# always approves cert issuance — safe because the range CA is internal-only.
log "Starting Caddy on_demand TLS permission server on 127.0.0.1:9090..."
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
    def log_message(self, *args): pass
HTTPServer(('127.0.0.1', 9090), H).serve_forever()
" &

# ── 6. Caddy ──────────────────────────────────────────────────────────────────
log "Starting Caddy..."
/usr/bin/caddy run --config /etc/caddy/Caddyfile &

# ── 7. Sliver teamserver ──────────────────────────────────────────────────────
log "Starting Sliver teamserver on port 31337..."
# sliver-server daemon is the correct subcommand for always-on mode.
# Operator creds generated on first start and stored in /root/.sliver/configs/
sliver-server daemon --lhost 0.0.0.0 --lport 31337 &

# ── 8. Postfix ────────────────────────────────────────────────────────────────
log "Configuring Postfix..."
postconf -e "myhostname=${SMTP_HOSTNAME:-mail.attacker.com}"
postconf -e "mydomain=${SMTP_DOMAIN:-attacker.com}"
newaliases
postfix start

# ── 9. Python setup file server ───────────────────────────────────────────────
log "Starting Python setup server on port 8000 (directory: /srv/setup)..."
python3 -m http.server 8000 --directory /srv/setup &

log "All services started. Container ready."
exec tail -f /dev/null
