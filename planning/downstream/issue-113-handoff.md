# Issue #113 / Epic 23 — Themes, Quick Look and final Mac integration

## Owner summary

Users get a coherent set of readable light/dark themes, a safe way to import and manage custom themes, and useful Markdown previews in Finder without opening the editor. The final app identity and icon must match that experience. The implementation reuses the existing document rendering/export engines; it does not create a second Markdown product inside Quick Look.

This is a downstream hand-off, not permission to start E23 while Claude is implementing E22. Baseline reviewed: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, 2026-09-24. At E23 start, reconcile against exact post-E22 master and write the binding `planning/epic-23-implementation.md` using this plan. Record renamed upstream interfaces rather than modifying E22 to fit old spellings. No E22 slice, active PR or editor editing contract is changed by this architecture commit.

## Baseline and dependencies

Read Theme, TokenStyle/EditorChrome, ThemeController, PreviewTheme, Package.swift, project.yml, the three renderer harnesses, and #113's security-reuse comment. ThemeController already has separate light/dark selections and an app-wide current theme, but its available catalog is immutable. Its initial persisted lookup does not enforce appearance-slot matching as strictly as selectLight/selectDark. PreviewTheme independently derives code colors and hardcodes link colors. The project registers Markdown with LSHandlerRank Owner and has no Quick Look target. Existing production icon resources were generated as placeholders; resource presence is not final art approval.

Dependencies: completed E22 chrome/settings contracts; public identity re-freeze; #79 diagram policy/calibration; #116 math fixes; #117 anchors/capabilities/export snapshots; and #121's contained reader as consumed by #118. Implement shared pure foundations in dependency order before E23's final integration. Their evidence can run later through #88/#115; do not introduce cyclic requirements that force E23 to wait for a gate that itself waits for E23.

Public brand direction from the owner's naming work is MostlyText. The current com.joncallim/macdown2 engineering identifiers are interim. Domain purchase, final bundle IDs, custom theme UTI and appcast URL are NOT established by this hand-off. The identity gate must record exact values and namespace migration before committing final identifiers. Do not guess a purchased domain or silently turn a provisional bundle ID into release identity. Theme/presentation code can be prepared with injected identity configuration, but final Finder/extension packaging cannot bypass that gate.

## User journeys and non-goals

Choose different light and dark themes; change system appearance; inspect editor, preview, menus and technical content; import a valid theme, duplicate a built-in, edit/reload it, remove the selected custom theme and recover to a readable matching fallback. A malformed file produces one useful diagnostic and leaves the current selection intact.

In Finder, Space-preview ordinary Markdown and a technical note with math/diagrams/TOC. A bad diagram, oversized file or unavailable image produces bounded readable fallback, not a blank preview or network request. Repeatedly open/close previews without growing worker/cache state. Open Markdown with the app without taking over unrelated plain-text formats.

No general theme CSS/JavaScript, remote assets/fonts, theme marketplace, visual diagram editor, arbitrary Quick Look HTML/file preview, system default-app coercion, iPad work or additional capability epic. E23 is the last planned pre-1.0 feature epic.

## Semantic palette and schema

Themes owns `ResolvedPresentationPalette`, the one semantic value used by editor chrome, PreviewTheme, export stylesheet generation and Quick Look's built-in reader appearance. Its roles include foreground/background, caret, selection background/foreground, current line, gutter foreground/background, status foreground/background, invisibles, heading, link, muted text, rule, inline/fenced code foreground/background and quote foreground/background/border. Resolve legacy optional values once through a deterministic fallback; consumers do not independently mix arbitrary RGB values.

E22 supplies the actual gutter/status/invisibles/current-line ownership. E23 applies colors through those completed interfaces without rescanning lines or recreating edit systems. Theme-only changes must not mutate document text, dirty state, undo history, source generation or parser state. Rehighlight using the existing capture/style application path; a palette change does not require reparsing.

The import/export theme-file schema is version 1: schemaVersion, stable ID, display name, appearance, chrome/semantic colors and tokenStyles. Built-in schema-less files have an internal migration path; external imports must declare a supported schema. Preserve the existing hierarchical token fallback. Built-in IDs are reserved and immutable. Imported IDs are namespaced application-generated UUIDs; retain a source theme's identity only as metadata so it cannot overwrite a built-in or unrelated installed theme.

