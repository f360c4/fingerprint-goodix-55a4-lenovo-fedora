#!/usr/bin/env bash
# Phase 4: probe (read-only) -> pair_psk.py (ONE write) -> probe, all under a
# usbmon capture, with sleep inhibited. Only run after FLASH AUTORIZADO.
# Usage: sudo tools/run_pair_captured.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
command -v tshark >/dev/null || { echo "tshark missing"; exit 1; }

# preconditions
ac=$(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1 || echo "?")
bat=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1 || echo "?")
echo "AC online: $ac  battery: $bat%"
[ "$ac" = "1" ] || { echo "ABORT: AC not connected"; exit 1; }
[ "${bat:-0}" -ge 50 ] 2>/dev/null || { echo "ABORT: battery < 50%"; exit 1; }
if systemctl is-active --quiet fprintd; then echo "ABORT: fprintd active (systemctl stop fprintd)"; exit 1; fi

sysdev=$(grep -l '^27c6$' /sys/bus/usb/devices/*/idVendor | xargs -n1 dirname |
  while read -r d; do [ "$(cat "$d/idProduct")" = 55a4 ] && echo "$d"; done | head -1)
[ -n "$sysdev" ] || { echo "ABORT: 27c6:55a4 not found"; exit 1; }
bus=$(cat "$sysdev/busnum"); addr=$(cat "$sysdev/devnum")
devnode=$(printf '/dev/bus/usb/%03d/%03d' "$bus" "$addr")
if fuser "$devnode" 2>/dev/null; then echo "ABORT: $devnode is open by another process"; exit 1; fi

stamp=$(date +%Y%m%d-%H%M%S)
log=logs/pair-$stamp.log
raw=$(mktemp --suffix=.pcapng)
cap=dumps/pair-$stamp.pcapng

systemd-inhibit --what=sleep:idle:handle-lid-switch --who=goodix-psk --why="PSK write" sleep 600 &
inh=$!
modprobe usbmon
tshark -q -i "usbmon$bus" -w "$raw" 2>/dev/null &
tpid=$!
sleep 2
cleanup() {
  sleep 1; kill "$tpid" 2>/dev/null; wait "$tpid" 2>/dev/null || true
  kill "$inh" 2>/dev/null || true
  tshark -r "$raw" -Y "usb.bus_id == $bus && usb.device_address == $addr" -w "$cap" 2>/dev/null || true
  rm -f "$raw"
  chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$log" "$cap" dumps/probe-*.json dumps/pair-*.json 2>/dev/null || true
  echo "log $log ; capture $cap"
}
trap cleanup EXIT

{
  echo "== bus $bus addr $addr ($devnode)"
  echo "== probe BEFORE"
  .venv/bin/python tools/probe_readonly.py -o "dumps/probe-$stamp-before.json" 2>&1 || { echo "ABORT: probe failed, not writing"; exit 1; }
  echo "== pair"
  .venv/bin/python tools/pair_psk.py --i-typed-flash-autorizado -o "dumps/pair-$stamp.json" 2>&1
  rc=$?
  echo "== pair exit $rc"
  sleep 1
  echo "== probe AFTER"
  .venv/bin/python tools/probe_readonly.py -o "dumps/probe-$stamp-after.json" 2>&1 || true
  exit "$rc"
} 2>&1 | tee "$log"
