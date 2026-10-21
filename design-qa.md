**Comparison Target**

- Source visual truth: selected Product Design Option 1 (single-level groups nested under Favorites), grounded in `/Users/chenzibo/git/SubnetDesk/assets/screenshots/device-discovery.png`.
- Implementation screenshot: `/Users/chenzibo/.codex/visualizations/2026/07/27/019fa1f6-22c1-78c2-9e68-9e18563b9023/favorite-groups-implementation.jpeg`.
- Full-view comparison: `/Users/chenzibo/.codex/visualizations/2026/07/27/019fa1f6-22c1-78c2-9e68-9e18563b9023/favorite-groups-comparison.png`.
- Focused sidebar comparison: `/Users/chenzibo/.codex/visualizations/2026/07/27/019fa1f6-22c1-78c2-9e68-9e18563b9023/favorite-groups-sidebar-comparison.png`.
- Viewport: 1366 × 768 desktop application frame, light theme.
- Source pixels: 2112 × 1454. The source is a 2× capture and was normalized to 1056 × 727 CSS pixels, then padded to the comparison viewport without scaling the UI density.
- Implementation pixels and CSS size: 1366 × 768 at device scale factor 1.
- State: Favorites selected, All selected, one custom group with one assigned favorite, ungrouped count zero.

**Findings**

- No actionable P0, P1, or P2 differences remain.
- Fonts and typography: the implementation uses the existing SubnetDesk type scale and weights. Group labels, counts, headings, and device-card text retain the source hierarchy and remain legible without clipping.
- Spacing and layout rhythm: the 280 px sidebar, navigation alignment, selected-row treatment, 8 px radii, group indentation, card grid, and toolbar spacing match the existing product system. The additional rows push Settings downward without overlapping the desktop-status card.
- Colors and visual tokens: the existing blue selected state, neutral backgrounds, gray secondary text, borders, and status colors are reused rather than introducing new tokens.
- Image quality and asset fidelity: all existing platform icons, app branding, and device-card assets remain source assets; the feature adds only Material icons already consistent with the application.
- Copy and content: group names, counts, All, and Other are visible in the expected hierarchy. Create, rename, delete, assignment, filtering, and removal states were exercised with live data.
- Accessibility and interaction: the add button exposes a tooltip, group rows have full-width click targets, per-group actions use a standard popup menu, and device grouping is nested under the existing overflow menu.

**Open Questions**

- The current Simplified Chinese translation for the existing `Select All` key is “全选”. A future localization pass could introduce a dedicated filter label such as “全部”, but this is P3 copy polish and does not block the interaction.
- “Other” currently reuses the existing localized key. A dedicated “Ungrouped” key could be considered later if product terminology changes.

**Implementation Checklist**

- [x] Preserve the existing SubnetDesk visual system and device-card flow.
- [x] Show All, custom groups, and ungrouped favorites with live counts.
- [x] Support create, rename, delete, assignment, migration, and filtering.
- [x] Keep favorites when their group is deleted.
- [x] Remove stale assignments when a favorite is removed.
- [x] Verify the primary interactions in the native macOS application.
- [x] Run model tests, targeted analysis, build checks, and visual comparison.

**Follow-up Polish**

- Consider adding a dedicated localized “All” filter key instead of reusing `Select All`.

**Comparison History**

- Initial pass: blocked because the native Rust/Flutter bridge and media dependencies prevented an application capture.
- Interaction pass: creating a group exposed a `TextEditingController was used after being disposed` failure during dialog dismissal. The dialog was changed to use `TextFormField.initialValue` plus local value tracking, removing the prematurely disposed controller.
- Post-fix pass: create, rename, delete, assignment, migration, counts, All/custom/Other filtering, and favorite cleanup completed without Flutter runtime exceptions.
- Visual pass: the full view and focused sidebar comparison found no actionable P0/P1/P2 mismatch. No visual fix loop was required after the post-fix capture.

final result: passed

---

## Password onboarding — 2026-08-25

**Comparison Target**

- Source visual truth: selected Product Design Option 1, `/Users/chenzibo/.codex/generated_images/01a0389d-7dd1-7653-a03b-8a805208cd40/exec-4e9096bb-9543-4aaa-bd22-5919def3d358.png`.
- Native implementation screenshot: `/Users/chenzibo/.codex/visualizations/2026/08/25/01a0389d-7dd1-7653-a03b-8a805208cd40/subnetdesk-password-onboarding-implementation.png`.
- Source viewport: 1536 × 1024, light-theme concept. Implementation viewport: 974 × 768, the user's active dark theme. The two full-screen images were inspected together in one comparison input; component proportions and state were compared without treating the theme and viewport differences as pixel-level defects.
- State: LAN credentials incomplete, username available, password missing, persistent setup CTA visible.

**Findings**

- No actionable P0, P1, or P2 differences remain.
- Hierarchy: the local-desktop card exposes the missing-password state before any remote attempt, then gives the setup action the strongest emphasis in the card.
- Layout: the selected concept was adapted to the existing compact sidebar width without clipping, overflow, or interference with discovery navigation and device cards.
- Colors and tokens: the implementation keeps SubnetDesk's existing dark-theme surfaces, blue primary action, red blocking status, border treatment, radii, typography, and Material icon set.
- Copy and content: the card identifies the username, marks the password as required, and labels the CTA “Set Password”; all visible strings use the existing localization system.
- Interaction: clicking the CTA opened the existing LAN settings dialog. The dialog was then cancelled without typing or saving credentials.
- State handling: a configured machine keeps the existing compact local-device summary; the onboarding card is shown only when the LAN credential status is incomplete.

**Implementation Checklist**

- [x] Make the missing-password requirement visible immediately after installation.
- [x] Keep the prompt persistent instead of relying on a dismissible modal.
- [x] Route the primary CTA directly to the credential settings flow.
- [x] Focus the first incomplete credential field when settings open.
- [x] Refresh the desktop status after a successful save.
- [x] Verify the native macOS interaction without modifying real credentials.
- [x] Run targeted tests and static analysis.

**Follow-up Polish**

- A future localization pass could add a dedicated explanatory sentence matching the concept's longer onboarding copy. The current title, status, field row, and CTA already communicate the required action and do not block the flow.

**Comparison History**

- Initial native capture showed the configured-machine state, so the unconfigured branch was temporarily forced only in the running QA build.
- The onboarding state rendered without clipping in the compact sidebar and the primary CTA opened the correct LAN settings dialog.
- The temporary QA override was removed from source before final verification; no credential values were entered or saved.

final result: passed

---

## Flutter redesign implementation — 2026-10-20

