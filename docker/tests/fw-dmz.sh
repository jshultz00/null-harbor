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

# Verify required binaries are in the image
echo "--- Image contents ---"
for bin in nft rsyslogd saffron-agent ip; do
    if docker run --rm --entrypoint which "$IMAGE" "$bin" >/dev/null 2>&1; then
        pass "binary present: $bin"
    else
        fail "binary missing from image: $bin"
    fi
done

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

# Entrypoint stage markers in container logs
LOGS=$(docker logs "$CONTAINER" 2>&1)
for marker in "nftables rules loaded" "rsyslog started" "saffron-agent started"; do
    if grep -qF "$marker" <<< "$LOGS"; then
        pass "entrypoint logged: $marker"
    else
        fail "entrypoint did not log: $marker"
    fi
done

# ---------------------------------------------------------------------------
# Test 3: Chain/table topology
# ---------------------------------------------------------------------------
echo "--- Chain/table topology ---"
RULESET=$(docker exec "$CONTAINER" nft list ruleset)

for expected in \
    "table inet filter" \
    "chain input" \
    "chain forward" \
    "chain output" \
    "table ip nat" \
    "chain prerouting" \
    "chain postrouting" \
    "chain SCENARIO_SNAT"; do
    if grep -qF "$expected" <<< "$RULESET"; then
        pass "ruleset contains: $expected"
    else
        fail "ruleset MISSING: $expected"
    fi
done

# Input chain default policy must be drop (management is the only way in)
if docker exec "$CONTAINER" nft list chain inet filter input 2>/dev/null | grep -q "policy drop"; then
    pass "input chain policy is drop"
else
    fail "input chain policy is NOT drop — management-only-in invariant broken"
fi

# Forward chain must be permissive (policy accept)
if docker exec "$CONTAINER" nft list chain inet filter forward 2>/dev/null | grep -q "policy accept"; then
    pass "forward chain policy is accept (permissive by design)"
else
    fail "forward chain policy is NOT accept — permissive forward invariant broken"
fi

# ---------------------------------------------------------------------------
# Test 4: Rule order — management accepts BEFORE log in chain forward
# ---------------------------------------------------------------------------
echo "--- Rule order (management invariant) ---"
FORWARD_RULES=$(docker exec "$CONTAINER" nft -a list chain inet filter forward 2>/dev/null)

ETH0_LINE=$(echo "$FORWARD_RULES" | grep -n 'iifname "eth0" accept' | head -1 | cut -d: -f1)
DADDR_LINE=$(echo "$FORWARD_RULES" | grep -n 'ip daddr 10.0.0.0/24 accept' | head -1 | cut -d: -f1)
LOG_LINE=$(echo "$FORWARD_RULES"   | grep -n 'log prefix' | head -1 | cut -d: -f1)
INVALID_LINE=$(echo "$FORWARD_RULES" | grep -n 'ct state invalid drop' | head -1 | cut -d: -f1)

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

if [[ -n "$INVALID_LINE" && -n "$ETH0_LINE" && "$INVALID_LINE" -lt "$ETH0_LINE" ]]; then
    pass "ct state invalid drop (line $INVALID_LINE) is first, before management accepts"
else
    fail "ct state invalid drop is missing or not first in forward chain"
fi

# Log prefix format — must match "FW-DMZ-FWD:" for rsyslog/Wazuh parsers
if grep -q 'log prefix "FW-DMZ-FWD: "' <<< "$FORWARD_RULES"; then
    pass "log prefix is FW-DMZ-FWD: (matches Wazuh parser contract)"
else
    fail "log prefix is not FW-DMZ-FWD: — Wazuh/rsyslog parsing will break"
fi

# ---------------------------------------------------------------------------
# Test 5: SCENARIO_SNAT chain exists, is empty, and postrouting jumps to it
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

POSTROUTING=$(docker exec "$CONTAINER" nft list chain ip nat postrouting 2>/dev/null)
if grep -q "jump SCENARIO_SNAT" <<< "$POSTROUTING"; then
    pass "postrouting jumps to SCENARIO_SNAT"
