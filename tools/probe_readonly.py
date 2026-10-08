#!/usr/bin/env python3
"""Read-only probe for the Goodix 27c6:55a4 fingerprint sensor.

Sends only the read commands audited in NOTES.md (2026-10-08):
  0x00 nop, 0xa8 firmware version, 0xf6 IAP version,
  0xe4 preset PSK read (PMK hash), 0xa6 read OTP.
Any other opcode raises before touching USB. No set_configuration, no reset,
no PSK/firmware write, no erase. Framing mirrors goodix-fp-dump goodix.py
(commit cc43bb3); the transport is reimplemented so protocol.py (SPI deps,
set_configuration) is not imported.

Usage: sudo .venv/bin/python tools/probe_readonly.py [--dry-run] [-o OUT.json]
fprintd must be stopped.
"""
import argparse
import datetime
import hashlib
import json
import os
import struct
import sys

ALLOWED_COMMANDS = {
    0x00: "nop",
    0xa8: "firmware_version",
    0xf6: "get_iap_version",
    0xe4: "preset_psk_read",
    0xa6: "read_otp",
}
COMMAND_ACK = 0xb0
FLAGS_MESSAGE_PROTOCOL = 0xa0

VID, PID = 0x27c6, 0x55a4
EXPECTED_FIRMWARE = "GF3208_RTSEC_APP_10039"
EXPECTED_IAP = "MILAN_RTSEC_IAP_10027"
PSK_HASH_FLAGS = 0xbb020007
# SHA-256 of the PMK derived from the all-zero PSK (goodix-fp-dump driver_55x4.py)
PMK_HASH_ZERO_PSK = bytes.fromhex(
    "81b8ff490612022a121a9449ee3aad2792f32b9f3141182cd01019945ee50361")


class NotAllowed(Exception):
    pass


def encode_message_pack(payload, flags=FLAGS_MESSAGE_PROTOCOL):
    head = struct.pack("<BH", flags, len(payload))
    return head + bytes([sum(head) & 0xff]) + payload


def decode_message_pack(data):
    length = struct.unpack("<H", data[1:3])[0]
    if sum(data[0:3]) & 0xff != data[3]:
        raise ValueError("bad pack checksum")
    return data[4:4 + length], data[0], length


def encode_message_protocol(payload, command, checksum=True):
    data = struct.pack("<BH", command, len(payload) + 1) + payload
    return data + bytes([(0xaa - sum(data)) & 0xff if checksum else 0x88])


def decode_message_protocol(data, checksum=True):
    length = struct.unpack("<H", data[1:3])[0]
    if checksum and data[2 + length] != (0xaa - sum(data[0:2 + length])) & 0xff:
        raise ValueError("bad protocol checksum")
    if not checksum and data[2 + length] != 0x88:
        raise ValueError("bad protocol trailer")
    return data[3:2 + length], data[0], length - 1


class Probe:

    def __init__(self, dry_run, log):
        self.dry_run = dry_run
        self.log = log  # list of {"dir", "hex"} entries, saved in the JSON
        self.dev = None
        if dry_run:
            return

        import usb.core
        import usb.util
        self.usb = usb
        dev = usb.core.find(idVendor=VID, idProduct=PID)
        if dev is None:
            raise SystemExit("27c6:55a4 not found")
        self.dev = dev
        cfg = dev.get_active_configuration()  # GET_CONFIGURATION only
        intf = cfg[(0, 0)]
        self.ep_out = usb.util.find_descriptor(
            intf, custom_match=lambda e: usb.util.endpoint_direction(
                e.bEndpointAddress) == usb.util.ENDPOINT_OUT).bEndpointAddress
        self.ep_in = usb.util.find_descriptor(
            intf, custom_match=lambda e: usb.util.endpoint_direction(
                e.bEndpointAddress) == usb.util.ENDPOINT_IN).bEndpointAddress
        if dev.is_kernel_driver_active(0):
            raise SystemExit("a kernel driver is bound to interface 0; refusing")
        usb.util.claim_interface(dev, 0)
        print(f"device bus {dev.bus} addr {dev.address}, "
              f"ep_out {self.ep_out:#x} ep_in {self.ep_in:#x}")

    def close(self):
        if self.dev is not None:
            self.usb.util.release_interface(self.dev, 0)
            self.usb.util.dispose_resources(self.dev)

    def _write(self, data):
        if data[0] != FLAGS_MESSAGE_PROTOCOL or data[4] not in ALLOWED_COMMANDS:
            raise NotAllowed(f"refusing to send {data[:8].hex()}")
        self.log.append({"dir": "out", "hex": data.hex()})
        if self.dry_run:
            print(f"  OUT {data.hex()}")
            return
        if len(data) % 0x40:
            data += b"\x00" * (0x40 - len(data) % 0x40)
        for i in range(0, len(data), 0x40):
            self.dev.write(self.ep_out, data[i:i + 0x40], 2000)

    def _read(self, timeout_ms=2000):
        data = self.dev.read(self.ep_in, 0x10000, timeout_ms).tobytes()
        self.log.append({"dir": "in", "hex": data.hex()})
        return data

    def drain(self):
        """Read and discard stale replies (goodix.py empty_buffer)."""
        if self.dry_run:
            return 0
        n = 0
        while True:
            try:
                self._read(100)
                n += 1
            except self.usb.core.USBTimeoutError:
                return n

    def command(self, cmd, payload, reply=True):
        if cmd not in ALLOWED_COMMANDS:
            raise NotAllowed(f"command {cmd:#x} not in whitelist")
        checksum = cmd != 0x00
        self._write(encode_message_pack(
            encode_message_protocol(payload, cmd, checksum)))
        if self.dry_run:
            return None
        if cmd == 0x00:
            try:
                self._read(100)
            except self.usb.core.USBTimeoutError:
                pass
            return None
        ack, flags, _ = decode_message_pack(self._read())
        if flags != FLAGS_MESSAGE_PROTOCOL:
            raise ValueError(f"unexpected pack flags {flags:#x}")
        ack_payload, ack_cmd, _ = decode_message_protocol(ack)
        if ack_cmd != COMMAND_ACK or ack_payload[0] != cmd or not ack_payload[1] & 1:
            raise ValueError(f"bad ack for {cmd:#x}: {ack.hex()}")
        if not reply:
            return None
        msg, flags, _ = decode_message_pack(self._read())
        payload, got, _ = decode_message_protocol(msg)
        if got != cmd:
            raise ValueError(f"reply for {got:#x}, expected {cmd:#x}")
        return payload


