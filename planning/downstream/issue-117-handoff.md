# Issue #117 — Contribution destinations, anchors and export identity

## Owner summary

A table of contents should navigate to its actual heading, and exporting one document must never switch to a different window or combine two revisions. Contribution types must tell consumers which representations they can display. This plan supplies those contracts without creating a general HTML plugin surface or replacing the native preview.

Baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, 2026-09-24. Deferred until the relevant post-E22 interfaces are reconciled. E22 exclusively owns the command-palette registry portion of #117: consume its completed command descriptors/consistency tests, do not design or edit those slices here. #113 consumes this document's anchors/presentation capabilities; #118 consumes its export snapshot/origin. The issue remains open until implementation and evidence are complete.

## Observed implementation

Read ContributionRepresentation, TOCContribution, MarkdownDocument, TextualMarkdownPreview/BlockView, ExportCoordinator and WindowCoordinator+Export. The issue had no comments. `.html` documentation says neither adapter handles it, although Export now does. TOCContribution deliberately emits escaped plain-text list entries. BlockView sends every resolved link to NSWorkspace. MarkdownDocument already contains a fresh immutable parse result, original SourceMap and front-matter line offset.

ExportCoordinator resolves a key model inside an async entry, later anchors panels/alerts to NSApp.keyWindow, and rereads document.text/generation/theme after awaits during contribution adaptation/request creation. WindowCoordinator already owns an exportingModels guard by model identity. Preserve that guard, but attach it to a synchronously captured origin and one immutable content snapshot.

## Journeys and invariants

Click a generated TOC entry or authored same-document heading link and reach the intended heading in native Preview and exported HTML. Duplicate and Unicode headings remain distinguishable. Invalid internal links stay internal with bounded feedback rather than launching externally. Export from window A, focus/edit B while rendering is active, and obtain only the chosen snapshot of A. Closing A never attaches its completion alert to B.

No authored heading/source rewrite. No stale Preview parse reused for export. No HTML execution capability added to native Preview. Preserve contribution range validation, overlap rejection, diagnostics, limits and source fallback. Every navigation carries current document/generation identity. Source coordinates are original-source UTF-16 offsets at module boundaries, not mixed cmark byte columns and Swift character offsets.

## Destination capability contract

In Contributions add `ContributionDestination`: nativePreview, htmlExport, pdfExport and quickLook. Keep representations as values; compute supported destinations centrally rather than maintain duplicated booleans. Markdown supports its admitted destinations; passive first-party HTML supports only static destinations. A registry run receives its destination and rejects unsupported producer/representation combinations with a typed diagnostic before presentation.

Do not add a user-settable trusted Boolean. Passive first-party HTML is produced by the trusted renderer/adapters under destination policy; Quick Look still applies its stricter serializer/resource rules. User-authored raw HTML is not reclassified as trusted contribution HTML. Native math/diagram views retain their specialized renderer paths. Admission failure preserves original source and uses the normal diagnostic catalog. Update stale representation documentation and exhaustiveness tests in both adapters.

## One heading-anchor index

MarkdownEngine owns the pure `HeadingAnchorIndex` value and deterministic allocation algorithm. Each record contains heading source identity/range, level, plain title, canonical fragment ID and original source line. Build it once from the same parsed authored document, including the reserved authored-ID inventory below, and share that result with Contributions/Preview/Export. The index itself contains no DOM object or UI state.

Anchor-policy v1:

1. Extract plain heading text through the parser, not regex over Markdown. Normalize to Unicode NFC and lowercase without a user's locale-dependent transform.
2. Keep Unicode letters/numbers/combining marks, `_` and `-`; collapse whitespace into `-`, remove other punctuation and trim leading/trailing hyphens. Empty output becomes `section`.
3. Initialize the used-ID set with the exact decoded authored HTML IDs. Allocate headings in source order: base, then base-1, base-2, etc. Use one global set; counting identical titles alone mishandles `A`, `A`, `A-1`.
4. Bound IDs to 256 UTF-8 bytes with a grapheme-safe prefix and deterministic hash suffix for long bases, reserving space for collision suffixes. Never persist process-random hashValue.

IDs are deterministic for the same source/reservation inventory. An earlier duplicate heading or new explicit ID can change later suffixes; do not claim persistent cross-edit identity from a slug. Runtime navigation pairs the index with document revision and source/block identity. An old index cannot select offsets in a new document.

## Chosen raw-HTML collision policy

