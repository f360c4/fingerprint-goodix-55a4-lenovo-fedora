#!/usr/bin/env bash
# Build libfprint-goodixtls-55a4 RPMs from this directory, offline.
# The upstream snapshot comes from vendor/jith-55a4 (or is downloaded from
# jith's repo if vendor/ is absent); its sha256 is checked either way.
# Output: rpm/out/*.rpm. Usage: rpm/build.sh [--mock]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
spec="$here/libfprint-goodixtls-55a4.spec"
tarball=libfprint-TheWeirdDev-55b4-experimental-c1937b9.tar.xz
sha=56065bce8636147abe7f0a8da2019c815be9d92f297efa9381a0096d3d3a47c5
jith_raw=https://github.com/jith/goodix-55a4-fingerprint/raw/e8ee5bc/driver/upstream/$tarball

top="$here/_topdir"
rm -rf "$top"; mkdir -p "$top"/{SOURCES,SPECS,BUILD,RPMS,SRPMS} "$here/out"

src="$repo/vendor/jith-55a4/driver/upstream/$tarball"
if [ ! -f "$src" ]; then
  src="$top/SOURCES/$tarball"
  echo "vendor/ snapshot missing, downloading $jith_raw"
  curl -fL -o "$src" "$jith_raw"
fi
echo "$sha  $src" | sha256sum -c -
cp "$src" "$top/SOURCES/"
cp "$here"/patches/*.patch "$top/SOURCES/"
cp "$spec" "$top/SPECS/"

if [ "${1:-}" = "--mock" ]; then
  rpmbuild --define "_topdir $top" -bs "$top/SPECS/$(basename "$spec")"
  mock -r "fedora-$(rpm -E %fedora)-x86_64" --resultdir "$here/out" "$top"/SRPMS/*.src.rpm
else
  rpmbuild --define "_topdir $top" -ba "$top/SPECS/$(basename "$spec")"
  cp "$top"/RPMS/*/*.rpm "$top"/SRPMS/*.rpm "$here/out/"
fi
ls -l "$here/out"