Initial limits: 64 KiB per theme file, nesting depth 8, at most 512 token entries and 256 installed custom themes. These are reviewed defensive defaults, not measured throughput claims. Check byte limits before JSON decoding. Reject duplicate keys, unknown structural fields/version, invalid types, nonfinite/out-of-range numeric values, empty/oversized names, unsafe capture names and path/URL/executable/style fields. Codable alone does not reject duplicate or unknown keys: use a bounded structural validation pass before decoding. Do not accept CSS color strings with arbitrary syntax; normalize admitted numeric/hex colors to the existing finite color value type.

Require opaque base canvases so contrast does not depend on unknown wallpaper. Resolve selection/current-line overlays against their actual backgrounds before measuring contrast. For bundled themes, require 4.5:1 normal text and 3:1 meaningful non-text indicators; high-contrast variants target 7:1 body text. These are design acceptance thresholds based on WCAG contrast definitions, not a claim of complete WCAG conformance. Imported themes failing contrast may be installed only with a visible warning/confirmation and an always-available restore-default action; malformed/unsafe files are rejected, not merely warned.

## Theme catalog, persistence and UI

Add an actor-confined `ThemeCatalogStore` for file I/O/validation and immutable generation-tagged catalog snapshots. ThemeController remains MainActor/app-wide and publishes the current validated catalog, light/dark selections and resolved palette. Loading and selecting always validate appearance-slot compatibility. Keep one deterministic bundled fallback for each appearance; damaged external files cannot make the catalog empty or reach fatalError.

Theme storage is inside the final identity's Application Support namespace under Themes. Managed filenames derive from generated IDs, not user display names. Import reads the explicitly selected file once under its granted access and copies validated bytes into an exclusively-created staging file, then atomically renames into the owned directory. Never persist an external URL as an automatically trusted theme executable/resource. Duplicate built-ins to new custom IDs; export a copy through a save panel; delete only the chosen custom file whose identity still matches. Reject store symlinks/path redirection and do not overwrite an externally modified file without a fresh user decision.

Serialize catalog writes, but perform reads/decoding off MainActor. A debounced directory watcher emits revisioned snapshots; partial external writes retain the last-known-good current theme plus one diagnostic until a valid replacement appears. A later successful revision clears the error. Deleted/invalid selected themes resolve to same-appearance defaults and persist that deliberate fallback. Ignore late reloads after a newer import/selection, and balance watchers/security scopes on shutdown. A theme-only filesystem event cannot refresh unrelated documents or create one watcher per editor window.

Add one Appearance settings pane with system/light/dark mode if permitted by the completed settings contract, separate light/dark theme pickers, real preview sample, import/duplicate/export/delete/reveal controls, provenance and validation feedback. Do not create a second appearance preference owner when the app already has one. The sample includes prose, headings, link, quote, inline code, fenced code, selection and E22 chrome. Built-ins include at least eight distinct themes, at least four light and four dark: neutral, warm and high-contrast directions in both appearances, plus a distinct restrained accent pair. Create original palettes or retain documented compatible provenance; do not copy commercial assets.

All controls have meaningful accessibility labels, keyboard access and localized user-visible text. Built-in proper theme names need not be mechanically translated, but descriptions/errors/actions do. Resizing, pseudo-localization, Increase Contrast and Reduce Transparency must not clip the interface.

## Shared document presentation, not a second export engine

Add `DocumentPresentation` as a focused orchestration target. It depends on existing MarkdownEngine, Contributions, Math/diagram value modules and ExportService, plus injected rendering functions as needed. It must not import WindowCoordinator, Workspace, app settings UI or QuickLookUI. Platform rendering remains behind the existing renderer adapters; no duplicate cmark/template/contribution implementation lives in the extension.

Semantic input: `PresentationRequest` with immutable source, source identity, effective parse policy, resolved palette, destination policy, explicit resource capability and resource/deadline limits. Output: `PreparedPresentation` with static body/template data, approved immutable attachments, diagnostics and the #117 heading index. It wraps/refactors the existing ExportService composition and contribution adaptation; Export continues to consume the same engine with its own destination rules. No stale Preview parse or mutable application settings are read from a render task.

