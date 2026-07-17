<p align="center">
  <img src="res/subnetdesk-icon.svg" alt="SubnetDesk icon" width="128">
</p>

# SubnetDesk

SubnetDesk is a LAN/VPN-only fork of [RustDesk](https://github.com/rustdesk/rustdesk). This repository builds a native remote desktop client and host that does not use a device ID, rendezvous server, relay, NAT traversal, cloud account, cloud address book, proxy setting, or automatic public update service.

## Connect

On the controlled device:

1. Open LAN server settings.
2. Set the single access username and password.
3. Keep the default TCP port `21118`, or choose another port.
4. Optionally restrict listen addresses and allowed CIDR networks.
5. Verify that the service status is running and copy the displayed device fingerprint.

On the controller, enter:

- an endpoint such as `192.168.1.20`, `host.lan:21118`, or `[fd00::20]:21118`;
- the access username;
- the access password.

The first connection displays the controlled device fingerprint. Compare it with the value shown on that device before choosing **Trust and connect**. A later fingerprint change blocks automatic trust and requires explicit verification.

VPN products such as WireGuard, Tailscale, or OpenVPN only provide a routable address. The application still uses the same direct TCP protocol. Add the VPN CIDR to the allowed-network list when it is outside the default private, ULA, link-local, loopback, or CGNAT ranges.

## LAN performance and host sessions

New peer profiles default to 100% custom image quality and 60 FPS. SubnetDesk does not apply RustDesk's WAN-oriented delay-based bitrate or frame-rate downshifts to LAN/VPN sessions. A user can still select a lower quality or FPS, and decoder-capacity feedback remains active to prevent an overloaded controller from building an unbounded video queue.

After encrypted credential authentication, the controlled device runs the connection manager in headless mode. No separate incoming-connection window is created; the background manager remains responsible for session cleanup, file operations, chat transport, and other retained features.

## Security model

- A long-term Ed25519 device identity signs an ephemeral key exchange.
- Every application message after the handshake is encrypted and authenticated; there is no plaintext downgrade.
- Credentials are sent only after encryption and fingerprint verification.
- The host stores the password as an Argon2id PHC hash with a random salt.
- Unix configuration files are written with mode `0600`; Windows uses the application's per-user/service configuration location and inherited ACLs.
- Authentication has per-source exponential backoff, IPv6 prefix accounting, and a global Argon2 concurrency gate.
- Changing credentials increments a revision and disconnects sessions authenticated with the old revision.
- Client passwords are not written to peer history. Recent connections store endpoint, username, peer metadata, and device fingerprint only.

See [security details](docs/lan-only-security.md), the [regression matrix](docs/lan-only-regression-matrix.md), and [upgrade/rollback guidance](docs/lan-only-upgrade-and-rollback.md).

## Release targets

The LAN-only release targets native Flutter desktop and mobile clients. Web builds and deprecated Sciter builds are disabled in the release workflow. The optional plugin framework is not enabled in release commands.

Every push to `master` runs **SubnetDesk Installers CI** and uploads Windows x64/ARM64 MSI and portable EXE packages, macOS x86_64/ARM64 DMG packages, and Linux DEB/RPM/AppImage/Flatpak packages to the workflow run's **Artifacts** section. Ordinary branch CI does not create or modify a GitHub Release. Tag and nightly workflows publish the same packages to their configured prerelease after artifact generation. Packages are unsigned unless the repository signing secrets are configured.

For local native development, generate the Rust/Flutter bridge as described by the existing build tooling and build with the `flutter` feature. The release workflow remains the source of truth for platform-specific packaging commands.

## Verification

The source residual gate is:

```bash
scripts/check_lan_only_residuals.sh
```

The final implementation verification is one workspace `cargo check` followed by one workspace `cargo test`, after all implementation items are complete. Platform and hardware checks that cannot run on a single host are recorded separately in the regression matrix.

## Licensing and acceptable use

The repository retains its existing license files. Use remote-control functionality only on systems you own or are authorized to administer.
