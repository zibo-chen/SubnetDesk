# SubnetDesk automatic updates

Automatic updates are supported for Flutter desktop builds on Windows and
macOS. Stable installers remain hosted in GitHub Releases. The client trusts a
small, Ed25519-signed `update-stable.json` manifest rather than trusting release
filenames or HTTPS alone.

## Configure release signing

Generate the update signing key on an offline or otherwise trusted machine:

```bash
scripts/generate_update_signing_key.sh /secure/output/directory
```

The helper uses OpenSSL 3 when available and otherwise falls back to Python's
`cryptography` package.

Configure these GitHub Actions secrets:

- `SUBNETDESK_UPDATE_SIGNING_KEY_B64`: Base64 of the complete private PEM file.
- `SUBNETDESK_UPDATE_PUBLIC_KEY`: The 64-character public-key hex value.

For example, generate the private-key secret locally without printing it in CI:

```bash
base64 < /secure/output/directory/subnetdesk-update-private.pem | tr -d '\n'
```

Back up the private key securely. Losing it prevents existing clients from
trusting future manifests. Do not commit it to this repository.

`SUBNETDESK_UPDATE_PUBLIC_KEY` is embedded into release builds. A build without
that value remains functional but reports that automatic updates are not
configured. Stable releases without the update-signing or desktop
code-signing secrets still publish their normal installers, but skip
`update-stable.json` and in-app update delivery.

The desktop build enables the Cargo `software-update` feature through
`build.py --flutter` and `flutter/run.sh`. Mobile builds intentionally omit it.

## Release flow

When all update and desktop code-signing secrets are configured, the release
workflow runs these additional steps after the Windows and macOS assets have
been uploaded:

1. Downloads the release's MSI, EXE, and DMG assets.
2. Calculates their sizes and SHA-256 hashes.
3. Generates a deterministic `update-stable.json` manifest.
4. Signs the exact manifest bytes with Ed25519.
5. Uploads `update-stable.json` and `update-stable.json.sig` to the release.

The signature file contains the raw 64-byte Ed25519 signature encoded as hex.
Clients also verify Authenticode on Windows and code signing/Gatekeeper on
macOS before starting an installer.

Signed update-manifest publication therefore also requires the repository's
Windows signing service secrets and macOS Developer ID/notarization secrets.
Without them, the regular release remains available through GitHub Releases,
while in-app update delivery stays disabled. Unsigned local builds can exercise
the UI and manifest checks, but they cannot install a release package through
the automatic updater.

## Custom update origin

Enterprise builds can set `SUBNETDESK_UPDATE_MANIFEST_URL` at compile time. It
must be a plain HTTPS URL. The adjacent signature is read from the same URL with
`.sig` appended. Artifact URLs may point to an internal HTTPS server, but their
size and SHA-256 values remain covered by the signed manifest.
