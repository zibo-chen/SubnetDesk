#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 "$ROOT/scripts/generate_subnetdesk_icons.py"
