#!/usr/bin/env bash
set -euo pipefail

# https://docs.flutter.dev/deployment/ios
# flutter build ipa --release --obfuscate --split-debug-info=./split-debug-info
# no obfuscate, because no easy to check errors
flutter build ipa --release
