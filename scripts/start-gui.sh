#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GUI_DIR="$PROJECT_ROOT/gui"
BINARY="$GUI_DIR/cyberrange-gui"
PORT=8082

export LIBVIRT_DEFAULT_URI="qemu:///system"

# Check libvirt group membership (required to talk to libvirtd without sudo)
if ! groups | grep -qw libvirt; then
    echo "[!] WARNING: User '$(whoami)' is not in the 'libvirt' group."
    echo "    VM state and specs will show as 'unknown' until you fix this."
    echo ""
    echo "    Run these commands, then log out and back in:"
    echo "      sudo usermod -aG libvirt $(whoami)"
    echo "      newgrp libvirt   # applies without full logout (current shell only)"
    echo ""
fi

# Check if already running
if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
    echo "[!] Port ${PORT} is already in use. Is the GUI already running?"
    exit 1
fi

# Build if binary is missing or source is newer
if [ ! -f "$BINARY" ] || [ "$GUI_DIR/main.go" -nt "$BINARY" ]; then
    echo "[*] Building cyberrange-gui..."
    cd "$GUI_DIR"
    go build -o "$BINARY" .
    echo "[*] Build complete."
fi

echo "[*] Starting Cyber Range GUI at http://localhost:${PORT}"
exec "$BINARY" --port "$PORT" --web "$GUI_DIR/web"
