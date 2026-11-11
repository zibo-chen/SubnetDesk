#!/usr/bin/env python3
"""Wrap the unified, already audited Windows x64 runtime in MSI and self-extracting EXE."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

import audit_win7_pe
import build_win7

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    runtime = args.runtime.resolve(strict=True)
    output = args.output.resolve()
    provenance = json.loads((runtime / "build-provenance.json").read_text())
    if provenance["rust_target"] != "x86_64-win7-windows-msvc" or not {
        "hwcodec", "vram"
    }.issubset(provenance["native_features"]):
        raise ValueError("Expected the unified hardware-enabled Windows x64 runtime")
    output.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output([str(runtime / "SubnetDesk.exe"), "--version"], text=True).strip()
    # Record the payload before packaging; neither wrapper may alter its bytes.
    def hashes():
        return {p.relative_to(runtime).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(runtime.rglob("*")) if p.is_file()}
    expected = hashes()
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = str(ROOT / "target/win7-flutter/native")
    env["CFLAGS"] = env.get("CFLAGS", "") + " /D_WIN32_WINNT=0x0601 /DWINVER=0x0601"
    env["CXXFLAGS"] = env.get("CXXFLAGS", "") + " /D_WIN32_WINNT=0x0601 /DWINVER=0x0601"

    def run(command, cwd=ROOT):
        subprocess.run([str(v) for v in command], cwd=cwd, env=env, check=True)

    generate = build_win7.load_module("portable_generate", ROOT / "libs/portable/generate.py")
    packer = ROOT / "libs/portable"
    generate.write_package_metadata(generate.generate_md5_table(str(runtime), 11), str(packer),
                                    r".\SubnetDesk.exe")
    generate.write_app_metadata(str(packer))
    run(build_win7.cargo_command("x64", "-p", "rustdesk-portable-packer"))
    test = build_win7.cargo_command("x64", "-p", "rustdesk-portable-packer")
    test[2] = "test"
    run(test)
    executable = Path(env["CARGO_TARGET_DIR"]) / build_win7.TARGETS["x64"] / "release/rustdesk-portable-packer.exe"
    report = audit_win7_pe.inspect(executable)
    report["errors"] = audit_win7_pe.violations(report, "x64")
    (output / "self-extract-imports.json").write_text(json.dumps(report, indent=2))
    if report["errors"]:
        raise ValueError("Self-extracting bootstrapper is not Win7 compatible: " + str(report["errors"]))
    shutil.copy2(executable, output / f"subnetdesk-{version}-x86_64.exe")

    msi = ROOT / "res/msi"
    run(["python", "preprocess.py", "--arp", "--app-name", "SubnetDesk", "--manufacturer",
         "SubnetDesk", "-d", runtime], msi)
    run(["nuget", "restore", "msi.sln"], msi)
    run(["msbuild", "msi.sln", "-p:Configuration=Release", "-p:Platform=x64",
         "/p:TargetVersion=Windows7"], msi)
    packages = list((msi / "Package/bin").glob("*/Release/en-us/Package.msi"))
    if len(packages) != 1:
        raise ValueError("Expected one MSI package")
    # Audit the native custom-action DLL as well as the application payload.
    actions = list((msi / "CustomActions").rglob("CustomActions.dll"))
    if not actions:
        raise ValueError("MSI native custom-action DLL was not found")
    reports = []
    for path in actions:
        report = audit_win7_pe.inspect(path)
        report["errors"] = audit_win7_pe.violations(report, "x64")
        reports.append(report)
    (output / "msi-action-imports.json").write_text(json.dumps(reports, indent=2))
    if any(report["errors"] for report in reports):
        raise ValueError("MSI native custom actions are not Win7 compatible")
    shutil.copy2(packages[0], output / f"subnetdesk-{version}-x86_64.msi")
    build_win7.sign_files(sorted(output.glob("*.exe")) + sorted(output.glob("*.msi")))
    for path in output.glob("*-setup.exe"):
        metadata_path = path.with_suffix(".json")
        metadata = json.loads(metadata_path.read_text())
        metadata["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        metadata_path.write_text(json.dumps(metadata, indent=2))
    if hashes() != expected:
        raise ValueError("Packaging changed the unified runtime")
    (output / "installer-payload.json").write_text(json.dumps({
        "source": provenance, "runtime_files": expected,
        "formats": ["directory ZIP", "NSIS setup", "MSI", "self-extracting EXE"],
    }, indent=2))


if __name__ == "__main__":
    main()
