FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server \
        sudo \
        curl \
        wget \
        git \
        vim \
        python3 \
        python3-pip \
        net-tools \
        iproute2 \
        netcat-openbsd \
        gnupg2 \
        ca-certificates \
        build-essential \
        docker.io \
        ansible \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && rm -rf /var/lib/apt/lists/*

# Wazuh agent
RUN curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH \
        | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
        https://packages.wazuh.com/4.x/apt/ stable main" \
        > /etc/apt/sources.list.d/wazuh.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends wazuh-agent \
    && rm -rf /var/lib/apt/lists/*

# ── User accounts ─────────────────────────────────────────────────────────────
# devuser — developer with SSH keys, git, docker, sudo
RUN useradd -m -s /bin/bash devuser \
    && echo "devuser:Password1!" | chpasswd \
    && usermod -aG sudo devuser \
    && usermod -aG docker devuser \
    && mkdir -p /home/devuser/.ssh \
    && ssh-keygen -t rsa -b 4096 -f /home/devuser/.ssh/id_rsa -N "" -C "devuser@wks-linux" \
    && chown -R devuser:devuser /home/devuser/.ssh \
    # Realistic bash_history with sensitive-looking entries
    && echo 'ssh devuser@192.168.200.6' >> /home/devuser/.bash_history \
    && echo 'git clone https://github.com/secure-net/internal-tools' >> /home/devuser/.bash_history \
    && echo 'ansible-playbook -i inventory deploy.yml' >> /home/devuser/.bash_history \
    && chown devuser:devuser /home/devuser/.bash_history

# sysadmin — elevated user with sudo, ansible, credentials in history
RUN useradd -m -s /bin/bash sysadmin \
    && echo "sysadmin:Password1!" | chpasswd \
    && usermod -aG sudo sysadmin \
    # Incriminating bash history (classic scenario target)
    && echo 'ssh Administrator@192.168.200.1' >> /home/sysadmin/.bash_history \
    && echo 'net rpc password Administrator Password1! -U SECURE/Administrator -S 192.168.200.1' >> /home/sysadmin/.bash_history \
    && echo 'mysql -h 192.168.214.10 -u sa -pPassword1! secure_db' >> /home/sysadmin/.bash_history \
    && chown sysadmin:sysadmin /home/sysadmin/.bash_history

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
