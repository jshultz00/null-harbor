# config/fw-dmz/ — DMZ Perimeter Firewall

This directory contains `nftables.conf` for the `fw-dmz` container. fw-dmz is the perimeter firewall bridging the `external` segment (fake internet, `9.53.99.0/24`) and the `dmz` segment (`10.10.10.0/24`). It also hosts the SNAT chain used by scenarios to present arbitrary attacker source IPs.

---

## Interface Layout

| Interface | Segment | Subnet | IP |
|-----------|---------|--------|-----|
| `eth0` | management (OOB — not visible to participants) | 10.0.0.0/24 | 10.0.0.10 |
| `eth1` | external | 9.53.99.0/24 | 9.53.99.2 |
| `eth2` | dmz | 10.10.10.0/24 | 10.10.10.1 |

IPv4 forwarding is enabled via `net.ipv4.ip_forward=1` (set in `docker-compose.yml` sysctl).

---

## nftables Ruleset Structure

```nftables
table inet filter {

    chain input {
        type filter hook input priority 0; policy drop;

        # Allow established/related
        ct state established,related accept

        # Management interface — accepted before any logging
        iifname "eth0" accept

        # ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
    }

    chain forward {
        type filter hook forward priority 0; policy accept;

        # Drop invalid state
        ct state invalid drop

        # Management traffic — accepted silently before any logging
        # 10.0.0.0/24 must never appear in FW-DMZ-FWD log lines
        iifname "eth0" accept
        ip daddr 10.0.0.0/24 accept

        # Log all forwarded traffic (defenders analyze these via Wazuh)
        log prefix "FW-DMZ-FWD: " flags all
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
```

The `forward` chain is **permissive** — all traffic is forwarded. The primary security control is logging, not blocking. This matches training intent: defenders must detect attacks via SIEM, not have them silently blocked by the range.

> **Invariant:** Management traffic (eth0 / 10.0.0.0/24) is accepted *before* the `log` statement and must never appear in `FW-DMZ-FWD:` log lines.

---

## SNAT Chain (Attacker IP Diversity)

The SNAT chain is the mechanism by which scenario phases present arbitrary source IPs to defenders. It lives in the `nat` table and is toggled by scenario phase scripts via Saffron.

```nftables
table ip nat {

    # SNAT chain — empty by default; rules added/removed by scenario phases
    chain SCENARIO_SNAT {
        # Rules injected by scenario phases, e.g.:
        # ip saddr 9.53.99.1 oifname "eth2" snat to 3.3.3.3
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;

        # Jump to scenario SNAT chain first
        jump SCENARIO_SNAT

        # Default masquerade for traffic from external to DMZ
        # (only applies if SCENARIO_SNAT did not match)
        oifname "eth2" masquerade
    }
}
```

### How Scenario Phases Toggle SNAT Rules

Phase scripts use Saffron to run `nft` commands on fw-dmz:

```bash
# Activate a new attacker IP persona (e.g., phase 3 presents as 185.220.101.47)
cr_runcmd.bash fw-dmz "nft flush chain ip nat SCENARIO_SNAT"
cr_runcmd.bash fw-dmz "nft add rule ip nat SCENARIO_SNAT ip saddr 9.53.99.1 oifname eth2 snat to 185.220.101.47"
```

Because nftables is stateful, existing TCP connections from the previous phase's source IP continue to use that IP (tracked by conntrack) until the session closes. New connections from the next phase will use the new SNAT IP.

### Attacker IP Cleanup

At scenario reset, the SNAT chain is flushed:
```bash
cr_runcmd.bash fw-dmz "nft flush chain ip nat SCENARIO_SNAT"
```

---

## Logging

All forwarded traffic is logged with prefix `FW-DMZ-FWD:`. Logs go to the container's stdout (captured by Docker) and forwarded to rsyslog (`10.50.50.8:514`). From rsyslog they are picked up by Wazuh's syslog listener.

Wazuh decoders and rules for `FW-DMZ-FWD:` prefix should be configured in `ossec.conf` to generate alerts for:
- New connections from external → dmz
- Port scans (high volume SYN to multiple destinations)
- Unexpected protocols (non-HTTP/HTTPS to web servers)

---

## Files

| File | Description |
|------|-------------|
| `nftables.conf` | Full nftables ruleset loaded at container start via `nft -f /etc/nftables.conf` |
