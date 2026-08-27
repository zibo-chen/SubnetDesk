#!/usr/bin/env bash
set -euo pipefail

sed -n -E \
  's/^.*certificate SHA-256 digest:[[:space:]]*([0-9A-Fa-f]{64})[[:space:]]*$/\1/p' \
  | head -n 1