**Comparison Target**

- Source visual truth: `/Users/chenzibo/git/SubnetDesk/docs/design/2026-10-lan-ui/desktop/01-home.png` and `desktop/17-preferences.png`, each 1512 × 1040 pixels, light theme. The approved remote-window reference prioritizes canvas space and floating controls.
- Valid pre-fix native capture: `/Users/chenzibo/git/SubnetDesk/docs/design/2026-10-lan-ui/implementation-desktop-home-before.png`, 3840 × 1924 pixels, macOS Retina DPR 2, 1920 × 962 logical window including the 28-logical-pixel tab strip. Source and implementation were opened together in one comparison tool input. Their different viewport proportions were acknowledged; no pixel-equivalence claim was made.
- Additional valid compact runtime capture: `/Users/chenzibo/git/SubnetDesk/docs/design/2026-10-lan-ui/implementation-native-window.png`, 1600 × 1200 physical pixels / 800 × 600 logical pixels at DPR 2, device browser state.
- `implementation-settings-before.png` is a 364 × 278 tool-thumbnail capture, unsuitable for detailed fidelity acceptance. It is not accepted as final settings evidence. Test-font screenshots that rendered Ahem glyphs were also rejected and excluded from acceptance.
- Final Debug build requests a 1512 × 1068 logical frame so that its client area can match the 1512 × 1040 source after excluding the tab strip. Final dimensions must be measured from a new capture; macOS may constrain the requested frame to its work area.
- Runtime uses a separate QA bundle and `target/ui-preview-data`. No real credentials, file transfer, or remote-control input were used.

**Findings and Comparison History**

- [P2, source fixed; visual recheck pending] Nearby section title/actions clustered in the center. The actual home showed a centered group where the source places the heading left and View all right. Changed to a full-width wrapping row with a nested left group. A post-fix capture is required.
- [P2, source fixed; visual recheck pending] Narrow header actions did not occupy the trailing edge. Changed the compact brand to an expanded layout; navigation wraps onto a second row when width or text size requires it.
- [P2, source fixed; visual recheck pending] Hero controls used a smaller button and omitted the nearby More action. Set the primary action minimum height to 56 logical pixels, added a native popup menu, and centered hero content within a minimum-height area that can grow with text.
- [P2, source fixed; visual recheck pending] Appearance settings still contained host-sharing controls and a narrow left-aligned card. Split host controls into This device → Advanced settings; settings cards now center within a 1064-logical-pixel maximum width.
- [P2, fixed and widget-tested] Large text caused navigation, empty-search and detail layouts to overflow. Added flexible headings, wrapping navigation, scrollable empty states and a detail layout that keeps its primary action available. All tested scaling combinations now complete without Flutter layout exceptions.
- [Functional, fixed and widget-tested] Incoming-only mode could still expose Search/Add in the new work area. Those outgoing controls are hidden; Back returns from Sessions to This device. The existing desktop incoming-only host page is retained.
- [Functional, fixed and widget-tested] New copy initially followed system locale alone. It now follows the application language override, defaulting to system locale; current new copy supports Chinese and English.

**Required Fidelity Surfaces**

- Fonts/typography: native pre-fix home rendered legible platform Chinese/Latin fonts. Platform font fallback is preserved. Text scale is no longer globally forced to 1. Long names truncate intentionally; essential descriptions can wrap. Final typography inspection remains pending.
- Spacing/layout: pre-fix composition was compared against D01; the four visual findings above were corrected in source. The final screenshots and focused header/hero/settings comparisons are still required.
- Colors/tokens: shared porcelain `#F8F5F0`, aubergine `#332B3B` and lilac `#DDD7EE` tokens are connected to controls, surfaces and icons. Dark theme has separate foreground/background values. This is not a claim of a completed full accessibility contrast audit.
- Image quality/assets: custom transparent monitor art and the approved generated two-window mark are actual image assets, with high-resolution platform exports. The logo source is raster; SVG wrappers do not constitute a vector master. The native pre-fix capture showed the new assets loading.
- Copy/content: runtime discovery and saved models supply real devices and reachability states. No design-example latency, transfer speed or connection status is fabricated. Authentication and identity decisions stay in existing flows. Dedicated tool-page layouts and mixed-tool tab migration are outside this iteration's completed scope.

**Validation and Remaining Blocker**

- Automated suite: 40 tests, including 24 desktop/mobile × DPR × text-scale combinations, landscape details, incoming-only Back behavior, address validation, app-language override, favorites, presence and font fallback.
- Native macOS Debug build and 51 exported icon checks pass. Targeted analyzer reports no errors, with existing unused-item/deprecation warnings. The latest app log shows no Flutter layout exception before the locked-screen handoff.
- Earlier native UI interactions covered home, discovered devices, returning home and opening settings. Search editing, group dialogs and the revised settings layout still need final interactive checks in the new build.
- Windows/Linux runtime, Android/iOS devices, connected remote toolbar behavior and cross-monitor DPI changes have not been verified. CoreSimulator is incompatible with the installed Xcode version.
- Final native capture was attempted through CUA after rebuilding, but the tool reported that the Mac is locked and cannot be unlocked automatically. A request to unlock the Mac is pending. No attempt was made to bypass the lock.

**Implementation Checklist**

- [x] Apply the shared visual foundation and real device work area.
- [x] Preserve native DPI and system text scaling; exercise the layout matrix.
- [x] Build the actual Flutter application with isolated QA data.
- [x] Fix findings from the first native comparison in source.
- [ ] Unlock Mac, capture the revised home and settings, and compare both full views plus focused regions with source in the same tool input.
- [ ] Complete final native search/detail/group/settings interactions and inspect runtime errors.

final result: blocked

### Resumed native acceptance after unlock — 2026-10-20

This is the final result for the implemented core workspace, device-detail action hierarchy, appearance settings and shared brand/theme in this iteration. It does not certify all 43 target screens, connected remote tools, new mixed-tool tab migration, or every operating system.

**Evidence and normalization**

