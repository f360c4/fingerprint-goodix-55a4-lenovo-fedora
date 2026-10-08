#!/usr/bin/env bash
# Build the Arch package in a clean archlinux container (podman), so the result
# matches current Arch/CachyOS/Omarchy libraries. Output: arch/out/*.pkg.tar.zst
# plus needed-libs.txt (sonames the binary links, used by install.sh to decide
# whether the prebuilt package fits the target system).
# Usage: arch/build.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
tarball=libfprint-TheWeirdDev-55b4-experimental-c1937b9.tar.xz
sha=56065bce8636147abe7f0a8da2019c815be9d92f297efa9381a0096d3d3a47c5
src="$repo/vendor/jith-55a4/driver/upstream/$tarball"
[ -f "$src" ] || { echo "missing $src (see rpm/build.sh for the download URL)"; exit 1; }
echo "$sha  $src" | sha256sum -c -

work="$here/_work"; rm -rf "$work"; mkdir -p "$work" "$here/out"
cp "$src" "$here/PKGBUILD" "$repo"/rpm/patches/00*.patch "$work/"

podman run --rm -v "$work:/work:z" -v "$here/out:/out:z" docker.io/library/archlinux:latest \
  bash -euo pipefail -c '
    pacman -Syu --noconfirm --needed base-devel meson ninja pkgconf gobject-introspection gtk-doc \
      glib2 libgusb openssl pixman nss libgudev opencv fprintd usbutils >/dev/null
    useradd -m build
    cp -r /work /home/build/pkg && chown -R build /home/build/pkg
    cd /home/build/pkg
    su build -c "makepkg -f --noconfirm 2>&1 | tail -5"
    ls -1 *.pkg.tar.zst
    cp *.pkg.tar.zst /out/
    echo "---- install test"
    pacman -U --noconfirm *.pkg.tar.zst 2>&1 | grep -E "installing|removing|conflict|error" || true
    pacman -Q libfprint-goodixtls-55a4 fprintd
    ldd -r /usr/lib/fprintd 2>&1 | grep -i -E "undefined|not found" && echo "SYMBOL PROBLEM" || echo "fprintd: no undefined symbols against our libfprint"
    ldd /usr/lib/libfprint-2.so.2 | grep "not found" || echo "all libfprint deps resolve"
    readelf -d /usr/lib/libfprint-2.so.2 | awk "/NEEDED/{gsub(/[\\[\\]]/,\"\",\$5); print \$5}" > /out/needed-libs.txt
    grep -q 55X4 /usr/lib/libfprint-2.so.2 && echo "goodixtls55x4 driver present"
  '
(cd "$here/out" && sha256sum ./*.pkg.tar.zst | sed 's| \./| |' > SHA256SUMS)
rm -rf "$work"
ls -l "$here/out"; echo "needed libs:"; cat "$here/out/needed-libs.txt"
