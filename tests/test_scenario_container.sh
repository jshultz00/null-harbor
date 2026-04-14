#!/usr/bin/env bash
# tests/test_scenario_container.sh — Scenario container smoke tests
# Usage: bash tests/test_scenario_container.sh
# Run from the repo root. Requires Docker. Some tests require NET_ADMIN/NET_RAW caps.
set -euo pipefail

PASS=0
FAIL=0
SKIP=0
IMAGE_TAG="scenario-test"
CONTAINER="scenario-test-run"

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP+1)); }

cleanup() {
  docker rm -f "$CONTAINER" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Scenario container test suite ==="
echo

# ── 1. Build ───────────────────────────────────────────────────────────────────
echo "[1] docker build"
if docker build -t "$IMAGE_TAG" dockerfiles/scenario; then
  pass "docker build exited 0"
else
  fail "docker build failed — aborting remaining tests"
  echo
  echo "Results: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
  exit 1
fi

# ── 2. Startup ────────────────────────────────────────────────────────────────
echo "[2] Container startup"
docker rm -f "$CONTAINER" 2>/dev/null || true
docker run -d \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  --cap-add SYS_PTRACE \
  --name "$CONTAINER" \
  "$IMAGE_TAG"

echo "    Waiting up to 60s for services..."
READY=0
for i in $(seq 1 12); do
  sleep 5
  # Saffron (GET /api/clients returns 200) and Python server both must respond
  if docker exec "$CONTAINER" curl -sf http://localhost:8080/api/clients >/dev/null 2>&1 && \
     docker exec "$CONTAINER" curl -sf http://localhost:8000 >/dev/null 2>&1; then
    READY=1
    break
  fi
  echo "    ...waiting (${i}/12)"
done

if [[ $READY -eq 1 ]]; then
  pass "Container started and core services up within 60s"
else
  fail "Container did not become ready within 60s — continuing with remaining tests"
fi

# ── 3. Saffron ────────────────────────────────────────────────────────────────
echo "[3] Saffron API"
if docker exec "$CONTAINER" curl -sf http://localhost:8080/api/clients >/dev/null 2>&1; then
  pass "Saffron responds on :8080"
else
  fail "Saffron not responding on :8080"
fi

# Saffron should bind on 0.0.0.0 (entrypoint sets -host 0.0.0.0), so external
# hosts on the same docker network can reach it. Verify via the container's
# primary IP, not only localhost.
SAFFRON_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{"\n"}}{{end}}' "$CONTAINER" | head -1)
if [[ -n "$SAFFRON_IP" ]] && docker exec "$CONTAINER" curl -sf "http://${SAFFRON_IP}:8080/api/clients" >/dev/null 2>&1; then
  pass "Saffron reachable on container IP ${SAFFRON_IP}:8080 (bound 0.0.0.0)"
else
  fail "Saffron not reachable on container IP (expected bind on 0.0.0.0)"
fi

# ── 4. Python setup server ────────────────────────────────────────────────────
echo "[4] Python setup server"
if docker exec "$CONTAINER" curl -sf http://localhost:8000 >/dev/null 2>&1; then
  pass "Python server responds on :8000"
else
  fail "Python server not responding on :8000"
fi

# ── 5. DNS: all hard-coded fake-internet domains resolve correctly ────────────
echo "[5] DNS: fake-internet zone integrity"
declare -A EXPECTED=(
  [google.com]=142.250.80.46
  [microsoft.com]=20.112.52.29
  [github.com]=140.82.121.4
  [linkedin.com]=108.174.10.10
  [pastebin.com]=104.23.98.190
  [dropbox.com]=162.125.6.6
  [slack.com]=54.192.151.10
  [attacker.com]=3.89.100.42
)
for domain in "${!EXPECTED[@]}"; do
  expected=${EXPECTED[$domain]}
  got=$(docker exec "$CONTAINER" dig @127.0.0.1 "$domain" +short 2>/dev/null | head -1)
  if [[ "$got" == "$expected" ]]; then
    pass "$domain -> $expected"
  else
    fail "$domain resolved to '$got' (expected $expected)"
  fi
done