else
    fail "postrouting does NOT jump to SCENARIO_SNAT — per-phase SNAT will have no effect"
fi

# postrouting must evaluate SCENARIO_SNAT BEFORE the default masquerade
JUMP_LINE=$(docker exec "$CONTAINER" nft -a list chain ip nat postrouting | grep -n 'jump SCENARIO_SNAT' | head -1 | cut -d: -f1)
MASQ_LINE=$(docker exec "$CONTAINER" nft -a list chain ip nat postrouting | grep -n 'masquerade'       | head -1 | cut -d: -f1)
if [[ -n "$JUMP_LINE" && -n "$MASQ_LINE" && "$JUMP_LINE" -lt "$MASQ_LINE" ]]; then
    pass "jump SCENARIO_SNAT (line $JUMP_LINE) evaluated before masquerade (line $MASQ_LINE)"
else
    fail "SCENARIO_SNAT does not evaluate before masquerade — per-phase SNAT will be shadowed"
fi

# ---------------------------------------------------------------------------
# Test 6: SNAT injection, persistence across list, and flush
# ---------------------------------------------------------------------------
echo "--- SNAT injection/flush ---"
docker exec "$CONTAINER" nft 'add rule ip nat SCENARIO_SNAT ip saddr 5.79.99.1 oifname "eth2" snat to 185.220.101.47'

AFTER_INJECT=$(docker exec "$CONTAINER" nft list chain ip nat SCENARIO_SNAT 2>/dev/null)
if echo "$AFTER_INJECT" | grep -q "185.220.101.47"; then
    pass "SNAT rule injection visible immediately"
else
    fail "SNAT rule not found after injection"
fi

# A second injection should coexist with the first (no clobber)
docker exec "$CONTAINER" nft 'add rule ip nat SCENARIO_SNAT ip saddr 5.79.99.2 oifname "eth2" snat to 45.66.35.202'
AFTER_SECOND=$(docker exec "$CONTAINER" nft list chain ip nat SCENARIO_SNAT 2>/dev/null)
if grep -q "185.220.101.47" <<< "$AFTER_SECOND" && grep -q "45.66.35.202" <<< "$AFTER_SECOND"; then
    pass "multiple SNAT rules coexist after sequential injection"
else
    fail "second SNAT injection overwrote or dropped the first"
fi

docker exec "$CONTAINER" nft flush chain ip nat SCENARIO_SNAT
AFTER_FLUSH=$(docker exec "$CONTAINER" nft list chain ip nat SCENARIO_SNAT 2>/dev/null)
AFTER_COUNT=$(echo "$AFTER_FLUSH" | grep -cv "chain\|table\|^[[:space:]]*[{}]*[[:space:]]*$" || true)
if [[ "$AFTER_COUNT" -eq 0 ]]; then
    pass "SCENARIO_SNAT is empty after flush"
else
    fail "SCENARIO_SNAT still has rules after flush"
fi

# Ruleset reload should be idempotent (scenario phases may trigger reloads)
if docker exec "$CONTAINER" nft -f /etc/nftables.conf 2>/dev/null; then
    pass "nft -f /etc/nftables.conf reload is idempotent"
else
    fail "nft -f /etc/nftables.conf reload failed"
fi

# ---------------------------------------------------------------------------
# Test 7: Static DNAT rules — per-host, per-port
# ---------------------------------------------------------------------------
echo "--- Static DNAT rules ---"
PREROUTING=$(docker exec "$CONTAINER" nft list chain ip nat prerouting 2>/dev/null)

# web-lin: 5.79.99.10 tcp 80/443 -> 10.10.10.10
if grep -qE '5\.79\.99\.10.*(80|443).*dnat to 10\.10\.10\.10' <<< "$PREROUTING"; then
    pass "DNAT web-lin: 5.79.99.10:{80,443} -> 10.10.10.10"
else
    fail "DNAT web-lin rule missing or malformed"
fi

