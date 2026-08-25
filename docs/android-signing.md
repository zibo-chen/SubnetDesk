# Android release signing

SubnetDesk release APKs must always use the same Android signing certificate. The release workflow refuses to publish when the signing credentials are incomplete, and verifies every signed APK against a pinned SHA-256 certificate fingerprint.

## Create the release key once

Keep the generated keystore in an encrypted, backed-up secret store. Losing it prevents future APK updates from being installed over existing releases.

```bash
keytool -genkeypair \
  -keystore subnetdesk-release.jks \
  -alias subnetdesk \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000
```

Do not commit the keystore or passwords. Do not generate a new key for each build.

## Configure GitHub Actions

Set these repository secrets:

- `ANDROID_SIGNING_KEY`: Base64-encoded contents of `subnetdesk-release.jks`.
- `ANDROID_ALIAS`: Keystore alias, for example `subnetdesk`.
- `ANDROID_KEY_STORE_PASSWORD`: Keystore password.
- `ANDROID_KEY_PASSWORD`: Private-key password.
- `ANDROID_SIGNING_CERT_SHA256`: Signing certificate SHA-256 fingerprint.

Generate the Base64 value:

```bash
base64 < subnetdesk-release.jks | tr -d '\n'
```

Read the pinned fingerprint:

```bash
keytool -list -v -keystore subnetdesk-release.jks -alias subnetdesk \
  | sed -n 's/^[[:space:]]*SHA256: //p'
```

The fingerprint may contain colons and may use either letter case. The workflow normalizes it before comparison.

## Rotation

Do not replace the keystore or fingerprint during ordinary releases. Android treats a package signed by another certificate as a different trust identity and will reject an in-place APK update. If rotation is unavoidable, plan it through the relevant app-store signing-key upgrade process before changing these secrets.
