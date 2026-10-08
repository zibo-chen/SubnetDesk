#!/usr/bin/env python3
"""Check PE architecture, subsystem version and known post-Win7 static imports.

This is a regression gate, not a replacement for running on Windows 7. Dynamic
GetProcAddress calls and APIs outside the deny list require runtime testing.
No external Python packages are needed.
"""
import argparse
import json
from pathlib import Path
import struct

POST_WIN7_DLLS = {"shcore.dll", "bcryptprimitives.dll"}
POST_WIN7_APIS = {
    "waitonaddress", "wakebyaddresssingle", "wakebyaddressall",
    "getsystemtimepreciseasfiletime", "getoverlappedresultex", "createfile2",
    "setthreadinformation", "getthreadinformation", "setprocessinformation",
    "getprocessinformation", "getprocessmitigationpolicy", "setprocessmitigationpolicy",
    "getdpiforwindow", "getdpiforsystem", "adjustwindowrectexfordpi",
    "setprocessdpiawareness", "setprocessdpiawarenesscontext",
    "setthreaddpiawarenesscontext", "getthreaddpiawarenesscontext",
    "enable_non_client_dpi_scaling", "enablenonclientdpiscaling",
    "getautorotationstate", "discardvirtualmemory", "prefetchvirtualmemory",
    "offer_virtual_memory", "offervirtualmemory", "reclaimvirtualmemory",
    "processprng", "rooriginateerror", "rooriginateerrorex", "rogetactivationfactory",
    "roinitialize", "rouninitialize", "windowscreatestring", "windowsdeletestring",
    "windowsgetstringrawbuffer", "getpointerinfo", "getpointertype",
}


class PEError(ValueError):
    pass


def inspect(path):
    data = Path(path).read_bytes()

    def unpack(fmt, offset):
        if offset < 0 or offset + struct.calcsize(fmt) > len(data):
            raise PEError("truncated PE")
        return struct.unpack_from(fmt, data, offset)

    if data[:2] != b"MZ":
        raise PEError("missing DOS header")
    pe, = unpack("<I", 0x3C)
    if data[pe:pe + 4] != b"PE\0\0":
        raise PEError("missing PE signature")
    machine, count = unpack("<HH", pe + 4)
    optional_size, = unpack("<H", pe + 20)
    optional = pe + 24
    magic, = unpack("<H", optional)
    if magic not in (0x10B, 0x20B):
        raise PEError("unsupported optional header")
    bits = 64 if magic == 0x20B else 32
    image_base, = unpack("<Q" if bits == 64 else "<I", optional + (24 if bits == 64 else 28))
    subsystem_version = unpack("<HH", optional + 48)
    sections = []
    for i in range(count):
        section = optional + optional_size + i * 40
        size, rva, raw_size, raw = unpack("<IIII", section + 8)
        sections.append((rva, max(size, raw_size), raw, raw_size))

    def offset(rva):
        for base, size, raw, raw_size in sections:
            if base <= rva < base + size and rva - base < raw_size:
                return raw + rva - base
        raise PEError(f"unmapped RVA {rva:#x}")

    def string(rva):
        start = offset(rva)
        end = data.find(b"\0", start, min(start + 4096, len(data)))
        if end < 0:
            raise PEError("unterminated import name")
        return data[start:end].decode("ascii")

    directory = optional + (112 if bits == 64 else 96)
    directories, = unpack("<I", directory - 4)
    imports = {}
    for index, descriptor_size in ((1, 20), (13, 32)):
        if index >= directories:
            continue
        table_rva, table_size = unpack("<II", directory + index * 8)
        if not table_rva:
            continue
        table = offset(table_rva)
        for i in range(table_size // descriptor_size):
            words = unpack("<" + "I" * (descriptor_size // 4), table + i * descriptor_size)
            if not any(words):
                break
            if index == 1:
                thunk, name = words[0] or words[4], words[3]
            else:
                if not words[0] & 1:
                    # PE32 delay descriptors can use absolute addresses.
                    words = tuple(x - image_base if x >= image_base else x for x in words)
                name, thunk = words[1], words[4] or words[3]
            symbols = imports.setdefault(string(name).lower(), [])
            position = offset(thunk)
            while True:
                value, = unpack("<Q" if bits == 64 else "<I", position)
                if not value:
                    break
                symbols.append(f"ordinal:{value & 0xFFFF}" if value & (1 << (bits - 1)) else string(value + 2))
                position += bits // 8
    return {"file": str(path), "machine": machine, "bits": bits,
            "subsystem_version": subsystem_version, "imports": imports}


def violations(report, arch=None):
    errors = []
    if arch and report["machine"] != {"x86": 0x14C, "x64": 0x8664}[arch]:
        errors.append("wrong PE architecture")
    if tuple(report["subsystem_version"]) > (6, 1):
        errors.append("subsystem requires Windows newer than 7")
    for dll, symbols in report["imports"].items():
        if dll in POST_WIN7_DLLS or "winrt" in dll or dll.startswith("ext-ms-"):
            errors.append(f"post-Win7 DLL: {dll}")
        for name in symbols:
            if name.lower() in POST_WIN7_APIS:
                errors.append(f"post-Win7 import: {dll}!{name}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path)
    parser.add_argument("--arch", choices=("x86", "x64"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    reports = []
    for path in args.files:
        try:
            report = inspect(path)
            report["errors"] = violations(report, args.arch)
        except (OSError, ValueError, struct.error) as error:
            report = {"file": str(path), "errors": [str(error)]}
        reports.append(report)
        print(f"{path}: " + ("; ".join(report["errors"]) or "static checks passed"))
    if args.report:
        args.report.write_text(json.dumps(reports, indent=2), encoding="utf-8")
    return int(any(report["errors"] for report in reports))


if __name__ == "__main__":
    raise SystemExit(main())