- Source: `/Users/chenzibo/git/SubnetDesk/docs/design/2026-10-lan-ui/desktop/01-home.png`, `desktop/04-device-detail.png`, and `desktop/17-preferences.png`; each 1512 × 1040 pixels.
- Final native captures in that directory: `implementation-desktop-home-final-raw.png`, `implementation-device-detail-polished-raw.png`, `implementation-settings-polished-raw.png`, `implementation-settings-dark-final-raw.png`, `implementation-fingerprint-raw.png`, `implementation-search-empty-raw.png` and `implementation-credentials-final-raw.png`.
- Each accepted raw capture is 3024 × 1924 physical pixels, macOS Retina DPR 2 / 1512 × 962 logical window. macOS constrained the requested height to the available work area. Remove only the 56-physical-pixel native tab strip and downsample by 2 to produce the corresponding filename without `-raw`, at 1512 × 934 logical pixels. No vertical stretching or fabricated app content was used. The source is 106 pixels taller; compare proportions and component spacing with that difference explicit.
- Full source and native images were presented together in the same tool inputs for home/settings, and for detail. Focused source/render pairs were also presented together: `qa-home-brand-source.png` / `qa-home-brand-render.png` and `qa-settings-row-source.png` / `qa-settings-row-render.png`. `qa-dark-brand-render.png` confirms the corrected monochrome mark. The earlier 294 × 278 Stage Manager thumbnails were rejected, then replaced with full-window captures after the user brought the QA window forward.

**Fixes and post-fix comparison**

- [P1, resolved] Discovery refresh could move device rows between observation and selection. Nearby and browser lists now sort consistently by name with address as the tie-breaker, use device identity keys, and do not reorder when reachability changes. A regression test reverses incoming discovery order and flips presence while asserting unchanged row positions. Native selection subsequently opened the intended `mac.lan` target and matching address.
- [P2, resolved] The initial appearance page retained vertical radio controls, a detached title and a full-width advanced section. Replaced these with a branded header, aligned title/categories/content, theme-choice chips, responsive label/control rows and a bounded advanced section. Final light and dark screenshots show coherent alignment and readable controls.
- [P2, resolved] The first desktop detail reused the mobile footer action pattern. Desktop now places Connect, File transfer and More together under device identity; mobile keeps its bottom action. The revised native detail capture was compared with D04 in the same input. Unknown extra addresses, aliases, timestamps and saved-trust claims are not filled with design examples.
- [P2, resolved] Dark theme obscured the aubergine half of the mark. The same image alpha now supplies a light monochrome mark in dark theme; the post-fix focused capture shows both corners and the center opening clearly.
- Earlier header alignment, nearby section placement, hero button size and large-text overflow findings were rechecked in the revised evidence. Primary hero actions explicitly retain standard visual density. No actionable P0/P1/P2 finding remains within the acceptance scope above.

**Five required fidelity surfaces**

- Fonts/typography: native Chinese and Latin system fallback fonts render clearly. The implementation uses platform-appropriate 14–17 point supporting text and 30–34 point primary titles, with a slightly more compact control scale than the illustrative target. Long names truncate only in list summaries; details wrap. Text scaling remains enabled. The focused crops confirmed coherent weights and baselines.
- Spacing/layout: the central hero, thin navigation, left/right nearby heading actions, centered settings column and grouped detail actions preserve the intended hierarchy. Settings controls stack at large text sizes; detail actions wrap. A top Return to devices control is the intentional adaptation for the existing native settings tab. The shorter real viewport and two real discovered devices explain differences from the taller four-device example.
- Colors/tokens: porcelain, aubergine and lilac are applied consistently. Light/dark settings were inspected and the original Follow System preference restored. Presence is conveyed by text and icon as well as color. A full accessibility contrast audit is not claimed.
- Images/icons: generated monitor art loads sharply without an opaque image box. The two-window image mark is consistent with exported platform icons; its dark variant uses the same alpha. Existing rounded Material icons provide functional glyphs. Native choice chips and form controls deliberately replace raster-only mock controls. The brand master remains raster.
- Copy/content: discovery, reachability, identity fingerprint and saved-profile empty states use actual models. Search has a useful recovery action. Remote image scaling explicitly states that it does not change local UI size. Unimplemented guide toggles and mock identity/history values were not invented.

**Interactions, checks and limits**

- Exercised native home → search, nonmatching query, clear, matching query, device detail, full 64-character SHA-256 viewer and close, settings categories, theme changes and restoration, credentials empty state, Return to devices, and a new group saved in the isolated QA profile. The final preview is left on the device home with its test search cleared. Connected control/transfer/terminal execution were not used as acceptance tests.
- 42 selected tests pass, including 24 DPR/text-scale combinations covering home, search/empty state and details, plus settings wrapping, stable discovery order, language override, landscape and incoming-only behavior. macOS Debug build and 51 icon checks pass; diff whitespace checks pass. Targeted analysis has no errors; existing warnings remain. The final run log has no Flutter assertion, RenderFlex overflow or controller-disposal exception.
- Residual gaps: Windows/Linux runtime, cross-monitor DPI movement and Android/iOS device rendering. CoreSimulator remains incompatible with installed Xcode. Dedicated tool-page rewrites and cross-tool tab migration remain implementation work documented in `docs/design/2026-10-lan-ui/IMPLEMENTATION.md`.
- P3 polish: exact illustrated control proportions, the contiguous segmented-theme treatment and an editable vector brand master can be refined separately. These do not block the implemented core flows.

**Completed checklist**

- [x] Unlock and obtain full native window captures.
- [x] Compare revised full views and focused regions with source in the same input.
- [x] Fix actual layout, selection-stability and dark-brand issues; rebuild and recheck.
- [x] Complete core native interactions and inspect runtime exceptions.
- [x] Preserve explicit platform and remaining-feature limits.

final result: passed

## Compact desktop window correction — 2026-10-20

**Target and evidence**

- User defect screenshot: `/var/folders/2d/3fyx07bs1l97x4rrqxh715h00000gp/T/codex-clipboard-a60db4ed-7f4a-42d3-9273-15a1bb2633d6.png`, 2240×1524 physical pixels / approximately 1120×762 logical pixels at DPR 2. The user explicitly requests a smaller default and visible operations at minimum size; this changes the earlier large-hero composition requirement for compact windows.
- Native compact capture: `docs/design/2026-10-lan-ui/implementation-compact-default-raw.png`, 2114×1496 physical pixels / 1057×748 logical pixels at DPR 2. This capture had already been resized and is not evidence of the exact new default size.
- Native minimum home: `implementation-compact-minimum-raw.png`, 1280×960 physical pixels / 640×480 logical pixels at DPR 2. The client is 640×452 after the 28-pixel tab strip. `implementation-compact-minimum.png` is a diagnostic downsample by 2, preserving native chrome and without stretching or composing UI.
- Before/fixed minimum detail: `implementation-compact-detail-before-raw.png` / `implementation-compact-detail-final-raw.png`, also 1280×960; normalized copies omit `-raw`. The before capture shows no visible Connect operation. The revised capture shows the fixed footer. A subsequent 16-pixel horizontal margin and 8-pixel footer padding adjustment fixes the remaining double-text-scale case; that latest margin adjustment still needs its final native capture.
- The user screenshot and minimum home were opened in the same comparison input. Before/fixed detail were also opened together. Focused action evidence: `qa-compact-home-actions.png` and `qa-compact-detail-actions.png`. `implementation-compact-tools-raw.png` shows Details, Files, Terminal and Camera available through More at minimum size.

