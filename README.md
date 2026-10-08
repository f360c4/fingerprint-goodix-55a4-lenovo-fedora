# Goodix 27c6:55a4 fingerprint reader on Fedora (Lenovo ThinkPad E14 Gen 1)

**Guia completo em português: [README.pt-BR.md](README.pt-BR.md).**

Fedora packaging (RPM) of the community libfprint driver for the Goodix `27c6:55a4`
reader found in the ThinkPad E14 Gen 1 (20RA/20RB), plus a **pairing-only** tool: if your
reader already runs Lenovo's universal firmware `GF32xx_RTSEC_APP_10062` (likely, if the
laptop ever ran Windows with Windows Update), **no firmware flash is needed** — one command
replaces the Windows pairing key with the Linux one, and the driver works.

Tested 2026-10-08 on a 20RB002BBR, Fedora 44 KDE: enroll 40/40, verify 3/3, sudo and
lock screen by fingerprint, password fallback kept.

```
tools/probe_readonly.py   read firmware / bootloader / PSK state / OTP — writes nothing
rpm/build.sh              build the libfprint-goodixtls-55a4 RPM (replaces libfprint)
tools/run_pair_captured.sh  pair the reader with the Linux PSK (the only step that writes)
tools/enroll.sh           guided 40-press enrollment
tools/check-libfprint.sh  post-update sanity check
```

Based on [jith/goodix-55a4-fingerprint](https://github.com/jith/goodix-55a4-fingerprint)
(driver patches, Arch/CachyOS) and [goodix-fp-linux-dev](https://github.com/goodix-fp-linux-dev)
(protocol). Investigation notes with evidence: [NOTES.md](NOTES.md); what the write does and
why it is low-risk: [DOSSIER-PSK.md](DOSSIER-PSK.md).

Not covered: readers still on factory firmware `_10039` or community `_10041` (those need
the firmware flash described in jith's README), and dual boot (the reader holds one key).
