#!/bin/bash
# tests/fw-dmz.sh — automated acceptance tests for the fw-dmz container
#
# Usage:
#   bash tests/fw-dmz.sh
#
# Requires: docker, a host with NET_ADMIN + NET_RAW capabilities available to containers.
# Run from the repo root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="fw-test:local"
CONTAINER="fw-test-run"
NFTABLES_CONF="$REPO_ROOT/config/fw-dmz/nftables.conf"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    docker rmi -f "$IMAGE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Test 1: Build
# ---------------------------------------------------------------------------
echo "--- Build ---"
if docker build -t "$IMAGE" "$REPO_ROOT/dockerfiles/fw" >/dev/null 2>&1; then
    pass "docker build succeeds"
else
    fail "docker build failed — check dockerfiles/fw/ (saffron-agent binary present?)"
    echo "Aborting: remaining tests require a successful build."
    exit 1
fi

# ---------------------------------------------------------------------------
# Start container for runtime tests
# ---------------------------------------------------------------------------
docker run -d \
    --name "$CONTAINER" \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    --sysctl net.ipv4.ip_forward=1 \
    -v "$NFTABLES_CONF:/etc/nftables.conf:ro" \
    "$IMAGE" >/dev/null

sleep 3   # give entrypoint time to complete all four stages

# ---------------------------------------------------------------------------
# Test 2: Startup — container still running, nft exits 0
# ---------------------------------------------------------------------------
echo "--- Startup ---"
if docker ps --filter "name=$CONTAINER" --filter "status=running" | grep -q "$CONTAINER"; then
    pass "container is running after 3 seconds"
else
    fail "container exited prematurely — docker logs $CONTAINER for details"
fi

if docker exec "$CONTAINER" nft list ruleset >/dev/null 2>&1; then
    pass "nft list ruleset exits 0"
else
    fail "nft list ruleset failed"
fi

# ---------------------------------------------------------------------------
# Test 3: Rule order — management accepts BEFORE log in chain forward
# ---------------------------------------------------------------------------
echo "--- Rule order (management invariant) ---"
FORWARD_RULES=$(docker exec "$CONTAINER" nft -a list chain inet filter forward 2>/dev/null)

ETH0_LINE=$(echo "$FORWARD_RULES" | grep -n 'iifname "eth0" accept' | head -1 | cut -d: -f1)
DADDR_LINE=$(echo "$FORWARD_RULES" | grep -n 'ip daddr 10.0.0.0/24 accept' | head -1 | cut -d: -f1)
LOG_LINE=$(echo "$FORWARD_RULES"   | grep -n 'log prefix' | head -1 | cut -d: -f1)

if [[ -n "$ETH0_LINE" && -n "$LOG_LINE" && "$ETH0_LINE" -lt "$LOG_LINE" ]]; then
    pass "eth0 accept (line $ETH0_LINE) is before log (line $LOG_LINE)"
else
    fail "eth0 accept MISSING or appears after log — management traffic would leak to Wazuh!"
fi

if [[ -n "$DADDR_LINE" && -n "$LOG_LINE" && "$DADDR_LINE" -lt "$LOG_LINE" ]]; then
    pass "ip daddr 10.0.0.0/24 accept (line $DADDR_LINE) is before log (line $LOG_LINE)"
else
    fail "ip daddr 10.0.0.0/24 accept MISSING or appears after log — management traffic would leak to Wazuh!"
fi

# ---------------------------------------------------------------------------
# Test 4: SCENARIO_SNAT chain exists and is empty
# ---------------------------------------------------------------------------
echo "--- SCENARIO_SNAT ---"
SNAT_OUTPUT=$(docker exec "$CONTAINER" nft list chain ip nat SCENARIO_SNAT 2>/dev/null || true)
if echo "$SNAT_OUTPUT" | grep -q "chain SCENARIO_SNAT"; then
    pass "SCENARIO_SNAT chain exists"
else
    fail "SCENARIO_SNAT chain not found"
fi

RULE_COUNT=$(echo "$SNAT_OUTPUT" | grep -cv "chain\|table\|^[[:space:]]*[{}]*[[:space:]]*$" || true)
if [[ "$RULE_COUNT" -eq 0 ]]; then
    pass "SCENARIO_SNAT is empty on fresh start"
