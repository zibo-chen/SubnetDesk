# LAN-only regression matrix

This matrix separates repository-verifiable checks from tests that require multiple machines, platform permissions, installers, or VPN infrastructure. Do not convert a lab row to **Pass** without recording date, package hash, controller/host OS, and evidence location.

Latest repository verification: **2026-07-16**, macOS arm64. The final unified `cargo check --workspace --all-targets --features flutter` and `cargo test --workspace --features flutter` rerun passed after the real-UI fixes for IPv4-mapped IPv6 source handling and credential-bearing launch/window logging. The suite passed **170 tests**, failed none, and explicitly ignored one Enigo key-state test because it requires an interactive desktop plus input-injection permission. Flutter 3.24.5 analysis completed with no errors (existing warnings/info remain).

## Automated and source-level matrix

| Area | Case | Evidence | Status |
| --- | --- | --- | --- |
| Endpoint | IPv4 default/custom port, DNS, bracketed/bare IPv6 | `libs/hbb_common/src/lan.rs` tests | Pass |
| Endpoint | Empty, whitespace/control characters, invalid labels and ports | `libs/hbb_common/src/lan.rs` tests | Pass |
| Listener | Default private/CGNAT/ULA policy and custom CIDR normalization | `src/lan_server.rs` tests | Pass |
| Listener | IPv4-mapped IPv6 sources are canonicalized before allowlist/rate-limit handling | `src/lan_server.rs` mapped-address assertions and macOS dual-stack E2E | Pass |
| Transport | Direct TCP is the only connector | `Client::start`, `socket_client::connect_tcp_local`, residual gate | Implemented |
| Transport | Real loopback TCP handshake secures the stream and hides an application payload from the forwarding capture | `lan_protocol::tests::loopback_handshake_encrypts_application_payload` | Pass |
| Identity | Signed transcript binds version, both nonces, and ephemeral key | `src/lan_protocol.rs` tests | Pass |
| Identity | Tampered signature and replayed hello values fail | `src/lan_protocol.rs` tests | Pass |
| Authentication | Username/password validation and Argon2id verification | `libs/hbb_common` LAN tests | Pass |
| Authentication | Primary config stores an Argon2id PHC value, no plaintext marker, and Unix mode `0600` | `config::tests::lan_credentials_store_hash_only_with_owner_permissions` | Pass |
| Authentication | Per-source delay, IPv6 prefix keys, and global gate | `login_failure_check.rs`, connection tests | Pass |
| Migration | Old identity/auth/server/proxy options are cleared | `config.rs` sanitizer tests | Pass |
| Recent history | Same fingerprint follows address change; sort/remove | `config.rs` recent endpoint tests | Pass |
| Credential change | Revision mismatch closes active sessions | `server/connection.rs` timer path | Source verified |
| Release | No Web build, legacy jobs disabled, no public runtime symbols/options | `scripts/check_lan_only_residuals.sh` | Pass |
| Secret handling | Launch/window method logs cannot print credential-bearing argument payloads | Redacted Flutter/Rust logs plus `scripts/check_lan_only_residuals.sh` | Pass |
| Shared features | Desktop/file/camera/terminal/port-forward/RDP use `Client::start` | `docs/lan-only-baseline.md` | Source verified |

## Current macOS arm64 package and runtime evidence

The 2026-07-16 local release build used Flutter 3.24.5 and vcpkg baseline `120deac3062162151622ca4860575a33844ba10b`. The resulting `RustDesk.app` has `LSMinimumSystemVersion=12.3`; the app executable, embedded service, and Rust dynamic library are all arm64. `codesign --verify --deep --strict` passed after the build copied and re-signed the service. The unsigned/local bundle has the required client/server network entitlements; signed release CI applies `Release.entitlements` explicitly.

Artifact component SHA-256 values:

- `RustDesk.app/Contents/MacOS/RustDesk`: `49a19c32f5e14021c2538d7a5541189213b221198ac98e7d314dac8714bda685`
- `RustDesk.app/Contents/MacOS/service`: `682a88730f2d2a29b00992f174f149af6c143edac7b1653237c733c34f30d621`
- `RustDesk.app/Contents/Frameworks/liblibrustdesk.dylib`: `a7aa69975deeb629449049b3bb8c88783ef2a7a38d86ab36b08aa86c8b55fefd`
- Local test image `RustDesk-LAN-only-1.4.9-arm64-local.dmg`: `6cfbb808bed7105f784566cf0bd3fa94ed1cbbd525dd89f66ac1d952c78fac58`