**Findings and fixes**

- [P1, implemented] Large fixed illustration/spacing consumed short-window height. Desktop home now selects a compact layout using available width and height, hides decorative illustration in short windows or large text, and keeps Connect/More/Address/Refresh outside the scrolling content.
- [P1, implemented] Minimum detail also hid connection operations. Compact detail uses a smaller identity icon and a fixed Connect/More footer, while long metadata scrolls. Full-size desktop retains its grouped upper actions; mobile keeps its existing footer.
- [P2, implemented] Wide header assumptions overflowed under English labels. Retained the conservative width/text-aware navigation breakpoint, reduced compact header padding and allowed navigation wrapping. No text-scaling override was introduced.
- [P2, implemented] Double-size text needed less fixed detail padding to keep all controls within 640×452 client bounds. Compact detail uses 16-pixel horizontal margins and an 8-pixel footer margin; widget hit tests and overflow checks now pass.
- Default normal desktop size is 960×640 logical pixels, minimum 640×480. Existing valid window size preferences remain. Both default and restored sizes are bounded by the current logical work area; Windows physical screen coordinates are converted using monitor DPI. The original incoming-only sizing rules and remote-canvas zoom remain separate.

**Fidelity and interaction review**

- Typography: system fonts and user text scaling remain; primary compact headings use 26 logical pixels and controls retain readable text/click targets. Large names wrap or truncate summaries rather than pushing persistent actions out of the window.
- Spacing: reduced hero/icon sizes and margins are intentional for this request. Only content scrolls; navigation and main actions stay available. Partially visible device rows indicate scrollable content, and View all opens the complete device browser.
- Colors: the existing porcelain/aubergine/lilac palette and semantic status text/icons are retained.
- Assets: the approved image assets are reused; the illustration is omitted where it would displace operations. No new rasterized controls or replacement drawing was introduced.
- Copy: real discovery state, addresses and device names remain. Tooltip-labelled header icons and the visible More menu retain access to features rather than discarding them at breakpoints.
- Native interactions verified at minimum size: More opens all four actions; Details opens the selected device; fixed connection operation is visible. No remote control or credential change was needed for this acceptance check.

**Checks and final state**

- 67 tests pass. New cases cover 640×452 and 960×612 clients × DPR 1/1.25/1.5/2 × text 1/1.5/2, checking directly hit-testable persistent actions, tool-menu callbacks, scrolling to device details, and hit-testable detail footer actions. A separate test covers fitting default/restored windows to scaled work areas.
- Final normal macOS Debug build succeeds without viewport defines; separate Debug viewport defines were used only to obtain minimum-size evidence. Targeted analysis has no errors, existing warnings remain; `git diff --check` passes. No Flutter overflow/assertion is present in the inspected runtime logs. Parallel local app instances can report discovery-port conflicts, and the unrelated update endpoint still reports HTTP 404; these are not represented as zero runtime errors.
- The final executable restored 640×480 in the QA profile, confirming the saved-size path. While attempting its last screenshot, CUA reported that the Mac had automatically locked again. A request to unlock is pending. Final native verification of the latest margins/work-area fit and an exact 960×640 first-run capture remains blocked by that lock; the code/build/test work is complete.
- Windows/Linux real-device and cross-monitor DPI checks remain outside available native runtime coverage.

final result: blocked

## Proportional desktop scaling and direct connection — 2026-10-20

- Desktop workspaces scale uniformly below a 960×612 client area. At the 640×452 client of a 640×480 window, standard text retains the monitor illustration and nearby rows. Existing text scaling and the mobile presentation remain supported.
- Desktop device rows in nearby, favorites and recent lists connect directly. Each row and the hero share a More menu for Files, Terminal, Camera, Favorite/Remove favorite, Copy address and Device information. Information opens a scrollable dialog containing real metadata and favorite-group assignment.
- 69 selected tests pass. Coverage includes 24 compact viewport/DPR/text-scale combinations, uniform image scaling by 2/3 in both axes, direct desktop callbacks, tool and favorite target identity, copied address, dialog dismissal, and existing mobile/favorites/presence/font tests. Analyzer reports no errors; style notices remain. A normal macOS Debug build without viewport overrides succeeds, and diff whitespace checks pass.
- Native evidence: `docs/design/2026-10-lan-ui/implementation-scaled-home-native.png`, `implementation-scaled-more-native.png` and `implementation-scaled-info-native.png`. These are actual 1496×1160 physical / 748×580 logical captures, inspected for visible content, menu placement and readable metadata. They are not exact 640×480 captures; that size is covered by widget layout and hit testing. No connected remote session was used for acceptance.
- Preview: `target/ui-scaled-preview/SubnetDesk Scaled QA.app`, with isolated data in its sibling `userdata` folder. The preview is left on Home. Windows/Linux runtime and cross-monitor DPI remain outside this native acceptance.

final result: passed for implemented changes; exact minimum native capture remains unverified

## Restore the centered connection action — 2026-10-20

- Corrected the compact home regression reported by the user: Connect and More now appear together, centered directly below the device metadata and above Nearby devices. The bottom strip contains only Refresh and Connect by address.
- Kept proportional scaling and direct desktop row connections. At large text sizes, the centered action group can use the available width to avoid excessive button wrapping.
- All 57 workspace tests pass, including the compact viewport/DPR/text-scale matrix. The matrix now also asserts horizontal centering and vertical placement between device metadata and the nearby heading, in addition to hit testing. Targeted analysis reports no errors; existing style notices remain. Normal macOS Debug build and whitespace checks pass.
- Replaced and reopened the same isolated preview bundle. Native evidence: `docs/design/2026-10-lan-ui/implementation-centered-connect-native.png`, 1932×1410 physical / 966×705 logical pixels. The screenshot confirms the corrected centered action and the nearby list beneath it. Exact 640×480 positioning is covered by the automated 640×452 client tests.

final result: passed for the centered-action correction

## Home spacing and endpoint display cleanup — 2026-10-20

