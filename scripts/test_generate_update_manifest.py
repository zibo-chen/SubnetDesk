#!/usr/bin/env python3

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("generate_update_manifest.py")


class GenerateUpdateManifestTests(unittest.TestCase):
    def test_generates_all_desktop_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for arch in ("x86_64", "aarch64"):
                for extension in ("msi", "exe", "dmg"):
                    (root / f"subnetdesk-1.3.0-{arch}.{extension}").write_bytes(
                        f"{arch}-{extension}".encode()
                    )
            output = root / "update-stable.json"
            subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--asset-dir",
                    str(root),
                    "--repository",
                    "zibo-chen/SubnetDesk",
                    "--tag",
                    "v1.3.0",
                    "--version",
                    "1.3.0",
                    "--sequence",
                    "42",
                    "--output",
                    str(output),
                ],
                check=True,
            )
            manifest = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(manifest["schema"], 1)
            self.assertEqual(manifest["sequence"], 42)
            self.assertEqual(len(manifest["artifacts"]), 6)
            artifact = manifest["artifacts"]["windows-x86_64-msi"]
            expected = hashlib.sha256(b"x86_64-msi").hexdigest()
            self.assertEqual(artifact["sha256"], expected)
            self.assertTrue(artifact["url"].endswith("/subnetdesk-1.3.0-x86_64.msi"))

    def test_missing_asset_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--asset-dir",
                    directory,
                    "--repository",
                    "zibo-chen/SubnetDesk",
                    "--tag",
                    "v1.3.0",
                    "--version",
                    "1.3.0",
                    "--sequence",
                    "42",
                    "--output",
                    str(Path(directory) / "update-stable.json"),
                ],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("required update asset is missing", result.stderr)


if __name__ == "__main__":
    unittest.main()
