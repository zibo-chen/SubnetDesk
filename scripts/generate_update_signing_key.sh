#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <output-directory>" >&2
  exit 2
fi

output_dir=$1
mkdir -p "$output_dir"
private_key="$output_dir/subnetdesk-update-private.pem"
public_key="$output_dir/subnetdesk-update-public.hex"

if [[ -e $private_key || -e $public_key ]]; then
  echo "refusing to overwrite an existing update key" >&2
  exit 1
fi

if openssl genpkey -algorithm ED25519 -out "$private_key" 2>/dev/null; then
  openssl pkey -in "$private_key" -pubout -outform DER \
    | tail -c 32 \
    | xxd -p -c 64 > "$public_key"
else
  rm -f "$private_key"
  python3 - "$private_key" "$public_key" <<'PY'
import pathlib
import sys

try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
except ImportError as exc:
    raise SystemExit(
        "OpenSSL does not support Ed25519 and Python cryptography is unavailable"
    ) from exc

private_path = pathlib.Path(sys.argv[1])
public_path = pathlib.Path(sys.argv[2])
key = Ed25519PrivateKey.generate()
private_path.write_bytes(
    key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
)
public_path.write_text(
    key.public_key()
    .public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    .hex()
    + "\n",
    encoding="ascii",
)
PY
fi
chmod 600 "$private_key"

echo "Private key: $private_key"
echo "Public key:  $public_key"
echo "Store the base64-encoded private PEM as SUBNETDESK_UPDATE_SIGNING_KEY_B64."
echo "Store the public hex value as SUBNETDESK_UPDATE_PUBLIC_KEY."
