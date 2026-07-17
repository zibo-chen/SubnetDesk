#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

require_fixed() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Missing Linux service contract in %s: %s\n' "$file" "$expected" >&2
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

service_resource=res/subnetdesk.service
debian_scripts=(
  res/DEBIAN/preinst
  res/DEBIAN/postinst
  res/DEBIAN/prerm
)
rpm_specs=(
  res/rpm-flutter.spec
  res/rpm-flutter-suse.spec
  res/rpm.spec
  res/rpm-suse.spec
)
arch_files=(res/PKGBUILD res/pacman_install)
packaging_files=(build.py "${debian_scripts[@]}" "${rpm_specs[@]}" "${arch_files[@]}")

if [[ ! -f "$service_resource" ]]; then
  printf 'Missing canonical Linux systemd unit: %s\n' "$service_resource" >&2
  exit 1
fi
if [[ -e res/rustdesk.service ]]; then
  printf 'Legacy systemd unit source must be removed: res/rustdesk.service\n' >&2
  exit 1
fi

require_fixed "$service_resource" 'Description=SubnetDesk'
require_fixed "$service_resource" 'ExecStop=/usr/bin/pkill -f "rustdesk --"'
require_fixed res/DEBIAN/postinst '/usr/lib/systemd/system/subnetdesk.service'
require_fixed res/DEBIAN/postinst 'systemctl enable subnetdesk'
require_fixed res/DEBIAN/postinst 'systemctl start subnetdesk'
require_fixed res/DEBIAN/preinst 'systemctl stop subnetdesk'
require_fixed res/DEBIAN/prerm 'systemctl stop subnetdesk'
require_fixed res/DEBIAN/prerm 'systemctl disable subnetdesk'

for file in "${rpm_specs[@]}"; do
  require_fixed "$file" '$HBB/res/subnetdesk.service'
  require_fixed "$file" '/etc/systemd/system/subnetdesk.service'
  require_fixed "$file" 'systemctl enable subnetdesk'
  require_fixed "$file" 'systemctl start subnetdesk'
  require_fixed "$file" 'systemctl stop subnetdesk'
  require_fixed "$file" 'systemctl disable subnetdesk'
done

require_fixed res/PKGBUILD '$HBB/res/subnetdesk.service'
require_fixed res/pacman_install '/etc/systemd/system/subnetdesk.service'
require_fixed res/pacman_install 'systemctl enable subnetdesk'
require_fixed res/pacman_install 'systemctl start subnetdesk'
require_fixed res/pacman_install 'systemctl stop subnetdesk'
require_fixed res/pacman_install 'systemctl disable subnetdesk'

# Stopping/removing rustdesk.service is retained only as an upgrade migration.
# It must never be installed, enabled, or started by a SubnetDesk package.
reject_pattern 'res/rustdesk\.service' "${packaging_files[@]}"
reject_pattern 'cp .*rustdesk\.service .*/(etc|usr/lib)/systemd' "${packaging_files[@]}"
reject_pattern 'systemctl +(enable|start) +rustdesk([ .;]|$)' "${packaging_files[@]}"

printf 'Linux systemd service branding check passed.\n'
