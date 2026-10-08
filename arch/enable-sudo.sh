#!/usr/bin/env bash
# Arch-based distros: fingerprint for sudo as "sufficient" (password still works;
# fingerprint failure or missing reader just falls through to the password).
# Short timeout so a missed touch does not block the password prompt for long.
#   arch/enable-sudo.sh             enable (timeout 10 s, 2 tries)
#   arch/enable-sudo.sh --disable   remove again
# Omarchy users: Omarchy's own fingerprint setup (omarchy-setup-fingerprint) does
# the same for sudo/login and can be used instead.
set -u
f=/etc/pam.d/sudo
line="auth sufficient pam_fprintd.so max-tries=${MAX_TRIES:-2} timeout=${TIMEOUT:-10}"
if [ "${1:-}" = "--disable" ]; then
  sudo sed -i '/^auth[[:space:]]\+sufficient[[:space:]]\+pam_fprintd\.so/d' "$f" && echo "removed from $f"
  exit 0
fi
sudo cp -n "$f" "$f.before-fingerprint"
if grep -q '^auth[[:space:]]\+sufficient[[:space:]]\+pam_fprintd\.so' "$f"; then
  sudo sed -i "s|^auth[[:space:]]\+sufficient[[:space:]]\+pam_fprintd\.so.*|$line|" "$f"
else
  sudo sed -i "0,/^auth/s||$line\n&|" "$f"   # before the first auth line (the password one)
fi
echo "== $f"; grep '^auth' "$f"
echo "test: sudo -k; sudo true   (touch the reader, or just press Enter for the password)"
