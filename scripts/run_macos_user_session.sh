#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
native_root=${SUBNETDESK_NATIVE_ROOT:-"$repo_root/target/local-native-deps"}
bash scripts/prepare_macos_native_deps.sh
VCPKG_ROOT="$native_root" VCPKG_INSTALLED_ROOT="$native_root" \
  cargo build --locked --lib --features flutter,software-update

cd flutter
flutter pub get
# Xcode 27 requires a macOS 12+ deployment target for local builds.
# Release CI can override this while using its own SDK/native dependency set.
FLUTTER_XCODE_MACOSX_DEPLOYMENT_TARGET="${SUBNETDESK_MACOS_DEPLOYMENT_TARGET:-12.0}" \
FLUTTER_XCODE_ARCHS="$(uname -m)" FLUTTER_XCODE_ONLY_ACTIVE_ARCH=YES \
FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=com.zibochen.subnetdesk.preview \
  flutter build macos --debug --no-pub
cd "$repo_root"
preview_root="$repo_root/target/user-session-preview"
preview_app="$preview_root/SubnetDesk Portable.app"
mkdir -p "$preview_root"
ditto flutter/build/macos/Build/Products/Debug/SubnetDesk.app "$preview_app"
/usr/libexec/PlistBuddy -c 'Set CFBundleIdentifier com.zibochen.subnetdesk.portable-preview' "$preview_app/Contents/Info.plist"
codesign --force --sign - --deep "$preview_app"
codesign --verify --deep --strict "$preview_app"
touch "$preview_root/portable"
echo "Preview application: $preview_app"
if [[ ${1:-} != --build-only ]]; then
  open "$preview_app"
fi
