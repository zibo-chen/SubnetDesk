#!/usr/bin/env python3
"""Wrap a verified Win7 Flutter directory package in a Unicode NSIS installer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import audit_win7_pe

ROOT = Path(__file__).resolve().parents[1]


def nsis_literal(value):
    return str(value).replace("$", "$$").replace('"', '$\\"')


def payload_files(package):
    required = ("SubnetDesk.exe", "app/SubnetDesk.exe", "app/flutter_windows.dll",
                "app/librustdesk.dll", "app/data/app.so", "app/build-provenance.json")
    if not all((package / name).is_file() for name in required):
        raise ValueError("Expected a complete Win7 Flutter directory package")
    provenance = json.loads((package / "app/build-provenance.json").read_text(encoding="utf-8"))
    if provenance.get("rust_target") != "x86_64-win7-windows-msvc" or provenance.get("sciter") is not False:
        raise ValueError("Expected Win7 x64 Flutter build provenance")
    files = []
    for path in sorted(package.rglob("*")):
        relative = path.relative_to(package)
        if relative.parts[0] == "userdata":
            continue
        if path.is_symlink():
            raise ValueError("Symlinks are not supported in the installer payload")
        if path.is_file():
            if relative.parts[0] != "app" and relative.as_posix() != "SubnetDesk.exe":
                raise ValueError("Unexpected file outside the runtime: " + str(relative))
            if path.suffix.lower() in (".exe", ".dll"):
                errors = audit_win7_pe.violations(audit_win7_pe.inspect(path), "x64")
                if errors:
                    raise ValueError(f"{relative}: {errors}")
            files.append(relative)
    return files, provenance


def file_commands(package, files):
    install = []
    uninstall = []
    directories = set()
    for relative in files:
        target = nsis_literal(str(relative).replace("/", "\\"))
        parent = nsis_literal(str(relative.parent).replace("/", "\\"))
        install.extend([f'SetOutPath "$INSTDIR\\{parent}"',
                        f'File "{nsis_literal(package / relative)}"'])
        uninstall.append(f'Delete "$INSTDIR\\{target}"')
        directories.update(parent for parent in relative.parents if parent != Path("."))
    for directory in sorted(directories, key=lambda path: (-len(path.parts), str(path))):
        target = nsis_literal(str(directory).replace("/", "\\"))
        uninstall.append(f'RMDir "$INSTDIR\\{target}"')
    return "\n".join(install) + "\n", "\n".join(uninstall) + "\n"


def find_makensis():
    compiler = shutil.which("makensis")
    if compiler:
        return compiler
    for variable in ("ProgramFiles(x86)", "ProgramFiles"):
        compiler = Path(os.environ.get(variable, "")) / "NSIS/makensis.exe"
        if compiler.is_file():
            return str(compiler)
    raise FileNotFoundError("Install NSIS 3 and add makensis to PATH")


def package_installer(package, output, version, makensis=None):
    package = package.resolve(strict=True)
    output = output.resolve()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Installer version must contain three numeric components")
    if output.exists():
        raise ValueError("An existing installer is never overwritten")
    if package in output.parents:
        raise ValueError("Installer output must be outside the package")
    files, provenance = payload_files(package)
    compiler = makensis or find_makensis()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="subnetdesk-nsis-") as temporary:
        temporary = Path(temporary)
        install, uninstall = file_commands(package, files)
        for name, contents in (("install.nsh", install), ("uninstall.nsh", uninstall)):
            (temporary / name).write_text(contents, encoding="utf-8-sig")
        definitions = {
            "OUTPUT": str(output), "VERSION": version,
            "ICON": str(ROOT / "res/icon.ico"),
            "INSTALL_FILES": str(temporary / "install.nsh"),
            "UNINSTALL_FILES": str(temporary / "uninstall.nsh"),
        }
        prefix = "/" if os.name == "nt" else "-"
        subprocess.run([str(compiler), prefix + "V2", *[
            f"{prefix}D{key}={value}" for key, value in definitions.items()],
            str(ROOT / "res/win7/installer.nsi")], check=True)
    report = audit_win7_pe.inspect(output)
    # NSIS uses a 32-bit bootstrapper which installs the gated x64 payload.
    report["errors"] = audit_win7_pe.violations(report, "x86")
    if report["errors"]:
        raise ValueError("Installer bootstrapper is not Win7 compatible: " + str(report["errors"]))
    metadata = {
        "package": output.name, "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "source": provenance, "minimum_os": "Windows 7 SP1 x64", "installer": "NSIS Unicode",
        "compiler_version": subprocess.check_output([str(compiler), prefix + "VERSION"], text=True).strip(),
        "userdata_included": False, "uninstall_preserves_userdata": True,
        "files": {path.as_posix(): hashlib.sha256((package / path).read_bytes()).hexdigest()
                  for path in files},
        "bootstrapper": report,
    }
    output.with_suffix(".json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--makensis", type=Path)
    args = parser.parse_args()
    print(package_installer(args.package, args.output, args.version, args.makensis))
