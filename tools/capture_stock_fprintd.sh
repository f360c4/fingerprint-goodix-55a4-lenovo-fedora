#!/usr/bin/env bash
# Baseline: usbmon capture of what the stock Fedora fprintd/libfprint sends to
# 27c6:55a4 while running fprintd-list and fprintd-verify. Stops fprintd at the end.
# Usage: sudo tools/capture_stock_fprintd.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
user=${SUDO_USER:?run via sudo}

sysdev=$(grep -l '^27c6$' /sys/bus/usb/devices/*/idVendor | xargs -n1 dirname |
  while read -r d; do [ "$(cat "$d/idProduct")" = 55a4 ] && echo "$d"; done | head -1)
bus=$(cat "$sysdev/busnum"); addr=$(cat "$sysdev/devnum")
stamp=$(date +%Y%m%d-%H%M%S)
log=logs/stock-fprintd-$stamp.log
raw=$(mktemp --suffix=.pcapng)
cap=dumps/stock-fprintd-$stamp.pcapng

systemctl stop fprintd
modprobe usbmon
tshark -q -i "usbmon$bus" -w "$raw" 2>/dev/null &
tpid=$!
sleep 2
since=$(date '+%Y-%m-%d %H:%M:%S')
{
  echo "== bus $bus addr $addr"
  echo "== fprintd-list $user"; timeout 20 fprintd-list "$user" 2>&1 || echo "(exit $?)"
  echo "== fprintd-verify $user"; timeout 20 fprintd-verify "$user" 2>&1 || echo "(exit $?)"
  echo "== journalctl -u fprintd"; journalctl -u fprintd --since "$since" --no-pager 2>&1
} | tee "$log"
sleep 1
kill "$tpid"; wait "$tpid" 2>/dev/null || true
systemctl stop fprintd
tshark -r "$raw" -Y "usb.bus_id == $bus && usb.device_address == $addr" -w "$cap"
rm -f "$raw"
echo "== frames to/from sensor: $(tshark -r "$cap" 2>/dev/null | wc -l)" | tee -a "$log"
tshark -r "$cap" -T fields -e frame.number -e usb.transfer_type -e usb.endpoint_address \
  -e usb.urb_type -e usb.setup.bRequest -e usb.data_len 2>/dev/null >> "$log" || true
chown "${SUDO_UID}:${SUDO_GID}" "$log" "$cap"
echo "log $log ; capture $cap"
