%global commit c1937b9
%global snapshot libfprint-TheWeirdDev-55b4-experimental-%{commit}
# the tarball unpacks into this directory
%global srcdir_name libfprint-goodixtls-55x4

Name:           libfprint-goodixtls-55a4
Version:        1.94.6
Release:        0.1.%{commit}%{?dist}
Summary:        libfprint with the goodixtls driver for the Goodix 27c6:55a4 fingerprint reader

License:        LGPL-2.1-or-later
URL:            https://github.com/jith/goodix-55a4-fingerprint
# TheWeirdDev/libfprint, branch 55b4-experimental, commit c1937b9, as snapshotted
# in jith/goodix-55a4-fingerprint driver/upstream/ (sha256 56065bce...47c5).
Source0:        %{snapshot}.tar.xz

# Patches 0001-0011 from jith/goodix-55a4-fingerprint (driver/patches), unmodified.
Patch0001:      0001-goodix55x4-host-side-finger-detect.patch
Patch0002:      0002-sigfm-opencv-pkgconfig-fallback.patch
Patch0008:      0008-sigfm-tuned-matcher-clahe-mutual.patch
Patch0010:      0010-goodix55x4-windows-fdt-flow-10062.patch
Patch0011:      0011-image-device-clean-enroll-completion.patch
# Ours: Fedora's doctest-devel has no pkg-config file; skip the tests binary.
Patch0012:      0012-sigfm-optional-doctest.patch

BuildRequires:  meson >= 0.56.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  gobject-introspection-devel
BuildRequires:  gtk-doc
BuildRequires:  pkgconfig(glib-2.0) >= 2.68
BuildRequires:  pkgconfig(gio-unix-2.0)
BuildRequires:  pkgconfig(gusb) >= 0.2.0
BuildRequires:  pkgconfig(gudev-1.0)
BuildRequires:  pkgconfig(udev)
BuildRequires:  pkgconfig(openssl)
BuildRequires:  pkgconfig(opencv4)
BuildRequires:  pkgconfig(pixman-1)
BuildRequires:  pkgconfig(nss)

# Drop-in replacement for the distro libfprint (same soname libfprint-2.so.2,
# same API); fprintd only depends on the soname.
Provides:       libfprint = %{version}-%{release}
Provides:       libfprint%{?_isa} = %{version}-%{release}
Conflicts:      libfprint

%description
libfprint 1.94.6 from the TheWeirdDev 55b4-experimental fork with the goodixtls
driver and the SIGFM (OpenCV) matcher, plus the patches from
jith/goodix-55a4-fingerprint that implement the Windows-driver capture flow for
the Goodix 27c6:55a4 reader (Lenovo ThinkPad E14 Gen 1) running the Lenovo
universal firmware GF32xx_RTSEC_APP_10062.

This package replaces the distribution libfprint. The reader must be paired with
the community Linux PSK first (see the project README); the driver itself never
writes to the sensor.

%package        devel
Summary:        Development files for %{name}
Requires:       %{name}%{?_isa} = %{version}-%{release}
Provides:       libfprint-devel = %{version}-%{release}
Provides:       libfprint-devel%{?_isa} = %{version}-%{release}
Conflicts:      libfprint-devel

%description    devel
Headers, pkg-config file and GObject introspection data for %{name}.

%prep
%autosetup -n %{srcdir_name} -p1

%build
%meson \
    -D doc=false \
    -D gtk-examples=false \
    -D installed-tests=false \
    -D udev_rules=disabled \
    -D udev_hwdb=disabled
%meson_build

%install
%meson_install

%files
%license COPYING
%doc AUTHORS NEWS README.md THANKS
%{_libdir}/libfprint-2.so.2
%{_libdir}/libfprint-2.so.2.0.0
%{_libdir}/girepository-1.0/FPrint-2.0.typelib

%files devel
%{_includedir}/libfprint-2/
%{_libdir}/libfprint-2.so
%{_libdir}/pkgconfig/libfprint-2.pc
%{_datadir}/gir-1.0/FPrint-2.0.gir

%changelog
* Wed Oct 08 2026 Luiz Felipe <f360c4@gmail.com> - 1.94.6-0.1.c1937b9
- Initial package: TheWeirdDev 55b4-experimental c1937b9 + jith patches
  0001/0002/0008/0010/0011 + Fedora doctest fix (0012)
