Based on rustdesk-org/rust-sciter commit 5322f3a755a0e6bf999fbc60d1efc35246c0f821 (dyn).
Retains its MIT license.

Local compatibility patches:
- Window, event and DOM state bit masks use transparent integer wrappers instead of invalid Rust enum values.
- Windows x86 video vtables use thiscall, matching upstream dyn_x86 commit 674e07d3066ca9a92ced3816203ab6b652629d1e.
- Both architectures share one local source, built with the current Win7 toolchain.
- Indexing keeps independently owned temporary Values behind a mutex, avoiding
  writes through a shared reference and preserving previously returned references.
- Unknown native behavior event codes and reasons stay integer values instead of creating invalid
  Rust enum discriminants.

`examples/win7_smoke.rs` runs against the exact shipped engine and exercises
array/map values, live indexed references, window creation and script-to-Rust
dispatch. CI runs it on both Windows architectures. This does not replace Win7
runtime acceptance, or a remote video rendering test of the x86 thiscall ABI.
