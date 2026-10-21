#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

require_fixed() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Missing Linux packaging contract in %s: %s\n' "$file" "$expected" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  shift
  if rg -n -- "$pattern" "$@"; then
    printf 'Legacy RustDesk service activation remains in Linux packaging.\n' >&2
    exit 1
  fi
}

packaging_files=(build.py res/DEBIAN/postinst res/rpm-flutter.spec res/rpm-flutter-suse.spec res/rpm.spec res/rpm-suse.spec res/PKGBUILD res/pacman_install)
require_fixed build.py 'Package: subnetdesk'
require_fixed flutter/linux/CMakeLists.txt 'set(BINARY_NAME "subnetdesk")'
require_fixed res/rustdesk.desktop 'Exec=subnetdesk %u'
require_fixed res/rustdesk.desktop 'Icon=subnetdesk'
if [[ -e res/subnetdesk.service ]]; then
  echo 'The user-session application must not ship a system service' >&2
  exit 1
fi
reject_pattern 'systemctl +(enable|start) +subnetdesk' "${packaging_files[@]}"
reject_pattern 'res/subnetdesk\.service' build.py res/rpm-flutter.spec res/rpm-flutter-suse.spec res/rpm.spec res/rpm-suse.spec res/PKGBUILD
reject_pattern 'res/rustdesk\.service' "${packaging_files[@]}"
reject_pattern 'cp .*rustdesk\.service .*/(etc|usr/lib)/systemd' "${packaging_files[@]}"
reject_pattern 'systemctl +(enable|start|stop|disable) +rustdesk([ .;]|$)' "${packaging_files[@]}"
reject_pattern '/usr/bin/rustdesk' res/DEBIAN/postinst res/DEBIAN/prerm res/rpm-flutter.spec res/rpm-flutter-suse.spec res/rpm.spec res/rpm-suse.spec res/PKGBUILD res/pacman_install
reject_pattern '/usr/share/rustdesk' "${packaging_files[@]}"
reject_pattern 'Package: rustdesk' build.py
reject_pattern '^Name: +rustdesk$' res/rpm-flutter.spec res/rpm-flutter-suse.spec res/rpm.spec res/rpm-suse.spec
reject_pattern '^pkgname=rustdesk$' res/PKGBUILD

printf 'Linux user-session packaging check passed.\n'
