"""Package the optional Windows 10+ x64 headless display driver.

These resources are installed only behind the runtime's Windows build 19041
gate. The pinned IDD DLL is not an application DLL loaded on Windows 7.
"""
import hashlib
from pathlib import Path
import urllib.request
import zipfile


URL = "https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip"
ARCHIVE_SHA256 = "629b51e9944762bae73948171c65d09a79595cf4c771a82ebc003fbba5b24f51"
FILES_SHA256 = {
    "usbmmIdd.inf": "a8750ca15a86742f3012886c9932bb974158cd2d9779cf891c730d976a47726a",
    "usbmmidd.cat": "470149c4cf9970ba59070aa7c9409c9f63a15727de99bab53e7e51f55310779f",
    "x64/usbmmIdd.dll": "dc135d675127113915a7e5aa9fe57c84edad6be41d0890b265ef124ab26ea9e3",
    "License.txt": "44c73fc4110979899dbb5054662de581f7d4350939f19bb2d50574f613314ba2",
    "idd_instructions.txt": "4928ad8aca39eec287d5ceaaf13f0e44a29f519821b495898692a62ece97c4c3",
}


def ensure_archive(path):
    path = Path(path)
    if not path.is_file():
        with urllib.request.urlopen(URL, timeout=60) as response:
            data = response.read(2 * 1024 * 1024)
        if hashlib.sha256(data).hexdigest() != ARCHIVE_SHA256:
            raise ValueError("Virtual display driver archive checksum mismatch")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    if hashlib.sha256(path.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise ValueError("Virtual display driver archive checksum mismatch")
    return path


def stage(archive, runtime):
    archive = ensure_archive(archive)
    with zipfile.ZipFile(archive) as source:
        payload = {name: source.read("usbmmidd_v2/" + name) for name in FILES_SHA256}
    # Validate the entire bundle before writing any of it into the runtime.
    for name, data in payload.items():
        if hashlib.sha256(data).hexdigest() != FILES_SHA256[name]:
            raise ValueError("Virtual display driver checksum mismatch: " + name)
    for name, data in payload.items():
        path = Path(runtime) / "usbmmidd_v2" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return validate(runtime)


def validate(runtime):
    for name, expected in FILES_SHA256.items():
        path = Path(runtime) / "usbmmidd_v2" / name
        if not path.is_file():
            raise ValueError("Missing virtual display driver file: usbmmidd_v2/" + name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError("Virtual display driver checksum mismatch: " + name)
    return {
        "minimum_windows_build": 19041,
        "source": URL,
        "archive_sha256": ARCHIVE_SHA256,
        "files": dict(FILES_SHA256),
    }


def is_optional_driver_dll(relative):
    return Path(relative).as_posix() == "usbmmidd_v2/x64/usbmmIdd.dll"
