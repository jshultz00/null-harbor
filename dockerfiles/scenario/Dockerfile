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
        # Infrastructure
        openssh-server curl wget git python3 python3-pip \
        ca-certificates gnupg2 \
        # General utilities
        screen tmux vim less \
    && rm -rf /var/lib/apt/lists/*

# ── ldapdomaindump — pip package, not in Kali apt ────────────────────────────
RUN pip3 install --break-system-packages ldapdomaindump

# ── kerbrute — GitHub binary release ─────────────────────────────────────────
RUN curl -fsSL \
        "https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_amd64" \
        -o /usr/local/bin/kerbrute \
    && chmod +x /usr/local/bin/kerbrute

# ── CoreDNS — GitHub binary release ──────────────────────────────────────────
RUN curl -fsSL \
        "https://github.com/coredns/coredns/releases/download/v1.14.2/coredns_1.14.2_linux_amd64.tgz" \
        | tar -xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/coredns

# ── Caddy — fake HTTPS C2/phishing server ─────────────────────────────────────
RUN curl -fsSL \
        "https://github.com/caddyserver/caddy/releases/download/v2.11.2/caddy_2.11.2_linux_amd64.tar.gz" \
        | tar -xz -C /usr/local/bin caddy \
    && chmod +x /usr/local/bin/caddy

# ── Sliver C2 framework ───────────────────────────────────────────────────────
RUN curl -fsSL \
        "https://github.com/BishopFox/sliver/releases/download/v1.7.3/sliver-server_linux-amd64" \
        -o /usr/local/bin/sliver-server \
    && chmod +x /usr/local/bin/sliver-server \
    && curl -fsSL \
        "https://github.com/BishopFox/sliver/releases/download/v1.7.3/sliver-client_linux-amd64" \
        -o /usr/local/bin/sliver \
    && chmod +x /usr/local/bin/sliver

# ── SSH configuration ─────────────────────────────────────────────────────────
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo "root:${RANGE_PASSWORD:-P@55w0rd!}" | chpasswd || true

# ── Attacker user — primary trainer/student SSH account ───────────────────────
RUN useradd -m -s /bin/bash attacker \
    && echo "attacker:NewPassWhoDis?" | chpasswd \
    && usermod -aG sudo attacker

# ── Caddyfile for serving setup scripts and fake internet content ─────────────
COPY Caddyfile /etc/caddy/Caddyfile

# ── Web document root ─────────────────────────────────────────────────────────
RUN mkdir -p /var/www/html/setup

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 80 443

ENTRYPOINT ["/entrypoint.sh"]
