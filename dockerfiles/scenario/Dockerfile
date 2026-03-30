FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# ── Core attack and recon tools ───────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        # Recon / scanning
        nmap masscan netcat-openbsd dnsutils whois \
        # Exploitation
        metasploit-framework \
        # AD / Windows attack toolkit
        impacket-scripts python3-impacket \
        bloodhound \
        crackmapexec \
        evil-winrm \
        enum4linux enum4linux-ng \
        ldapdomaindump \
        kerbrute \
        # LLMNR/NBT-NS poisoning
        responder \
        # Web
        gobuster feroxbuster nikto \
        # Password attacks
        hydra john hashcat \
        # SMB / file access
        smbclient smbmap \
        # Traffic / networking
        tcpdump wireshark-common net-tools iproute2 \
        # Fake-internet services
        postfix \
        coredns \
        # Infrastructure
        openssh-server curl wget git python3 python3-pip \
        ca-certificates gnupg2 \
        # General utilities
        screen tmux vim less \
    && rm -rf /var/lib/apt/lists/*

# ── Caddy — fake HTTPS C2/phishing server ─────────────────────────────────────
RUN curl -fsSL https://caddyserver.com/api/download?os=linux&arch=amd64 \
        -o /usr/local/bin/caddy \
    && chmod +x /usr/local/bin/caddy

# ── Sliver C2 framework ───────────────────────────────────────────────────────
RUN SLIVER_VER=$(curl -fsSL https://api.github.com/repos/BishopFox/sliver/releases/latest \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])") \
    && curl -fsSL \
        "https://github.com/BishopFox/sliver/releases/download/${SLIVER_VER}/sliver-server_linux" \
        -o /usr/local/bin/sliver-server \
    && chmod +x /usr/local/bin/sliver-server \
    && curl -fsSL \
        "https://github.com/BishopFox/sliver/releases/download/${SLIVER_VER}/sliver-client_linux" \
        -o /usr/local/bin/sliver \
    && chmod +x /usr/local/bin/sliver

# ── Wazuh agent (scenario is monitored too) ───────────────────────────────────
RUN curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH \
        | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
        https://packages.wazuh.com/4.x/apt/ stable main" \
        > /etc/apt/sources.list.d/wazuh.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends wazuh-agent \
    && rm -rf /var/lib/apt/lists/*

# ── SSH configuration ─────────────────────────────────────────────────────────
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo "root:${RANGE_PASSWORD:-Password!}" | chpasswd || true

# ── Caddyfile for serving setup scripts and fake internet content ─────────────
COPY Caddyfile /etc/caddy/Caddyfile

# ── Web document root ─────────────────────────────────────────────────────────
RUN mkdir -p /var/www/html/setup

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 80 443

ENTRYPOINT ["/entrypoint.sh"]