The local DMG follows the release workflow's app-plus-`/Applications`-link layout. `hdiutil verify` passed, the image mounted read-only, and copying the app out with `ditto` produced a byte-identical bundle. Both the mounted and copied bundles passed `codesign --verify --deep --strict`; their three component hashes exactly matched the release bundle above, and the copied executable reported version `1.4.9`. A clean-HOME first launch from the copied app created `RustDesk.toml` with mode `0600`, left LAN credentials unset, exposed no TCP listener before credential setup, exposed only UDP discovery `*:21119`, and released that socket on stop. This local image is ad-hoc signed and is not Developer ID notarized; production signing/notarization and privileged installed-service behavior remain CI/device-lab requirements.

An isolated clean-HOME launch configured one LAN account and reached **LAN Ready**. The process exposed only TCP `*:21118` (listener) and UDP `*:21119` (discovery), with no outbound TCP socket. `RustDesk.toml` was mode `0600`, contained the Argon2id PHC and username, did not contain the plaintext password, and produced no serialization/storage error. After stopping and relaunching with the same HOME, LAN Ready and the username returned without re-entry, the listener/discovery ports returned, and the complete primary-config SHA-256 remained unchanged. This is local app-bundle evidence, not a substitute for the installer, two-host, VPN, firewall, or retained-feature platform labs below.

A real same-machine macOS UI E2E then connected through the release bundle to `127.0.0.1:21118`. The first connection stopped for explicit fingerprint confirmation; after trust, wrong credentials were rejected and correct credentials entered the full-access remote desktop with the recursive screen and toolbar visible. A second connection reused the same device trust without prompting. Changing the live listener to `22118` released `21118`, bound `22118`, retained UDP discovery on `21119`, and a connection to the custom endpoint again entered full access without a new fingerprint prompt. Changing the host password during that active session disconnected it, and the old password was rejected. Socket inspection throughout showed only the selected listener/discovery sockets and same-machine loopback TCP pairs, with no outbound TCP. Runtime and file-log searches found none of the E2E credentials or Argon2id hash, and the user independently confirmed that same-machine control was working. These results prove the macOS loopback product path, but do not replace two-host routing, VPN, packet-capture, installer, or other-platform evidence.

## Network lab matrix

| Case | Required setup | Pass condition | Status |
| --- | --- | --- | --- |
| IPv4 default port | Two LAN hosts | Desktop connects to `host-ip`, fingerprint and login succeed | Partial: macOS same-machine release E2E passed; two-host route not run |
| IPv4 custom port | Host configured to non-default port | All selected session types connect to `host-ip:port` | Partial: live rebind and macOS same-machine desktop E2E passed; two-host/other session types not run |
| IPv6 ULA | Routed IPv6 LAN/VPN | Bracketed endpoint connects; unallowed source is rejected | Not run |
| Internal DNS/mDNS | Local resolver entry | Hostname resolves without public DNS and connects | Not run |
| WireGuard | Routed VPN CIDR | Direct TCP works with internet route removed | Not run |
| Tailscale/CGNAT | `100.64.0.0/10` path | Direct TCP works under default allowlist | Not run |
| OpenVPN/custom CIDR | Non-default VPN range | Rejected before configuration; accepted after explicit CIDR | Not run |
| Offline LAN | Block WAN at router/firewall | Install/configure/discover/connect/operate with no WAN packets | Not run |
| Idle egress | Application idle for 15 minutes | No DNS or WAN connection attempt | Not run |
| Session egress | Exercise every retained feature | Only LAN/VPN peer and user-requested port-forward destinations appear | Not run |

Suggested packet capture on the controller:

```bash
sudo tcpdump -i <interface> -nn -s0 -w lan-session.pcap 'tcp port 21118 or udp port 21119'
```

Capture a failed login and a successful desktop/file-transfer session. Confirm that plaintext searches do not reveal the access username, password, clipboard sample, test filename, or visible screen text. Also capture all non-local traffic with the platform firewall or packet tool and verify that the core application opens none.

