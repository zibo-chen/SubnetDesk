#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <release-tag> <asset-path>" >&2
  exit 2
fi

release_tag="$1"
asset_path="$2"
max_attempts="${RELEASE_UPLOAD_MAX_ATTEMPTS:-5}"
retry_delay_seconds="${RELEASE_UPLOAD_RETRY_DELAY_SECONDS:-5}"

if [[ ! -s "$asset_path" ]]; then
  echo "release asset is missing or empty: $asset_path" >&2
  exit 2
fi

if ! [[ "$max_attempts" =~ ^[1-9][0-9]*$ ]]; then
  echo "RELEASE_UPLOAD_MAX_ATTEMPTS must be a positive integer" >&2
  exit 2
fi

if ! [[ "$retry_delay_seconds" =~ ^[0-9]+$ ]]; then
  echo "RELEASE_UPLOAD_RETRY_DELAY_SECONDS must be a non-negative integer" >&2
  exit 2
fi

gh_args=(release upload "$release_tag" "$asset_path" --clobber)
release_view_args=(release view "$release_tag")
release_create_args=(release create "$release_tag" --prerelease --title "$release_tag")
if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  gh_args+=(--repo "$GITHUB_REPOSITORY")
  release_view_args+=(--repo "$GITHUB_REPOSITORY")
  release_create_args+=(--repo "$GITHUB_REPOSITORY")
fi
if [[ -n "${GITHUB_SHA:-}" ]]; then
  release_create_args+=(--target "$GITHUB_SHA")
fi

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  echo "Uploading $(basename "$asset_path") to $release_tag (attempt $attempt/$max_attempts)"
  release_ready=false
  if gh "${release_view_args[@]}" >/dev/null 2>&1; then
    release_ready=true
  elif gh "${release_create_args[@]}"; then
    release_ready=true
  elif gh "${release_view_args[@]}" >/dev/null 2>&1; then
    # Another matrix job may have created the release concurrently.
    release_ready=true
  fi

  if [[ "$release_ready" == "true" ]] && gh "${gh_args[@]}"; then
    exit 0
  fi

  if [[ "$attempt" -eq "$max_attempts" ]]; then
    echo "release upload failed after $max_attempts attempts" >&2
    exit 1
  fi

  sleep "$((retry_delay_seconds * attempt))"
done
