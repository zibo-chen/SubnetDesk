#!/usr/bin/env python3
"""Require a complete cross-platform release before reporting publication success."""

import argparse
import json
from pathlib import Path
import re


def required_assets(version):
    prefix = f"subnetdesk-{version}"
    names = {
        f"{prefix}-x86_64-portable.zip",
        f"{prefix}-x86_64-setup.exe",
        f"{prefix}-universal-signed.apk",
    }
    for arch in ("x86_64", "aarch64"):
        for extension in ("deb", "AppImage", "flatpak", "dmg"):
            names.add(f"{prefix}-{arch}.{extension}")
        names.add(f"{prefix}-{arch}-signed.apk")
        names.update({f"{prefix}-0.{arch}.rpm", f"{prefix}-0.{arch}-suse.rpm"})
    names.add(f"{prefix}-armv7-signed.apk")
    return names


def validate(release, tag):
    match = re.fullmatch(r"v?(\d+\.\d+\.\d+)(?:-[0-9A-Za-z.-]+)?", tag)
    if match is None:
        raise ValueError(f"Invalid release tag: {tag}")
    if release.get("tagName") != tag:
        raise ValueError("The published tag does not match the requested release")
    if release.get("isPrerelease") != ("-" in tag):
        raise ValueError("The release prerelease flag does not match its tag")
    assets = {asset["name"]: asset for asset in release.get("assets", [])}
    required = required_assets(match.group(1))
    missing = sorted(required - assets.keys())
    if missing:
        raise ValueError("Missing release downloads: " + ", ".join(missing))
    incomplete = sorted(name for name in required
                        if assets[name].get("size", 0) <= 0
                        or assets[name].get("state") != "uploaded")
    if incomplete:
        raise ValueError("Incomplete release downloads: " + ", ".join(incomplete))
    return required


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", required=True, type=Path)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    try:
        required = validate(json.loads(args.release.read_text()), args.tag)
    except ValueError as error:
        parser.exit(1, f"{error}\n")
    print(f"Verified {len(required)} required downloads for {args.tag}")


if __name__ == "__main__":
    main()
