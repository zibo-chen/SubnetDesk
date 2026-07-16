# LAN-only implementation baseline

## Locked source state

- Root repository baseline: `cf2b28faf934fedb498c33b9746cd289426d8645`
- `libs/hbb_common` baseline: `7e1c392c62d39c364127307cd408421dd5f8cfb0`
- Default native LAN port: TCP `21118`
- LAN discovery port: UDP `21119`

The existing remote feature implementations were intentionally left in place. The change replaces discovery, connection establishment, device identity, and application authentication before those services receive a session.

## Shared connection entry evidence

All retained connection types enter through the same encrypted LAN connector:

| Connection type | Entry |
| --- | --- |
| Remote desktop | `src/client/io_loop.rs` -> `Client::start()` |
| File transfer | `src/client/io_loop.rs` -> `Client::start()` |
| Camera view | `src/client/io_loop.rs` -> `Client::start()` |
| Terminal | `src/client/io_loop.rs` -> `Client::start()` |
| Port forwarding | `src/port_forward.rs` -> `Client::start()` |
| RDP tunnel | `src/port_forward.rs` -> `Client::start()` |

`Client::start()` now accepts only a validated `Endpoint`, opens direct TCP, and completes the signed LAN handshake. After fingerprint confirmation, every type sends the same `LanLoginRequest`. The server authenticates first and then selects the requested session scope without an application permission matrix or click-to-approve step.

## Historical plaintext evidence

At the locked baseline, `Client::secure_connection()` returned successfully after sending an empty message when `signed_id_pk` was absent or invalid. Direct IP connections could therefore continue without a session key. The baseline source at `src/client.rs` lines 759-792 is the reproducible evidence for the removed downgrade path.

The LAN-only protocol has no equivalent branch: an invalid version, nonce, device key, signature, ephemeral key, or encrypted key exchange returns an error and closes the connection. Tests cover transcript binding, signature tampering, and replayed hello data. A live packet-capture procedure for a two-device lab is included in the regression matrix.

## Build and product boundary

- Native Flutter desktop/mobile are release targets.
- Web has no release job and does not attempt to reuse the removed public connection path.
- Deprecated Sciter jobs are explicitly disabled.
- `plugin_framework` is optional and absent from LAN-only release commands.
- Core runtime options sanitize historical server, relay, proxy, account, and old-password inputs on load.

Repository verification commands and expected native artifacts:

```bash
cargo check --workspace --all-targets --features flutter
cargo test --workspace --features flutter
cd flutter && flutter analyze --no-pub
```

The release workflow builds native Flutter desktop/mobile packages only. Platform-specific installer artifacts remain those produced by `.github/workflows/flutter-build.yml`; Web and Sciter artifacts are intentionally absent. The locked baseline is preserved as source evidence rather than rebuilt after the LAN-only changes.
