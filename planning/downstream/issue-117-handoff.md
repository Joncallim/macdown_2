# Issue #117 — Contribution destinations, anchors and export identity

## Owner summary

A table of contents should navigate to its actual heading, and exporting one document must never switch to a different window or combine two revisions. Contribution types must tell consumers which representations they can display. This plan supplies those missing contracts without creating a general HTML plugin surface or replacing the native preview.

Baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, 2026-09-24. Deferred until the relevant post-E22 interfaces are reconciled. E22 exclusively owns the command-palette registry portion of #117: consume its completed command descriptors/consistency tests, do not design or edit those slices here. #113 consumes this document's anchors and presentation capabilities; #118 consumes its export snapshot/origin. The issue remains open until its implementation and evidence are complete.

## Observed implementation

Read ContributionRepresentation, TOCContribution, MarkdownDocument, TextualMarkdownPreview/BlockView, ExportCoordinator and WindowCoordinator+Export. The issue had no comments. `.html` documentation says neither adapter handles it, although Export now does. TOCContribution deliberately emits escaped plain-text list entries. BlockView sends every resolved link to NSWorkspace. MarkdownDocument already contains a fresh immutable parse result, original SourceMap and front-matter line offset.

ExportCoordinator resolves a key model inside an async entry, later anchors panels/alerts to NSApp.keyWindow, and rereads document.text/generation/theme after awaits during contribution adaptation and request creation. WindowCoordinator already owns an exportingModels guard by model identity. Preserve that guard, but attach it to a synchronous captured origin and one immutable content snapshot.

## Journeys and invariants

Click a generated TOC entry or authored same-document link and reach the intended heading in native Preview and exported HTML. Duplicate and Unicode headings remain distinguishable. An invalid internal link stays internal and gives bounded feedback; it is not launched externally. Export from window A, focus/edit window B while the panel/render is active, and obtain only the chosen snapshot of A. Closing A never attaches its completion alert to B.

No authored heading/source rewrite. No stale Preview parse is reused for export. No HTML execution capability is added to native Preview. Preserve contribution range validation, overlap rejection, diagnostics, limits and source fallback. Every navigation carries current document/generation identity. Source positions are original-source UTF-16 offsets at module boundaries, never an unlabelled mixture of cmark byte columns and Swift character offsets.

## Destination capability contract

In Contributions add `ContributionDestination` with nativePreview, htmlExport, pdfExport and quickLook. Keep representations as values; compute their supported destinations centrally rather than maintaining contradictory duplicated booleans. Markdown supports the admitted Markdown destinations; passive first-party HTML supports only static destinations. A registry run receives its destination and rejects unsupported producer/representation combinations with a typed diagnostic before presentation.

Do not add a boolean 'trusted' field which untrusted input can set. Passive HTML is produced by the already-trusted first-party renderer/adapters under destination policy; Quick Look still applies its stricter serializer/resource rules. User-authored raw HTML is not reclassified as trusted contribution HTML. Native math/diagram views retain their specialized renderer paths. Admission failure preserves original source and uses the normal diagnostic catalog. Update stale representation documentation and exhaustiveness tests in both adapters.

## One heading-anchor index

MarkdownEngine owns a pure `HeadingAnchorIndex`, generated from the same parsed authored document used by the consumer. Each record contains heading source identity/range, level, plain title, canonical fragment ID and its original source line. This module already feeds Contributions, Preview and ExportService; no new package is needed.

Version the algorithm as anchor-policy v1 and lock it with golden fixtures:

1. Extract plain heading text through the parser, not a regex over Markdown syntax. Normalize to Unicode NFC and lowercase without a user's locale-dependent transform.
2. Keep Unicode letters/numbers/combining marks, `_` and `-`. Collapse whitespace into `-`, remove other punctuation and trim leading/trailing hyphens. Empty output becomes `section`.
3. Allocate IDs in authored document order using one used-ID set. Try the base, then base-1, base-2, etc. Never assume counting identical titles alone prevents collisions: `A`, `A`, `A-1` must produce three distinct IDs.
4. Bound generated IDs to 256 UTF-8 bytes using a grapheme-safe prefix plus a deterministic hash suffix of the full normalized base when necessary; then reserve room for collision suffixes. No process-random Swift hashValue enters persisted HTML.

IDs are deterministic for the same source. Inserting an earlier identical heading can change later duplicate suffixes; do not claim persistent cross-edit identity from a slug. Runtime navigation instead pairs the index with a document revision and stable source/block identity. No index from an old revision may select offsets in a new one.

Static Export assigns these IDs during its existing authored-heading cmark walk, mapping original source positions through front-matter offsets/SourceMap. Match heading records to actual authored nodes and assert level/title/source agreement. Do not zip blindly with all rendered `<h*>` strings: raw HTML and generated fragments can contain headings that are not authored Markdown headings. A mismatch yields an explicit diagnostic/failure in the parity test, not guessed IDs. Raw authored HTML IDs remain authored behavior; collisions with generated anchors are a documented ordinary-export policy and must not silently make TOCs navigate to an unrelated raw element. Resolve such collisions by reserving parsed explicit HTML IDs when that destination preserves them, or use a distinct generated anchor namespace with tested alias rules; choose one in the raw-HTML parity fixture before broad implementation.

