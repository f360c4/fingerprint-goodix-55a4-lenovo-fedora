#!/usr/bin/env bash
# Phase 2b: start one fprintd-enroll so the driver runs its activate sequence
# (firmware check -> PSK check). On a Windows-paired sensor this must stop with
# "Invalid device PSK" before any TLS; nothing is written to the sensor.
# No finger is needed. Usage: sudo tools/phase2_enroll_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
user=${SUDO_USER:?run via sudo}

systemctl stop fprintd 2>/dev/null || true
stamp=$(date +%Y%m%d-%H%M%S)
log=logs/phase2-enroll-$stamp.log
since=$(date '+%Y-%m-%d %H:%M:%S')
{
  echo "== $(rpm -q libfprint-goodixtls-55a4)"
  echo "== fprintd-enroll $user (expect: Invalid device PSK)"
  timeout 30 fprintd-enroll "$user" 2>&1 || echo "(exit $?)"
  sleep 2
  echo "== journalctl -u fprintd"
  journalctl -u fprintd --since "$since" --no-pager -o short-precise 2>&1
} | tee "$log"
systemctl stop fprintd 2>/dev/null || true
chown "${SUDO_UID}:${SUDO_GID}" "$log"
echo
echo "log: $log"
echo "== resumo:"
grep -E "firmware|Firmware|PSK|psk|TLS|tls|Invalid|error|Error" "$log" | grep -v "Requesting\|Authorization" | head -20 || true
