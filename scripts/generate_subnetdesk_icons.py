#!/usr/bin/env python3
"""Generate every shipped SubnetDesk icon from res/subnetdesk-icon.svg."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "res/subnetdesk-icon.svg"
MANIFEST = ROOT / "res/subnetdesk-icon-manifest.json"
BACKGROUND = (0x0B, 0x1F, 0x33, 0xFF)

PNG_TARGETS = {
    "res/icon.png": (1024, 1024, "RGBA"),
    "flutter/assets/icon.png": (1024, 1024, "RGBA"),
    "res/mac-icon.png": (1024, 1024, "RGBA"),
    "res/128x128.png": (128, 128, "RGBA"),
    "res/128x128@2x.png": (256, 256, "RGBA"),
    "res/64x64.png": (64, 64, "RGBA"),
    "res/32x32.png": (32, 32, "RGBA"),
}

ANDROID_DENSITIES = {
    "mdpi": (48, 108, 24),
    "hdpi": (72, 162, 36),
    "xhdpi": (96, 216, 48),
    "xxhdpi": (144, 324, 72),
    "xxxhdpi": (192, 432, 96),
}

IOS_TARGETS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def render_svg(destination: Path) -> None:
    sips = shutil.which("sips")
    if not sips:
        raise SystemExit("sips is required to rasterize the SVG on macOS")
    subprocess.run(
        [sips, "-s", "format", "png", str(SOURCE), "--out", str(destination)],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def resized(image, size: int):
    from PIL import Image

    return image.resize((size, size), Image.Resampling.LANCZOS)


def save_rgba(image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    resized(image, size).save(path, format="PNG", optimize=True)


def save_rgb(image, path: Path, size: int) -> None:
    from PIL import Image

    foreground = resized(image, size)
    canvas = Image.new("RGBA", foreground.size, BACKGROUND)
    canvas.alpha_composite(foreground)
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(path, format="PNG", optimize=True)


def foreground_image(image, size: int):
    from PIL import Image

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    safe_size = round(size * 2 / 3)
    icon = resized(image, safe_size)
    offset = (size - safe_size) // 2
    canvas.alpha_composite(icon, (offset, offset))
    return canvas


def monochrome_mask(image):
    from PIL import Image, ImageChops

    opaque_background = Image.new("RGBA", image.size, BACKGROUND)
    difference = ImageChops.difference(image, opaque_background).convert("L")
    strokes = difference.point(lambda value: 255 if value > 18 else 0)
    return ImageChops.multiply(strokes, image.getchannel("A"))


def save_monochrome(mask, path: Path, size: int, luminance: int) -> None:
    from PIL import Image

    alpha = resized(mask, size)
    gray = Image.new("L", (size, size), luminance)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.merge("LA", (gray, alpha)).save(path, format="PNG", optimize=True)


def write_icns(image, destination: Path) -> None:
    iconutil = shutil.which("iconutil")
    if not iconutil:
        raise SystemExit("iconutil is required to generate the macOS AppIcon.icns")
    with tempfile.TemporaryDirectory(prefix="subnetdesk-iconset-") as temp:
        iconset = Path(temp) / "AppIcon.iconset"
        iconset.mkdir()
        for logical in (16, 32, 128, 256, 512):
            save_rgba(image, iconset / f"icon_{logical}x{logical}.png", logical)
            save_rgba(
                image,
                iconset / f"icon_{logical}x{logical}@2x.png",
                logical * 2,
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [iconutil, "-c", "icns", str(iconset), "-o", str(destination)],
            check=True,
        )


def generated_paths() -> list[Path]:
    paths = [ROOT / path for path in PNG_TARGETS]
    paths.extend(
        [
            ROOT / "res/icon.ico",
            ROOT / "res/tray-icon.ico",
            ROOT / "res/scalable.svg",
            ROOT / "flutter/assets/icon.svg",
            ROOT / "flutter/windows/runner/resources/app_icon.ico",
            ROOT / "flutter/macos/Runner/AppIcon.icns",
            ROOT / "res/mac-tray-dark-x2.png",
            ROOT / "res/mac-tray-light-x2.png",
        ]
    )
    for density in ANDROID_DENSITIES:
        base = ROOT / f"flutter/android/app/src/main/res/mipmap-{density}"
        paths.extend(
            base / filename
            for filename in (
                "ic_launcher.png",
                "ic_launcher_foreground.png",
                "ic_launcher_round.png",
                "ic_stat_logo.png",
            )
        )
    ios_dir = ROOT / "flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    paths.extend(ios_dir / filename for filename in IOS_TARGETS)
    return sorted(paths)


def write_manifest() -> None:
    payload = {
        "source": str(SOURCE.relative_to(ROOT)),
        "source_sha256": sha256(SOURCE),
        "generated": {
            str(path.relative_to(ROOT)): sha256(path) for path in generated_paths()
        },
    }
    MANIFEST.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def generate() -> None:
    from PIL import Image

    if not SOURCE.is_file():
        raise SystemExit(f"missing icon source: {SOURCE}")
    with tempfile.TemporaryDirectory(prefix="subnetdesk-icon-") as temp:
        raster = Path(temp) / "icon.png"
        render_svg(raster)
        base = Image.open(raster).convert("RGBA")
        if base.size != (1024, 1024):
            raise SystemExit(f"expected a 1024x1024 raster, got {base.size}")

        for relative, (width, height, _mode) in PNG_TARGETS.items():
            if width != height:
                raise SystemExit(f"non-square icon target: {relative}")
            save_rgba(base, ROOT / relative, width)

        ico_sizes = [(16, 16), (32, 32), (48, 48), (128, 128), (256, 256)]
        base.save(ROOT / "res/icon.ico", format="ICO", sizes=ico_sizes)
        base.save(
            ROOT / "flutter/windows/runner/resources/app_icon.ico",
            format="ICO",
            sizes=ico_sizes,
        )
        base.save(
            ROOT / "res/tray-icon.ico",
            format="ICO",
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48)],
        )

        mask = monochrome_mask(base)
        save_monochrome(mask, ROOT / "res/mac-tray-dark-x2.png", 60, 255)
        save_monochrome(mask, ROOT / "res/mac-tray-light-x2.png", 48, 0)

        for density, (launcher, foreground, stat) in ANDROID_DENSITIES.items():
            directory = ROOT / f"flutter/android/app/src/main/res/mipmap-{density}"
            save_rgba(base, directory / "ic_launcher.png", launcher)
            save_rgba(base, directory / "ic_launcher_round.png", launcher)
            foreground_image(base, foreground).save(
                directory / "ic_launcher_foreground.png", format="PNG", optimize=True
            )
            save_monochrome(mask, directory / "ic_stat_logo.png", stat, 255)

        ios_dir = ROOT / "flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset"
        for filename, size in IOS_TARGETS.items():
            save_rgb(base, ios_dir / filename, size)

        write_icns(base, ROOT / "flutter/macos/Runner/AppIcon.icns")
        shutil.copyfile(SOURCE, ROOT / "res/scalable.svg")
        shutil.copyfile(SOURCE, ROOT / "flutter/assets/icon.svg")
        write_manifest()


def check() -> None:
    if not MANIFEST.is_file():
        raise SystemExit(f"missing generated icon manifest: {MANIFEST}")
    payload = json.loads(MANIFEST.read_text())
    if payload.get("source_sha256") != sha256(SOURCE):
        raise SystemExit("SubnetDesk icon source changed; regenerate platform assets")
    expected = payload.get("generated", {})
    actual_paths = generated_paths()
    if set(expected) != {str(path.relative_to(ROOT)) for path in actual_paths}:
        raise SystemExit("SubnetDesk icon manifest target list is out of date")
    for path in actual_paths:
        relative = str(path.relative_to(ROOT))
        if not path.is_file() or sha256(path) != expected[relative]:
            raise SystemExit(f"generated SubnetDesk icon is stale: {relative}")
    print(f"SubnetDesk icon check passed ({len(actual_paths)} assets).")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    check() if args.check else generate()


if __name__ == "__main__":
    main()
