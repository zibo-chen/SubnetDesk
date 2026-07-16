#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

failed=0

report_matches() {
  local title=$1
  local pattern=$2
  shift 2
  local output
  if output=$(rg -n -i "$pattern" "$@" 2>/dev/null); then
    echo "LAN-only residual check failed: $title" >&2
    echo "$output" >&2
    failed=1
  fi
}

release_globs=(
  --glob '!src/lang/**'
  --glob '!src/ui/**'
  --glob '!src/ui.rs'
  --glob '!src/plugin/**'
  --glob '!src/hbbs_http.rs'
  --glob '!src/hbbs_http/**'
  --glob '!flutter/lib/web/**'
  --glob '!flutter/lib/plugin/**'
  --glob '!libs/hbb_common/src/protos/**'
  --glob '!libs/hbb_common/src/config.rs'
  --glob '!libs/hbb_common/src/config/**'
)

release_paths=(src flutter/lib libs/hbb_common/src Cargo.toml)

report_matches \
  'hard-coded RustDesk public runtime URL' \
  "['\"]https?://[^'\"]*(rustdesk\\.(com|net)|api\\.github\\.com/repos/rustdesk)" \
  "${release_globs[@]}" "${release_paths[@]}"

report_matches \
  'public discovery, relay, or fallback transport symbol in release code' \
  '\b(RendezvousMediator|request_relay|create_relay|new_direct_udp_for|get_rendezvous_server|test_nat_type|KcpStream|WebSocketStream|WebRtcStream)\b' \
  "${release_globs[@]}" "${release_paths[@]}"

report_matches \
  'public server option read or write in release code' \
  '(get_option|set_option)[^(]*\([^\n]*(id-server|rendezvous-server|relay-server|api-server|proxy-url|force-always-relay|access-token)' \
  "${release_globs[@]}" "${release_paths[@]}"

report_matches \
  'removed public server CI environment variable' \
  '\b(RENDEZVOUS_SERVER|API_SERVER|RS_PUB_KEY)\b' \
  .github/workflows

report_matches \
  'Web release build' \
  'flutter[[:space:]]+build[[:space:]]+web|build-web' \
  .github/workflows build.py

report_matches \
  'plugin framework enabled in a release command' \
  '(--features|--feature)[^\n]*plugin_framework' \
  .github/workflows build.py

report_matches \
  'raw credential-bearing launch or window arguments in logs' \
  '(launch args:.*\$args|with args .*call\.arguments|android msg.*\$arguments|debugPrint\([^\n]*call\.arguments|Wrong command:.*args)' \
  flutter/lib src/ui.rs

for removed in \
  src/rendezvous_mediator.rs \
  src/kcp_stream.rs \
  src/updater.rs \
  src/custom_server.rs \
  libs/hbb_common/src/proxy.rs \
  libs/hbb_common/src/udp.rs \
  libs/hbb_common/src/websocket.rs \
  libs/hbb_common/src/webrtc.rs
do
  if [[ -e "$removed" ]]; then
    echo "LAN-only residual check failed: removed file exists: $removed" >&2
    failed=1
  fi
done

if ! rg -U -q 'build-for-windows-sciter:\n    if: \$\{\{ false \}\}' .github/workflows/flutter-build.yml; then
  echo 'LAN-only residual check failed: legacy Windows UI release job is not disabled' >&2
  failed=1
fi

if ! rg -U -q 'build-rustdesk-linux-sciter:\n    if: \$\{\{ false \}\}' .github/workflows/flutter-build.yml; then
  echo 'LAN-only residual check failed: legacy Linux UI release job is not disabled' >&2
  failed=1
fi

if [[ $failed -ne 0 ]]; then
  exit 1
fi

echo 'LAN-only residual check passed.'
