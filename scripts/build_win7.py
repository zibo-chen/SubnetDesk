#!/usr/bin/env python3
"""Build the shared Flutter UI with RustDesk's custom Win7 x64 engine."""
import argparse
import hashlib
import json
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import re
import zipfile

import audit_win7_pe
import audit_dart_aot
import prepare_win7_flutter

ROOT = Path(__file__).resolve().parents[1]
TOOLCHAIN = "nightly-2025-08-01"  # Rust 1.90.0 nightly; rust-src is required.
TARGETS = {"x64": "x86_64-win7-windows-msvc", "x86": "i686-win7-windows-msvc"}


def cargo_command(arch, *args):
    return ["cargo", f"+{TOOLCHAIN}", "build", "--locked", "--release",
            "--target", TARGETS[arch], "-Z", "build-std=std,panic_abort", *args]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def win7_import_library_paths(arch, cargo_home, lock_file=ROOT / "Cargo.lock"):
    """Old windows-rs packages omit Win7 dependency/search-path declarations."""
    crate = "windows_x86_64_msvc" if arch == "x64" else "windows_i686_msvc"
    versions = re.findall(r'\[\[package\]\]\s+name = "' + crate + r'"\s+version = "([^"]+)"',
                          lock_file.read_text(encoding="utf-8"))
    paths = []
    for version in sorted(versions, key=lambda value: tuple(map(int, value.split("."))), reverse=True):
        paths.extend(sorted((cargo_home / "registry" / "src").glob(f"*/{crate}-{version}/lib")))
    libraries = {file.name for path in paths for file in path.glob("*.lib")}
    if not {"windows.lib", "windows.0.48.5.lib"}.issubset(libraries):
        raise RuntimeError("Missing locked legacy windows-rs import libraries after Cargo fetch")
    return paths