## Authentication and identity lab matrix

| Case | Pass condition | Status |
| --- | --- | --- |
| Correct credentials | Immediate full-feature login | Pass in macOS same-machine release E2E; other platforms not run |
| Wrong username/password | Same generic error; no user enumeration | Partial: wrong password rejected in macOS E2E; wrong-username UI comparison not run |
| Empty/oversized/control input | Rejected before session setup | Automated input coverage; UI lab not run |
| Repeated failures | Increasing bounded `retry_after`; client respects countdown | Not run |
| Concurrent attempts | At most two Argon2 checks; excess gets busy response | Source verified; load test not run |
| IPv6 address rotation | Prefix counters prevent bypass | Source verified; routed IPv6 test not run |
| Credential change | Existing session closes and old credential fails | Pass in macOS same-machine release E2E; other platforms not run |
| First-use fingerprint | User must explicitly trust after out-of-band comparison | Pass in macOS same-machine release E2E; two-host comparison not run |
| Address change, same key | Existing fingerprint follows new endpoint | Pass for 21118 to 22118 in macOS same-machine UI E2E plus automated registry coverage |
| Device key replacement | Connection stops at changed-fingerprint warning | Not run |
| MITM/downgrade | Invalid signature/version or unencrypted login is rejected | Automated protocol coverage; live MITM not run |

## Retained feature matrix

Run each row over the same authenticated LAN connector on every claimed release platform.

| Feature | Windows | macOS | Linux X11 | Linux Wayland | Android host/client |
| --- | --- | --- | --- | --- | --- |
| Screen and keyboard/mouse | Not run | Partial: same-machine full-access desktop and user control check passed | Not run | Not run | Not run |
| Multi-display, resolution, quality, scaling | Not run | Not run | Not run | Not run | Not run |
| Audio | Not run | Not run | Not run | Not run | Not run |
| Text and file clipboard | Not run | Not run | Not run | Not run | Not run |
| File manager/transfer | Not run | Not run | Not run | Not run | Not run |
| Chat and voice call | Not run | Not run | Not run | Not run | Not run |
| Camera | Not run | Not run | Not run | Not run | Not run |
| Port forwarding and RDP tunnel | Not run | Not run | Not run | Not run | N/A or Not run |
| Terminal | Not run | Not run | Not run | Not run | Not run |
| Restart/reconnect | Not run | Not run | Not run | Not run | Not run |
| Recording/privacy/block input | Not run | Not run | Not run | Not run | Not run |
| Printing/whiteboard/virtual display | Not run | Not run | Not run | Not run | N/A or Not run |
| Lock/system actions | Not run | Not run | Not run | Not run | Not run |
| Multi-window/tabs/recent/discovery | Not run | Partial: additional remote window and recent endpoint card observed; discovery not exercised | Not run | Not run | Not run |
| Concurrent session types | Not run | Not run | Not run | Not run | Not run |

## Lifecycle and packaging matrix

| Case | Evidence required | Status |
| --- | --- | --- |
| Fresh install | Installer log, config permissions/ACL, first credential setup | Partial: local macOS DMG verify/mount/copy/clean-HOME launch and mode `0600` passed; Developer ID notarization and privileged service install not run |
| Upgrade from locked baseline | Sanitized old config, stable or explicitly changed fingerprint | Not run |
| Service start/stop/restart/rebind | Port ownership before and after every transition | Partial: macOS app stop/relaunch restored 21118/21119 and live config rebind moved 21118 to 22118; installed-service lifecycle not run |
| Host reboot | Service recovery and client reconnect prompt | Not run |
| Client crash/network loss | Resource cleanup and bounded reconnect behavior | Not run |
| Uninstall/reinstall | No accidental credential/key disclosure | Not run |
| Rollback | Separate protected data and verified outbound behavior | Not run |
| Windows service/UAC/lock screen | Screen/input continuity and ACL inspection | Not run |
| macOS permissions | Screen recording and Accessibility prompts/capabilities | Partial: bundle entitlements/signature and launch passed; Screen Recording/Accessibility feature lab not run |
| Linux X11/Wayland | Session/portal behavior and service ownership | Not run |
| Android permissions | Capture, Accessibility, audio, file access, clipboard | Not run |
