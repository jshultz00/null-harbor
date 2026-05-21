#!/usr/bin/env bash
# tests/range_integration.sh — master integration harness for the local cyber range.
#
# Spins up every implemented range container on a shared `control` docker network
# (10.0.0.0/24) and verifies inter-machine connectivity plus the Saffron OOB plane.
#
# Usage:   bash tests/range_integration.sh
# Run from the repo root. Requires docker, NET_ADMIN + NET_RAW.
#
# Extending: when a new container is added under dockerfiles/<name>/, append an
# entry to the MACHINES array below. Each entry is a single string:
#
#   "<role>|<build-context>|<control-ip>|<caps>|<extra-args>|<readiness-probe>"
#
# where <readiness-probe> is a shell snippet executed via `docker exec $CID sh -c`.
# The harness waits up to 60s per machine for the probe to exit 0.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NETWORK="range-control-test"
SUBNET="10.0.0.0/24"
GATEWAY="10.0.0.254"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
section() { echo; echo "=== $1 ==="; }

# ── Machine registry ──────────────────────────────────────────────────────────
# Format: role|build-ctx|control-ip|caps|extra-docker-args|readiness-probe
# NOTE: scenario MUST be first — it provides the Saffron server all agents register with.
MACHINES=(
  "scenario|dockerfiles/scenario|10.0.0.1|NET_ADMIN,NET_RAW,SYS_PTRACE||curl -sf http://localhost:8080/api/clients >/dev/null && curl -sf http://localhost:8000 >/dev/null"
  "fw-dmz|dockerfiles/fw|10.0.0.10|NET_ADMIN,NET_RAW|--sysctl net.ipv4.ip_forward=1 -v ${REPO_ROOT}/config/fw-dmz/nftables.conf:/etc/nftables.conf:ro|nft list ruleset >/dev/null && pgrep saffron-agent >/dev/null"
)

# Per-run container name prefix (avoids clashes with a live range)
PREFIX="range-it"
declare -a CONTAINERS=()

