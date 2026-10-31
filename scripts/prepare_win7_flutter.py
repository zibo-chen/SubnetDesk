#!/usr/bin/env python3
"""Prepare the current Flutter UI for RustDesk's pinned Win7 engine SDK.

Only the isolated build copy is changed. Layouts, assets and business logic come
from flutter/; this is not a separate UI implementation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ENGINE = json.loads((ROOT / "res/win7/flutter-engine.json").read_text())


def ui_source_hash():
    digest = hashlib.sha256()
    for directory in (ROOT / "flutter/lib", ROOT / "flutter/assets", ROOT / "flutter/windows"):
        for path in sorted(directory.rglob("*")):
            if path.is_file() and "ephemeral" not in path.parts:
                digest.update(path.relative_to(ROOT / "flutter").as_posix().encode())
                digest.update(b"\0")
                digest.update(path.read_bytes())
    return digest.hexdigest()


def yaml_section(source, name, replacements):
    """Replace existing flat section entries, keeping unrelated YAML intact."""
    lines = source.splitlines(keepends=True)
    start = lines.index(name + ":\n") + 1
    end = next((i for i in range(start, len(lines))
                if re.match(r"^[A-Za-z_]", lines[i])), len(lines))
    for key, value in replacements.items():
        first = next((i for i in range(start, end)
                      if re.match(r"^  " + re.escape(key) + r":", lines[i])), None)
        if first is None:
            raise ValueError(f"Missing {name}.{key} in the current pubspec")
        last = first + 1
        while last < end and (lines[last].startswith("    ") or not lines[last].strip()):
            last += 1
        lines[first:last] = [f"  {key}: {json.dumps(value)}\n"]
        end -= last - first - 1
    return "".join(lines)


def closing_parenthesis(source, start):
    depth = 1
    quote = None
    escaped = False
    for i in range(start, len(source)):
        char = source[i]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return i
    raise ValueError("Unbalanced Dart call while preparing Win7 sources")


def compatible_dart(source):
    for new, old in (("DialogThemeData(", "DialogTheme("),
                     ("TabBarThemeData(", "TabBarTheme(")):
        source = source.replace(new, old)
    source = re.sub(r"\bactiveThumbColor\s*:", "activeColor:", source)
    if "OverlayPortal.overlayChildLayoutBuilder(" in source:
        source = ("import 'package:flutter_hbb/common/widgets/win7_overlay_portal.dart';\n"
                  + source.replace("OverlayPortal.overlayChildLayoutBuilder(", "win7OverlayPortal("))
    marker = ".withValues("
    while marker in source:
        first = source.index(marker)
        last = closing_parenthesis(source, first + len(marker))
        arguments = source[first + len(marker):last].strip().rstrip(",").strip()
        if not arguments.startswith("alpha:"):
            raise ValueError("Win7 color compatibility requires an alpha-only withValues call")
        source = (source[:first] + ".withOpacity(" + arguments[len("alpha:"):].strip()
                  + ")" + source[last + 1:])
    pattern = r"DropdownButtonFormField(?:<[^>]+>)?\("
    position = 0
    while match := re.search(pattern, source[position:]):
        first = position + match.end()
        last = closing_parenthesis(source, first)
        arguments = re.sub(r"\binitialValue\s*:", "value:", source[first:last])
        source = source[:first] + arguments + source[last:]
        position = first + len(arguments) + 1
    for method in ("saveFile", "pickFiles", "getDirectoryPath", "clearTemporaryFiles"):
        source = source.replace(f"FilePicker.{method}(", f"FilePicker.platform.{method}(")
    return source


def prepare(destination):
    destination = destination.resolve()
    if destination.exists():
        raise ValueError("Choose a new Win7 build directory; existing build/profile data is not overwritten")
    if destination == ROOT or ROOT in destination.parents and "target" not in destination.relative_to(ROOT).parts:
        raise ValueError("Prepare Win7 under target/ or outside the repository")
    flutter = destination / "flutter"
    shutil.copytree(ROOT / "flutter", flutter, ignore=shutil.ignore_patterns(
        "build", ".dart_tool", ".git", "Pods", "ephemeral", ".plugin_symlinks",
        ".symlinks", ".flutter-plugins", ".flutter-plugins-dependencies"))
    pubspec = (flutter / "pubspec.yaml").read_text(encoding="utf-8")
    pubspec = yaml_section(pubspec, "environment", {"sdk": ">=3.5.0 <4.0.0", "flutter": ">=3.24.5 <3.25.0"})
    profile = json.loads((ROOT / "res/win7/flutter-dependencies.json").read_text())
    for section, replacements in profile.items():
        pubspec = yaml_section(pubspec, section, replacements)
    (flutter / "pubspec.yaml").write_text(pubspec, encoding="utf-8")
    lock = ROOT / "res/win7/flutter-pubspec.lock"
    if lock.is_file():
        shutil.copy2(lock, flutter / "pubspec.lock")
    else:
        (flutter / "pubspec.lock").unlink(missing_ok=True)
    changed = []
    for directory in (flutter / "lib", flutter / "test"):
        for path in sorted(directory.rglob("*.dart")):
            original = path.read_text(encoding="utf-8")
            compatible = compatible_dart(original)
            if compatible != original:
                path.write_text(compatible, encoding="utf-8")
                changed.append(str(path.relative_to(flutter)))
    shutil.copy2(ROOT / "res/win7/overlay_portal.dart",
                 flutter / "lib/common/widgets/win7_overlay_portal.dart")
    (destination / "ui-compatibility.json").write_text(json.dumps({
        "source": "flutter/", "sdk": ENGINE["flutter_version"],
        "source_sha256": ui_source_hash(),
        "changed_api_files": changed, "separate_ui": False,
    }, indent=2), encoding="utf-8")
    return flutter


def install_engine(sdk, archive):
    sdk = sdk.resolve()
    version = json.loads((sdk / "bin/cache/flutter.version.json").read_text())
    if version["frameworkVersion"] != ENGINE["flutter_version"]:
        raise ValueError("The RustDesk Win7 engine must only be used with Flutter " + ENGINE["flutter_version"])
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(ENGINE["url"], timeout=180) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != ENGINE["sha256"]:
        raise ValueError("RustDesk custom engine checksum mismatch; refusing to use an unverified engine")
    destination = sdk / "bin/cache/artifacts/engine/windows-x64-release"
    if not destination.is_dir():
        raise ValueError("Run flutter precache --windows before replacing the engine")
    with zipfile.ZipFile(archive) as package:
        required = {"flutter_windows.dll", "flutter_windows.dll.lib", "flutter_windows.h", "gen_snapshot.exe"}
        if not required.issubset(package.namelist()) or any(Path(name).name != name for name in package.namelist()):
            raise ValueError("Unexpected custom engine archive contents")
        package.extractall(destination)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--install-engine", type=Path, metavar="FLUTTER_SDK")
    parser.add_argument("--engine-archive", type=Path, default=ROOT / "target/win7-flutter/windows-x64-release.zip")
    args = parser.parse_args()
    if args.workspace:
        print(prepare(args.workspace))
    if args.install_engine:
        print(install_engine(args.install_engine, args.engine_archive))
    if not args.workspace and not args.install_engine:
        parser.error("Specify --workspace and/or --install-engine")


if __name__ == "__main__":
    main()