- Removed the compact desktop footer and the redundant address-connect entry from both desktop home variants. Refresh sits beside View all in the compact nearby heading. The nearby area finishes with a 16-logical-pixel content margin; surplus height is shared above and below the centered hero instead of leaving a band beneath device rows. Taller content scrolls normally.
- Device address readouts and address-based fallback names hide port 21118 for IPv4, hostnames and bracketed IPv6. Custom ports remain visible. Connection IDs, search input matching and copied endpoints retain their original values. The manual-address hint also omits the default port.
- All 59 workspace tests pass. New checks cover default/custom endpoint display, original connection IDs, bottom spacing at the user's 966×677 client size, Refresh, and entering a custom endpoint through Add. Existing compact viewport/DPR/text-scale and centered-action checks still pass. Targeted analysis reports no errors, with style notices remaining; normal macOS Debug build and whitespace checks pass.
- Native evidence: `docs/design/2026-10-lan-ui/implementation-home-cleanup-native.png`, 1932×1410 physical / 966×705 logical pixels. Verified the nearby rows near the lower edge, hidden default port, absent footer/address button and centered connection action. Opened the address dialog through the top-right plus, cancelled and returned Home. No remote session or credentials were entered.

final result: passed for the requested home cleanup

## Desktop composition and true centering — 2026-10-20

**Scope and visual sources**

- Audit step 1: Devices home, supporting the existing direct-connection task. Initial health: visible composition/alignment issues. Final health: those issues resolved in the revised native capture.
- User source: `/var/folders/2d/3fyx07bs1l97x4rrqxh715h00000gp/T/codex-clipboard-79568ef0-88f0-40f4-b668-aac10d800af8.png`.
- Existing visual foundation: `docs/design/2026-10-lan-ui/desktop/01-home.png`, 1512×1040. Its porcelain/lilac palette, monitor artwork, central identity hierarchy and desktop navigation are the starting direction. This is an improvement to the current screen, not a pixel-identical recreation: the user's later instructions require hidden default ports, direct row connections and no redundant bottom address link. Centered pill navigation and bordered nearby cards are intentional refinements.
- Current-run before evidence: `docs/design/2026-10-lan-ui/01-home-balance-before.png`. Revised implementation: `docs/design/2026-10-lan-ui/02-home-balance-after.png`. Both were saved and opened, each 1932×1410 physical pixels / 966×705 logical pixels at DPR 2, including the same 28-logical-pixel title strip. Their client areas are 966×677. The source D01 is taller and has different example devices; exact pixel fidelity to that source is not claimed.
- State: light theme, two real discovered devices, same selected home screen. Reachability changes naturally during discovery; status differences are not treated as layout changes or fabricated to match the design.

**Findings and comparison history**

- [P1, resolved] Header consumed two rows at ordinary desktop sizes, detaching navigation from brand and actions. Revised the header to one row with equal 200-pixel side tracks and centered navigation. Large system text still allows navigation to move below the header.
- [P2, resolved] The button/More group was centered while the primary button itself was left of the device axis. Added a matching 60-pixel left reservation against the 48-pixel More action and its 12-pixel gap. A pixel scan of the native aubergine button found its center moving from x=913.5 before to x=965.5 after, exactly the captured window's horizontal pixel center.
- [P2, resolved] Small illustration, expansive whitespace and full-width loose device rows competed rather than reading as a single composition. Reused a proportionally sized monitor, restored the Continue connecting eyebrow, unified the desktop home layout and bounded header/content to 1040 logical pixels with matching margins. Nearby cards now have consistent padding, 16-pixel corners, 16-pixel column gaps and a 24-pixel bottom margin.
- Initial comparison of the before capture with the existing D01 foundation identified these issues. After implementation, both full native captures and D01 were opened together in one comparison tool input. The revised image shows the corrected one-line header, common visual axis, proportionate hero and balanced nearby row. No additional visual fix was needed after that native comparison.

**Required visual checks**

- Typography: existing system Chinese/Latin font fallback remains. Brand uses 21-point text, desktop navigation 14, hero title 26, supporting metadata 13, nearby titles 14 and nearby addresses/status 12. Summary truncation remains deliberate. Text scaling is preserved; large text wraps/reflows rather than being forced to 1.
- Spacing/layout: header, monitor, identity, primary action and nearby section were checked for their horizontal axes. Header and content share their outer tracks. Nearby devices form a consistent two-column row, switching to one column for large text. The same desktop composition is used at different widths instead of abruptly switching to a separate spacious page.
- Colors/tokens: retained canvas `#F8F5F0`, ink `#332B3B`, lilac `#DDD7EE`, existing theme surface and divider colors, and text-plus-icon presence states. The selected navigation pill and quiet More circle use those existing tokens. A complete WCAG contrast or assistive-technology audit is not claimed.
- Image quality: original PNG monitor and logo remain, rendered with their alpha and aspect ratio. No replacement asset or screenshot-as-interface was introduced.
- Copy/content: real peer names, addresses and presence are unchanged. Port 21118 is hidden only for presentation; custom ports remain visible. Direct desktop row connections, existing tools and the top-right Add dialog retain their existing behavior.
- Full-view original-resolution comparisons made header labels, button alignment, nearby metadata, icon treatment and typography legible. Those specific regions were reviewed within the same full-resolution image input; separate crop artifacts were unnecessary. The native pixel measurement additionally confirms the primary-action alignment.

**Validation and limits**

- 65 workspace tests pass, including six new English/Chinese alignment cases at 640×452, 966×677 and 1440×900; existing 24 compact viewport/DPR/text-scale cases; direct connections; menu targets; port display; Add; dialogs; language override and mobile regressions. The checks now assert the primary button's own center as well as image/navigation/section axes and shared outer margins.
- Normal macOS Debug build succeeds without viewport defines. Targeted analysis has no errors and retains style notices. Whitespace checks pass.
- Native interactions: switched to Sessions and back, opened/dismissed hero More, opened/cancelled Add, then left the preview on Devices. No actual remote session or credential entry was used for acceptance. There was no visible overflow in the accepted screenshot; no claim of zero runtime log errors is made.
- Native acceptance is for the captured macOS viewport. Exact 640×480 rendering, Windows/Linux runtime, cross-monitor movement, dark native rendering and comprehensive accessibility remain outside this native visual check; automated compact layout/hit tests cover the minimum client's required controls.

**Implementation checklist**

- [x] Capture and inspect the current screen before editing.
- [x] Keep existing brand assets, tokens and confirmed connection behavior.
- [x] Correct the header, primary action axis and nearby density together.
- [x] Compare original-resolution before/after and the visual foundation in the same input.
- [x] Verify compact/large-text behavior, build and native header actions.

final result: passed


## Compact device list — 2026-10-20

**Comparison Target**

