# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.

## Selected design

The user selected the first displayed concept on 2026-11-14: contextual left group directory plus a compact right device table. Preserve the existing porcelain/plum/lavender palette, top navigation, single-group membership, explicit search scope, group counts, multi-select move and undo. This folder is a standalone design prototype. The user subsequently authorized production Flutter implementation of grouping and manual IP editing, preserving mDNS. Use the original product logo in public/assets/subnetdesk-mark.png and Tabler outline icons.

## Mutable device addresses

User requirement: device IP addresses may change. Support manual editing alongside mDNS automatic updates. Update the original device record rather than creating a new device; preserve its name, group and other metadata. Keep mDNS automatic updates enabled by default, show the policy explicitly, and allow manual pinning by turning it off. The prototype demonstrates manual changes/undo only; native discovery integration remains future work.

Latest identity requirement: use the device public-key fingerprint as the sole key. IP and name are unreliable mutable attributes. Production code follows this requirement and permits duplicate cached addresses for different fingerprints; connection handshakes must enforce the expected fingerprint. Early prototype address-conflict validation is historical, not the final persistence contract. See ../IMPLEMENTATION.md for the actual client implementation.

Latest layout requirement: all desktop device source tabs (Nearby, Recent, Favorites, All) use the same persistent sidebar, toolbar, table and pagination. Source changes update data and enabled actions without replacing layouts or moving major regions.
