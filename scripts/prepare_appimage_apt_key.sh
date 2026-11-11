#!/usr/bin/env bash
set -euo pipefail

# Use Ubuntu's installed archive keys instead of relying on a public keyserver.
gpg --batch --no-options --no-default-keyring \
  --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg \
  --armor --export > /tmp/subnetdesk-ubuntu-archive.asc
test -s /tmp/subnetdesk-ubuntu-archive.asc
