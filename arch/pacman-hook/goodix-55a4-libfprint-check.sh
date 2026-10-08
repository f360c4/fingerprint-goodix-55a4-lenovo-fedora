#!/bin/sh
# Pacman post-transaction hook: warn (never fail) when an update broke the
# patched libfprint or replaced it with the stock one. Passwords always keep working.
lib=/usr/lib/libfprint-2.so.2
if [ -e "$lib" ] && ldd "$lib" 2>/dev/null | grep -q "not found"; then
  echo "WARNING: libfprint-goodixtls-55a4 can no longer load:"
  ldd "$lib" | grep "not found"
  echo "Fingerprint is off until rebuilt: <repo>/arch/install.sh --source"
fi
if ! pacman -Q libfprint-goodixtls-55a4 >/dev/null 2>&1 && pacman -Q libfprint >/dev/null 2>&1; then
  echo "WARNING: stock libfprint replaced libfprint-goodixtls-55a4 (Goodix 55a4 reader stops working); reinstall with <repo>/arch/install.sh"
fi
exit 0