def win7_sodium_library_path(arch, cargo_home, lock_file=ROOT / "Cargo.lock"):
    """Select the locked bundled MSVC library for a target-specific override."""
    version = re.search(r'\[\[package\]\]\s+name = "libsodium-sys"\s+version = "([^"]+)"',
                        lock_file.read_text(encoding="utf-8"))
    if not version:
        raise RuntimeError("Missing locked libsodium-sys package")
    platform = "x64" if arch == "x64" else "Win32"
    paths = sorted((cargo_home / "registry" / "src").glob(
        f"*/libsodium-sys-{version.group(1)}/msvc/{platform}/Release/v142"))
    if len(paths) != 1 or not (paths[0] / "libsodium.lib").is_file():
        raise RuntimeError(f"Missing unambiguous locked {platform} libsodium library")
    return paths[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("x64",), default="x64")
    parser.add_argument("--output", type=Path, default=ROOT / "target/win7-dist")
    parser.add_argument("--workspace", type=Path, default=ROOT / "target/win7-flutter/build")
    parser.add_argument("--flutter-sdk", type=Path)
    parser.add_argument("--print-commands", action="store_true")
    args = parser.parse_args()
    command = cargo_command(args.arch, "-p", "rustdesk", "--features", "flutter,software-update", "--lib")
    if args.print_commands:
        print(subprocess.list2cmdline(command))
        print("flutter build windows --release --no-pub (RustDesk custom engine "
              + prepare_win7_flutter.ENGINE["flutter_version"] + ")")
        return
    if sys.platform != "win32":
        parser.error("Build on a Windows 10/11 MSVC developer shell or GitHub Windows runner")
    if not os.environ.get("VCPKG_ROOT") or not os.environ.get("VCPKG_INSTALLED_ROOT"):
        parser.error("Set the isolated Win7 VCPKG_ROOT and VCPKG_INSTALLED_ROOT")
    if os.environ.get("RUSTFLAGS") or os.environ.get("CARGO_ENCODED_RUSTFLAGS"):
        parser.error("Unset RUSTFLAGS/CARGO_ENCODED_RUSTFLAGS so the dedicated Win7 target flags apply")
    sdk = args.flutter_sdk or Path(os.environ.get("FLUTTER_ROOT", ""))
    flutter = sdk / "bin/flutter.bat"
    if not flutter.is_file():
        parser.error("Pass --flutter-sdk pointing to Flutter " + prepare_win7_flutter.ENGINE["flutter_version"])
    args.workspace = args.workspace.resolve()
    if args.workspace.exists():
        if not (args.workspace / "ui-compatibility.json").is_file():
            parser.error("Existing workspace was not prepared by prepare_win7_flutter.py")
        ui = args.workspace / "flutter"
    else:
        ui = prepare_win7_flutter.prepare(args.workspace)
    ui_metadata = json.loads((args.workspace / "ui-compatibility.json").read_text())
    if ui_metadata["source_sha256"] != prepare_win7_flutter.ui_source_hash():
        parser.error("The prepared UI is stale; choose a new workspace for the current sources")
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = str(ROOT / "target/win7-flutter/native")
    env["SUBNETDESK_WIN7"] = "1"
    for key in ("CFLAGS", "CXXFLAGS"):
        env[key] = env.get(key, "") + " /D_WIN32_WINNT=0x0601 /DWINVER=0x0601"
    def run(arguments, cwd=ROOT):
        subprocess.run([str(value) for value in arguments], cwd=cwd, env=env, check=True)
    run(["cargo", f"+{TOOLCHAIN}", "fetch", "--locked", "--target", "x86_64-pc-windows-msvc"])
    cargo_home = Path(env.get("CARGO_HOME", str(Path.home() / ".cargo")))
    import_paths = win7_import_library_paths(args.arch, cargo_home)
    sodium_path = win7_sodium_library_path(args.arch, cargo_home)
    for key in ("SODIUM_LIB_DIR", "SODIUM_SHARED", "SODIUM_USE_PKG_CONFIG", "SODIUM_STATIC"):
        env.pop(key, None)
    sodium_config = Path(env["CARGO_TARGET_DIR"]) / "sodium-x64.toml"
    sodium_config.parent.mkdir(parents=True, exist_ok=True)
    sodium_config.write_text(
        f"[target.{TARGETS[args.arch]}.sodium]\n"
        'rustc-link-lib = ["static=libsodium"]\n'
        f"rustc-link-search = {json.dumps([sodium_path.as_posix()])}\n"
        f"lib = {json.dumps(sodium_path.as_posix())}\n", encoding="utf-8")
    command.extend(["--config", str(sodium_config)])
    env["LIB"] = ";".join(str(path) for path in import_paths) + ";" + env.get("LIB", "")
    run(command)
    release = Path(env["CARGO_TARGET_DIR"]) / TARGETS[args.arch] / "release"
    native = args.workspace / "target/release"
    native.mkdir(parents=True, exist_ok=True)
    shutil.copy2(release / "librustdesk.dll", native / "librustdesk.dll")
    run([flutter, "pub", "get", "--enforce-lockfile"], ui)
    run([flutter, "precache", "--windows"])
    engine_archive = ROOT / "target/win7-flutter/windows-x64-release.zip"
    prepare_win7_flutter.install_engine(sdk, engine_archive)
    run([flutter, "build", "windows", "--release", "--no-pub"], ui)
    runtime = ui / "build/windows/x64/runner/Release"
    with zipfile.ZipFile(engine_archive) as engine:
        expected = hashlib.sha256(engine.read("flutter_windows.dll")).hexdigest()
    if hashlib.sha256((runtime / "flutter_windows.dll").read_bytes()).hexdigest() != expected:
        raise RuntimeError("The compiled runtime does not contain the pinned RustDesk Win7 engine")
    host = runtime / "rustdesk.exe"
    host.rename(runtime / "SubnetDesk.exe")
    shutil.copy2(ROOT / "LICENCE", runtime / "SubnetDesk-LICENSE.txt")
    shutil.copy2(sdk / "LICENSE", runtime / "Flutter-LICENSE.txt")
    manifest = (ROOT / "Cargo.toml").read_text(encoding="utf-8").split("[package]", 1)[1].split("\n[", 1)[0]
    version_match = re.search(r'^version\s*=\s*"([^"\n]+)"', manifest, re.MULTILINE)
    if not version_match:
        raise RuntimeError("Missing package version")
    name = f"subnetdesk-{version_match.group(1)}-win7-x64-flutter"
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    provenance = {
        "ui": "shared Flutter UI", "sciter": False, "minimum_os": "Windows 7 SP1 x64",
        "rust_target": TARGETS[args.arch], "rust_toolchain": TOOLCHAIN,
        "ui_source_sha256": ui_metadata["source_sha256"],
        "engine": prepare_win7_flutter.ENGINE, "engine_dll_sha256": expected,
        "source_commit": os.environ.get("GITHUB_SHA") or subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "run": os.environ.get("GITHUB_SERVER_URL", "https://github.com") + "/" +
               os.environ.get("GITHUB_REPOSITORY", "zibo-chen/SubnetDesk") + "/actions/runs/" +
               os.environ.get("GITHUB_RUN_ID", "local"),
    }
    (runtime / "build-provenance.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    reports = []
    snapshots = []
    for path in sorted(runtime.rglob("*")):
        if "sciter" in path.name.lower() or path.name.lower() == "service.exe":
            raise RuntimeError("Retired Sciter/service file found in the Flutter package: " + path.name)
        if path.suffix.lower() == ".so":
            if path.relative_to(runtime).as_posix() != "data/app.so":
                raise RuntimeError("Unexpected shared object in the Windows package: " + str(path))
            snapshots.append(audit_dart_aot.inspect(path))
        if path.suffix.lower() in (".exe", ".dll"):
            report = audit_win7_pe.inspect(path)
            report["errors"] = audit_win7_pe.violations(report, "x64")
            reports.append(report)
    (args.output / (name + "-imports.json")).write_text(json.dumps(reports, indent=2), encoding="utf-8")
    if len(snapshots) != 1:
        raise RuntimeError("Expected one Dart AOT snapshot in the Flutter runtime")
    (args.output / (name + "-aot.json")).write_text(json.dumps(snapshots, indent=2), encoding="utf-8")
    if any(report["errors"] for report in reports):
        raise RuntimeError("Win7 PE import checks failed: " + json.dumps([
            {"file": row["file"], "errors": row["errors"]} for row in reports if row["errors"]]))
    portable = load_module("win7_portable_directory", ROOT / "scripts/package_portable.py")
    archive = portable.package(runtime, runtime / "SubnetDeskLauncher.exe", args.output / name)
    provenance["package"] = archive.name
    provenance["sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
    provenance["pe_files_checked"] = len(reports)
    provenance["aot_files_checked"] = len(snapshots)
    (args.output / (name + "-provenance.json")).write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    print(f"Win7 Flutter test package: {archive}; {len(reports)} PE files checked")


if __name__ == "__main__":
    main()
