import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("package_portable", Path(__file__).with_name("package_portable.py"))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class PortablePackageTests(unittest.TestCase):
    def runtime_fixture(self, root):
        runtime = root / "runner"
        runtime.mkdir()
        (runtime / "SubnetDesk.exe").write_bytes(b"host")
        launcher = root / "SubnetDesk.exe"
        launcher.write_bytes(b"launcher")
        return runtime, launcher

    def test_output_inside_runtime_is_rejected_before_copying(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime, launcher = self.runtime_fixture(root)
            output = runtime / "portable"
            with self.assertRaisesRegex(ValueError, "outside"):
                packager.package(runtime, launcher, output)
            self.assertFalse(output.exists())

    def test_symlinked_output_inside_runtime_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime, launcher = self.runtime_fixture(root)
            alias = root / "runtime-alias"
            try:
                alias.symlink_to(runtime, target_is_directory=True)
            except OSError as error:
                self.skipTest(f"Cannot create a directory symlink: {error}")
            output = alias / "portable"
            with self.assertRaisesRegex(ValueError, "outside"):
                packager.package(runtime, launcher, output)
            self.assertFalse(output.exists())

    def test_existing_archive_is_preserved_without_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime, launcher = self.runtime_fixture(root)
            output = root / "portable"
            archive = root / "portable.zip"
            archive.write_bytes(b"previous release")
            with self.assertRaisesRegex(ValueError, "archive"):
                packager.package(runtime, launcher, output)
            self.assertEqual(archive.read_bytes(), b"previous release")
            self.assertFalse(output.exists())

    def test_external_launcher_does_not_exclude_host_with_the_same_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime, launcher = self.runtime_fixture(root)
            output = root / "portable"
            archive = packager.package(runtime, launcher, output)
            with zipfile.ZipFile(archive) as result:
                self.assertEqual(result.read("portable/SubnetDesk.exe"), b"launcher")
                self.assertEqual(result.read("portable/app/SubnetDesk.exe"), b"host")

    def test_zip_is_self_contained_without_service_and_does_not_overwrite_profiles(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime = root / "runner"
            runtime.mkdir()
            for name in ("rustdesk.exe", "SubnetDeskLauncher.exe", "service.exe", "flutter_windows.dll"):
                (runtime / name).write_bytes(b"fixture")
            (runtime / "data").mkdir()
            (runtime / "data/icudtl.dat").write_bytes(b"fixture")
            output = root / "SubnetDesk-1.3.0-Portable"
            archive = packager.package(runtime, runtime / "SubnetDeskLauncher.exe", output)
            self.assertEqual(archive.name, "SubnetDesk-1.3.0-Portable.zip")
            with zipfile.ZipFile(archive) as result:
                files = set(result.namelist())
                self.assertIn("SubnetDesk-1.3.0-Portable/SubnetDesk.exe", files)
                self.assertIn("SubnetDesk-1.3.0-Portable/app/rustdesk.exe", files)
                self.assertIn("SubnetDesk-1.3.0-Portable/app/data/icudtl.dat", files)
                self.assertIn("SubnetDesk-1.3.0-Portable/userdata/", files)
                self.assertNotIn("SubnetDesk-1.3.0-Portable/app/service.exe", files)
            (output / "userdata/identity.toml").write_text("existing identity")
            with self.assertRaises(ValueError):
                packager.package(runtime, runtime / "SubnetDeskLauncher.exe", output)
            self.assertEqual((output / "userdata/identity.toml").read_text(), "existing identity")


if __name__ == "__main__":
    unittest.main()