- Selected visual: Option 1, `/Users/chenzibo/.codex/generated_images/01a15a39-ad31-70e0-8362-6ca48b3388bb/exec-67cf50be-92ca-46ce-86be-d0aa135fde72.png`, 1469 × 1071 pixels.
- Current-run native evidence: `docs/design/2026-10-lan-ui/device-list/before.jpg`, `after.jpg` (first implementation), and `final.jpg` (revised implementation), each 1932 × 1410 pixels, 966 × 705 logical frame at DPR 2; client area 966 × 677 after the native title strip.
- State: Chinese, light theme, View all, two real LAN records. The concept contains twelve fictional records; the runtime keeps actual names, count and presence. The concept and native captures share the same aspect ratio and were inspected together in each comparison input at a common full-frame visual scale, accounting for the different raster densities. No pixel-identical comparison is claimed.

**Findings and comparison history**

- [P2, resolved] The first native list started 16 logical pixels too far below the title. Removed that extra gap in the desktop column layout. The revised `final.jpg` restores the compact title/header/list rhythm.
- [P2, resolved] Address and status columns sat too far right in the first capture. Adjusted the flexible device/address tracks and reserved more of the existing table width for the status track. Source and final native screenshots were opened together after the fix; headings and values now follow the selected layout.
- No actionable P0/P1/P2 findings remain. Search is absent from the app header and browser, and the Nearby/Favorites/All filter chips are absent from View all. Every device retains its explicit Connect button, existing overflow menu and original connection endpoint.

**Required Fidelity Surfaces**

- Fonts/typography: retained existing system Chinese/Latin fallback; 28-point title, 14-point device names and buttons, 13-point address/header text and compact status text. Long names and endpoints truncate with full-value tooltips. System text scaling remains enabled.
- Spacing/layout: shared 32-point desktop margins and 1040-point content bound, 32-point device avatars, approximately 40-point rows, aligned device/address/status/action tracks, quiet dividers, count beside title and labeled Refresh. Large text and narrow/mobile layouts use multi-line metadata; mobile large-text actions stack to preserve space for status text.
- Colors/tokens: retained porcelain, aubergine and lilac theme, with existing dark-theme support. Unreachable remains the existing muted state rather than the concept's red; unknown retains its distinct question-mark icon and text. This preserves the app's existing presence semantics.
- Image/asset quality: existing supplied brand PNG and Material device/action icons are reused. No screenshot-as-interface or new decorative assets. Native macOS title-strip/recording chrome is platform-owned and differs from the concept's traffic lights.
- Copy/content: real count and real peer values replace fictional mock data. No search placeholders, filter prompts, fake discovery results or device-count guarantees were introduced. The optional explanatory mock footer was omitted to keep the requested list focused.
- Full-resolution comparison made the headers, row labels, addresses, statuses and actions readable; a separate focused crop was unnecessary for this bounded screen.

**Validation and limits**

- All 66 workspace tests pass, including 30-device scrolling, deduplicated count, first/last endpoint connection callbacks, custom port preservation, empty-list recovery, DPI/text-scale matrices, small desktop windows, mobile details and existing overflow actions.
- Targeted analysis passes without errors or warnings; 18 existing style infos remain. macOS Debug build and signature verification pass. Xcode emitted the existing CoreSimulator-version notice; the macOS application built and ran successfully.
- Native checks: opened View all, activated Refresh, opened a row's overflow menu, verified Device information targets that row, dismissed the dialog, and reopened the final built list. No remote session or credentials were used. Connection routing is covered by widget callbacks; real remote-session establishment and Windows/Linux native rendering are outside this UI change's acceptance.
- Final preview: `target/ui-scaled-preview/SubnetDesk Scaled QA.app`, using its existing isolated sibling `userdata`. Left open on the device list.

**Implementation Checklist**

- [x] Modify the existing Flutter workspace directly.
- [x] Remove search and View all filter controls.
- [x] Keep original device data, per-row connections, Refresh, Add and More.
- [x] Verify list density, scrolling, small windows and large text.
- [x] Compare revised native capture with the selected visual and preserve prior QA history.

final result: passed


## Local computer redesign — selected option 2 — 2026-10-20

**Comparison target and evidence**

- Selected visual truth: `docs/design/2026-10-lan-ui/local-device/selected-option-2.png`, copied without editing from `/Users/chenzibo/.codex/generated_images/01a15c2f-1d52-7be2-9ba6-55e0d2cf4613/exec-ce4b5c4c-7b91-42ee-aa2c-783a64e87bc8.png` (1468 × 1071).
- Native implementation: `docs/design/2026-10-lan-ui/local-device/final.jpg` (1510 × 1104 CUA export), light theme, Chinese, Local computer, actual host `macbook-pro-11607`, incomplete macOS permissions and no access password. Earlier evidence: `before.jpg`, `after-first.jpg`; identity disclosure: `identity.jpg`.
- Resized the native window to the reference's approximately 1.37 frame aspect ratio. CUA exports 1510 × 1104; its capture scaling and the native runtime DPR were not independently measured. No CSS viewport applies to this Flutter app and no exact logical-pixel fidelity is claimed. Automated layout viewports are explicitly 640 × 452, 966 × 677 and 1440 × 900 logical pixels.
- Full-view evidence: `comparison.png`, source on the left and final native capture on the right in the same image. Source was uniformly scaled to 1510 pixels wide (1102 pixels tall), then padded to 1104; the native capture was kept unchanged. Both were opened together again after the dialog repair. Platform title-strip chrome differs intentionally.
- Focused controls evidence: `comparison-controls.png` compares the actual source and implementation address, copy action, primary action and helper text at readable resolution. The full-view input also makes header alignment and the three requirement items legible.

**Findings and iteration history**

- [P2, resolved] The first native implementation placed access status near the middle instead of the outer right edge. Removed the equally flexible status track and bounded status text independently. The final capture puts status at the right content margin; the local widget regression now asserts that geometry.
- [P2, resolved] Stacking the title above the artwork pushed the central identity and address too low. Placed the small title/status row beside the upper portion of the centered artwork, restored the reference's main action height and section rhythm, and centered each requirement group in its track. Added Menlo with platform monospace fallbacks for the endpoint. `final.jpg` and the post-fix comparison show the corrected composition.
- [P1, resolved] Cancelling the existing LAN/password dialog caused a disposed TextEditingController error during the closing animation, followed by a red Flutter error screen. The native log for the earlier process (54767) confirmed that sequence. Both LAN settings and rename now await `DialogRoute.completed` before clearing/disposing their controllers. Rebuilt, reopened the password form and cancelled it, opened/cancelled Rename, opened Advanced settings and returned successfully. Final preview process 58479 produced no Flutter error log during this retest. No credentials were entered and no permissions or access settings were changed.
- No actionable P0/P1/P2 issues remain for this scope.