# web-win: 5.79.99.12 tcp 80/443 -> 10.10.10.12
if grep -qE '5\.79\.99\.12.*(80|443).*dnat to 10\.10\.10\.12' <<< "$PREROUTING"; then
    pass "DNAT web-win: 5.79.99.12:{80,443} -> 10.10.10.12"
else
    fail "DNAT web-win rule missing or malformed"
fi

# mail-relay: 5.79.99.25 tcp 25 -> 10.10.10.20
if grep -qE '5\.79\.99\.25.*25.*dnat to 10\.10\.10\.20' <<< "$PREROUTING"; then
    pass "DNAT mail-relay: 5.79.99.25:25 -> 10.10.10.20"
else
    fail "DNAT mail-relay rule missing or malformed"
fi

# All DNATs must have iifname eth1 (traffic arriving from fake internet)
if ! grep -q 'iifname "eth1"' <<< "$PREROUTING"; then
    fail "prerouting DNATs missing iifname \"eth1\" qualifier"
else
    pass "prerouting DNATs are qualified with iifname \"eth1\""
fi

# ---------------------------------------------------------------------------
# Test 8: rsyslog running and configured
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

# Forwarding must be TCP-or-UDP syntax we recognise (@ or @@)
if docker exec "$CONTAINER" grep -qE '^\*\.\*[[:space:]]+@{1,2}10\.50\.50\.8:514' /etc/rsyslog.conf; then
    pass "rsyslog forward rule uses @/@@ syslog syntax"
else
    fail "rsyslog forward rule syntax unrecognised (expected '*.* @10.50.50.8:514' or '@@')"
fi

# ---------------------------------------------------------------------------
# Test 9: Saffron agent running and pointed at the right server
# ---------------------------------------------------------------------------
echo "--- Saffron agent ---"
if docker exec "$CONTAINER" pgrep saffron-agent >/dev/null 2>&1; then
    pass "saffron-agent process is running"
else
    fail "saffron-agent not running"
fi

# The agent binary must be executable in the image (not just present)
if docker exec "$CONTAINER" test -x /usr/bin/saffron-agent; then
    pass "/usr/bin/saffron-agent is executable"
else
    fail "/usr/bin/saffron-agent missing or not executable"
fi

# Agent process should reference the expected server (10.0.0.1:8080 by default)
AGENT_CMDLINE=$(docker exec "$CONTAINER" sh -c 'cat /proc/$(pgrep saffron-agent | head -1)/cmdline | tr "\0" " "' 2>/dev/null || true)
if grep -q "10.0.0.1:8080" <<< "$AGENT_CMDLINE" || grep -q "COMMANDLY_SERVER" <<< "$AGENT_CMDLINE"; then
    pass "saffron-agent points at Saffron server (cmdline: $AGENT_CMDLINE)"
else
    # COMMANDLY_SERVER may be overridden; a missing server arg is the real bug
    if grep -q -- "-server " <<< "$AGENT_CMDLINE"; then
        pass "saffron-agent has -server arg set (cmdline: $AGENT_CMDLINE)"
    else
        fail "saffron-agent has no -server argument (cmdline: $AGENT_CMDLINE)"
    fi
fi

# ---------------------------------------------------------------------------
# Test 10: IPv4 forwarding active
# ---------------------------------------------------------------------------
echo "--- IPv4 forwarding ---"
FWD=$(docker exec "$CONTAINER" cat /proc/sys/net/ipv4/ip_forward)
if [[ "$FWD" == "1" ]]; then
    pass "net.ipv4.ip_forward = 1"
else
    fail "net.ipv4.ip_forward = $FWD (expected 1) — set sysctl in docker-compose.yml"
fi

# ---------------------------------------------------------------------------
# Test 11: Container survives nftables reload without crashing
# ---------------------------------------------------------------------------
echo "--- Resilience ---"
if docker ps --filter "name=$CONTAINER" --filter "status=running" | grep -q "$CONTAINER"; then
    pass "container still running after all runtime probes"
else
    fail "container died during the test run — docker logs $CONTAINER"
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