cleanup() {
  echo
  echo "--- Cleanup ---"
  for cid in "${CONTAINERS[@]}"; do
    docker rm -f "$cid" >/dev/null 2>&1 || true
  done
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── 0. Preflight ──────────────────────────────────────────────────────────────
section "Preflight"
if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found in PATH — abort"
  exit 2
fi

# Clean any leftover state from a previous aborted run
for m in "${MACHINES[@]}"; do
  IFS='|' read -r role _ _ _ _ _ <<<"$m"
  docker rm -f "${PREFIX}-${role}" >/dev/null 2>&1 || true
done
docker network rm "$NETWORK" >/dev/null 2>&1 || true
pass "preflight: stale state cleaned"

# ── 1. Create shared control network ──────────────────────────────────────────
section "Control network"
if docker network create --subnet "$SUBNET" --gateway "$GATEWAY" "$NETWORK" >/dev/null; then
  pass "created network $NETWORK ($SUBNET, gw=$GATEWAY)"
else
  fail "could not create network $NETWORK"
  exit 1
fi

# ── 2. Build every machine image ──────────────────────────────────────────────
section "Build images"
for m in "${MACHINES[@]}"; do
  IFS='|' read -r role ctx _ _ _ _ <<<"$m"
  tag="${PREFIX}-${role}:local"
  if docker build -t "$tag" "$REPO_ROOT/$ctx" >/dev/null 2>&1; then
    pass "build $role ($ctx)"
  else
    fail "build $role FAILED — abort"
    exit 1
  fi
done

# ── 3. Start every machine on the control network ─────────────────────────────
section "Start machines on control network"
for m in "${MACHINES[@]}"; do
  IFS='|' read -r role _ ip caps extra _ <<<"$m"
  tag="${PREFIX}-${role}:local"
  name="${PREFIX}-${role}"

  cap_args=""
  IFS=',' read -ra CAPS <<<"$caps"
  for c in "${CAPS[@]}"; do
    [[ -n "$c" ]] && cap_args="$cap_args --cap-add $c"
  done

  # shellcheck disable=SC2086
  if docker run -d \
        --name "$name" \
        --network "$NETWORK" \
        --ip "$ip" \
        --hostname "$role" \
        $cap_args \
        $extra \
        "$tag" >/dev/null; then
    CONTAINERS+=("$name")
    pass "started $role at $ip"
  else
    fail "docker run failed for $role — abort"
    exit 1
  fi
done

# ── 4. Wait for each machine's readiness probe ────────────────────────────────
section "Readiness probes"
for m in "${MACHINES[@]}"; do
  IFS='|' read -r role _ _ _ _ probe <<<"$m"
  name="${PREFIX}-${role}"
  ok=0
  for i in $(seq 1 12); do
    if docker exec "$name" sh -c "$probe" >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 5
  done
  if [[ $ok -eq 1 ]]; then
    pass "$role ready (probe passed within 60s)"
  else
    fail "$role did not become ready in 60s"
    echo "    Last 20 log lines from $name:"
    docker logs --tail 20 "$name" 2>&1 | sed 's/^/      /'
  fi
done

# ── 5. Layer-3 reachability across the control plane ─────────────────────────
section "Layer-3 reachability (control plane)"
# Exhaustive pairwise ping — every machine should reach every other machine on
# the control segment. This catches network_mode / iptables regressions early.
for m_src in "${MACHINES[@]}"; do
  IFS='|' read -r src_role _ _ _ _ _ <<<"$m_src"
  src_name="${PREFIX}-${src_role}"
  # Some images don't ship ping; fall back to /dev/tcp probes on the Saffron port
  has_ping=0
  docker exec "$src_name" sh -c 'command -v ping >/dev/null 2>&1' && has_ping=1

  for m_dst in "${MACHINES[@]}"; do
    IFS='|' read -r dst_role _ dst_ip _ _ _ <<<"$m_dst"
    [[ "$src_role" == "$dst_role" ]] && continue

    if [[ $has_ping -eq 1 ]]; then
      if docker exec "$src_name" ping -c 1 -W 2 "$dst_ip" >/dev/null 2>&1; then
        pass "$src_role -> $dst_role ($dst_ip) ICMP"
      else
        fail "$src_role -> $dst_role ($dst_ip) ICMP FAILED"
      fi
    else
      # No ping in image — use bash /dev/tcp on the Saffron port, which every
      # range machine is either serving (scenario) or has an outbound path to.
      probe_port=8080
      if docker exec "$src_name" sh -c \
          "timeout 3 bash -c 'cat </dev/null >/dev/tcp/${dst_ip}/${probe_port}' 2>/dev/null" ; then
        pass "$src_role -> $dst_role ($dst_ip):${probe_port} TCP"
      else
        # TCP probe only meaningful if dst actually listens on 8080 (Saffron server).
        # Otherwise just confirm the src can ARP/route-reach by binding /dev/tcp to :22
        # (which will reset — but a "connection refused" proves routing works).
        out=$(docker exec "$src_name" sh -c \
          "timeout 3 bash -c 'cat </dev/null >/dev/tcp/${dst_ip}/22' 2>&1" || true)
        if grep -qi "refused" <<<"$out"; then
          pass "$src_role -> $dst_role ($dst_ip) reachable (TCP RST)"
        else
          fail "$src_role -> $dst_role ($dst_ip) unreachable: $out"
        fi
      fi
    fi
  done
done

# ── 6. Saffron OOB plane: every non-scenario machine must check in ───────────
section "Saffron OOB plane"
SCENARIO_NAME="${PREFIX}-scenario"

# Give agents a few extra seconds to complete their first check-in
sleep 5

CLIENTS_JSON=$(docker exec "$SCENARIO_NAME" curl -sf http://127.0.0.1:8080/api/clients 2>/dev/null || echo "")
if [[ -z "$CLIENTS_JSON" ]]; then
  fail "GET /api/clients returned empty — Saffron server not responding"
else
  pass "GET /api/clients returned a response"
fi

for m in "${MACHINES[@]}"; do
  IFS='|' read -r role _ _ _ _ _ <<<"$m"
  [[ "$role" == "scenario" ]] && continue

  # The fw entrypoint registers with client-id = $(hostname). We set --hostname $role,
  # so the client should show up in /api/clients keyed by "$role".
  if grep -q "\"$role\"" <<<"$CLIENTS_JSON"; then
    pass "saffron client registered: $role"
  else
    # Retry once with a longer delay — some agents back off on first connect
    sleep 10
    CLIENTS_JSON=$(docker exec "$SCENARIO_NAME" curl -sf http://127.0.0.1:8080/api/clients 2>/dev/null || echo "")
    if grep -q "\"$role\"" <<<"$CLIENTS_JSON"; then
      pass "saffron client registered: $role (after retry)"
    else
      fail "saffron client NOT registered: $role"
      echo "    /api/clients payload: $CLIENTS_JSON"
    fi
  fi
done

# ── 7. DNS: every non-scenario machine resolves fake-internet via scenario ───
section "DNS via scenario CoreDNS (10.0.0.1:53)"
for m in "${MACHINES[@]}"; do
  IFS='|' read -r role _ _ _ _ _ <<<"$m"
  [[ "$role" == "scenario" ]] && continue
  name="${PREFIX}-${role}"

  # Prefer dig/nslookup so we can target 10.0.0.1 explicitly. Firewall images
  # stay lean (no bind-tools) — fall back to a raw bash /dev/udp DNS query and
  # check the answer section for the expected A record (3.89.100.42 = 0359642a).
  if docker exec "$name" sh -c 'command -v dig >/dev/null 2>&1'; then
    got=$(docker exec "$name" sh -c 'dig @10.0.0.1 attacker.com +short +time=3 +tries=1 | head -1' 2>/dev/null || true)
  elif docker exec "$name" sh -c 'command -v nslookup >/dev/null 2>&1'; then
    got=$(docker exec "$name" sh -c 'nslookup attacker.com 10.0.0.1 2>/dev/null | awk "/^Address: /{print \$2; exit}"' 2>/dev/null || true)
  else
    hex=$(docker exec "$name" bash -c '
        exec 3<>/dev/udp/10.0.0.1/53
        printf "\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x08attacker\x03com\x00\x00\x01\x00\x01" >&3
        (timeout 3 cat <&3 || true) | od -An -tx1 | tr -d " \n"
    ' 2>/dev/null || true)
    if [[ "$hex" == *0359642a* ]]; then
      got="3.89.100.42"
    else
      got=""
    fi
  fi

  if [[ "$got" == "3.89.100.42" ]]; then
    pass "$role resolves attacker.com -> 3.89.100.42 via scenario CoreDNS"
  else
    fail "$role resolved attacker.com to '$got' (expected 3.89.100.42)"
  fi
done

# ── 8. Ruleset-specific integration: scenario can inject SNAT via fw-dmz nft ─
section "SNAT injection via Saffron (scenario -> fw-dmz)"
FW_DMZ_NAME="${PREFIX}-fw-dmz"
if docker inspect "$FW_DMZ_NAME" >/dev/null 2>&1; then
  # Baseline: chain empty
  before=$(docker exec "$FW_DMZ_NAME" nft list chain ip nat SCENARIO_SNAT 2>/dev/null | grep -c "snat to" || true)

  # Inject via nft directly on the target (simulating a Saffron exec of an nft command).
  # A full API exec path is covered in the scenario-engine test suite; here we are
  # verifying that the command takes effect as expected across the control plane.
  docker exec "$FW_DMZ_NAME" nft 'add rule ip nat SCENARIO_SNAT ip saddr 5.79.99.1 oifname "eth2" snat to 185.220.101.47' 2>/dev/null || true

  after=$(docker exec "$FW_DMZ_NAME" nft list chain ip nat SCENARIO_SNAT 2>/dev/null | grep -c "snat to" || true)
  if [[ "$after" -gt "$before" ]]; then
    pass "SNAT rule injected into SCENARIO_SNAT (before=$before, after=$after)"
  else
    fail "SNAT injection had no effect (before=$before, after=$after)"
  fi

  docker exec "$FW_DMZ_NAME" nft flush chain ip nat SCENARIO_SNAT 2>/dev/null || true
fi

# ── 9. Survivability — every machine still running at end of suite ───────────
section "Survivability"
for m in "${MACHINES[@]}"; do
  IFS='|' read -r role _ _ _ _ _ <<<"$m"
  name="${PREFIX}-${role}"
  if docker ps --filter "name=^${name}$" --filter "status=running" | grep -q "$name"; then
    pass "$role still running at end of suite"
  else
    fail "$role exited during the test run"
    echo "    Last 20 log lines:"
    docker logs --tail 20 "$name" 2>&1 | sed 's/^/      /'
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "=============================="
echo "Integration results: PASS=$PASS  FAIL=$FAIL"
echo "=============================="

[[ $FAIL -eq 0 ]]
