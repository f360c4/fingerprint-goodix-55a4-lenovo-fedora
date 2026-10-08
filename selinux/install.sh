#!/usr/bin/env bash
# Build and load the fprintd_opencv SELinux module (silences the nr_hugepages
# alert). Needs: sudo dnf install selinux-policy-devel
# Usage: sudo selinux/install.sh      remove: sudo semodule -r fprintd_opencv
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ -f /usr/share/selinux/devel/Makefile ] || { echo "install selinux-policy-devel first"; exit 1; }
make -f /usr/share/selinux/devel/Makefile fprintd_opencv.pp
semodule -i fprintd_opencv.pp
rm -f fprintd_opencv.pp tmp -r
semodule -l | grep fprintd_opencv && echo "loaded"
