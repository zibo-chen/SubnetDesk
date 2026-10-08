#!/usr/bin/env python3
"""Verify a completed Win7 Actions build and publish its prerelease assets."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

import audit_win7_pe


def gh_json(*args):
    return json.loads(subprocess.check_output(["gh", *args], text=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"\d+", args.run_id) or not re.fullmatch(r"[0-9a-f]{40}", args.commit):
        parser.error("Require a numeric Actions run ID and full source commit SHA")
    if not re.fullmatch(r"win7-test-\d{8}(?:-[A-Za-z0-9.-]+)?", args.tag):
        parser.error("Require a win7-test-YYYYMMDD test tag")
    repo = "zibo-chen/SubnetDesk"
    run = gh_json("run", "view", args.run_id, "--repo", repo, "--json",
                  "databaseId,status,conclusion,headSha,jobs,url")
    if run["headSha"] != args.commit or run["status"] != "completed" or run["conclusion"] != "success":
        raise RuntimeError("Source build must have succeeded for the requested commit")
    if {j["name"] for j in run["jobs"]} != {"win7 (x64)", "win7 (x86)"}:
        raise RuntimeError("Require both architecture jobs")
    if any(j["conclusion"] != "success" for j in run["jobs"]):
        raise RuntimeError("Both architecture jobs must succeed")
    output = args.artifacts / "release"
    output.mkdir(parents=True, exist_ok=True)
    assets = []
    for arch in ("x64", "x86"):
        packages = list(args.artifacts.glob(f"subnetdesk-*-win7-{arch}.zip"))
        if len(packages) != 1:
            raise RuntimeError(f"Require exactly one {arch} ZIP")
        package = packages[0]
        name = package.stem
        report = json.loads((args.artifacts / f"{name}-imports.json").read_text())
        if len(report) != 5 or any(r.get("errors") for r in report):
            raise RuntimeError(f"{arch} PE report failed")
        with tempfile.TemporaryDirectory() as directory:
            payload = Path(directory)
            with zipfile.ZipFile(package) as archive:
                if any(Path(m.filename).name != m.filename for m in archive.infolist()):
                    raise RuntimeError("Unexpected package paths")
                required = {"rustdesk.exe", "service.exe", "sciter.dll", "sciter-license.htm",
                            "sciter-bindings-license.txt", "material-icons-license.txt", "material-icons-notice.txt"}
                if not required.issubset(archive.namelist()):
                    raise RuntimeError("Missing package files or licenses")
                archive.extractall(payload)
            paths = [payload / f for f in ("rustdesk.exe", "service.exe", "sciter.dll")]
            paths += [args.artifacts / f"{name}.exe", args.artifacts / f"{name}-sciter-smoke.exe"]
            for path in paths:
                errors = audit_win7_pe.violations(audit_win7_pe.inspect(path), arch)
                if errors:
                    raise RuntimeError(f"{path.name}: {errors}")
        for suffix in (".exe", ".zip", "-imports.json"):
            destination = output / f"{name}{suffix}"
            shutil.copyfile(args.artifacts / destination.name, destination)
            assets.append(destination)
        print(f"{arch}: package contents and five PE files verified", flush=True)
    provenance = output / "github-ci-build.json"
    provenance.write_text(json.dumps(run, indent=2) + "\n", encoding="utf-8")
    assets.append(provenance)
    checksums = output / "SHA256SUMS.txt"
    checksums.write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n"
                                for p in sorted(assets)), encoding="utf-8")
    assets.append(checksums)
    notes = output / "release-notes.md"
    notes.write_text(args.notes.read_text(encoding="utf-8")
                     + f"\n构建记录：{run['url']}\n源码提交：{args.commit}\n", encoding="utf-8")
    # A rerun after an unknown upload outcome must recover the same publication.
    existing = subprocess.run(["gh", "release", "view", args.tag, "--repo", repo,
                               "--json", "url,isPrerelease,targetCommitish,assets"],
                              capture_output=True, text=True)
    if existing.returncode == 0:
        release = json.loads(existing.stdout)
        expected = {p.name: "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest() for p in assets}
        remote = gh_json("api", f"repos/{repo}/releases/tags/{args.tag}")
        actual = {p["name"]: p.get("digest") for p in remote["assets"]}
        if not release["isPrerelease"] or release["targetCommitish"] != args.commit or actual != expected:
            raise RuntimeError("Existing test release differs; refusing to replace it")
        print(release["url"])
        return
    subprocess.run(["gh", "release", "create", args.tag, "--repo", repo,
                    "--target", args.commit, "--prerelease", "--latest=false",
                    "--title", "SubnetDesk Win7 测试版 — " + args.tag,
                    "--notes-file", str(notes), *(str(p) for p in assets)], check=True)


if __name__ == "__main__":
    main()
