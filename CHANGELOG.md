# Changelog

All notable SubnetDesk changes are documented in this file.

## [1.3.0] - 2026-08-27

### Added

- Added signed in-app updates for stable Windows and macOS builds, including startup checks, optional automatic downloads, progress reporting, release notes, and guarded installation.
- Added a persistent LAN password setup prompt so a new installation clearly shows what must be configured before remote access is ready.

### Changed

- Remote-session tabs now prefer a local alias, then the remote device name, and finally the peer address.
- Explicit Web remote-access listeners now support VPN addresses outside the default private ranges when their CIDR is allowed, include those addresses in generated certificates, and provide clearer rejection diagnostics.
- Android release builds now require a fixed signing identity and verify every APK against a pinned certificate fingerprint before publication.

### Fixed

- Fixed Windows remote desktop and camera stalls caused by texture lifecycle races during session changes.
- Fixed Windows portable builds unpacking into RustDesk's data directory instead of an isolated SubnetDesk directory.
- Fixed known LAN peers being rejected before the user could confirm an unexpected device-identity fingerprint.
- Hardened macOS update extraction with unique mount paths, symlink-safe cleanup, code-signature verification, and Gatekeeper validation.

[1.3.0]: https://github.com/zibo-chen/SubnetDesk/compare/v1.2.3...v1.3.0
