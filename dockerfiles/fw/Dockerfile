FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        nftables \
        iproute2 \
        netcat-openbsd \
        openssh-server \
        sudo \
        curl \
        gnupg2 \
        ca-certificates \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && rm -rf /var/lib/apt/lists/*

# ── Administrator account ──────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash administrator \
    && echo "administrator:P@55w0rd!" | chpasswd \
    && usermod -aG sudo administrator

# Wazuh agent — pre-install so every startup is fast
RUN curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH \
        | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
        https://packages.wazuh.com/4.x/apt/ stable main" \
        > /etc/apt/sources.list.d/wazuh.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends wazuh-agent \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
