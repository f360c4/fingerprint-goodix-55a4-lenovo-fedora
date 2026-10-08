#!/usr/bin/env python3
"""Pair the Goodix 27c6:55a4 sensor with the community Linux PSK (all-zero).

THIS TOOL WRITES TO THE SENSOR: one command, 0xe0 preset_psk_write, with the
goodix-fp-dump white-box PSK (flags 0xbb010003), while the application
firmware is running. No erase, no IAP/bootloader, no firmware write, no reset.
Precedent: jith/goodix-55a4-fingerprint#1 (55a4, fw 10052) and
TheWeirdDev/libfprint#3 (55b4, fw 10056), both Windows-paired sensors.

Guards:
  * refuses unless firmware matches GF32xx_RTSEC_APP_10062 and the bootloader
    is MILAN_RTSEC_IAP_10027 (the only combination with a tested precedent
    for this reader's driver);
  * exits without writing when the sensor already has the Linux PSK;
  * needs --i-typed-flash-autorizado AND an interactive confirmation code;
  * sends the write exactly once; on any failure it stops, saves the log and
    does not retry (re-reading the hash is the only follow-up).
Transport and read commands come from probe_readonly.py (same whitelist plus
0xe0). Usage: sudo .venv/bin/python tools/pair_psk.py [--dry-run] [-o OUT.json]
"""
import argparse
import datetime
import json
import os
import random
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_readonly as ro  # noqa: E402

COMMAND_PRESET_PSK_WRITE = 0xe0
ALLOWED = {**ro.ALLOWED_COMMANDS, COMMAND_PRESET_PSK_WRITE: "preset_psk_write"}

FIRMWARE_OK = re.compile(r"GF32[0-9]{2}_RTSEC_APP_10062")
IAP_OK = "MILAN_RTSEC_IAP_10027"
PSK_WRITE_FLAGS = 0xbb010003
# goodix-fp-dump driver_55x4.py / driver_5503.py PSK_WHITE_BOX: the all-zero
# PSK wrapped in Goodix's white-box format (96 bytes).
PSK_WHITE_BOX = bytes.fromhex(
    "ec35ae3abb45ed3f12c4751f1e5c2cc05b3c5452e9104d9f2a3118644f37a04b"
    "6fd66b1d97cf80f1345f76c84f03ff30bb51bf308f2a9875c41e6592cd2a2f9e"
    "60809b17b5316037b69bb2fa5d4c8ac31edb3394046ec06bbdacc57da6a756c5")
assert len(PSK_WHITE_BOX) == 96


class Pairer(ro.Probe):

    def _write(self, data):
        if data[0] != ro.FLAGS_MESSAGE_PROTOCOL or data[4] not in ALLOWED:
            raise ro.NotAllowed(f"refusing to send {data[:8].hex()}")
        self.log.append({"dir": "out", "hex": data.hex()})
        if self.dry_run:
            print(f"  OUT {data.hex()}")
            return
        if len(data) % 0x40:
            data += b"\x00" * (0x40 - len(data) % 0x40)
        for i in range(0, len(data), 0x40):
            self.dev.write(self.ep_out, data[i:i + 0x40], 2000)

    def command(self, cmd, payload, reply=True):
        if cmd not in ALLOWED:
            raise ro.NotAllowed(f"command {cmd:#x} not in whitelist")
        if cmd == COMMAND_PRESET_PSK_WRITE:
            # same framing as the read commands; bypass the parent's whitelist
            self._write(ro.encode_message_pack(ro.encode_message_protocol(payload, cmd)))
            if self.dry_run:
                return None
            ack, flags, _ = ro.decode_message_pack(self._read(5000))
            ack_payload, ack_cmd, _ = ro.decode_message_protocol(ack)
            if ack_cmd != ro.COMMAND_ACK or ack_payload[0] != cmd or not ack_payload[1] & 1:
                raise ValueError(f"bad ack for {cmd:#x}: {ack.hex()}")
            msg, _, _ = ro.decode_message_pack(self._read(5000))
            out, got, _ = ro.decode_message_protocol(msg)
            if got != cmd:
                raise ValueError(f"reply for {got:#x}, expected {cmd:#x}")
            return out
        return super().command(cmd, payload, reply)


def read_psk_hash(p):
    r = p.command(0xe4, struct.pack("<II", ro.PSK_HASH_FLAGS, 0))
    if r is None:
        return None
    if r[0] != 0x00:
        return {"status": f"{r[0]:#04x}", "raw": r.hex()}
    flags, length = struct.unpack("<II", r[1:9])
    h = r[9:9 + length]
    return {"status": "0x00", "flags": f"{flags:#010x}", "pmk_hash": h.hex(),
            "is_zero_psk": h == ro.PMK_HASH_ZERO_PSK}