TOCContribution emits escaped link labels and percent-encoded fragment destinations from the index. Keep its existing top-level-paragraph-only marker admission, hierarchy and empty-heading behavior. Escape Markdown labels separately from HTML attributes/URL fragments. Generated TOC content must not create a second heading index.

## Native link routing

Add a value result `PreviewLinkAction`: internalHeading(record, generation), permittedExternal(URL), unresolvedInternal(fragment) or denied. Pure resolution precedes effects. Recognize bare `#fragment` and URLs that demonstrably identify the same current file without a different query; decode the fragment once and match the canonical index. Reject malformed encoding, controls and unsafe schemes. A missing anchor never falls through to NSWorkspace.

BlockView receives an internal-navigation closure owned by the document preview/controller. Use the existing ScrollSyncController jump/source-navigation machinery to reach the indexed heading, preserving Reduce Motion behavior and keyboard focus policy. Validate document/generation again when the action executes. E23 Quick Look simply uses static HTML fragment navigation; it never calls app window services.

Test same filenames in different directories, percent-encoded Unicode fragments, duplicate headings, empty anchors, moved documents, front matter, nested headings, failed links and rapid edits between click and dispatch. Keep external-link policy separate from resource fetching: allowing a deliberate browser navigation does not grant automatic network loads.

## Explicit export origin and immutable snapshot

Make the public command dispatch synchronous on MainActor: resolve/capture originating WindowController/model/document identity and reserve its export operation before creating a Task. Pass that explicit origin into the async coordinator. Menu validation may consult current focus, but execution must not consult ambient keyModel/keyWindow again.

Present the save panel on the captured origin window. After the panel returns, verify the same document lifetime still exists and is exportable. Capture `ExportSnapshot` once: document identity, source text, source generation, source URL/resource-root lease, effective parse policy, resolved semantic theme and destination policy. Use the normal editor-to-document publication boundary; do not invent a second edit publication. A closed/replaced origin cancels, rather than exporting whatever later occupies the window.

Parse and run every contribution from that immutable snapshot. Construct ExportRequest from the same snapshot. Do not reread live text, theme or generation after awaiting ParseEngine or a renderer. Export represents the accepted snapshot; later edits may continue without cancelling a valid immutable export. Only operation cancellation or lost permissions abort its remaining work. File-resource changes are governed separately by #118's snapshot/read policy.

Keep alert ownership explicit. When the original window is gone, cancel its pending UI and record completion/error through an existing safe application-level route only if required; never attach a sheet to an unrelated window. Release the exporting guard exactly once, including panel cancellation, origin disappearance and thrown errors. #118 extends this operation with progress and destination leases rather than adding a competing state machine.

## Extra parse disposition

Measure fresh MarkdownEngine parse and cmark composition separately on Release: ordinary 1 MiB text, technical content, and cold/warm operation timings. Do not remove cmark merely because swift-markdown also parses: they serve different structural/rendering responsibilities. E23's DocumentPresentation accepts the already-created immutable MarkdownDocument for contributions/heading index and reuses it only when its complete source/options identity matches; it must not ask Preview for mutable cached state.

Proposed materiality rule: avoid a redundant second MarkdownEngine parse when one identical parse has already been produced for the same export snapshot. Keep the distinct cmark pass unless measurements justify a separate architecture decision. Record its absolute duration and fraction of total export time; do not declare 'negligible' without numbers or replace cmark on a guess. Source identity is checked by value/generation within one immutable request, not solely by a saturating Int revision.

## Tests and execution sequence

A. Add pure anchor-policy/capability tests in MarkdownEngineTests/ContributionsTests. Golden corpus includes `A/A/A-1`, punctuation-only, CJK, combining marks, Turkish-I under different locales, very long headings, nested headings and front matter. Lock output escaping and destination admission.

B. Add cmark heading IDs and TOC links using one index, then native internal routing. Verify real HTML fragment targets and app source navigation, not just string containment. #113 consumes this outcome. Resolve the explicit-raw-HTML-ID collision policy before this implementation begins; it must remain compatible with #118's parity rules.

C. Capture origin and immutable export snapshot. Use controllable parse/render continuations to edit A, change its theme, focus B, Save As, close A and cancel while suspended. Assert output source/generation/theme/contribution identity remain one snapshot and no sheet targets B.

D. Consume E22 command-eligibility coverage as an upstream result without editing its work. Run post-E22 menu/palette consistency tests and require explicit exclusions for noneligible commands.

E. Run Release parse measurements, affected/full package tests, strict lint/format, Release app build and actual TOC/export multi-window journeys through #88's harness. Stop if correct node identity requires a different parser contract or any source-fidelity/security rule must weaken.

## Self-review, completion and residual risks

Review caught slug collisions with naturally suffixed headings, locale-sensitive output, front-matter/byte-offset mismatches, generated-heading contamination, external fallback for unknown anchors, ambient window capture before async dispatch, and source/theme rereads across awaits. The raw-HTML explicit-ID collision remains a bounded required policy fixture, not permission for arbitrary inconsistent anchors; its selected outcome must be recorded during the pre-implementation baseline pass.

No runtime/benchmark result is asserted. Completion requires all five issue areas: destinations, navigation, parse disposition, E22 registry evidence and export targeting, plus #115 reconciliation. Do not close #117 with only its static-presentation half implemented.