Policies are explicit: ordinary HTML Export may preserve its documented authored markup behavior; strict PDF/self-contained use their existing restrictions; Quick Look uses passive authored content and authorized attachments only. Do not encode Quick Look as 'export to a fake PDF URL' or grant it a pretend document-directory URL. #118's final-byte accounting and #121's opened-object read boundary are reused where applicable, with Quick Look-specific smaller limits.

## Quick Look provider and trust boundary

Use an embedded data-based `QLPreviewProvider` conforming to QLPreviewingController. Add its target/resources/entitlements to project.yml and regenerate the project. Set QLIsDataBasedPreview and the supported Markdown content types in the extension configuration. The initial platform probe must compile the actual macOS 26 QuickLookUI signatures, return one static HTML QLPreviewReply with one in-memory attachment, execute Finder preview/cancellation and document the file access actually granted. This is a narrow SDK/sandbox feasibility test, not permission to start a parallel renderer.

The provider receives one requested file capability. Read its bounded bytes without creating a FileDocument, recovery buffer, workspace, settings window or document watcher. Reuse the supported encoding policy through a stateless decode adapter; do not normalize/rewrite the source file. A user-selected/read-only entitlement does not itself grant the parent folder. Authored relative images outside the actual grant render as alt/source placeholders. Never request a broader entitlement or infer directory access merely because ordinary Export has it.

Return static HTML through a bounded QLPreviewReply data closure and `cid:` attachments supported by the verified SDK. Main document has no filesystem base URL. Escape or suppress authored raw HTML under an explicit passive serialization mode; never include authored scripts, styles, iframes, forms, objects, embeds, event handlers, remote URLs as rendering resources or active SVG. Navigation URLs use #117's safe link policy. Apply a deny-by-default CSP with only the generated inline stylesheet and approved attachments permitted. A data-based reply does not automatically prove network denial: exercise real hostile fixtures and observe network behavior.

The internal math/diagram renderers may execute bundled first-party engine code in their isolated WebKit workers; the returned document must not require that runtime. Keep the D2 WASM unsafe-eval exception confined to its internal harness, never copied into final Quick Look HTML. Preserve existing strict renderer containment and sanitize/validate resulting passive artifacts before delivery. For the bounded 1.0 Quick Look display, raster attachments are allowed for diagrams where safe SVG/foreignObject handling cannot be guaranteed; use the existing renderer's real preview artifact or its verified native conversion, not a third renderer. HTML/PDF Export still retains its vector output. Explicitly record this destination difference.

No App Group is introduced just to read live app theme selections. Quick Look ships a fixed readable light/dark reader pair derived from bundled semantic palettes, using the host-supported appearance mechanism/CSS media policy verified in the platform probe. A cold standalone Finder preview must work when the app has never launched.

## Request lifecycle and budgets

Each request has a unique ID, immutable input and one terminal reply gate. States: admitted -> reading -> preparing -> deriving -> replied/failed/cancelled. A completion from a cancelled/older request cannot publish into another. MainActor is reserved for APIs that require it; file reads, parsing, hashing and static assembly run on bounded workers.

Initial defensive ceilings: 8 MiB source admission, 16 MiB final HTML plus attachments, 4 MiB per attachment, 64 attachments, 16 million raster pixels per artifact, one active expensive renderer job per worker and a small fixed worker pool. Oversize source returns a clearly labelled bounded source preview using at most the first 64 KiB, decoded safely without splitting a Unicode unit; it does not parse the whole oversized document first. Existing narrower math/diagram limits still apply.

Use one absolute end-to-end derivation deadline, approximately two seconds for the technical preview path, not two seconds per diagram. On budget/deadline failure, complete the static reply with escaped source placeholders for unfinished/broken diagrams. Do not await an uncooperative child task before returning fallback. Revoke its publication rights, cancel through supported APIs and retain only bounded draining worker state. A stuck worker is not immediately returned to the free pool; repeated cancelled requests cannot create unlimited replacement web views. No claim is made that stopLoading interrupts arbitrary synchronous WASM immediately.

Performance targets from the issue remain targets: ordinary Markdown up to 1 MiB median under 300 ms and p95 under 750 ms on the named M-series test machine; 100–250 KiB technical fixtures with up to three diagrams around a two-second total budget. Measure cold provider startup as well as warm execution. If cold runtime cannot meet the deadline, return the specified source fallback rather than weakening the target or secretly downloading renderers. Run 100 open/close/cancel cycles and report retained memory/worker/descriptor counts, not just average render time.