**Reserve authored IDs; never rename authored HTML to make room for generated headings.** Example: `<div id="overview">…</div>` followed by `# Overview` reserves overview; the Markdown heading and generated TOC use overview-1. An authored link to #overview retains its explicit-HTML meaning in ordinary HTML export; native Markdown Preview does not pretend it displays arbitrary raw HTML and reports that target unavailable rather than jumping to the different heading. Quick Look may omit raw HTML but reserves the same source IDs so generated heading IDs remain consistent.

Introduce a narrow read-only `AuthoredHTMLIDInventory` adapter using exact SwiftSoup 2.13.9 (upstream non-prerelease inspected 2026-09-24). Its sole purpose here is non-executing HTML parsing/attribute-entity decoding and anchor validation, not sanitization, fetching, rendering or rewriting the user's markup. Confine parser objects to the background parse operation and return only immutable IDs. Keep dependency/version/license explicit; no DOM object is made unchecked Sendable.

Inventory the Markdown AST's authored raw-HTML blocks/inlines, coalescing adjacent fragments with their actual context rather than splitting a tag/attribute across calls. Use explicit HTML parsing mode, not auto-detected XML mode. Include quoted/unquoted IDs, character references, duplicate authored IDs and relevant legacy named anchors when they compete with fragment navigation. IDs are case-sensitive DOM values: do not lowercase or NFC-normalize an explicit ID just because generated slugs are normalized. Code fences/front matter/escaped markup are not active authored HTML.

The final ordinary static HTML is additionally checked before resource-data-URI amplification: each generated heading ID must resolve uniquely to its intended emitted Markdown heading, and every generated TOC href must refer to that verified target. Use a side table of expected emitted heading identity/order; do not assume any element carrying that ID is the correct heading. Preserve the original serialized HTML bytes rather than round-tripping/reformatting them through the parser. New resource rewriting may change approved URL fields only and must not add/remove ID attributes after this validation.

This second check catches raw markup that encloses or swallows generated headings, parser-context disagreement and IDs introduced by trusted contribution/template content. On ambiguity, missing generated targets, unsupported parsing or safety-budget exhaustion, emit a precise localized anchor diagnostic and refuse the static operation that would claim a working generated TOC. Keep the prior output untouched. Never silently choose the first duplicate element, add a second inconsistent index or fall through to an external browser. Native Preview retains source-readable fallback and does not publish a guessed index.

Use a trusted initial 8 MiB bound for HTML analyzed for anchor validation, 4,096 explicit IDs and bounded fragment count; perform preflight byte checks before DOM allocation. Plain Markdown without raw/generated HTML ID collision potential takes the direct emitted-heading validation path and does not acquire an unnecessary HTML DOM just because it is large. Large raw-HTML documents exceeding this analysis policy receive the explicit bounded-operation diagnostic, not unbounded parsing. Calibrate memory/latency with #118 before finalizing these limits. No HTTP/file-loading SwiftSoup API is called. A deadline does not imply a synchronous parser can be forcibly interrupted; bounded admission and confined workers remain required.

The contract is for the static generated document. Ordinary export's separately documented author-script behavior cannot guarantee anchors after authored JavaScript deliberately rewrites the DOM; do not claim that it can. Quick Look and native Preview do not enable such authored execution. Actual browser/WebKit fixtures must validate entity/rawtext/markup edge cases against the chosen parser; no browser-equivalence or security claim is accepted merely because a library advertises HTML5 support.

## TOC output and native navigation

Assign IDs during the existing authored-heading cmark walk, mapping original source positions through front matter/SourceMap. Match records to actual authored nodes and assert level/title/source agreement. Do not zip all rendered h1–h6 tags: raw HTML and generated fragments can contain headings that were not authored Markdown headings. A mismatch is a typed failure, never guessed IDs.

TOCContribution emits escaped link labels and percent-encoded fragment destinations from that index. Keep top-level-paragraph-only marker admission, hierarchy and empty-heading behavior. Escape Markdown labels separately from HTML attributes/URL fragments. Generated TOC content must not create another heading index.

Add pure `PreviewLinkAction`: internalHeading(record, generation), permittedExternal(URL), unresolvedInternal(fragment) or denied. Recognize bare fragments and URLs that demonstrably identify the same current file without a different query; decode a fragment once and match the index. Reject malformed encoding, controls and unsafe schemes. A missing or authored-HTML-only target never falls through to NSWorkspace.

