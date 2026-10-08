"""Regression tests for the Win7 artifact boundary and PE import reader."""
import struct
import tempfile
from pathlib import Path
import unittest

import audit_win7_pe
import build_win7


def pe_fixture(bits, symbol="WaitOnAddress", delay=False):
    data = bytearray(4096)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 128)
    data[128:132] = b"PE\0\0"
    optional_size = 240 if bits == 64 else 224
    struct.pack_into("<HH", data, 132, 0x8664 if bits == 64 else 0x14C, 1)
    struct.pack_into("<H", data, 148, optional_size)
    opt = 152
    struct.pack_into("<H", data, opt, 0x20B if bits == 64 else 0x10B)
    struct.pack_into("<HH", data, opt + 48, 6, 1)
    directory = opt + (112 if bits == 64 else 96)
    struct.pack_into("<I", data, directory - 4, 16)
    struct.pack_into("<IIII", data, opt + optional_size + 8, 2048, 0x1000, 2048, 512)
    if delay:
        struct.pack_into("<II", data, directory + 13 * 8, 0x1000, 64)
        struct.pack_into("<IIIIIIII", data, 512, 1, 0x1100, 0, 0x1200, 0x1200, 0, 0, 0)
    else:
        struct.pack_into("<II", data, directory + 8, 0x1000, 40)
        struct.pack_into("<IIIII", data, 512, 0x1200, 0, 0, 0x1100, 0x1200)
    data[768:781] = b"kernel32.dll\0"
    struct.pack_into("<Q" if bits == 64 else "<I", data, 1024, 0x1300)
    name = symbol.encode("ascii") + b"\0"
    data[1282:1282 + len(name)] = name
    return data


class Win7BuildTests(unittest.TestCase):
    def test_every_launcher_and_service_uses_dedicated_std(self):
        for arch, target in build_win7.TARGETS.items():
            command = build_win7.cargo_command(arch, "-p", "rustdesk-portable-packer")
            self.assertIn(target, command)
            self.assertIn("build-std=std,panic_abort", command)
            self.assertIn("--locked", command)
            self.assertNotIn("flutter", command)

    def report(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.exe"
            path.write_bytes(data)
            return audit_win7_pe.inspect(path)

    def test_detects_unsupported_normal_and_delay_imports_in_both_architectures(self):
        for bits in (32, 64):
            for delay in (False, True):
                with self.subTest(bits=bits, delay=delay):
                    report = self.report(pe_fixture(bits, delay=delay))
                    self.assertIn("WaitOnAddress", report["imports"]["kernel32.dll"])
                    self.assertTrue(audit_win7_pe.violations(report))

    def test_allows_win7_api_and_rejects_architecture_mismatch(self):
        report = self.report(pe_fixture(64, "GetCurrentProcessId"))
        self.assertEqual([], audit_win7_pe.violations(report, "x64"))
        self.assertTrue(audit_win7_pe.violations(report, "x86"))

    def test_rejects_newer_subsystem(self):
        data = pe_fixture(64, "GetCurrentProcessId")
        struct.pack_into("<HH", data, 152 + 48, 6, 2)
        self.assertTrue(audit_win7_pe.violations(self.report(data)))

    def test_corrupt_pe_fails_closed(self):
        for data in (b"", b"MZ", pe_fixture(64)[:200]):
            with self.assertRaises(audit_win7_pe.PEError):
                self.report(data)

    def test_import_libraries_use_locked_versions_and_matching_architecture(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = root / "Cargo.lock"
            lock.write_text('[[package]]\nname = "windows_x86_64_msvc"\nversion = "0.42.2"\n'
                            '[[package]]\nname = "windows_x86_64_msvc"\nversion = "0.48.5"\n')
            for crate, library in (("windows_x86_64_msvc-0.42.2", "windows.lib"),
                                   ("windows_x86_64_msvc-0.48.5", "windows.0.48.5.lib"),
                                   ("windows_i686_msvc-0.42.2", "windows.lib"),
                                   ("windows_x86_64_msvc-99.0.0", "windows.lib")):
                path = root / "registry" / "src" / "registry" / crate / "lib"
                path.mkdir(parents=True)
                (path / library).write_bytes(b"fixture")
            paths = build_win7.win7_import_library_paths("x64", root, lock)
            self.assertEqual(["windows_x86_64_msvc-0.48.5", "windows_x86_64_msvc-0.42.2"],
                             [path.parent.name for path in paths])
            with self.assertRaises(RuntimeError):
                build_win7.win7_import_library_paths("x86", root, lock)

    def test_sodium_library_uses_target_architecture_and_locked_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = root / "Cargo.lock"
            lock.write_text('[[package]]\nname = "libsodium-sys"\nversion = "0.2.7"\n')
            for version, arch in (("0.2.7", "x64"), ("0.2.7", "Win32"), ("99.0.0", "Win32")):
                path = root / "registry/src/registry" / f"libsodium-sys-{version}/msvc/{arch}/Release/v142"
                path.mkdir(parents=True)
                (path / "libsodium.lib").write_bytes(b"fixture")
            x86 = build_win7.win7_sodium_library_path("x86", root, lock)
            self.assertEqual("Win32", x86.parent.parent.name)
            self.assertIn("libsodium-sys-0.2.7", str(x86))
            self.assertEqual("x64", build_win7.win7_sodium_library_path("x64", root, lock).parent.parent.name)
            (x86 / "libsodium.lib").unlink()
            with self.assertRaises(RuntimeError):
                build_win7.win7_sodium_library_path("x86", root, lock)

    def test_missing_legacy_import_libraries_fail_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = root / "Cargo.lock"
            lock.write_text('[[package]]\nname = "windows_i686_msvc"\nversion = "0.48.5"\n')
            with self.assertRaises(RuntimeError):
                build_win7.win7_import_library_paths("x86", root, lock)


if __name__ == "__main__":
    unittest.main()
