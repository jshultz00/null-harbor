# dockerfiles/web-lin/ — Linux Web Server

web-lin is an Ubuntu 22.04 container running Apache 2.4 + PHP 8.1. It is the primary Linux web attack surface. Web content is scenario-swappable via a bind-mounted volume from `webapps/web01/`.

**Container:** web-lin  
**Control IP:** 10.0.0.40  
**DMZ IP:** 10.10.10.10  
**Exposed services:** HTTP :80, HTTPS :443 (Apache), SSH :22

---

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Ubuntu + Apache + PHP + Wazuh agent + Saffron agent |
| `entrypoint.sh` | Wazuh enrollment, Saffron start, Apache start |
| `apache2.conf` | Apache configuration (logging, headers, directory settings) |
| `php.ini` | PHP configuration (display_errors on — intentional for training) |

---

## Dockerfile

```dockerfile
FROM ubuntu:22.04

ARG WAZUH_VERSION=4.9.2
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    php8.1 libapache2-mod-php8.1 \
    php8.1-mysql php8.1-curl php8.1-xml php8.1-mbstring \
    curl wget git vim \
    rsyslog \
    ssh openssh-server \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Apache modules
RUN a2enmod rewrite headers ssl cgi

# Wazuh agent
RUN curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add - && \
    echo "deb https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list && \
    apt-get update && apt-get install -y wazuh-agent=${WAZUH_VERSION}-1 && \
    rm -rf /var/lib/apt/lists/*

# Saffron agent
COPY --from=saffron /usr/local/bin/saffron-agent /usr/local/bin/saffron-agent
RUN chmod +x /usr/local/bin/saffron-agent

# User accounts
RUN useradd -m -s /bin/bash www-admin && \
    echo "www-admin:${RANGE_PASSWORD}" | chpasswd && \
    usermod -aG sudo www-admin && \
    usermod -aG www-data www-admin

# SSH
RUN mkdir /var/run/sshd && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Apache config
COPY apache2.conf /etc/apache2/conf-available/range.conf
RUN a2enconf range

# PHP config (intentionally permissive for training)
COPY php.ini /etc/php/8.1/apache2/php.ini

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Web content volume mount point
VOLUME ["/var/www/html"]

EXPOSE 22 80 443
ENTRYPOINT ["/entrypoint.sh"]
```

---

## entrypoint.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# Saffron agent
saffron-agent --server "${COMMANDLY_SERVER:-http://10.0.0.1:8080}" --hostname web-lin &

# Wazuh enrollment + start
/var/ossec/bin/agent-auth \
    -m "${WAZUH_MANAGER:-10.0.0.5}" \
    -P "${WAZUH_ENROLLMENT_PSK}" \
    -A "web-lin"
/var/ossec/bin/wazuh-control start

# syslog forwarding
echo "*.* @10.50.50.8:514" >> /etc/rsyslog.conf
rsyslogd

# SSH daemon
/usr/sbin/sshd

# Apache (foreground)
exec apache2ctl -D FOREGROUND
```

---

## apache2.conf (Range-Specific Config)

```apache
# Log all requests with full detail (for Wazuh ingestion)
LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %D" combined_range
CustomLog /var/log/apache2/access.log combined_range

# Directory listing enabled (intentional — makes directory traversal findable in training)
<Directory /var/www/html>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

# Allow .htaccess overrides (needed for some vulnerable app scenarios)
AccessFileName .htaccess

# Expose server version (intentional — information disclosure for scanning scenarios)
ServerTokens Full
ServerSignature On
```

---

## php.ini (Training Permissive Settings)

```ini
; Intentionally permissive for training scenarios
display_errors = On
display_startup_errors = On
error_reporting = E_ALL

; Allow dangerous functions (needed for RCE simulation scenarios)
; disable_functions = (empty — all functions enabled)

; File uploads
file_uploads = On
upload_max_filesize = 50M
max_file_uploads = 20

; Allow URL include (needed for some RFI scenarios)
allow_url_include = On
allow_url_fopen = On
```

**Security note:** These settings are intentionally vulnerable — this is a training target, not a production server.

---

## Web Content (webapps/web01/)

The `/var/www/html` directory is volume-mounted from `webapps/web01/` on the host. Scenario phase scripts can modify this content via Saffron to simulate web defacement, inject backdoors, or replace the application.

Default content (pre-scenario): A simple "SECURE Corp Internal Portal" HTML page with a login form (non-functional by default).
