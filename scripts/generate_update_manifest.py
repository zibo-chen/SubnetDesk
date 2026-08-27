#!/usr/bin/env python3
"""Generate SubnetDesk's deterministic stable-update manifest."""

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
from urllib.parse import quote


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset-dir", required=True, type=Path)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--sequence", required=True, type=int)
    parser.add_argument("--expires-days", type=int, default=180)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def artifact(asset_dir: Path, filename: str, repository: str, tag: str) -> dict:
    path = asset_dir / filename
    if not path.is_file():
        raise SystemExit(f"required update asset is missing: {path}")
    return {
        "url": (
            f"https://github.com/{repository}/releases/download/"
            f"{quote(tag, safe='')}/{quote(filename, safe='')}"
        ),
        "size": path.stat().st_size,
        "sha256": sha256(path),
    }


def main() -> None:
    args = parse_args()
    if args.sequence < 1:
        raise SystemExit("sequence must be positive")
    if args.expires_days < 1:
        raise SystemExit("expires-days must be positive")

    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    filenames = {
        "windows-x86_64-msi": f"subnetdesk-{args.version}-x86_64.msi",
        "windows-x86_64-exe": f"subnetdesk-{args.version}-x86_64.exe",
        "windows-aarch64-msi": f"subnetdesk-{args.version}-aarch64.msi",
        "windows-aarch64-exe": f"subnetdesk-{args.version}-aarch64.exe",
        "macos-x86_64-dmg": f"subnetdesk-{args.version}-x86_64.dmg",
        "macos-aarch64-dmg": f"subnetdesk-{args.version}-aarch64.dmg",
    }
    manifest = {
        "schema": 1,
        "sequence": args.sequence,
        "channel": "stable",
        "version": args.version,
        "published_at": now.isoformat().replace("+00:00", "Z"),
        "expires_at": (now + dt.timedelta(days=args.expires_days))
        .isoformat()
        .replace("+00:00", "Z"),
        "min_supported_version": None,
        "mandatory_after": None,
        "release_notes_url": f"https://github.com/{args.repository}/releases/tag/{quote(args.tag, safe='')}",
        "artifacts": {
            key: artifact(
                args.asset_dir, filename, args.repository, args.tag
            )
            for key, filename in filenames.items()
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
