#!/usr/bin/env bash
# Package a device build for users to sign with their own Apple account.
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <device.app> <output.ipa>" >&2
  exit 2
fi

app_path="$1"
output_path="$2"
if [[ ! -d "$app_path" || "$app_path" != *.app || "$output_path" != *.ipa ]]; then
  echo "expected an existing .app directory and an .ipa output path" >&2
  exit 2
fi

# Reject simulator builds and incomplete bundles before creating a release asset.
python3 - "$app_path" <<'PY'
import plistlib
from pathlib import Path
import sys

app = Path(sys.argv[1])
with (app / "Info.plist").open("rb") as source:
    info = plistlib.load(source)
if info.get("DTPlatformName") != "iphoneos":
    sys.exit("An iPhoneOS device build is required; simulator builds cannot be sideloaded")
executable = app / info.get("CFBundleExecutable", "")
if not executable.is_file():
    sys.exit("The app executable is missing")
PY

mkdir -p "$(dirname "$output_path")"
output_path="$(cd "$(dirname "$output_path")" && pwd)/$(basename "$output_path")"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT
mkdir "$staging_dir/Payload"
ditto --norsrc --noextattr "$app_path" "$staging_dir/Payload/$(basename "$app_path")"

# Flutter's engine or embedded frameworks may retain signatures even with
# --no-codesign. Strip them from the copy, leaving the original build untouched.
while IFS= read -r -d '' bundle; do
  if codesign -d "$bundle" >/dev/null 2>&1; then
    codesign --remove-signature "$bundle"
  fi
done < <(find "$staging_dir/Payload" -depth \( -name '*.app' -o -name '*.appex' -o -name '*.framework' -o -name '*.dylib' \) -print0)
find "$staging_dir/Payload" -name embedded.mobileprovision -type f -delete
find "$staging_dir/Payload" -name _CodeSignature -type d -prune -exec rm -rf {} +

ditto -c -k --norsrc --noextattr --keepParent "$staging_dir/Payload" "$staging_dir/unsigned.ipa"
unzip -tq "$staging_dir/unsigned.ipa"
mv "$staging_dir/unsigned.ipa" "$output_path"
echo "Packaged unsigned IPA: $output_path"
