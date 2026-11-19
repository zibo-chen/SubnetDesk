"""Check installer boundaries that protect existing user profiles."""
import json
import hashlib
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

import package_win7_installer as packager
import windows_display_driver
from test_win7_build import pe_fixture


class Win7InstallerTests(unittest.TestCase):
    def setUp(self):
        self.driver_payload = {
            name: bytes(pe_fixture(64, "WaitOnAddress")) if name.endswith(".dll") else name.encode()
            for name in windows_display_driver.FILES_SHA256
        }
        patch = mock.patch.dict(windows_display_driver.FILES_SHA256, {
            name: hashlib.sha256(data).hexdigest() for name, data in self.driver_payload.items()
        }, clear=True)
        patch.start()
        self.addCleanup(patch.stop)

    def fixture(self, root):
        package = root / "portable"
        for name in ("SubnetDesk.exe", "app/SubnetDesk.exe", "app/flutter_windows.dll",
                     "app/librustdesk.dll"):
            path = package / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(pe_fixture(64, "GetCurrentProcessId"))
        (package / "app/data").mkdir()
        (package / "app/data/app.so").write_bytes(b"snapshot")
        (package / "app/build-provenance.json").write_text(json.dumps({
            "rust_target": "x86_64-win7-windows-msvc", "sciter": False}))
        for name, data in self.driver_payload.items():
            path = package / "app/usbmmidd_v2" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        (package / "userdata").mkdir()
        (package / "userdata/identity.toml").write_text("existing identity")
        return package

    @unittest.skipUnless(shutil.which("makensis"), "NSIS compiler is not installed")
    def test_compiles_installer_with_real_include_files(self):
        with tempfile.TemporaryDirectory(prefix="subnetdesk installer ") as temporary:
            root = Path(temporary)
            package = self.fixture(root)
            installer = packager.package_installer(package, root / "setup.exe", "2.0.0")
            self.assertGreater(installer.stat().st_size, 0)
            metadata = json.loads(installer.with_suffix(".json").read_text())
            self.assertFalse(metadata["userdata_included"])
            self.assertTrue(metadata["uninstall_preserves_userdata"])
            self.assertEqual("existing identity", (package / "userdata/identity.toml").read_text())

    def test_profile_is_never_packaged_or_deleted(self):
        with tempfile.TemporaryDirectory() as temporary:
            package = self.fixture(Path(temporary))
            files, _ = packager.payload_files(package)
            install, uninstall = packager.file_commands(package, files)
            self.assertNotIn("userdata", install + uninstall)
            self.assertNotIn("/r", uninstall.lower())
            self.assertIn('Delete "$INSTDIR\\app\\data\\app.so"', uninstall)
            self.assertLess(uninstall.index('RMDir "$INSTDIR\\app\\data"'),
                            uninstall.index('RMDir "$INSTDIR\\app"'))
            self.assertEqual("existing identity", (package / "userdata/identity.toml").read_text())

    def test_existing_output_and_output_inside_package_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = self.fixture(root)
            output = root / "setup.exe"
            output.write_bytes(b"previous installer")
            with self.assertRaisesRegex(ValueError, "never overwritten"):
                packager.package_installer(package, output, "1.3.0")
            self.assertEqual(b"previous installer", output.read_bytes())
            with self.assertRaisesRegex(ValueError, "outside"):
                packager.package_installer(package, package / "setup.exe", "1.3.0")

    def test_rejects_incompatible_payload_and_unexpected_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            package = self.fixture(Path(temporary))
            dll = package / "app/flutter_windows.dll"
            dll.write_bytes(pe_fixture(64, "WaitOnAddress"))
            with self.assertRaisesRegex(ValueError, "post-Win7"):
                packager.payload_files(package)
            dll.write_bytes(pe_fixture(32, "GetCurrentProcessId"))
            with self.assertRaisesRegex(ValueError, "wrong PE architecture"):
                packager.payload_files(package)
            dll.write_bytes(pe_fixture(64, "GetCurrentProcessId"))
            (package / "identity.toml").write_text("must not ship")
            with self.assertRaisesRegex(ValueError, "outside the runtime"):
                packager.payload_files(package)

    def test_nsis_paths_escape_literal_dollars_and_quotes(self):
        self.assertEqual('price$$1$\\"', packager.nsis_literal('price$1"'))

    def test_optional_driver_ships_but_other_incompatible_dlls_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            package = self.fixture(Path(temporary))
            files, _ = packager.payload_files(package)
            for name in self.driver_payload:
                self.assertIn(Path("app/usbmmidd_v2") / name, files)
            install, _ = packager.file_commands(package, files)
            self.assertIn("usbmmIdd.inf", install)
            self.assertIn("usbmmidd.cat", install)
            extra = package / "app/usbmmidd_v2/x64/unexpected.dll"
            extra.write_bytes(pe_fixture(64, "WaitOnAddress"))
            with self.assertRaisesRegex(ValueError, "post-Win7"):
                packager.payload_files(package)

    def test_missing_or_corrupt_driver_blocks_installer_packaging(self):
        with tempfile.TemporaryDirectory() as temporary:
            package = self.fixture(Path(temporary))
            inf = package / "app/usbmmidd_v2/usbmmIdd.inf"
            inf.unlink()
            with self.assertRaisesRegex(ValueError, "Missing virtual display driver"):
                packager.payload_files(package)
            inf.write_bytes(self.driver_payload["usbmmIdd.inf"])
            (package / "app/usbmmidd_v2/x64/usbmmIdd.dll").write_bytes(b"wrong driver")
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                packager.payload_files(package)


if __name__ == "__main__":
    unittest.main()