**Required fidelity surfaces**

- Typography: retained the app's system Chinese/Latin fallback; 28-point page title, 22-point device identity, 18-point monospace address, 14-point controls/requirement names and 12–13-point support text. Long names wrap up to two lines. Long IPv6 endpoints remain selectable and wrap instead of truncating the connection value. System text scaling stays enabled.
- Spacing/layout: continuous porcelain surface, centered laptop/name/address/action, 440-point address region, 220 × 40 primary action, 50-point outer content margins, three quiet requirement groups and small identity/advanced links. Small windows retain the existing uniform workspace scaling; large text reflows the address/copy controls and requirements into a vertical layout with scrolling.
- Colors/tokens: reuse existing porcelain/aubergine/lilac theme and dark surface tokens. Amber plus text indicates pending setup; check icon plus text indicates completed requirements. Access readiness requires both the actual server state and an empty platform-prerequisite list. Initial data is labelled as loading, never ready. The mock's neutral unset-password dot is amber in the implementation to match the other pending requirements; this is an intentional semantic refinement.
- Imagery/icons: reuse the approved logo and existing Material icon library. Added a real transparent laptop PNG generated from the selected visual, stored at `flutter/assets/subnetdesk-local-laptop.png`, with a narrow gitignore exception so it can be versioned. Its stronger laptop outline and faint ring outlines differ slightly from the concept's softer filled halos (P3 polish). Alpha and aspect ratio are preserved; the screenshot is not used as the interface.
- Copy/content: actual host name, endpoint, alternate addresses, username and complete fingerprint remain sourced from the current host. Full fingerprint is disclosed in Device identity. Screen-recording and input-control requirements group the actual macOS checks, and the password item reflects actual configured state. Other platform prerequisites/runtime errors remain surfaced with a detail action; portable start/install and enabled browser-access controls are retained. No extra cloud or account model was introduced.

**Validation and limits**

- 96 selected tests pass: local host interactions/loading/ready transitions and 12 viewport/text-size/language cases (including long IPv6), existing workspace regressions, platform setup resolution and LAN service status. Local callback tests include rename, copy, other addresses, configure, identity and advanced; compact hit targets and scrolling remain usable.
- Final targeted analysis has no errors or warnings; existing style/deprecation infos remain. Normal macOS Debug build, ad-hoc preview signature verification and `git diff --check` pass. Xcode's existing CoreSimulator-version diagnostic does not prevent this macOS build.
- Native actions verified: Copy address with visible Copied feedback, Other addresses with two actual endpoints, complete fingerprint disclosure/copy, Configure access with actual permission details, password dialog open/cancel, rename open/cancel, Advanced settings open/back. Left the isolated preview on Local computer. Native interactions use the existing sibling `userdata` directory.
- Native dark theme, Windows/Linux runtime, actual permission granting, credential saving, browser access and a real incoming remote session were not exercised. Dark color selection remains theme-driven; this is not a comprehensive accessibility/contrast audit.

**Implementation checklist**

- [x] Implement the selected second visual in the existing Flutter app.
- [x] Preserve actual host data and existing access/identity actions.
- [x] Replace the large warning/card stack with focused identity and compact requirements.
- [x] Fix observed alignment and dialog-lifecycle failures; capture and compare again.
- [x] Verify tests, analysis, macOS build and native navigation; leave preview open.

final result: passed


## Homepage local access — selected option 1 — 2026-10-20

**Comparison target and evidence**

- Source: `docs/design/2026-10-lan-ui/home-access/selected-option-1.png`, the first displayed generated design, 1516 × 1037 pixels.
- Native implementation: `home-access/final.jpg`, 2020 × 1382 pixels, Chinese/light theme, discovery enabled, remote pending, guide open and real LAN devices. `password-entry.jpg` and `permission-guide.jpg` record the existing configuration destinations. Earlier captures: `before.jpg`, `after-first.jpg`.
- Full-view comparison: `comparison-final.png`, source left / final right, each uniformly normalized to 1010 × 691. Opened this combined input and the readable focused toggle/guide comparison `comparison-controls.png` before acceptance. CSS viewport does not apply to this native app; logical native frame size/DPR were not independently queried. Automated viewports: 640 × 452, 966 × 677 and 1440 × 900 logical pixels.

**Findings and iteration history**

- [P1, resolved] Initial native accessibility activation of the guide button hit a different location. Replaced the composited follower with `OverlayPortal.overlayChildLayoutBuilder` and explicit overlay coordinates that account for workspace transforms. Rebuilt and verified that “前往本机配置” opens the actual local page, Configure access opens the password form first, Cancel returns cleanly, and permission items open the real platform guide.
- [P2, resolved] Initial switches inherited thin Material tracks. Scoped standard Material 3 switches to these controls, restoring lavender/gray capsules and white thumbs. Corrected guide numbering from inherited blue to app ink. Final full/focused evidence shows the revised controls.
- No actionable P0/P1/P2 issues remain for this macOS homepage scope.

**Required fidelity surfaces**

- Typography: existing system Chinese/Latin fonts; 13-point control names, 11-point statuses, 16-point guide title and 12–14-point support/actions. Text scaling remains enabled; larger text uses a scrollable dialog. Two repeated requirement descriptions from the concept are condensed into the intro and requirement titles intentionally.
- Spacing/layout: local controls at upper right, original centered outbound connection hero and nearby margins retained. The guide aligns with remote access and remains separate from the connection button; bounded scrolling handles small windows. Missing decorative pointer/elevation is P3 polish only.
- Colors/tokens: existing porcelain, aubergine and lavender palette; amber plus text for pending; explicit loading/updating/starting/error states. An enabled remote switch requires actual credentials, current permissions, sharing enabled and a running listener.
- Imagery/icons: retained approved logo, Material icons and current `DeviceArt` assets, including concurrent device-type changes already present in the workspace. The Windows target therefore uses the current desktop/tower asset instead of the concept's all-in-one. Native title/recording chrome differs intentionally. No screenshot-as-UI or handcrafted raster substitutes.
- Copy/content: controls explicitly affect 本机, independently of the featured target. Password is configured in 本机, with platform-specific macOS/Windows/Wayland permission guidance. No fake credentials, permission success or host readiness.

**Validation and limits**

