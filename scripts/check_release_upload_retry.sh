#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/flutter-build.yml"
nightly_workflow="$repo_root/.github/workflows/flutter-nightly.yml"
uploader="$repo_root/scripts/upload_release_asset_with_retry.sh"

grep -Fq 'build-mobile: false' "$nightly_workflow"
grep -Fq 'bash scripts/upload_release_asset_with_retry.sh "$TAG_NAME" "subnetdesk-${VERSION}-${{ matrix.job.arch }}.dmg"' "$workflow"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == "release view" ]]; then
  exit 0
fi
if [[ "$1 $2" != "release upload" ]]; then
  echo "unexpected gh command: $*" >&2
  exit 2
fi
attempt=0
if [[ -f "$GH_STUB_STATE" ]]; then
  attempt="$(cat "$GH_STUB_STATE")"
fi
attempt=$((attempt + 1))
printf '%s' "$attempt" > "$GH_STUB_STATE"
if [[ "${GH_STUB_ALWAYS_FAIL:-false}" == "true" || "$attempt" -lt 3 ]]; then
  exit 1
fi
EOF
chmod +x "$test_dir/gh"

asset="$test_dir/subnetdesk-test-aarch64.dmg"
printf 'test asset' > "$asset"
state="$test_dir/attempts"

PATH="$test_dir:$PATH" \
GH_STUB_STATE="$state" \
RELEASE_UPLOAD_MAX_ATTEMPTS=4 \
RELEASE_UPLOAD_RETRY_DELAY_SECONDS=0 \
bash "$uploader" nightly "$asset"

[[ "$(cat "$state")" == "3" ]]

rm -f "$state"
if PATH="$test_dir:$PATH" \
  GH_STUB_STATE="$state" \
  GH_STUB_ALWAYS_FAIL=true \
  RELEASE_UPLOAD_MAX_ATTEMPTS=2 \
  RELEASE_UPLOAD_RETRY_DELAY_SECONDS=0 \
  bash "$uploader" nightly "$asset"; then
  echo "uploader unexpectedly succeeded after exhausting retries" >&2
  exit 1
fi

[[ "$(cat "$state")" == "2" ]]

echo "Release upload retry checks passed."