BlockView receives an internal-navigation closure owned by its document/controller. Reuse ScrollSyncController/source-navigation machinery, preserving Reduce Motion and keyboard focus policy. Revalidate document/generation at execution. E23 Quick Look uses static HTML fragment navigation and never calls app window services. Test same filenames in different directories, encoded Unicode fragments, duplicate headings, moves, front matter and rapid edit/click interleaving. Deliberate external navigation does not grant automatic network resource loads.

## Explicit export origin and immutable snapshot

Make command dispatch synchronous on MainActor: resolve/capture originating WindowController/model/document identity and reserve its export operation before creating a Task. Pass that origin into the async coordinator. Menu validation may consult current focus, but execution must not consult ambient keyModel/keyWindow again.

Present the save panel on the captured origin. After it returns, verify the same document lifetime remains exportable. Capture `ExportSnapshot` once: document identity, source, generation, source URL/root lease, effective parse policy, resolved semantic theme and destination policy. Use the normal editor-to-document publication boundary, not a second edit publication. A closed/replaced origin cancels rather than exporting whatever later occupies the window.

Parse and run every contribution from this snapshot. Construct ExportRequest from the same value. Do not reread live text/theme/generation after ParseEngine or renderer awaits. Later typing may continue without invalidating an immutable export snapshot; operation cancellation or lost permissions may abort. File-resource changes follow #118's independent snapshot/read policy.

Keep alerts on the explicit origin; when it is gone, cancel pending UI and use only an existing safe application-level error route where required, never a sheet on an unrelated window. Release the exporting guard exactly once on every terminal path. #118 extends this same operation with progress/destination leases rather than adding a competing state machine.

## Extra parse disposition

Measure fresh MarkdownEngine parse, raw-ID analysis when needed and distinct cmark composition separately in Release: ordinary 1 MiB text, technical content, raw-HTML boundaries and cold/warm operations. Do not remove cmark just because swift-markdown also parses; they serve different responsibilities. E23 DocumentPresentation accepts an already-created immutable MarkdownDocument/index only when its complete source/options identity matches; it never borrows mutable Preview cache state.

Avoid a redundant second MarkdownEngine parse of the identical export snapshot. Keep the distinct cmark pass. Record absolute duration and fraction of export time instead of claiming negligible overhead without numbers. A later renderer/parser replacement requires a separate justified decision; it is not part of this hand-off. Source identity is not solely a saturating Int revision.

## Tests and execution sequence

A. Add pure index/capability tests and the bounded raw-ID adapter. Golden fixtures: A/A/A-1, punctuation-only, CJK/combining marks, locale changes, long headings, front matter, explicit ID/name collision, quoted/unquoted/entity IDs, rawtext/comments, malformed enclosing markup and generated contribution IDs. Assert unchanged authored bytes and deterministic generated IDs. Verify the actual SwiftSoup mode/API at the pinned version and preserve its license.

B. Add cmark IDs, TOC links and final pre-embedding target validation, then native internal routing. Verify actual HTML/browser targets and source navigation, not only string containment. Over-budget/ambiguous output must fail before writer publication. #113 consumes the same index/policy.

C. Capture origin/snapshot. Use controllable parse/render continuations to edit A, change its theme, focus B, Save As, close A and cancel while suspended. Output source/generation/theme/contribution identity remains one snapshot and no sheet targets B.

D. Consume E22 command-eligibility evidence without editing its work; run the final menu/palette consistency tests with explicit exclusions.

E. Run Release parse/HTML-analysis measurements, affected/full package tests, strict lint/format, Release app build and actual TOC/export multi-window journeys via #88. Stop on parser disagreement that can misroute links, unbounded analysis, node identity mismatch or any weakened source/security rule.

## Self-review and completion

Review caught natural-suffix slug collisions, locale-dependent output, front-matter/byte-offset confusion, generated-heading contamination, ambiguous raw HTML IDs, character-reference decoding, raw markup swallowing headings, final embedded HTML amplification, unknown-anchor browser fallback and mutable source/window rereads across awaits. The raw-HTML policy is now selected, not left as competing implementation alternatives.

No runtime/benchmark result is asserted. All five issue areas must close: destination semantics, navigable anchors, measured parse disposition, E22 registry evidence and export targeting, with #115 reconciliation. A static-presentation implementation alone does not close #117.

Primary parser references inspected: https://github.com/scinfu/SwiftSoup/releases/tag/2.13.9 and https://github.com/scinfu/SwiftSoup/blob/2.13.9/README.md .
