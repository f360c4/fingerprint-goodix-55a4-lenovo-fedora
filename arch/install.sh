#!/usr/bin/env bash
# Arch / CachyOS / Omarchy: install the patched libfprint for the Goodix 27c6:55a4.
#   arch/install.sh            prebuilt package from arch/out (or a Release) if its
#                              libraries match this system, else build with makepkg
#   arch/install.sh --source   always build locally
#   arch/install.sh --binary   prebuilt only (refuse if libraries differ)
# Also installs a pacman hook that warns when a library update breaks the driver.
# Nothing here touches the sensor; pairing is tools/pair_psk.py (once, ever).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
pkgname=libfprint-goodixtls-55a4
mode="${1:-auto}"; mode="${mode#--}"

command -v pacman >/dev/null || { echo "pacman not found: this installer is for Arch-based distros"; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "only x86_64"; exit 1; }
if command -v lsusb >/dev/null && ! lsusb -d 27c6:55a4 >/dev/null; then
  echo "no 27c6:55a4 reader on USB; this package is only for that reader"; exit 1
fi

pkg=$(ls -1 "$here"/out/${pkgname}-*-x86_64.pkg.tar.zst 2>/dev/null | sort -V | tail -1)
compat=1
if [ -n "$pkg" ] && [ -f "$here/out/needed-libs.txt" ]; then
  compat=0
  while read -r lib; do
    [ -z "$lib" ] && continue
    ldconfig -p | grep -qF "	$lib (" || { echo "system lacks $lib (needed by the prebuilt package)"; compat=1; }
  done < "$here/out/needed-libs.txt"
fi
case "$mode" in
  auto)   [ -n "$pkg" ] && [ $compat -eq 0 ] && mode=binary || mode=source ;;
  binary) { [ -n "$pkg" ] && [ $compat -eq 0 ]; } || { echo "prebuilt package missing or incompatible; use --source"; exit 1; } ;;
  source) ;;
  *) echo "usage: $0 [--source|--binary]"; exit 1 ;;
esac

sudo -v || exit 1
sudo pacman -S --needed --noconfirm fprintd usbutils || exit 1
if [ "$mode" = source ]; then
  echo "== building with makepkg"
  sudo pacman -S --needed --noconfirm --asdeps base-devel meson ninja pkgconf gobject-introspection gtk-doc || exit 1
  work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
  cp "$here/PKGBUILD" "$repo"/rpm/patches/00*.patch "$work/"
  tarball=libfprint-TheWeirdDev-55b4-experimental-c1937b9.tar.xz
  if [ -f "$repo/vendor/jith-55a4/driver/upstream/$tarball" ]; then
    cp "$repo/vendor/jith-55a4/driver/upstream/$tarball" "$work/"
  else
    curl -fL -o "$work/$tarball" "https://github.com/jith/goodix-55a4-fingerprint/raw/e8ee5bc/driver/upstream/$tarball" || exit 1
  fi
  (cd "$work" && makepkg -f --noconfirm) || { echo "build failed"; exit 1; }
  pkg=$(ls -1 "$work"/${pkgname}-*-x86_64.pkg.tar.zst | head -1)
fi
echo "== installing $(basename "$pkg") (replaces libfprint)"
sudo pacman -U --noconfirm --ask 4 "$pkg" || exit 1

hook=goodix-55a4-libfprint-check
sudo install -Dm755 "$here/pacman-hook/$hook.sh" "/usr/local/libexec/$hook.sh"
sudo install -Dm644 "$here/pacman-hook/$hook.hook" "/etc/pacman.d/hooks/$hook.hook"
sudo systemctl restart fprintd 2>/dev/null
if ldd /usr/lib/libfprint-2.so.2 | grep -q "not found"; then
  echo "installed library cannot resolve its dependencies:"; ldd /usr/lib/libfprint-2.so.2 | grep "not found"; exit 1
fi
pacman -Q "$pkgname"
echo "Installed. Reader already paired? -> tools/enroll.sh ; then arch/enable-sudo.sh"
echo "Not paired yet (fprintd logs 'Invalid device PSK')? -> read DOSSIER-PSK.md, then sudo tools/run_pair_captured.sh"