## Finder, identity and final artwork

The identity record must freeze final app bundle ID, Quick Look bundle ID, theme-file UTI/extension, public CLI name, support/defaults/recovery migration map, public repository links and updater identity before final packaging. Use the owner-approved name; do not restart a naming exercise or assume proposed domains were bought. #18 owns state migration mechanics and signing; E23 supplies the finalized theme and Finder identifiers.

Register the Quick Look extension for `net.daringfireball.markdown` and only the intended Markdown aliases/UTIs. Do not register a broad public.text/public.data preview handler. The app's Markdown declaration is an Editor, not the original owner of the shared Markdown UTI: correct LSHandlerRank accordingly and use imported declarations where appropriate. Retain intentional code/plain-text editing registrations without changing users' default applications programmatically. Verify Finder Open With and duplicate handler behavior with legacy MacDown installed alongside the new identity.

Replace the placeholder icon with approved final artwork and document its source/license. Validate every required asset size, actool compilation, effective Info.plist icon configuration, Dock/Finder/Launchpad/Quick Look presentation, transparency and small-size legibility. A generator script and populated slots alone do not satisfy final-icon acceptance. No final artwork is generated or claimed approved by this architecture hand-off.

## Test matrix and implementation sequence

A. After E22, record the exact identity/interface baseline and perform the minimal data-based Quick Look/attachment/permission probe. Stop on missing ownership values or unsupported sandbox assumptions; no broad entitlement fallback.

B. Implement semantic palette resolution and eight bundled palettes with contrast/golden adapter tests. Assert theme change leaves text, undo, selection, parse count and generation unchanged. Integrate #79's neutral diagram policy and calibration.

C. Implement the versioned theme catalog/storage/persistence and Appearance pane. Adversarial tests: invalid/duplicate JSON keys, unknown versions, NaN, oversized/deep input, malicious IDs/paths, reserved IDs, duplicate imports, store symlinks, interrupted writes, external edit/delete, wrong-appearance saved IDs, empty/corrupt catalog, concurrent imports and stale reloads.

D. Refactor DocumentPresentation around #116/#117/#118's shared contracts and prove existing Export regression tests pass before adding the provider. No duplicated anchor, parser, resource or stylesheet policy.

E. Implement static Quick Look requests and bounded fallbacks. Test no app launch, non-Markdown rejection, no parent grant, outside-root symlink race, raw HTML/URL injection, scripts/CSS/SVG/font/network attempts, bad/slow/oversized diagrams, encoding errors, cancellation and repeated lifecycle. Verify actual reply attachments and appearance in Finder, not only provider unit tests.

F. Finalize identity/Finder/icon integration; run Release app/provider builds, package/app tests, actual Quick Look/Appearance/VoiceOver journeys and full security/performance matrix. Reconcile README, E23 and #79/#115 evidence. All feature strings enter catalogs in the same implementation units; final E16 freezes them only after the debt gate.

## Self-review and completion

Review addressed appearance-slot mismatch, independent derived RGB values, reparsing on theme changes, duplicate JSON keys ignored by Codable, external files changing mid-import, directory access inferred from a file grant, app-only state leaking into the extension, per-diagram deadlines multiplying, TaskGroup cancellation still waiting, unsafe-eval leaking into final HTML, and output/caches unbounded by byte count.

The architecture fixes ownership/data flow and deliberately gates empirical SDK, minimum-OS, renderer and artwork facts. It is not a claim that Quick Look has been implemented or measured. E23 closes only with its acceptance matrix complete, #79 closed, identity/artwork finalized and no new required evidence debt hidden as 'polish'.

## Primary references

- Apple QLPreviewProvider: https://developer.apple.com/documentation/quicklookui/qlpreviewprovider
- Apple QLFilePreviewRequest: https://developer.apple.com/documentation/quicklookui/qlfilepreviewrequest
- Apple QLPreviewReply: https://developer.apple.com/documentation/quicklookui/qlpreviewreply
- W3C contrast definitions: https://www.w3.org/TR/WCAG22/#contrast-minimum and https://www.w3.org/TR/WCAG22/#non-text-contrast
