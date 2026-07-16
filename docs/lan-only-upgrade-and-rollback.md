# LAN-only upgrade and rollback

## Upgrade

1. Back up the existing application configuration using operating-system permissions that restrict it to the owning user or service account.
2. Install the LAN-only native package while preserving the existing data directory.
3. Start the application. Historical device ID, server, relay, proxy, cloud state, and old remote-control password fields are sanitized and are not imported into LAN authentication.
4. Set a new LAN access username and password. The listener remains unavailable until both are configured.
5. Review listen addresses, port, allowed CIDRs, and discovery preference.
6. Record the displayed device fingerprint in an administrator-controlled inventory.
7. Reconnect each controller and verify the fingerprint out of band before trusting it.

The long-term device key is retained when the existing protected configuration can be read. A new key is generated only when no usable key exists, so normal upgrades do not create an unexplained trust change.

## Offline distribution

The application performs no public update check. Distribute signed installers through an internal package repository, removable media, device-management system, or operating-system package manager. Verify package hashes/signatures before deployment and stage rollout to a test device first.

## Rollback

1. Stop the LAN service and disconnect active sessions.
2. Copy the current protected configuration and device fingerprint to a restricted backup. Do not place configuration files in tickets, chat, or unencrypted shared storage.
3. Uninstall the LAN-only package without exporting credentials.
4. If the old version must be restored, use a separate old-version data directory or remove LAN-only credential fields before exposing the file to software that does not understand them.
5. Do not reuse the LAN access password as an old permanent device password.
6. Treat rollback as a device identity transition unless the old version can safely preserve the same private key. Controllers must verify any changed fingerprint.
7. After rollback, verify listening ports and outbound traffic before returning the device to service; older software may re-enable public discovery or update behavior.

## Credential or key compromise

- Change the LAN password immediately; the revision mechanism disconnects sessions authenticated with the old revision.
- Restrict allowed CIDRs or stop the service while investigating.
- If the private device key may be exposed, remove the protected key material, restart to generate a new identity, and distribute the new fingerprint out of band.
- Remove the old fingerprint from every controller trust registry.
