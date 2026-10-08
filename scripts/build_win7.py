#!/usr/bin/env python3
"""Build the Sciter app, service and portable launcher for a dedicated Win7 target."""
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
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
TOOLCHAIN = "nightly-2025-08-01"  # Rust 1.90.0 nightly; rust-src is required.
TARGETS = {"x64": "x86_64-win7-windows-msvc", "x86": "i686-win7-windows-msvc"}
SDK_COMMIT = "f33df075d9eb2f8d252cb88f1b2c8096e56197ed"
SCITER_SHA256 = {
    "x64": "4d97528e157c55ef1fabe9e37a9697116ab66660d7da6163f90a3a7abf80dd56",
    "x86": "285f3e6a051a7c61845cd7e4d2120781b6bdf411239f70a85c65b38a52d38f28",
}


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


def sciter_dll(arch, destination):
    platform = "x64" if arch == "x64" else "x32"
    url = f"https://raw.githubusercontent.com/c-smile/sciter-sdk/{SDK_COMMIT}/bin.win/{platform}/sciter.dll"
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != SCITER_SHA256[arch]:
        raise RuntimeError("Sciter DLL checksum does not match the pinned SDK")
    destination.write_bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", required=True, choices=TARGETS)
    parser.add_argument("--output", type=Path, default=ROOT / "target" / "win7-dist")
    parser.add_argument("--print-commands", action="store_true")
    args = parser.parse_args()
    commands = [cargo_command(args.arch, "-p", "rustdesk", "--features", "inline", "--bin", "rustdesk", "--bin", "service"),
                cargo_command(args.arch, "-p", "sciter-rs", "--example", "win7_smoke"),
                cargo_command(args.arch, "-p", "rustdesk-portable-packer")]
    if args.print_commands:
        for command in commands:
            print(subprocess.list2cmdline(command))
        return
    if sys.platform != "win32":
        parser.error("Run from an MSVC developer shell on Windows 10/11; do not build on Windows 7")
    if not os.environ.get("VCPKG_ROOT") or not os.environ.get("VCPKG_INSTALLED_ROOT"):
        parser.error("Set VCPKG_ROOT and VCPKG_INSTALLED_ROOT to the Win7-specific dependency tree")
    if os.environ.get("RUSTFLAGS") or os.environ.get("CARGO_ENCODED_RUSTFLAGS"):
        parser.error("Unset RUSTFLAGS/CARGO_ENCODED_RUSTFLAGS so .cargo/config.toml applies")
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = str(ROOT / "target" / "win7")
    for key in ("CFLAGS", "CXXFLAGS"):
        env[key] = env.get(key, "") + " /D_WIN32_WINNT=0x0601 /DWINVER=0x0601"
    run = lambda command: subprocess.run(command, cwd=ROOT, env=env, check=True)
    # Fetch import-library packages whose old manifests list only pc/uwp targets.
    # This fetch does not compile an ordinary Windows target or its standard library.
    native_target = "x86_64-pc-windows-msvc" if args.arch == "x64" else "i686-pc-windows-msvc"
    run(["cargo", f"+{TOOLCHAIN}", "fetch", "--locked", "--target", native_target])
    cargo_home = Path(env.get("CARGO_HOME", str(Path.home() / ".cargo")))
    import_paths = win7_import_library_paths(args.arch, cargo_home)
    sodium_path = win7_sodium_library_path(args.arch, cargo_home)
    # Global SODIUM_LIB_DIR also affects x64 host build dependencies for x86 builds.
    # Cargo links overrides apply only to the dedicated target.
    for key in ("SODIUM_LIB_DIR", "SODIUM_SHARED", "SODIUM_USE_PKG_CONFIG", "SODIUM_STATIC"):
        env.pop(key, None)
    sodium_config = Path(env["CARGO_TARGET_DIR"]) / f"sodium-{args.arch}.toml"
    sodium_config.parent.mkdir(parents=True, exist_ok=True)
    sodium_config.write_text(
        f"[target.{TARGETS[args.arch]}.sodium]\n"
        'rustc-link-lib = ["static=libsodium"]\n'
        f"rustc-link-search = {json.dumps([sodium_path.as_posix()])}\n"
        f"lib = {json.dumps(sodium_path.as_posix())}\n",
        encoding="utf-8")
    for command in commands:
        command.extend(["--config", str(sodium_config)])
    env["LIB"] = ";".join(str(path) for path in import_paths) + ";" + env.get("LIB", "")
    run([sys.executable, "res/inline-sciter.py"])
    run(commands[0])
    manifest = (ROOT / "Cargo.toml").read_text(encoding="utf-8").split("[package]", 1)[1].split("\n[", 1)[0]
    version_match = re.search(r'^version\s*=\s*"([^"\n]+)"', manifest, re.MULTILINE)
    if not version_match:
        raise RuntimeError("Missing package version in Cargo.toml")
    version = version_match.group(1)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    name = f"subnetdesk-{version}-win7-{args.arch}"
    payload = args.output / name
    # Isolate packaging from stale DLLs or a previously built Flutter runner.
    if payload.exists():
        shutil.rmtree(payload)
    payload.mkdir()
    release = Path(env["CARGO_TARGET_DIR"]) / TARGETS[args.arch] / "release"
    for file in ("rustdesk.exe", "service.exe"):
        shutil.copy2(release / file, payload / file)
    sciter_dll(args.arch, payload / "sciter.dll")
    shutil.copy2(ROOT / "res/win7/sciter-license.htm", payload / "sciter-license.htm")
    shutil.copy2(ROOT / "src/ui/icons/LICENSE", payload / "material-icons-license.txt")
    shutil.copy2(ROOT / "src/ui/icons/NOTICE", payload / "material-icons-notice.txt")
    shutil.copy2(ROOT / "libs/sciter-rs/LICENSE", payload / "sciter-bindings-license.txt")
    run(commands[1])
    smoke = release / "examples" / "win7_smoke.exe"
    run([str(smoke), str(payload / "sciter.dll")])
    portable = load_module("win7_portable_generate", ROOT / "libs/portable/generate.py")
    portable.write_package_metadata(portable.generate_md5_table(str(payload), 11), str(ROOT / "libs/portable"), "./rustdesk.exe")
    portable.write_app_metadata(str(ROOT / "libs/portable"))
    run(commands[2])
    launcher = args.output / f"{name}.exe"
    shutil.copy2(release / "rustdesk-portable-packer.exe", launcher)
    run([sys.executable, "scripts/audit_win7_pe.py", "--arch", args.arch,
         "--report", str(args.output / f"{name}-imports.json"),
         *(str(file) for file in payload.iterdir() if file.suffix.lower() in (".exe", ".dll")), str(launcher), str(smoke)])
    shutil.copy2(smoke, args.output / f"{name}-sciter-smoke.exe")
    shutil.make_archive(str(args.output / name), "zip", payload)
    print(f"Win7 candidate built: {launcher}; verify on Windows 7 SP1 before release")


if __name__ == "__main__":
    main()