# ── 6. DNS: wildcard entries follow apex ──────────────────────────────────────
echo "[6] DNS: wildcard subdomains"
for sub in "mail.attacker.com" "sub.google.com" "login.microsoft.com"; do
  apex="${sub#*.}"
  expected=${EXPECTED[$apex]:-}
  got=$(docker exec "$CONTAINER" dig @127.0.0.1 "$sub" +short 2>/dev/null | head -1)
  if [[ -n "$expected" && "$got" == "$expected" ]]; then
    pass "$sub wildcard -> $expected"
  else
    fail "$sub wildcard resolved to '$got' (expected $expected)"
  fi
done

# ── 7. DNS: upstream forwarder passes through unknown domains ─────────────────
echo "[7] DNS: forward to upstream"
RESULT=$(docker exec "$CONTAINER" dig @127.0.0.1 example.com +short 2>/dev/null | head -1)
if [[ -n "$RESULT" ]]; then
  pass "example.com forwarded upstream (got: ${RESULT})"
else
  fail "example.com returned empty (upstream forwarding may be broken)"
fi

# ── 8. resolv.conf points at local CoreDNS ────────────────────────────────────
echo "[8] /etc/resolv.conf configuration"
if docker exec "$CONTAINER" grep -qE '^nameserver[[:space:]]+127\.0\.0\.1$' /etc/resolv.conf; then
  pass "/etc/resolv.conf uses nameserver 127.0.0.1"
else
  fail "/etc/resolv.conf does not use 127.0.0.1 (Docker DNS override may have won)"
fi

# ── 9. CA cert served ─────────────────────────────────────────────────────────
echo "[9] Range CA cert available via setup server"
if docker exec "$CONTAINER" curl -sf http://localhost:8000/range-ca.crt >/dev/null 2>&1; then
  pass "range-ca.crt served at :8000/range-ca.crt"
else
  fail "range-ca.crt not found at :8000/range-ca.crt"
fi

# Cert must parse as a valid X.509 certificate
if docker exec "$CONTAINER" sh -c 'openssl x509 -in /srv/setup/range-ca.crt -noout -subject' >/dev/null 2>&1; then
  pass "range-ca.crt parses as a valid X.509 certificate"
else
  # openssl may not be installed; use a lighter probe
  if docker exec "$CONTAINER" grep -q "BEGIN CERTIFICATE" /srv/setup/range-ca.crt 2>/dev/null; then
    pass "range-ca.crt appears to be PEM-encoded"
  else
    fail "range-ca.crt is not a valid PEM certificate"
  fi
fi

# ── 10. Caddy HTTPS + on_demand permission endpoint ───────────────────────────
echo "[10] Caddy"
if docker exec "$CONTAINER" pgrep -f "caddy run" >/dev/null 2>&1; then
  pass "caddy process is running"
else
  fail "caddy process not running"
fi

# on_demand TLS permission server on 127.0.0.1:9090 should return 200 on GET
if docker exec "$CONTAINER" curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9090/ 2>/dev/null | grep -q "^200$"; then
  pass "Caddy on_demand permission endpoint (127.0.0.1:9090) returns 200"
else
  fail "Caddy on_demand permission endpoint not returning 200 on :9090"
fi

# ── 11. CoreDNS process ───────────────────────────────────────────────────────
echo "[11] CoreDNS"
if docker exec "$CONTAINER" pgrep -f "coredns" >/dev/null 2>&1; then
  pass "coredns process is running"
else
  fail "coredns process not running"
fi

# Dynamic Corefile must exist (entrypoint generates it at boot)
if docker exec "$CONTAINER" test -s /etc/coredns/Corefile.dynamic; then
  pass "/etc/coredns/Corefile.dynamic is non-empty"
else
  fail "/etc/coredns/Corefile.dynamic missing or empty"
fi

# ── 12. Sliver teamserver listening on :31337 ─────────────────────────────────
echo "[12] Sliver teamserver"
if docker exec "$CONTAINER" pgrep -f "sliver-server" >/dev/null 2>&1; then
  pass "sliver-server process is running"
else
  fail "sliver-server process not running"
fi

# ── 13. Postfix running and listening on 25 ───────────────────────────────────
echo "[13] Postfix"
if docker exec "$CONTAINER" pgrep -x master >/dev/null 2>&1 || \
   docker exec "$CONTAINER" postfix status >/dev/null 2>&1; then
  pass "postfix (master) is running"
else
  fail "postfix master not running"
fi

if docker exec "$CONTAINER" sh -c 'exec 3<>/dev/tcp/127.0.0.1/25; read -t 2 banner <&3; echo "$banner"' 2>/dev/null | grep -qi "220"; then
  pass "postfix SMTP banner on :25 (220 response)"
