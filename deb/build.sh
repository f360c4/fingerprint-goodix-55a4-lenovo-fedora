#!/usr/bin/env bash
# Build libfprint-goodixtls-55a4 .deb packages inside podman containers, one per
# target distro, from the same snapshot + patches used by rpm/. Output: deb/out/.
# Usage: deb/build.sh [ubuntu:24.04] [ubuntu:26.04] [debian:13]   (default: all three)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
tarball=libfprint-TheWeirdDev-55b4-experimental-c1937b9.tar.xz
sha=56065bce8636147abe7f0a8da2019c815be9d92f297efa9381a0096d3d3a47c5
src="$repo/vendor/jith-55a4/driver/upstream/$tarball"
[ -f "$src" ] || { echo "missing $src (clone vendor/jith-55a4 or see rpm/build.sh for the download URL)"; exit 1; }
echo "$sha  $src" | sha256sum -c -
mkdir -p "$here/out" "$here/_work"
cp "$src" "$here/_work/"

targets=("$@"); [ ${#targets[@]} -gt 0 ] || targets=(ubuntu:24.04 ubuntu:26.04 debian:13)
# package version: higher than the distro fprintd's libfprint-2-2 (>= 1:1.94.9)
# requirement while stating the real base (1.94.6, commit c1937b9)
base_version="1:1.94.9+goodix55a4.1.94.6.c1937b9"

for img in "${targets[@]}"; do
  suffix=$(echo "$img" | tr -d ':' | tr -d '.')   # ubuntu2404
  echo "================ $img"
  podman run --rm -v "$here/debian:/debian:ro,Z" -v "$here/_work:/work:Z" \
    -v "$repo/rpm/patches:/patches:ro,Z" -v "$here/out:/out:Z" \
    -e DEBIAN_FRONTEND=noninteractive -e BASEVER="$base_version" -e SUFFIX="$suffix" \
    "docker.io/library/$img" bash -euo pipefail -c '
      apt-get update -qq
      apt-get install -y -qq --no-install-recommends \
        build-essential debhelper devscripts fakeroot meson ninja-build pkgconf \
        libglib2.0-dev libgusb-dev libgudev-1.0-dev libudev-dev libssl-dev libopencv-dev \
        libpixman-1-dev libnss3-dev libgirepository1.0-dev gobject-introspection gtk-doc-tools \
        xz-utils patch >/dev/null
      . /etc/os-release
      rm -rf /build && mkdir -p /build && cd /build
      tar -xJf /work/'"$tarball"'
      mv libfprint-goodixtls-55x4 libfprint-goodixtls-55a4-1.94.6
      cd libfprint-goodixtls-55a4-1.94.6
      for p in /patches/0001-*.patch /patches/0002-*.patch /patches/0008-*.patch /patches/0010-*.patch /patches/0011-*.patch /patches/0012-*.patch; do
        patch -Np1 -s -i "$p"
      done
      cp -r /debian debian
      mkdir -p debian/source && echo "3.0 (native)" > debian/source/format
      ver="${BASEVER}-1~${SUFFIX}"
      cat > debian/changelog <<EOF
libfprint-goodixtls-55a4 (${ver}) ${VERSION_CODENAME}; urgency=medium

  * libfprint 1.94.6 (TheWeirdDev 55b4-experimental c1937b9) + jith patches
    0001/0002/0008/0010/0011 + 0012 (optional doctest), packaged as a
    drop-in replacement for libfprint-2-2 on ${PRETTY_NAME}.

 -- Luiz Felipe <f360c4@gmail.com>  $(date -R)
EOF
      dpkg-buildpackage -us -uc -b 2>&1 | tail -5
      cd ..
      ls -1 *.deb
      cp *.deb /out/
      echo "---- install test (does not abort the build)"
      set +e
      apt-get install -y -qq --no-install-recommends fprintd >/dev/null 2>&1
      apt-get install -y -qq ./libfprint-goodixtls-55a4_*.deb 2>&1 | grep -E "^(Setting up|Removing|E:)"
      dpkg -l | grep -E "fprint" | awk "{print \$1, \$2, \$3}"
      echo "---- symbols: fprintd vs our lib"
      fprintd_bin=""
      for c in /usr/libexec/fprintd /usr/lib/fprintd/fprintd; do [ -x "$c" ] && fprintd_bin="$c" && break; done
      if [ -n "$fprintd_bin" ]; then
        if ldd -r "$fprintd_bin" 2>&1 | grep -i -E "undefined|not found"; then echo "SYMBOL PROBLEM"; else echo "no undefined symbols: fprintd links against our libfprint"; fi
      else echo "fprintd binary not found"; fi
      echo "---- lib resolves / lists 55a4"
      ldd /usr/lib/x86_64-linux-gnu/libfprint-2.so.2 | grep "not found" || echo "all libfprint deps resolve"
      strings /usr/lib/x86_64-linux-gnu/libfprint-2.so.2 | grep -q "55X4" && echo "goodixtls55x4 driver present"
      set -e
    '
done
ls -l "$here/out"
