#!/usr/bin/env python3
"""Package a Windows runner as SubnetDesk.exe + app/ + userdata/."""
import argparse
from pathlib import Path
import shutil
import zipfile


def package(runtime: Path, launcher: Path, output: Path) -> Path:
    runtime = runtime.resolve()
    launcher = launcher.resolve()
    output = output.resolve()
    if output.exists():
        raise ValueError("Choose a new output directory; an existing portable profile is never overwritten")
    if runtime in output.parents:
        raise ValueError("The output directory must be outside the Windows runtime")
    archive = output.parent / (output.name + ".zip")
    if archive.exists():
        raise ValueError("Choose a new output name; an existing archive is never overwritten")
    if not any((runtime / name).is_file() for name in ("rustdesk.exe", "SubnetDesk.exe")) or not launcher.is_file():
        raise ValueError("Missing Windows host or portable launcher")
    output.mkdir(parents=True)
    excluded = {"service.exe", "RuntimeBroker_rustdesk.exe"}
    if launcher.parent == runtime:
        excluded.add(launcher.name)
    shutil.copytree(runtime, output / "app", ignore=shutil.ignore_patterns(*excluded))
    shutil.copy2(launcher, output / "SubnetDesk.exe")
    (output / "userdata").mkdir()
    with zipfile.ZipFile(archive, "x", zipfile.ZIP_DEFLATED) as result:
        for path in sorted(output.rglob("*")):
            result.write(path, path.relative_to(output.parent))
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--launcher", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(package(args.runtime, args.launcher, args.output))