- 112 selected Flutter tests pass, including 15 new host-access cases: credentials/permission/service combinations, independent discovery, enable/disable intents, guide navigation/Escape and Chinese/English compact/large-text layouts. Existing workspace/local/readiness/status tests also pass. Decorative artwork visibility is checked through current `DeviceArt` geometry, rather than assuming an `AssetImage` input target.
- Targeted analysis has no errors or warnings; existing style/deprecation infos remain. Rust library build, two existing LAN-server tests, macOS Debug build, signature verification and whitespace checks pass. Restored the locally cached universal Flutter engine after an intermediate missing-arm64 linker error; the subsequent build succeeds. Existing CoreSimulator-version diagnostics do not block macOS.
- Native checks: pending remote → guide → local page → real username/password form → cancel; real macOS permission details; discovery off/on independently while remote remains pending. No credentials entered, permissions granted or real incoming remote session established.
- Backend permission checks also gate incoming listeners. Desktop discovery is independent of the listener; visibility changes do not restart incoming sessions. Mobile discovery behavior is preserved. Wayland polls live portal state without blocking on the consent mutex; interactive requests run on the bridge worker pool.
- Windows administrator and Linux Wayland authorization paths are implemented but not exercised on native machines here. Native dark mode, real authorized incoming sessions and comprehensive cross-platform/security validation are outside this acceptance pass.
- Independent preview: `target/home-access-preview/SubnetDesk Access Preview.app`, bundle `com.zibochen.subnetdesk.access-qa`, with its own sibling userdata copied from the existing isolated preview. Other previews remain unchanged.

**Implementation checklist**

- [x] Selected layout implemented in the existing Flutter app.
- [x] Actual discovery, sharing and permission states connected.
- [x] Password and permissions routed through 本机.
- [x] Native guide activation and switch styling repaired and recaptured.
- [x] Tests, builds, analysis and native navigation verified.

final result: passed


---

## Remote toolbar — selected option 3 — 2026-10-21

**Comparison Target**

- Source visual truth: `docs/design/2026-10-lan-ui/remote-toolbar/selected.png`, the third displayed concept selected by the user.
- Native implementation: `docs/design/2026-10-lan-ui/remote-toolbar/final-native.png`; normalized application content: `remote-toolbar/final.png` in the same design directory.
- Full-view comparison: `docs/design/2026-10-lan-ui/remote-toolbar/comparison-full.png`.
- Focused comparison: `docs/design/2026-10-lan-ui/remote-toolbar/comparison-toolbar.png`.
- Source: 1774 × 887 physical pixels. Native window: 1774 × 950 at DPR 2 (887 × 475 logical pixels). The 64-pixel title strip is excluded, leaving 1774 × 886 / 887 × 443 logical pixels. One wallpaper-only bottom row is excluded from the source for equal viewports. Full comparisons use 0.5× downsampling; focused comparisons preserve 2× density. CSS size does not apply to this Flutter component.
- State: light theme, pinned, expanded, top edge, one display, recording idle, no active voice call. The toolbar itself is about 564 × 56 logical pixels. The plain teal QA canvas substitutes for remote content; wallpaper is outside this component's scope.
- The native QA executable builds a copy of the production toolbar library and imports the production style/assets. It initializes local session models without starting a remote connection; the QA host and controls live under ignored `target/remote-toolbar-qa/` only.

**Findings**

- Fonts/typography: the main toolbar remains icon-only. Existing localized tooltips and menus retain the application font and readable text. Chat menu text and Escape dismissal were checked in the native preview.
- Spacing/layout: a single capsule contains drag, pin, session actions, fullscreen, collapse and close. Group separators, 40-pixel hit areas, 4/8-pixel button margins and a 28-pixel radius follow the selected hierarchy. No hanging secondary panel remains in the expanded state.
- Colors/tokens: porcelain surface, plum foreground, lilac selection and a restrained error tint reuse the application's color scheme. The inherited dark palette was inspected independently.
- Asset fidelity: the toolbar uses local, unmodified Tabler outline SVGs, with source revision and MIT license included. The SVG viewport is larger than the visible strokes so the perceived icon size matches the reference. The grip is centered inside its drag target rather than stretched to that target.
- Copy/content: recording idle uses an outline circle; active recording retains its stop action. Existing permissions, monitor controls, Android actions, text/voice menu, active-call controls, disconnect audit and platform-specific minimize rules are retained.

**Interaction Evidence And Validation**

- Native component checks: pin/unpin, whole-toolbar drag along the top edge, all four edge layouts, vertical scrolling to the final action, collapse/reveal, pointer-triggered reveal, idle auto-hide, and keeping the toolbar visible while the chat menu remains open.
- Evidence: `remote-toolbar/dragged.png`, `right-scrolled.png`, `collapsed.png`, `auto-hidden.png`, `menu-open.png` and `dark.png` in the same design directory. These interaction captures precede the final spacing polish; `final-native.png` is the final light-state capture.
- Five Flutter tests cover small horizontal/vertical viewports in both themes, reaching the last action by scrolling, and menu overlays remaining usable outside the clipped capsule.
- Targeted analysis: no errors or warnings; 14 existing deprecated-API informational messages remain in the legacy toolbar file. Twenty bundled upstream SVGs were parsed and checked. `git diff --check` passes.
- macOS Debug build uses the existing local deployment-target override of 12.0. The repository minimum deployment target is unchanged.
- Final native QA error log is empty. End-to-end remote commands, real recording/call/close execution, multi-monitor sessions, Windows and Linux runtime behavior were not exercised.

**Comparison History**

- Native inspection exposed inconsistent Material silhouettes and off-center menu labels. They were replaced by one outline icon set and explicit centered button faces.
- Initial sizing was narrower than the reference. Margins and the grip/outer spacing were aligned to the reference capsule proportions.
- Focused comparison exposed the SVG grip stretching inside its drag target; a centered child now keeps its intended visual size while preserving the drag target.
- Final rebuilt capture was reopened and compared with the source in both combined comparison images. The corrected grip size, matching capsule proportions, centered controls and consistent outline assets leave no actionable P0/P1/P2 findings. Only the P3 differences listed below remain.

**Follow-up Polish**

- [P3] Pin and close states use the shared 40-pixel button background rather than the concept's slightly smaller inset background.
- [P3] The stock message icon represents the existing text/voice submenu instead of the generated phone-in-bubble glyph. Both existing actions remain available.

**Implementation Checklist**

- [x] Preserve existing session behavior and localization.
- [x] Integrate drag/fullscreen/collapse in one surface.
- [x] Use one locally bundled outline icon set and include attribution.
- [x] Verify scrolling, menus, docking layouts and auto-hide in the native component.
- [x] Complete final rebuilt native capture and production build checks. The five tests and final targeted analysis pass; the normal `lib/main.dart` macOS Debug build and strict signature verification pass.

final result: passed
