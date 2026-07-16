# LAN-only residual allowlist

The residual gate intentionally excludes only the following non-release or migration surfaces.
Every exclusion has a bounded reason; adding another exclusion requires updating this file.

| Path | Allowed residual | Reason |
| --- | --- | --- |
| `libs/hbb_common/src/protos/**` | `rendezvous` protobuf module and `ConnType` naming | The shared wire schema still owns session type enums and the `PeerDiscovery` envelope. The LAN runtime does not execute server discovery, relay, or hole punching. |
| `src/lan.rs` and imports of `rendezvous_proto::ConnType` | `RendezvousMessage`, `PeerDiscovery`, `ConnType` | LAN discovery reuses the historical protobuf envelope; connection establishment always parses an `Endpoint` and opens direct TCP. |
| `libs/hbb_common/src/config.rs` and `config/**` | Historical server, proxy, device-ID, and permanent-password fields | These fields are deserialize-only upgrade inputs. `sanitize_lan_only()` clears them and public option getters reject them. They are not connection inputs. |
| `src/lang/**` | Historical translations | Catalog keys are retained to avoid destructive localization churn and are not runtime network behavior. |
| `src/ui.rs`, `src/ui/**` | Deprecated Sciter UI strings | Sciter release jobs are hard-disabled. The native Flutter UI is the only desktop/mobile release surface. |
| `flutter/lib/web/**` | Historical Web bridge methods | Web builds are absent from release workflows and `main.dart` shows an unsupported target page. Browser TCP support is outside this release. |
| `src/plugin/**`, `src/hbbs_http*`, `flutter/lib/plugin/**` | User-installed plugin HTTP support | `plugin_framework` is optional and is not enabled by any LAN-only release command. It is not used by the core runtime. |

Build-time dependency downloads in CI are not runtime network behavior and are outside the source gate.
