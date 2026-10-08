# Patches

| Patch | Origin | What |
|---|---|---|
| 0001, 0002, 0008, 0010, 0011 | [jith/goodix-55a4-fingerprint](https://github.com/jith/goodix-55a4-fingerprint) `driver/patches`, commit e8ee5bc, unmodified | 55a4 driver: host-side finger detect, OpenCV pkg-config fallback, tuned SIGFM matcher, Windows-driver capture flow for firmware 10062, clean enroll completion |
| 0012 | this repo | make `doctest` optional so meson configures on Fedora (doctest-devel ships only a CMake config) |

Applied on top of TheWeirdDev/libfprint branch `55b4-experimental` commit `c1937b9`
(tarball `libfprint-TheWeirdDev-55b4-experimental-c1937b9.tar.xz`,
sha256 `56065bce8636147abe7f0a8da2019c815be9d92f297efa9381a0096d3d3a47c5`, as snapshotted
by jith). The patches are all LGPL-2.1-or-later like libfprint.
