# SubnetDesk Web client

This browser client speaks the same LAN-only protocol as the native client through the embedded
HTTPS/WebSocket gateway. It does not use the public RustDesk ID, rendezvous, or relay services.

The generated bundle is embedded into the desktop binary by `src/web_gateway.rs`. Rebuild it after
changing the TypeScript source or `libs/hbb_common/protos/message.proto`:

```sh
bun install --frozen-lockfile
bun run generate:proto
bun test
bun run build
```

Remote video uses WebCodecs VP9, so a current Chromium-based browser is required. The access password
is used only for the current connection and is not written to browser storage.
