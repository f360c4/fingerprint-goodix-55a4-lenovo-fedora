#!/usr/bin/env bash
# Run tools/probe_readonly.py under a usbmon capture, as root.
# Read-only: the probe only sends whitelisted read opcodes (see NOTES.md).
# Usage: sudo tools/run_probe_captured.sh
set -euo pipefail
cd "$(dirname "$0")/.."

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
command -v tshark >/dev/null || { echo "tshark missing (dnf install wireshark-cli)"; exit 1; }

if systemctl is-active --quiet fprintd; then
  echo "fprintd is active; stop it first: sudo systemctl stop fprintd"; exit 1
fi

sysdev=$(grep -l '^27c6$' /sys/bus/usb/devices/*/idVendor | xargs -n1 dirname |
  while read -r d; do [ "$(cat "$d/idProduct")" = 55a4 ] && echo "$d"; done | head -1)
[ -n "$sysdev" ] || { echo "27c6:55a4 not found"; exit 1; }
bus=$(cat "$sysdev/busnum"); addr=$(cat "$sysdev/devnum")
devnode=$(printf '/dev/bus/usb/%03d/%03d' "$bus" "$addr")
if fuser "$devnode" 2>/dev/null; then
  echo "$devnode is open by another process; aborting"; exit 1
fi

stamp=$(date +%Y%m%d-%H%M%S)
log=logs/probe-$stamp.log
raw=$(mktemp --suffix=.pcapng)
cap=dumps/probe-$stamp.pcapng

modprobe usbmon
tshark -q -i "usbmon$bus" -w "$raw" 2>/dev/null &
tpid=$!
sleep 2

echo "bus $bus addr $addr ($devnode), log $log" | tee "$log"
set +e
.venv/bin/python tools/probe_readonly.py -o "dumps/probe-$stamp.json" 2>&1 | tee -a "$log"
rc=${PIPESTATUS[0]}
set -e

sleep 1
kill "$tpid"; wait "$tpid" 2>/dev/null || true
# keep only the sensor's traffic (the bus also carries the webcam and bluetooth)
tshark -r "$raw" -Y "usb.bus_id == $bus && usb.device_address == $addr" -w "$cap"
rm -f "$raw"
tshark -r "$cap" -Y "usb.endpoint_address.direction == 0 && usb.capdata" \
  -T fields -e frame.number -e usb.endpoint_address -e usb.capdata > "logs/probe-$stamp-out-frames.txt" || true

uid=${SUDO_UID:-0}; gid=${SUDO_GID:-0}
chown "$uid:$gid" "$log" "$cap" "logs/probe-$stamp-out-frames.txt" "dumps/probe-$stamp.json" 2>/dev/null || true
echo "capture: $cap ; host->device frames: logs/probe-$stamp-out-frames.txt ; exit $rc"
exit "$rc"
