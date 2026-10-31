import copy
import unittest

from check_release_assets import required_assets, validate


class ReleaseAssetsTests(unittest.TestCase):
    def setUp(self):
        self.release = {
            "tagName": "v2.0.0-rc.1",
            "isPrerelease": True,
            "assets": [{"name": name, "size": 123, "state": "uploaded"}
                       for name in required_assets("2.0.0")],
        }

    def test_accepts_complete_prerelease_and_stable_release(self):
        validate(self.release, "v2.0.0-rc.1")
        self.release.update(tagName="v2.0.0", isPrerelease=False)
        validate(self.release, "v2.0.0")

    def test_contract_covers_requested_downloads(self):
        names = required_assets("2.0.0")
        self.assertEqual(18, len(names))
        self.assertIn("subnetdesk-2.0.0-x86_64-portable.zip", names)
        self.assertIn("subnetdesk-2.0.0-x86_64-setup.exe", names)
        self.assertIn("subnetdesk-2.0.0-0.aarch64-suse.rpm", names)
        self.assertIn("subnetdesk-2.0.0-universal-signed.apk", names)
        for arch in ("x86_64", "aarch64"):
            for extension in ("deb", "AppImage", "flatpak", "dmg"):
                self.assertIn(f"subnetdesk-2.0.0-{arch}.{extension}", names)
            self.assertIn(f"subnetdesk-2.0.0-{arch}-signed.apk", names)

    def test_requires_every_platform_and_architecture(self):
        for asset in self.release["assets"]:
            with self.subTest(asset=asset["name"]):
                release = copy.deepcopy(self.release)
                release["assets"].remove(asset)
                with self.assertRaisesRegex(ValueError, "Missing release downloads"):
                    validate(release, "v2.0.0-rc.1")

    def test_modern_windows_packages_do_not_replace_win7_defaults(self):
        self.release["assets"] = [asset for asset in self.release["assets"]
                                  if not asset["name"].endswith("-portable.zip")]
        self.release["assets"].append({
            "name": "subnetdesk-2.0.0-x86_64-win10-portable.zip",
            "size": 123, "state": "uploaded",
        })
        with self.assertRaisesRegex(ValueError, "x86_64-portable.zip"):
            validate(self.release, "v2.0.0-rc.1")

    def test_rejects_empty_or_unfinished_uploads(self):
        for change in ({"size": 0}, {"state": "new"}):
            release = copy.deepcopy(self.release)
            release["assets"][0].update(change)
            with self.assertRaisesRegex(ValueError, "Incomplete release downloads"):
                validate(release, "v2.0.0-rc.1")

    def test_rejects_wrong_release_and_prerelease_flags(self):
        with self.assertRaisesRegex(ValueError, "published tag"):
            validate(self.release, "v2.0.0-rc.2")
        self.release["isPrerelease"] = False
        with self.assertRaisesRegex(ValueError, "prerelease flag"):
            validate(self.release, "v2.0.0-rc.1")


if __name__ == "__main__":
    unittest.main()
