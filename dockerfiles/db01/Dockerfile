FROM mcr.microsoft.com/mssql/server:2022-latest

USER root

ENV DEBIAN_FRONTEND=noninteractive

# Install AD join tools and Wazuh agent dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        realmd \
        sssd \
        sssd-tools \
        adcli \
        samba-common-bin \
        packagekit \
        openssh-server \
        sudo \
        curl \
        gnupg2 \
        ca-certificates \
        krb5-user \
        msktutil \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && rm -rf /var/lib/apt/lists/*

# ── Administrator account ──────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash administrator \
    && echo "administrator:P@55w0rd!" | chpasswd \
    && usermod -aG sudo administrator

# Wazuh agent
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

# Run entrypoint as root — handles AD join, sshd, Wazuh setup
# sqlservr is exec'd at the end; it handles its own privilege model
ENTRYPOINT ["/entrypoint.sh"]
