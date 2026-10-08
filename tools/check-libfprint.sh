#!/usr/bin/env bash
# After a system update, check that our libfprint still loads and still sees
# the reader. Exit 0 = fine; 1 = library broken (rebuild rpm/build.sh and
# reinstall); 2 = library ok but reader not found (USB/suspend issue).
# Usage: tools/check-libfprint.sh   (no root needed)
set -u
lib=/usr/lib64/libfprint-2.so.2
pkg=$(rpm -q libfprint-goodixtls-55a4 2>/dev/null) || { echo "libfprint-goodixtls-55a4 not installed"; exit 1; }
echo "package: $pkg"
missing=$(ldd "$lib" 2>/dev/null | grep "not found")
if [ -n "$missing" ]; then
  echo "BROKEN: $lib has unresolved libraries (a dependency changed soname):"
  echo "$missing"
  echo "fix: rpm/build.sh && sudo dnf reinstall rpm/out/libfprint-goodixtls-55a4-*.x86_64.rpm"
  exit 1
fi
if ! python3 - <<'EOF'
import ctypes, sys
try:
    ctypes.CDLL("/usr/lib64/libfprint-2.so.2")
except OSError as e:
    print("BROKEN: dlopen failed:", e); sys.exit(1)
EOF
then exit 1; fi
echo "library loads"
if ! lsusb -d 27c6:55a4 >/dev/null; then
  echo "reader 27c6:55a4 not on the USB bus (after suspend: try 'sudo systemctl restart fprintd')"
  exit 2
fi
if out=$(timeout 20 fprintd-list "$USER" 2>&1) && grep -q "Goodix" <<<"$out"; then
  echo "fprintd sees the reader: ok"
  exit 0
fi
echo "fprintd does not see the reader:"
echo "$out"
exit 2
