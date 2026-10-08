#!/usr/bin/env bash
# Remove the fprintd debug drop-in installed by tools/phase2_install_test.sh.
# Usage: sudo tools/debug-off.sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
rm -f /etc/systemd/system/fprintd.service.d/50-goodix-debug.conf
rmdir /etc/systemd/system/fprintd.service.d 2>/dev/null || true
systemctl daemon-reload
systemctl restart fprintd 2>/dev/null || true
echo "fprintd debug output disabled"
