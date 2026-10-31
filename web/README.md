# SubnetDesk Web client

This browser client speaks the same LAN-only protocol as the native client through the embedded
HTTPS/WebSocket gateway. It does not use the public RustDesk ID, rendezvous, or relay services.

The generated bundle is embedded into the desktop binary by `src/web_gateway.rs`. Rebuild it after
changing the TypeScript source or `libs/base/protos/message.proto`:

```sh
bun install --frozen-lockfile
bun run generate:proto
bun test --coverage
bun run typecheck
bun run build
```

Remote video uses WebCodecs and negotiates VP9, H.264, or AV1 according to the browser's real decoder
support. The decoder normally runs in a worker with queue backpressure and falls back to the main
thread when worker rendering is unavailable. A current WebCodecs-capable browser is required.

Browser access is opt-in and HTTPS-only. The desktop settings expose separate listen addresses,
allowed networks, allowed hosts, and `view-only`, `control`, or `collaboration` permission profiles.
The generated local certificate authority can be installed from the desktop UI; custom certificates
must cover every explicitly allowed host. Browser sessions are classified by server-side transport
metadata, so a client cannot gain native administrative capabilities by changing its reported
platform.

The access password is used only for the current connection and is not written to browser storage.
The gateway also enforces Host and Origin validation, per-source rate and connection limits, bounded
WebSocket payloads, idle cleanup, and restrictive browser security headers.
