#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

failed=0
has_rg=0
if command -v rg >/dev/null 2>&1; then
  has_rg=1
fi

report_matches() {
  local title=$1
  local pattern=$2
  shift 2
  local output
  if [[ $has_rg -eq 1 ]]; then
    output=$(rg -n -i "$pattern" "$@" 2>/dev/null) || output=''
  else
    local -a pathspecs=()
    while [[ $# -gt 0 ]]; do
      if [[ $1 == --glob ]]; then
        shift
        if [[ $1 == !* ]]; then
          pathspecs+=(":(exclude)${1#!}")
        else
          pathspecs+=("$1")
        fi
      else
        pathspecs+=("$1")
      fi
      shift
    done
    output=$(git grep --recurse-submodules -n -i -P -e "$pattern" -- "${pathspecs[@]}" 2>/dev/null) || output=''
  fi
  if [[ -n $output ]]; then
    echo "LAN-only residual check failed: $title" >&2
    echo "$output" >&2
    failed=1
  fi
}

job_is_disabled() {
  local job=$1
  local workflow=$2
  if [[ $has_rg -eq 1 ]]; then
    local needle
    printf -v needle '%s:\n    if: ${{ false }}' "$job"
    rg -U -F -q "$needle" "$workflow"
  else
    awk -v job="$job" '
      {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)
      }
      line == job ":" {
        if (getline > 0) {
          sub(/^[[:space:]]*/, "", $0)
          sub(/[[:space:]]*$/, "", $0)
          if (index($0, "if: ${{ false }}") == 1) found = 1
        }
      }
      END { exit(found ? 0 : 1) }
    ' "$workflow"
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

if ! job_is_disabled build-for-windows-sciter .github/workflows/flutter-build.yml; then
  echo 'LAN-only residual check failed: legacy Windows UI release job is not disabled' >&2
  failed=1
fi

if ! job_is_disabled build-rustdesk-linux-sciter .github/workflows/flutter-build.yml; then
  echo 'LAN-only residual check failed: legacy Linux UI release job is not disabled' >&2
  failed=1
fi

if [[ $failed -ne 0 ]]; then
  exit 1
fi

echo 'LAN-only residual check passed.'
