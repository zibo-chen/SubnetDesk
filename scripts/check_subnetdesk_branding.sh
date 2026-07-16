#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

require_fixed() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Missing SubnetDesk branding in %s: %s\n' "$file" "$expected" >&2
    exit 1
  fi
}

require_fixed README.md '# SubnetDesk'
require_fixed Cargo.toml 'description = "SubnetDesk LAN/VPN Remote Desktop"'
require_fixed Cargo.toml 'ProductName = "SubnetDesk"'
require_fixed Cargo.toml 'identifier = "com.zibochen.subnetdesk"'
require_fixed libs/hbb_common/src/config.rs 'RwLock::new("SubnetDesk".to_owned())'
require_fixed libs/hbb_common/src/config.rs 'RwLock::new("com.zibochen".to_owned())'
require_fixed flutter/android/app/build.gradle 'applicationId "com.zibochen.subnetdesk"'
require_fixed flutter/android/app/src/main/res/values/strings.xml '<string name="app_name">SubnetDesk</string>'
require_fixed flutter/ios/Runner/Info.plist '<string>com.zibochen.subnetdesk</string>'
require_fixed flutter/ios/Runner/Info.plist '<string>subnetdesk</string>'
require_fixed flutter/macos/Runner/Configs/AppInfo.xcconfig 'PRODUCT_NAME = SubnetDesk'
require_fixed flutter/macos/Runner/Configs/AppInfo.xcconfig 'PRODUCT_BUNDLE_IDENTIFIER = com.zibochen.subnetdesk'
require_fixed flutter/windows/runner/Runner.rc 'VALUE "ProductName", "SubnetDesk"'
require_fixed flutter/linux/CMakeLists.txt 'set(APPLICATION_ID "com.zibochen.subnetdesk")'
require_fixed flatpak/rustdesk.json '"id": "com.zibochen.SubnetDesk"'
require_fixed flatpak/com.zibochen.SubnetDesk.metainfo.xml '<name>SubnetDesk</name>'
require_fixed res/rustdesk.desktop 'Name=SubnetDesk'
require_fixed res/rustdesk.service 'Description=SubnetDesk'
require_fixed .gitmodules 'https://github.com/zibo-chen/hbb_common.git'
require_fixed build.py 'Build/Products/Release/SubnetDesk.app'
require_fixed .github/workflows/flutter-build.yml 'Build/Products/Release/SubnetDesk.app'
require_fixed .github/workflows/flutter-build.yml 'subnetdesk-${{ env.VERSION }}'

if grep -Fq 'RustDesk.app' .github/workflows/flutter-build.yml; then
  printf 'Release workflow still references RustDesk.app\n' >&2
  exit 1
fi

for stale in \
  flutter/ios/Runner/GoogleService-Info.plist \
  flutter/ios/exportOptions.plist \
  flatpak/com.rustdesk.RustDesk.metainfo.xml \
  .github/workflows/fdroid.yml; do
  if [[ -e "$stale" ]]; then
    printf 'Stale upstream release file is still present: %s\n' "$stale" >&2
    exit 1
  fi
done

python3 scripts/generate_subnetdesk_icons.py --check
printf 'SubnetDesk branding and generated icons are consistent.\n'
