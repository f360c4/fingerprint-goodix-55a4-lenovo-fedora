#!/usr/bin/env bash
# Phase 2: swap the distro libfprint for our RPM, lock it, enable driver debug
# output in fprintd, and run one fprintd-verify to see how far the driver gets.
# Expected on a Windows-paired sensor: firmware "GF3268_RTSEC_APP_10062" then
# "Invalid device PSK". Nothing here writes to the sensor (the driver only reads).
# Usage: sudo tools/phase2_install_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
user=${SUDO_USER:?run via sudo}

rpm=$(ls rpm/out/libfprint-goodixtls-55a4-1.94.6-*.x86_64.rpm | grep -v -e debuginfo -e debugsource -e devel | head -1)
[ -f "$rpm" ] || { echo "RPM not found, run rpm/build.sh first"; exit 1; }

echo "== installing $rpm"
if rpm -q libfprint-goodixtls-55a4 >/dev/null 2>&1; then
  dnf -y reinstall "$rpm" || dnf -y install "$rpm"
else
  dnf -y swap libfprint "$rpm"
fi
dnf versionlock add libfprint-goodixtls-55a4
echo "== versionlock:"; dnf versionlock list | grep -i fprint || true

# fprintd drop-in: libfprint debug output goes to the journal. Remove with
# tools/phase2_debug_off.sh (or rm the file + daemon-reload) once not needed.
mkdir -p /etc/systemd/system/fprintd.service.d
cat > /etc/systemd/system/fprintd.service.d/50-goodix-debug.conf <<'EOF'
[Service]
Environment=G_MESSAGES_DEBUG=all
EOF
systemctl daemon-reload
systemctl stop fprintd 2>/dev/null || true

stamp=$(date +%Y%m%d-%H%M%S)
log=logs/phase2-fprintd-$stamp.log
since=$(date '+%Y-%m-%d %H:%M:%S')
{
  echo "== $(rpm -q libfprint-goodixtls-55a4)"
  echo "== fprintd-list $user"; timeout 30 fprintd-list "$user" 2>&1 || echo "(exit $?)"
  echo "== fprintd-verify $user (no finger needed; expect a PSK error)"
  timeout 30 fprintd-verify "$user" 2>&1 || echo "(exit $?)"
  sleep 2
  echo "== journalctl -u fprintd"
  journalctl -u fprintd --since "$since" --no-pager -o short-precise 2>&1
} | tee "$log"
systemctl stop fprintd 2>/dev/null || true
chown "${SUDO_UID}:${SUDO_GID}" "$log"
echo
echo "log: $log"
grep -E "firmware|PSK|psk|TLS|Error|error" "$log" | head -20 || true