def decode_otp(otp):
    """Mirror jith patch 0010 on_read_otp (Wbdi.dll 0x64530 / 0x64370)."""
    out = {"length": len(otp)}
    if len(otp) < 0x20:
        out["error"] = "OTP shorter than 0x20 bytes"
        return out
    v, vc = otp[0x16], otp[0x17]
    out["byte_0x16"], out["byte_0x17"] = f"{v:#04x}", f"{vc:#04x}"
    out["calibration_valid"] = v != 0 and v + vc == 0xff
    if out["calibration_valid"]:
        tcode = ((v >> 4) + 1) << 4
        delta = ((((v & 0xF) + 2) * 100) << 8) // tcode // 3 >> 4
    else:
        tcode, delta = 0x80, 0x15  # driver defaults
    out["tcode"] = f"{tcode:#x}"
    out["fdt_delta"] = f"{delta:#x}"
    out["image_tcode_jith_default"] = f"{max(0x30, tcode * 3 // 5 // 0x10 * 0x10):#x}"
    b = otp[0x11]
    f0, f2, f4 = b & 3, (~b >> 2) & 3, (b >> 4) & 3
    offset = f0 if f0 in (f4, f2) else (f4 if f4 == f2 else 0)
    out["byte_0x11"] = f"{b:#04x}"
    out["fdt_offset"] = offset
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="print the bytes that would be sent; no USB access")
    ap.add_argument("-o", "--output")
    args = ap.parse_args()

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_path = args.output or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "dumps",
        f"probe-{stamp}{'-dryrun' if args.dry_run else ''}.json")

    log = []
    result = {"timestamp": stamp, "dry_run": args.dry_run,
              "commands_allowed": {f"{k:#04x}": v for k, v in ALLOWED_COMMANDS.items()},
              "steps": {}, "usb_log": log}
    probe = Probe(args.dry_run, log)
    steps = result["steps"]

    def step(name, fn):
        print(f"[{name}]")
        try:
            value = fn()
            steps[name] = {"ok": True, "value": value}
            print(f"  -> {value}")
            return value
        except NotAllowed:
            raise
        except Exception as error:  # stop at the first failure (CLAUDE.md rule 6)
            steps[name] = {"ok": False, "error": repr(error)}
            print(f"  !! {error!r} -- stopping, no retries")
            raise StopProbe from error

    class StopProbe(Exception):
        pass

    def as_str(payload):
        return None if payload is None else payload.split(b"\x00")[0].decode(errors="replace")

    try:
        step("drain_stale_replies", probe.drain)
        step("nop", lambda: probe.command(0x00, b"\x00\x00\x00\x00"))
        fw = step("firmware_version", lambda: as_str(probe.command(0xa8, b"\x00\x00")))
        if fw == EXPECTED_IAP:
            print("  device is in IAP bootloader mode")
            steps["iap_version"] = {"ok": True, "value": fw, "note": "reported by 0xa8 in IAP mode"}
        else:
            step("iap_version", lambda: as_str(probe.command(0xf6, struct.pack("<B", 25) + b"\x00")))

        def psk():
            p = probe.command(0xe4, struct.pack("<II", PSK_HASH_FLAGS, 0))
            if p is None:
                return None
            if p[0] != 0x00:
                return {"status": f"{p[0]:#04x}", "raw": p.hex()}
            flags, length = struct.unpack("<II", p[1:9])
            h = p[9:9 + length]
            return {"status": "0x00", "flags": f"{flags:#010x}",
                    "pmk_hash": h.hex(), "is_zero_psk": h == PMK_HASH_ZERO_PSK}
        step("psk_hash", psk)

        def otp():
            p = probe.command(0xa6, b"\x00\x00")
            if p is None:
                return None
            return {"raw": p.hex(), "sha256": hashlib.sha256(p).hexdigest(),
                    "decoded": decode_otp(p)}
        step("otp", otp)
    except StopProbe:
        result["stopped_early"] = True
    finally:
        probe.close()
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        with open(out_path, "w") as f:
            json.dump(result, f, indent=2)
        uid, gid = os.environ.get("SUDO_UID"), os.environ.get("SUDO_GID")
        if uid and gid:
            os.chown(out_path, int(uid), int(gid))
        print(f"saved {os.path.abspath(out_path)}")

    fw = steps.get("firmware_version", {}).get("value")
    iap = steps.get("iap_version", {}).get("value")
    if fw is not None:
        print(f"firmware: {fw} ({'as expected' if fw == EXPECTED_FIRMWARE else 'NOT ' + EXPECTED_FIRMWARE})")
    if iap is not None:
        print(f"iap:      {iap} ({'as expected' if iap == EXPECTED_IAP else 'NOT ' + EXPECTED_IAP})")
    return 1 if result.get("stopped_early") else 0


if __name__ == "__main__":
    sys.exit(main())
