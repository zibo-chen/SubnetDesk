import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).with_name("package_unsigned_ios.sh")


@unittest.skipUnless(sys.platform == "darwin", "Packaging uses macOS ditto and codesign")
class UnsignedIosPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="subnetdesk ios ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "Runner.app"
        self.app.mkdir()
        self.info = {
            "CFBundleIdentifier": "com.zibochen.subnetdesk",
            "CFBundleExecutable": "Runner",
            "CFBundlePackageType": "APPL",
            "DTPlatformName": "iphoneos",
        }
        self.write_info()
        shutil.copy("/bin/echo", self.app / "Runner")
        self.output = self.root / "release assets" / "test-unsigned.ipa"

    def write_info(self):
        with (self.app / "Info.plist").open("wb") as target:
            plistlib.dump(self.info, target)

    def package(self, check=True):
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.app), str(self.output)],
            capture_output=True, text=True, check=check,
        )

    def test_preserves_bundle_layout_permissions_and_links_without_signatures(self):
        frameworks = self.app / "Frameworks"
        frameworks.mkdir()
        library = frameworks / "helper.dylib"
        shutil.copy("/bin/echo", library)
        subprocess.run(["codesign", "--force", "--sign", "-", str(library)], check=True,
                       capture_output=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(self.app)], check=True,
                       capture_output=True)
        # A profile and resource link exercise cleanup and ditto's archive semantics.
        (self.app / "embedded.mobileprovision").write_text("test profile")
        (self.app / "resource with spaces").write_text("resource")
        (self.app / "resource-link").symlink_to("resource with spaces")
        self.package()
        with zipfile.ZipFile(self.output) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(b"resource", archive.read("Payload/Runner.app/resource with spaces"))
            executable = archive.getinfo("Payload/Runner.app/Runner")
            self.assertTrue(executable.external_attr >> 16 & stat.S_IXUSR)
            link = archive.getinfo("Payload/Runner.app/resource-link")
            self.assertTrue(stat.S_ISLNK(link.external_attr >> 16))
            self.assertEqual(b"resource with spaces", archive.read(link))
            self.assertFalse(any("_CodeSignature" in name or "embedded.mobileprovision" in name
                                 for name in archive.namelist()))
        extracted = self.root / "extracted"
        subprocess.run(["ditto", "-x", "-k", str(self.output), str(extracted)], check=True)
        for relative in ("Runner", "Frameworks/helper.dylib"):
            signed = subprocess.run(
                ["codesign", "-d", str(extracted / "Payload/Runner.app" / relative)],
                capture_output=True, text=True,
            )
            self.assertNotEqual(0, signed.returncode)
            self.assertIn("not signed", signed.stderr)
        self.assertTrue((self.app / "embedded.mobileprovision").exists())
        subprocess.run(["codesign", "-d", str(library)], check=True, capture_output=True)

    def test_rejects_simulator_build_without_overwriting_output(self):
        self.output.parent.mkdir()
        self.output.write_bytes(b"existing release")
        self.info["DTPlatformName"] = "iphonesimulator"
        self.write_info()
        result = self.package(check=False)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("device build is required", result.stderr)
        self.assertEqual(b"existing release", self.output.read_bytes())

    def test_rejects_missing_app_executable(self):
        os.unlink(self.app / "Runner")
        result = self.package(check=False)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("executable is missing", result.stderr)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
