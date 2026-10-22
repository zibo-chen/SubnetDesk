"""Validate the x64 ELF snapshot loaded by Dart, including on Windows.

Flutter's app-aot-elf output is not loaded by the Windows PE loader. It must
export the four snapshot regions and must not require external ELF libraries.
This structural check does not replace engine identity or runtime validation.
"""
from pathlib import Path
import struct

SNAPSHOT_SYMBOLS = {"_kDartVmSnapshotData", "_kDartVmSnapshotInstructions",
                    "_kDartIsolateSnapshotData", "_kDartIsolateSnapshotInstructions"}


def inspect(path):
    data = Path(path).read_bytes()

    def region(start, size):
        if start < 0 or size < 0 or start + size > len(data):
            raise ValueError("truncated Dart AOT ELF")
        return data[start:start + size]

    def unpack(fmt, start):
        return struct.unpack(fmt, region(start, struct.calcsize(fmt)))

    if region(0, 7) != b"\x7fELF\x02\x01\x01":
        raise ValueError("Dart AOT must be little-endian ELF64")
    kind, machine, version, _, phoff, shoff, _, ehsize, phsize, phnum, shsize, shnum, _ = unpack(
        "<HHIQQQIHHHHHH", 16)
    if (kind, machine, version, ehsize, phsize, shsize) != (3, 62, 1, 64, 56, 64):
        raise ValueError("Dart AOT must be an x64 ELF shared snapshot")
    if not phnum or not shnum:
        raise ValueError("Dart AOT is missing program or section headers")
    executable = False
    for index in range(phnum):
        segment, flags, offset, _, _, size, _, _ = unpack("<IIQQQQQQ", phoff + index * phsize)
        region(offset, size)
        executable |= segment == 1 and bool(flags & 1)
        if segment == 2:
            if size % 16:
                raise ValueError("Invalid Dart AOT dynamic table")
            for entry in range(size // 16):
                tag, _ = unpack("<qQ", offset + entry * 16)
                if tag == 0:
                    break
                if tag == 1:
                    raise ValueError("Dart AOT must not depend on external ELF libraries")
    if not executable:
        raise ValueError("Dart AOT is missing executable snapshot instructions")
    sections = [unpack("<IIQQQQIIQQ", shoff + index * shsize) for index in range(shnum)]
    exports = set()
    for section in sections:
        if section[1] != 11:  # SHT_DYNSYM
            continue
        if section[9] != 24 or section[5] % 24 or section[6] >= len(sections):
            raise ValueError("Invalid Dart AOT symbol table")
        strings = sections[section[6]]
        if strings[1] != 3:
            raise ValueError("Invalid Dart AOT string table")
        names = region(strings[4], strings[5])
        region(section[4], section[5])
        for index in range(section[5] // 24):
            name, _, _, defined, _, _ = unpack("<IBBHQQ", section[4] + index * 24)
            if name >= len(names) or names.find(b"\0", name) < 0:
                raise ValueError("Invalid Dart AOT symbol name")
            symbol = names[name:names.find(b"\0", name)].decode("ascii")
            if symbol and not defined:
                raise ValueError("Unresolved external Dart AOT symbol: " + symbol)
            if symbol:
                exports.add(symbol)
    if not SNAPSHOT_SYMBOLS.issubset(exports):
        raise ValueError("Dart AOT is missing snapshot exports")
    return {"file": str(path), "format": "ELF64-Dart-AOT", "bits": 64,
            "machine": machine, "external_libraries": [], "exports": sorted(exports)}
