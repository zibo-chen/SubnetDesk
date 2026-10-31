#!/usr/bin/env python3
"""Check that application, package, and CI release versions agree."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def extract(path, pattern):
    match = re.search(pattern, (ROOT / path).read_text(encoding="utf-8"), re.MULTILINE)
    if not match:
        raise ValueError(f"Missing release version in {path}")
    return match.group(1)


def main():
    version = extract("Cargo.toml", r'^version = "([^"]+)"$')
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("The release version must have three numeric components")
    checks = {
        "flutter/pubspec.yaml": r"^version: ([^+\s]+)\+\d+$",
        "libs/portable/Cargo.toml": r'^version = "([^"]+)"$',
        "flutter/android/app/build.gradle": r"flutterVersionName = '([^']+)'",
        "flutter/windows/runner/Runner.rc": r'^#define VERSION_AS_STRING "([^"]+)"$',
        "res/PKGBUILD": r"^pkgver=(.+)$",
        "res/win7/vcpkg.json": r'"version-string": "([^"]+)"',
        ".github/workflows/flutter-build.yml": r'^  VERSION: "([^"]+)"$',
        ".github/workflows/windows-validation.yml": r"^  VERSION: (\S+)$",
        ".github/workflows/windows-win7-flutter.yml": r"\$version -ne '([^']+)'",
    }
    for name in ["rpm", "rpm-suse", "rpm-flutter", "rpm-flutter-suse"]:
        checks[f"res/{name}.spec"] = r"^Version:\s+(\S+)$"
    for arch in ["x86_64", "aarch64"]:
        checks[f"appimage/AppImageBuilder-{arch}.yml"] = r"^    version: (\S+)$"
    for path, pattern in checks.items():
        actual = extract(path, pattern)
        if actual != version:
            raise ValueError(f"{path}: expected {version}, found {actual}")
    numeric = extract("flutter/windows/runner/Runner.rc", r"^#define VERSION_AS_NUMBER ([\d,]+)$")
    if numeric != version.replace(".", ",") + ",0":
        raise ValueError(f"Windows numeric version is inconsistent: {numeric}")
    for name in ["rustdesk", "rustdesk-portable-packer"]:
        locked = extract("Cargo.lock", rf'^name = "{name}"\nversion = "([^"]+)"$')
        if locked != version:
            raise ValueError(f"Cargo.lock: {name} is still at {locked}")
    print(f"Release versions agree: {version}")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(error, file=sys.stderr)
        sys.exit(1)
