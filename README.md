# Lenovo ThinkPad E14 Gen 1 fingerprint reader on Linux (Fedora) — Goodix 27c6:55a4

**Guia completo em português: [README.pt-BR.md](README.pt-BR.md).**

`lsusb` shows `27c6:55a4 Shenzhen Goodix Technology Co.,Ltd. Goodix FingerPrint Device`,
`fprintd-enroll` says **`No devices available`**, KDE/GNOME "Fingerprint" settings show
nothing — and the Fedora `libfprint` lists the reader as *unsupported*. This repository
makes that reader work on **Fedora** (sudo, screen lock, login via `fprintd`/PAM) with:

- a **Fedora RPM** of the community libfprint driver (`goodixtls`, from
  [jith/goodix-55a4-fingerprint](https://github.com/jith/goodix-55a4-fingerprint), which
  targets Arch/CachyOS) — [prebuilt RPM in Releases](../../releases), or `rpm/build.sh`;
- a **pairing-only** tool: if the reader already runs Lenovo's universal firmware
  `GF32xx_RTSEC_APP_10062` (likely, if the laptop ever ran Windows with Windows Update), **no
  firmware flash is needed** — one 112-byte command replaces the Windows pairing key (PSK)
  with the Linux one. No bootloader, no erase, no brick risk from a firmware write;
- **Debian/Ubuntu `.deb`** packages (Ubuntu 24.04/26.04, Debian 13) built in clean containers —
  experimental until someone confirms on real hardware (see the Portuguese guide);
- a **read-only probe** that tells you which firmware, bootloader and pairing state your
  reader is in before you change anything;
- the measured results and every log (NOTES.md), so the next person does not have to guess.

Tested 2026-10-08: ThinkPad E14 Gen 1 **20RB002BBR** (machine types 20RA/20RB share the
reader), Fedora 44 KDE Plasma, kernel 7.2, OpenSSL 3.5, OpenCV 4.13 — enrollment 40/40
presses accepted, verification 3/3, sudo + lock screen by fingerprint, password fallback kept,
survives suspend/resume. The same pairing-only path was reported working on a ThinkBook 15-IIL
with firmware 10052 on Omarchy (jith's issue #1).

## Quick start

```bash
git clone https://github.com/f360c4/fingerprint-goodix-55a4-lenovo-fedora
cd fingerprint-goodix-55a4-lenovo-fedora
python3 -m venv .venv && .venv/bin/pip install pyusb
sudo systemctl stop fprintd && sudo .venv/bin/python tools/probe_readonly.py   # 1. read state, writes nothing
# firmware must be GF32xx_RTSEC_APP_10062 and iap MILAN_RTSEC_IAP_10027 to continue
sudo dnf swap libfprint ./libfprint-goodixtls-55a4-*.x86_64.rpm   # 2. driver (RPM from Releases, or rpm/build.sh)
sudo dnf versionlock add libfprint-goodixtls-55a4
sudo tools/run_pair_captured.sh                                   # 3. pair: THE ONLY STEP THAT WRITES TO THE READER
tools/enroll.sh && fprintd-verify                                 # 4. enroll (40 light presses), test
sudo authselect enable-feature with-fingerprint                   # 5. PAM: fingerprint as "sufficient", password stays
```

Each step is explained in the Portuguese guide; `DOSSIER-PSK.md` explains exactly what step 3
writes and why it is low-risk; `NOTES.md` has the full investigation with evidence.

## Debian / Ubuntu (.deb, experimental)

Ubuntu 24.04 LTS, Ubuntu 26.04 LTS and Debian 13 packages are attached to the release, built in
clean containers (`deb/build.sh`). They replace `libfprint-2-2` (and Ubuntu's `libfprint-2-tod1`);
the distro `fprintd` keeps working. Verified in containers: clean install over the stock package,
`fprintd` resolves every symbol against our library, driver present. **Not yet tested with the
sensor on real Debian/Ubuntu hardware** — if it works for you, open an issue.

```bash
sudo apt install ./libfprint-goodixtls-55a4_*ubuntu2404_amd64.deb   # or ubuntu2604 / debian13
sudo apt-mark hold libfprint-goodixtls-55a4
# then the same probe -> pair -> enroll steps; PAM via: sudo pam-auth-update
```

## Which firmware is your reader on?

| `tools/probe_readonly.py` says | Then |
|---|---|
| `GF3208/3258/3268_RTSEC_APP_10062` | this repo: pair only, no flash |
| `GF3208_RTSEC_APP_10039` (factory) or `GF3268_RTSEC_APP_10041` (goodix-fp-dump) | needs a firmware flash through the bootloader — **not covered here**, see jith's README (risk of unusable reader) |
| `MILAN_RTSEC_IAP_10027` as *firmware* | reader is in bootloader mode (app erased) — same as above |

## Why isn't this "in the kernel" / in Fedora already?

Fingerprint readers are not kernel drivers on Linux. The kernel only exposes the USB
device; the driver lives in **libfprint** (userspace, freedesktop.org), and `fprintd` talks
to it. Upstream libfprint has not accepted a driver for the Goodix "TLS" family (5110, 5503,
55a4, 55b4…) because of how these sensors work: they send **raw fingerprint images** to the
host over a TLS-PSK session, matching is done on the host (upstream libfprint prefers
match-on-chip or its own matcher), the community solution requires **writing a publicly known
key into the device**, the matcher depends on OpenCV, and the firmware/protocol were
reverse-engineered. So the driver exists only as forks (TheWeirdDev → jith) that replace
`libfprint` wholesale. That is why Fedora cannot ship it and why this repo packages it as a
replacement RPM with `Provides/Conflicts: libfprint` and a `dnf versionlock`.

What *can* go upstream, and what this repo contributes back:
- to **jith/goodix-55a4-fingerprint**: a second confirmed pairing-only case (10062,
  Windows-paired, 20RB, Fedora) and a pairing-only helper (issue #1);
- to **TheWeirdDev/libfprint**: the `goodix_send_preset_psk_write` length bug (truncated
  key) and the fact that the TLS handshake works under Fedora's default crypto policy;
- to **goodix-fp-linux-dev**: a 10062 Windows-paired data point and read-only probe/pairing
  tools that never call the erase/flash path.

## Security notes

The Linux pairing key is public (all zeros): anyone with physical USB access could
impersonate the reader. No liveness detection. PAM `sufficient` means a fingerprint replaces
the password wherever enabled. Templates live in `/var/lib/fprint` (root only). Windows
Hello pairing is lost (Windows re-pairs when reinstalled; dual boot does not work with one key).

## Credits and license

Driver patches: [jith](https://github.com/jith/goodix-55a4-fingerprint). libfprint fork:
[TheWeirdDev/libfprint](https://github.com/TheWeirdDev/libfprint) (`55b4-experimental`).
Protocol: [goodix-fp-linux-dev](https://github.com/goodix-fp-linux-dev). libfprint and the
driver patches are LGPL-2.1-or-later; this repository's scripts and docs are MIT (see
`LICENSE`). Firmware is not redistributed.

*Keywords: ThinkPad E14 Gen 1 fingerprint Linux, 20RA, 20RB, Goodix 27c6:55a4, Goodix
FingerPrint Device, fprintd No devices available, Invalid device PSK, libfprint goodixtls,
Fedora fingerprint reader, GF3208_RTSEC_APP_10062, Lenovo fingerprint Linux, leitor de
digitais Linux.*
