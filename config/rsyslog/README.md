# config/rsyslog/ — Centralized Syslog Receiver

This directory contains `rsyslog.conf` for the `rsyslog` container. rsyslog acts as the central syslog aggregator for all Linux containers and firewall logs, then forwards to the Wazuh manager.

---

## Data Flow

```
fw-dmz      → UDP/TCP 514 → rsyslog (10.50.50.8) → Wazuh manager syslog listener (10.0.0.5:514)
fw-core     ↗
web-lin     ↗
wks-linux   ↗
db01        ↗
```

Windows machines do not send syslog. They use Wazuh agent directly (installed by `setup.ps1`).

---

## rsyslog.conf Structure

### Input Modules

```
module(load="imudp")
input(type="imudp" port="514")

module(load="imtcp")
input(type="imtcp" port="514")
```

Both UDP and TCP listeners on port 514. Firewall containers use UDP (nftables log → kernel syslog → UDP forward). Linux service containers use TCP for reliability.

### Template — Structured Log Format

```
template(name="RangeForwardFormat" type="string"
         string="<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag%%msg%\n")
```

Preserves the original hostname from the sending container. This is important so Wazuh rules can match on `%HOSTNAME%` to correlate events to specific machines (e.g., `fw-dmz` vs `wks-linux`).

### Local Storage

```
# Store all received logs locally by hostname
template(name="RemoteHostLog" type="string"
         string="/var/log/remote/%HOSTNAME%/%$YEAR%-%$MONTH%-%$DAY%.log")

*.* ?RemoteHostLog
```

Logs are also stored locally under `/var/log/remote/` (volume-mounted to `./data/rsyslog/`). This provides a persistent forensic archive that survives range restarts, useful for post-exercise review.

### Forward to Wazuh

```
# Forward everything to Wazuh manager syslog listener
*.* action(
    type="omfwd"
    target="10.0.0.5"
    port="514"
    protocol="tcp"
    action.resumeRetryCount="-1"
    queue.type="linkedList"
    queue.size="50000"
    queue.filename="wazuh-fwd"
    queue.saveOnShutdown="on"
)
```

Uses a disk-assisted queue so logs are not lost if Wazuh manager is temporarily unavailable during container startup ordering.

### Rate Limiting (Per-Host)

```
module(load="imudp"
       ratelimit.interval="1"
       ratelimit.burst="10000")
```

Prevents a scenario phase generating massive traffic from flooding the syslog receiver and dropping legitimate host logs.

---

## Files

| File | Description |
|------|-------------|
| `rsyslog.conf` | Full rsyslog configuration as described above |
