# LAN-only security design

## Trust and encryption

The host persists an Ed25519 identity key pair. For each TCP connection it generates an ephemeral Curve25519 key pair and a random server nonce, then signs a transcript containing:

- protocol domain separator and version;
- client nonce;
- server nonce;
- ephemeral public key.

The controller verifies the signature, derives the SHA-256 device fingerprint, and requires trust-on-first-use confirmation or an existing fingerprint match. The session key exchange then enables the existing authenticated `secretbox` framing before login data is sent. Protocol version `1` is mandatory and is not negotiated down.

The trust registry maps the latest endpoint to a fingerprint and can recognize the same fingerprint after an address change. An unexpected fingerprint at a known endpoint is displayed as an identity change and requires explicit verification.

## Credentials

The host has exactly one application account. Usernames are trimmed, limited to 64 bytes, and reject control characters. Passwords must be non-empty valid UTF-8, are limited to 256 bytes, and reject control characters.

Passwords are stored as Argon2id PHC strings using a random salt with these current parameters:

| Parameter | Value |
| --- | ---: |
| Memory | 64 MiB |
| Iterations | 3 |
| Parallelism | 1 |

The parameters are intentionally centralized so constrained target hardware can be benchmarked before a release adjustment. Login verification runs in `spawn_blocking` behind a two-permit global semaphore, so it neither blocks the Tokio executor nor allows unbounded Argon2 memory use.

The client carries plaintext credentials only in the connection-start payload, the active session's in-memory credential holder, and transient login-stage byte buffers. Transient copies are zeroized after transmission or rejection, and the session holder is zeroized when the session is dropped. This permits automatic reconnect within the current session without persisting a reusable secret. Passwords are not stored in `PeerConfig`, recent connections, command-line/deep-link arguments, or logs. Starting a new session from recent history asks for credentials again.

## Failure controls

- Failure state is recorded by source IP.
- IPv6 sources are also charged to `/64`, `/56`, and `/48` prefixes.
- Exponential retry delay starts after the first failure and is capped at 60 seconds.
- Stale source state expires after 15 minutes of inactivity.
- The response exposes only a generic credential error plus a bounded `retry_after`.
- A successful login clears only its exact source entry, not global or neighboring-prefix protection.
- Credential changes increment `credential_revision`; active sessions compare it once per second and close on mismatch.

## Network boundary

The listener binds only configured IP addresses, or all local addresses when the list is empty. Before handshake and Argon2 work, it rejects sources outside configured CIDRs. The default allowlist covers RFC1918, CGNAT, IPv4 link-local/loopback, IPv6 ULA/link-local, and IPv6 loopback. A VPN range outside these defaults must be listed explicitly.

LAN discovery replies only when credentials are configured, the service is running, discovery is enabled, and the source passes the same network policy. Discovery advertises endpoint metadata and the public fingerprint; it never authenticates or establishes a session.

## Local storage and upgrade handling

Unix configuration writes use `0600`. Windows configuration remains in the established per-user/service location and relies on its inherited ACL boundary. Historical identity, public-server, proxy, old permanent-password, and trusted-device fields are deserialize-only migration inputs and are cleared or ignored by the LAN-only sanitizer. They are never accepted as LAN credentials.

## Security verification

Automated coverage includes endpoint/input validation, configuration sanitization, fingerprint-stable recent history, allowed-network policy, transcript tampering, replay binding, protocol mismatch behavior, credential hashing/verification, and authentication backoff. The static residual gate prevents reintroduction of public transport symbols, public server options, runtime public URLs, Web release builds, and enabled legacy release jobs.