def as_str(payload):
    return None if payload is None else payload.split(b"\x00")[0].decode(errors="replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="no USB access; print the frames")
    ap.add_argument("--i-typed-flash-autorizado", action="store_true",
                    help="required for the real write (the user typed FLASH AUTORIZADO)")
    ap.add_argument("-o", "--output")
    args = ap.parse_args()

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_path = args.output or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "dumps",
        f"pair-{stamp}{'-dryrun' if args.dry_run else ''}.json")
    write_payload = struct.pack("<II", PSK_WRITE_FLAGS, len(PSK_WHITE_BOX)) + PSK_WHITE_BOX

    log = []
    result = {"timestamp": stamp, "dry_run": args.dry_run, "steps": {}, "usb_log": log,
              "write_payload_hex": write_payload.hex(), "wrote": False}
    steps = result["steps"]
    p = Pairer(args.dry_run, log)
    rc = 1
    try:
        p.drain()
        p.command(0x00, b"\x00\x00\x00\x00")
        fw = as_str(p.command(0xa8, b"\x00\x00"))
        steps["firmware"] = fw
        print(f"firmware: {fw}")
        if not args.dry_run and (fw is None or not FIRMWARE_OK.fullmatch(fw)):
            print("ABORT: firmware is not GF32xx_RTSEC_APP_10062; no tested precedent, not writing")
            return 2
        if fw == IAP_OK:
            print("ABORT: device is in bootloader mode; not writing")
            return 2
        iap = as_str(p.command(0xf6, struct.pack("<B", 25) + b"\x00"))
        steps["iap"] = iap
        print(f"iap:      {iap}")
        if not args.dry_run and iap != IAP_OK:
            print("ABORT: unexpected bootloader; not writing")
            return 2
        before = read_psk_hash(p)
        steps["psk_before"] = before
        print(f"psk before: {before}")
        if before is not None and before.get("is_zero_psk"):
            print("already paired with the Linux PSK; nothing to do")
            return 0

        print()
        print("⚠️  ESTE PASSO ESCREVE NO SENSOR")
        print("  comando : 0xe0 preset_psk_write")
        print(f"  flags   : {PSK_WRITE_FLAGS:#010x}")
        print(f"  payload : {len(write_payload)} bytes = flags(4) + len(4) + white-box PSK(96)")
        print(f"            {write_payload.hex()}")
        print("  efeito  : a PSK do Windows deste sensor é substituída pela PSK Linux (toda-zero).")
        print("            Firmware e bootloader NÃO são tocados.")
        print()
        if args.dry_run:
            print("[dry-run] frame que seria enviado:")
            p.command(COMMAND_PRESET_PSK_WRITE, write_payload)
            rc = 0
            return 0
        if not args.i_typed_flash_autorizado:
            print("ABORT: --i-typed-flash-autorizado missing; nothing written")
            return 3
        code = f"{random.randint(1000, 9999)}"
        if input(f"Digite {code} para gravar a PSK (qualquer outra coisa aborta): ").strip() != code:
            print("ABORT: nothing written")
            return 3

        reply = p.command(COMMAND_PRESET_PSK_WRITE, write_payload)
        result["wrote"] = True
        steps["write_reply"] = reply.hex()
        ok = len(reply) >= 1 and reply[0] == 0x00
        print(f"write reply: {reply.hex()} -> {'OK' if ok else 'FAILED (status != 0)'}")
        after = read_psk_hash(p)
        steps["psk_after"] = after
        print(f"psk after:  {after}")
        if ok and after and after.get("is_zero_psk"):
            print("SUCCESS: sensor now has the Linux PSK")
            rc = 0
        else:
            print("FAILED: hash does not match the Linux PSK. Not retrying; see the log.")
            rc = 4
        return rc
    except ro.NotAllowed:
        raise
    except Exception as error:
        steps["error"] = repr(error)
        print(f"!! {error!r} -- stopping, no retries")
        return 5
    finally:
        p.close()
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        with open(out_path, "w") as f:
            json.dump(result, f, indent=2)
        uid, gid = os.environ.get("SUDO_UID"), os.environ.get("SUDO_GID")
        if uid and gid:
            os.chown(out_path, int(uid), int(gid))
        print(f"saved {os.path.abspath(out_path)}")


if __name__ == "__main__":
    sys.exit(main())
