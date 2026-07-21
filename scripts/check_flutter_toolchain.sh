#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

require_fixed() {
  local file=$1
  local needle=$2
  if ! grep -Fq "$needle" "$file"; then
    printf 'Missing required Flutter migration marker in %s: %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

reject_fixed() {
  local needle=$1
  shift
  if rg -F -q -- "$needle" "$@"; then
    printf 'Legacy Flutter/Windows compatibility marker remains: %s\n' "$needle" >&2
    exit 1
  fi
}

require_fixed .github/workflows/flutter-build.yml 'FLUTTER_VERSION: "3.44.1"'
require_fixed .github/workflows/flutter-build.yml 'ANDROID_FLUTTER_VERSION: "3.44.1"'
require_fixed .github/workflows/bridge.yml 'FLUTTER_VERSION: "3.44.1"'
require_fixed flutter/pubspec.yaml "sdk: '^3.12.0'"
require_fixed flutter/pubspec.yaml "flutter: '>=3.44.0'"
require_fixed flutter/pubspec.yaml 'extended_text: 15.0.2'
require_fixed flutter/windows/runner/runner.exe.manifest '<!-- Windows 10 and Windows 11 -->'
require_fixed flutter/macos/Podfile "platform :osx, '10.15'"
require_fixed flutter/macos/Runner/AppDelegate.swift 'applicationSupportsSecureRestorableState'

checked_files=(
  .github/workflows/bridge.yml
  .github/workflows/flutter-build.yml
  flutter/build_fdroid.sh
  flutter/build_ios.sh
  flutter/lib
  flutter/windows/runner/runner.exe.manifest
  build.py
)

reject_fixed '3.22.3' "${checked_files[@]}"
reject_fixed '3.24.5' "${checked_files[@]}"
reject_fixed 'rustdesk/engine/releases/download/main/windows-x64-release.zip' "${checked_files[@]}"
reject_fixed 'flutter_3.24.4_dropdown_menu_enableFilter.diff' "${checked_files[@]}"
reject_fixed 'apply_flutter_3.44_source_patches.sh' "${checked_files[@]}"
reject_fixed 'Windows 7' "${checked_files[@]}"
reject_fixed 'win7' "${checked_files[@]}"
reject_fixed 'kUseCompatibleUiMode' flutter/lib

printf 'Flutter 3.44.1 toolchain migration checks passed.\n'
