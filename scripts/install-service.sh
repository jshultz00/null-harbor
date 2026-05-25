#!/usr/bin/env bash
# Installs null-harbor-gui as a systemd service that starts at boot.
# Idempotent: will kill and reinstall if already running.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GUI_DIR="$PROJECT_ROOT/gui"
BINARY="$GUI_DIR/null-harbor-gui"
SERVICE_NAME="null-harbor-gui"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CURRENT_USER="$(whoami)"

export LIBVIRT_DEFAULT_URI="qemu:///system"

# Stop service if running
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo "[*] Service is running. Stopping..."
    sudo systemctl stop "$SERVICE_NAME"
    sleep 1
fi

# Kill any processes still listening on port 8082
if sudo lsof -i :8082 &>/dev/null; then
    echo "[*] Killing process on port 8082..."
    PID=$(sudo lsof -ti :8082)
    sudo kill -9 "$PID" 2>/dev/null || true
    sleep 1
fi

# Build binary
echo "[*] Building null-harbor-gui..."
cd "$GUI_DIR"
go build -o "$BINARY" .
echo "[*] Build complete: $BINARY"

# Write service file
echo "[*] Writing $SERVICE_FILE ..."
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Null Harbor VM GUI
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
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"
sleep 2

echo ""
echo "[+] Done. Service status:"
systemctl status "$SERVICE_NAME" --no-pager || true
echo ""
echo "[+] GUI available at: http://localhost:8082"
echo "    Manage with: sudo systemctl {start,stop,restart,status} $SERVICE_NAME"
