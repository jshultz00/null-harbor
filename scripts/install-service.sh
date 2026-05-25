#!/usr/bin/env bash
# Installs cyberrange-gui as a systemd service that starts at boot.
# Run once as a user with sudo access.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GUI_DIR="$PROJECT_ROOT/gui"
BINARY="$GUI_DIR/cyberrange-gui"
SERVICE_NAME="cyberrange-gui"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CURRENT_USER="$(whoami)"

export LIBVIRT_DEFAULT_URI="qemu:///system"

# Build binary first
echo "[*] Building cyberrange-gui..."
cd "$GUI_DIR"
go build -o "$BINARY" .
echo "[*] Build complete: $BINARY"

# Write service file
echo "[*] Writing $SERVICE_FILE ..."
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Cyber Range VM GUI
After=libvirtd.service network.target
Wants=libvirtd.service

[Service]
Type=simple
User=${CURRENT_USER}
Environment=LIBVIRT_DEFAULT_URI=qemu:///system
ExecStart=${BINARY} --port 8082 --web ${GUI_DIR}/web
WorkingDirectory=${GUI_DIR}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

echo "[*] Reloading systemd and enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE_NAME"

echo ""
echo "[+] Done. Service status:"
systemctl status "$SERVICE_NAME" --no-pager || true
echo ""
echo "[+] GUI available at: http://localhost:8082"
echo "    Manage with: sudo systemctl {start,stop,restart,status} $SERVICE_NAME"
