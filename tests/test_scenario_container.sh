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

# ── 4. Python setup server ────────────────────────────────────────────────────
echo "[4] Python setup server"
if docker exec "$CONTAINER" curl -sf http://localhost:8000 >/dev/null 2>&1; then
  pass "Python server responds on :8000"
else
  fail "Python server not responding on :8000"
fi

# ── 5. DNS: attacker.com ──────────────────────────────────────────────────────
echo "[5] DNS: attacker.com"
RESULT=$(docker exec "$CONTAINER" dig @127.0.0.1 attacker.com +short 2>/dev/null | head -1)
if [[ "$RESULT" == "3.89.100.42" ]]; then
  pass "attacker.com resolves to 3.89.100.42"
else
  fail "attacker.com resolved to '${RESULT}' (expected 3.89.100.42)"
fi

# ── 6. DNS: google.com ────────────────────────────────────────────────────────
echo "[6] DNS: google.com"
RESULT=$(docker exec "$CONTAINER" dig @127.0.0.1 google.com +short 2>/dev/null | head -1)
if [[ "$RESULT" == "142.250.80.46" ]]; then
  pass "google.com resolves to 142.250.80.46"
else
  fail "google.com resolved to '${RESULT}' (expected 142.250.80.46)"
fi

# ── 7. DNS: wildcard ──────────────────────────────────────────────────────────
echo "[7] DNS: wildcard (sub.google.com)"
RESULT=$(docker exec "$CONTAINER" dig @127.0.0.1 sub.google.com +short 2>/dev/null | head -1)
if [[ "$RESULT" == "142.250.80.46" ]]; then
  pass "sub.google.com wildcard resolves to 142.250.80.46"
else
  fail "sub.google.com resolved to '${RESULT}' (expected 142.250.80.46)"
fi

# ── 8. DNS: forward (domain not in fake-internet zone files) ─────────────────
echo "[8] DNS: forward to upstream"
RESULT=$(docker exec "$CONTAINER" dig @127.0.0.1 example.com +short 2>/dev/null | head -1)
if [[ -n "$RESULT" ]]; then
  pass "example.com forwarded upstream (got: ${RESULT})"
else
  fail "example.com returned empty (upstream forwarding may be broken)"
fi

# ── 9. CA cert served ─────────────────────────────────────────────────────────
echo "[9] Range CA cert available via setup server"
if docker exec "$CONTAINER" curl -sf http://localhost:8000/range-ca.crt >/dev/null 2>&1; then
  pass "range-ca.crt served at :8000/range-ca.crt"
else
  fail "range-ca.crt not found at :8000/range-ca.crt"
fi

# ── 10. Tool availability ─────────────────────────────────────────────────────
echo "[10] Tool availability"
TOOLS=(nmap msfconsole nxc evil-winrm sliver bloodhound-python runcmd.bash)
ALL_TOOLS_OK=1
for tool in "${TOOLS[@]}"; do
  if docker exec "$CONTAINER" which "$tool" >/dev/null 2>&1; then
    echo "      found: $tool"
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

# ── 11. Saffron binary ────────────────────────────────────────────────────────
echo "[11] Saffron binary executable"
if docker exec "$CONTAINER" test -x /usr/bin/saffron-server 2>/dev/null; then
  pass "/usr/bin/saffron-server exists and is executable"
else
  fail "/usr/bin/saffron-server missing or not executable"
fi

# ── 12. NET_ADMIN capability ──────────────────────────────────────────────────
echo "[12] NET_ADMIN capability  # requires caps"
if docker exec "$CONTAINER" ip addr add 127.0.0.2/32 dev lo 2>/dev/null; then
  # Clean up alias
  docker exec "$CONTAINER" ip addr del 127.0.0.2/32 dev lo 2>/dev/null || true
  pass "NET_ADMIN: ip addr add succeeded"
else
  skip "NET_ADMIN: ip addr add failed (container may lack NET_ADMIN cap)"
fi

# ── 13. NET_RAW capability ────────────────────────────────────────────────────
echo "[13] NET_RAW capability  # requires caps"
if docker exec "$CONTAINER" hping3 --icmp 127.0.0.1 -c 1 >/dev/null 2>&1; then
  pass "NET_RAW: hping3 ICMP succeeded"
else
  skip "NET_RAW: hping3 failed (container may lack NET_RAW cap)"
fi

# ── 14. Cleanup ───────────────────────────────────────────────────────────────
echo "[14] Cleanup"
docker rm -f "$CONTAINER" 2>/dev/null && pass "Container removed" || fail "Container removal failed"

echo
echo "=============================="
echo "Results: PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "=============================="

[[ $FAIL -eq 0 ]]