else
  # Some bash builds lack /dev/tcp; fall back to ss/netstat
  if docker exec "$CONTAINER" sh -c 'ss -ltn 2>/dev/null | grep -q ":25 "'; then
    pass "postfix listening on :25 (ss)"
  else
    fail "postfix not accepting connections on :25"
  fi
fi

# ── 14. Tool availability ─────────────────────────────────────────────────────
echo "[14] Tool availability"
TOOLS=(nmap msfconsole nxc evil-winrm sliver bloodhound-python runcmd.bash
       hashcat john hydra sqlmap nikto gobuster ffuf hping3 tcpdump
       responder curl wget dig yq caddy coredns)
ALL_TOOLS_OK=1
for tool in "${TOOLS[@]}"; do
  if docker exec "$CONTAINER" which "$tool" >/dev/null 2>&1; then
    echo "      found: $tool"
  elif [[ "$tool" == "responder" ]] && docker exec "$CONTAINER" test -f /opt/Responder/Responder.py; then
    echo "      found: $tool (at /opt/Responder/Responder.py)"
  else
    echo "      MISSING: $tool"
    ALL_TOOLS_OK=0
  fi
done
if [[ $ALL_TOOLS_OK -eq 1 ]]; then
  pass "All required tools present"
else
  fail "One or more tools missing (see above)"
fi

# ── 15. Saffron binary ────────────────────────────────────────────────────────
echo "[15] Saffron binary executable"
if docker exec "$CONTAINER" test -x /usr/bin/saffron-server 2>/dev/null; then
  pass "/usr/bin/saffron-server exists and is executable"
else
  fail "/usr/bin/saffron-server missing or not executable"
fi

# ── 16. Directory layout (persistent volumes, zone dir, setup dir) ────────────
echo "[16] Directory layout"
for d in /opt/saffron/data /etc/coredns/zones /srv/setup /srv/www /home/attacker/scenarios; do
  if docker exec "$CONTAINER" test -d "$d"; then
    pass "directory present: $d"
  else
    fail "directory missing: $d"
  fi
done

# Zone files for every seeded domain
for domain in "${!EXPECTED[@]}"; do
  if docker exec "$CONTAINER" test -s "/etc/coredns/zones/${domain}.db"; then
    pass "zone file present: ${domain}.db"
  else
    fail "zone file missing: ${domain}.db"
  fi
done

# ── 17. NET_ADMIN capability ──────────────────────────────────────────────────
echo "[17] NET_ADMIN capability  # requires caps"
if docker exec "$CONTAINER" ip addr add 127.0.0.2/32 dev lo 2>/dev/null; then
  docker exec "$CONTAINER" ip addr del 127.0.0.2/32 dev lo 2>/dev/null || true
  pass "NET_ADMIN: ip addr add succeeded"
else
  skip "NET_ADMIN: ip addr add failed (container may lack NET_ADMIN cap)"
fi

# ── 18. NET_RAW capability ────────────────────────────────────────────────────
echo "[18] NET_RAW capability  # requires caps"
if docker exec "$CONTAINER" hping3 --icmp 127.0.0.1 -c 1 >/dev/null 2>&1; then
  pass "NET_RAW: hping3 ICMP succeeded"
else
  skip "NET_RAW: hping3 failed (container may lack NET_RAW cap)"
fi

# ── 19. Entrypoint log markers ────────────────────────────────────────────────
echo "[19] Entrypoint completion markers"
LOGS=$(docker logs "$CONTAINER" 2>&1)
for marker in \
    "resolv.conf set to nameserver 127.0.0.1" \
    "Starting Saffron server" \
    "Starting CoreDNS" \
    "Starting Caddy" \
    "Starting Sliver teamserver" \
    "Configuring Postfix" \
    "All services started. Container ready."; do
  if grep -qF "$marker" <<< "$LOGS"; then
    pass "entrypoint logged: $marker"
  else
    fail "entrypoint did NOT log: $marker"
  fi
done

# ── 20. Cleanup ───────────────────────────────────────────────────────────────
echo "[20] Cleanup"
docker rm -f "$CONTAINER" 2>/dev/null && pass "Container removed" || fail "Container removal failed"

echo
echo "=============================="
echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "=============================="

[[ $FAIL -eq 0 ]]