else
    fail "SCENARIO_SNAT has $RULE_COUNT unexpected rule(s) on fresh start"
fi

# ---------------------------------------------------------------------------
# Test 5: SNAT injection and flush
# ---------------------------------------------------------------------------
echo "--- SNAT injection/flush ---"
docker exec "$CONTAINER" nft add rule ip nat SCENARIO_SNAT ip saddr 5.79.99.1 oifname '"eth2"' snat to 185.220.101.47 2>/dev/null || \
docker exec "$CONTAINER" nft 'add rule ip nat SCENARIO_SNAT ip saddr 5.79.99.1 oifname "eth2" snat to 185.220.101.47'

AFTER_INJECT=$(docker exec "$CONTAINER" nft list chain ip nat SCENARIO_SNAT 2>/dev/null)
if echo "$AFTER_INJECT" | grep -q "185.220.101.47"; then
    pass "SNAT rule injection visible immediately"
else
    fail "SNAT rule not found after injection"
fi

docker exec "$CONTAINER" nft flush chain ip nat SCENARIO_SNAT
AFTER_FLUSH=$(docker exec "$CONTAINER" nft list chain ip nat SCENARIO_SNAT 2>/dev/null)
AFTER_COUNT=$(echo "$AFTER_FLUSH" | grep -cv "chain\|table\|^[[:space:]]*[{}]*[[:space:]]*$" || true)
if [[ "$AFTER_COUNT" -eq 0 ]]; then
    pass "SCENARIO_SNAT is empty after flush"
else
    fail "SCENARIO_SNAT still has rules after flush"
fi

# ---------------------------------------------------------------------------
# Test 6: Static DNAT rules present
# ---------------------------------------------------------------------------
echo "--- Static DNAT rules ---"
PREROUTING=$(docker exec "$CONTAINER" nft list chain ip nat prerouting 2>/dev/null)

for entry in "5.79.99.10" "5.79.99.12" "5.79.99.25"; do
    if echo "$PREROUTING" | grep -q "$entry"; then
        pass "DNAT rule present for $entry"
    else
        fail "DNAT rule MISSING for $entry"
    fi
done

# ---------------------------------------------------------------------------
# Test 7: rsyslog running and configured
# ---------------------------------------------------------------------------
echo "--- rsyslog ---"
if docker exec "$CONTAINER" pgrep rsyslogd >/dev/null 2>&1; then
    pass "rsyslogd process is running"
else
    fail "rsyslogd not running"
fi

if docker exec "$CONTAINER" grep -q "10.50.50.8:514" /etc/rsyslog.conf; then
    pass "/etc/rsyslog.conf contains forwarding to 10.50.50.8:514"
else
    fail "/etc/rsyslog.conf missing 10.50.50.8:514 forwarding rule"
fi

# ---------------------------------------------------------------------------
# Test 8: Saffron agent running
# ---------------------------------------------------------------------------
echo "--- Saffron agent ---"
if docker exec "$CONTAINER" pgrep saffron-agent >/dev/null 2>&1; then
    pass "saffron-agent process is running"
else
    fail "saffron-agent not running"
fi

# ---------------------------------------------------------------------------
# Test 9: IPv4 forwarding active
# ---------------------------------------------------------------------------
echo "--- IPv4 forwarding ---"
FWD=$(docker exec "$CONTAINER" cat /proc/sys/net/ipv4/ip_forward)
if [[ "$FWD" == "1" ]]; then
    pass "net.ipv4.ip_forward = 1"
else
    fail "net.ipv4.ip_forward = $FWD (expected 1) — set sysctl in docker-compose.yml"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

# ---------------------------------------------------------------------------
# Manual verification note
# ---------------------------------------------------------------------------
# Control segment log exclusion test (requires packet injection — not automated):
#   1. From inside the container, inject a packet with source 10.0.0.1:
#        docker exec fw-dmz nft insert rule inet filter forward ip saddr 10.0.0.1 log prefix "TEST: "
#      Then observe that nothing matching "FW-DMZ-FWD:" appears for 10.0.0.x source IPs.
#   2. Send a packet from 5.79.99.1 (scenario) toward 10.10.10.10 and confirm a FW-DMZ-FWD: line
#      appears in `docker logs fw-dmz` or in the rsyslog output at 10.50.50.8.
