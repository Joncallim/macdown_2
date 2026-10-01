# Issue #117 — Destination capabilities, anchors and export identity

## Owner summary

Make TOCs navigate to the intended heading, make contribution destinations explicit, and ensure an export always uses one document revision from the initiating window. Preserve the native preview and ordinary HTML export's documented authored-markup policy; do not turn TOC work into an arbitrary HTML sanitizer or a new whole-document size restriction.

Reviewed baseline: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`, 2026-09-26. See [README](README.md), [readiness review](READINESS_REVIEW.md) and original #125 history. E22 retains command-catalog consistency. This hand-off consumes its result and its selection/reveal APIs, not its active implementation branch.

## Reconciliation

ContributionRepresentation, TOCContribution, MarkdownDocument, native Preview BlockView and ExportCoordinator remain unchanged from the first review. Export supports HTML representations while native generic contribution admission rejects them. TOC is plain text; links are sent to NSWorkspace. Export's asynchronous code rereads mutable document/theme state and chooses ambient key windows for UI.

E22 now owns a cached `EditorTextSystem.selectionSet` because AppKit alone does not preserve every caret set. Native TOC/source actions must route through the completed controller single-selection/reveal path, which invalidates stale secondary selection state. Do not assign NSTextView.selectedRanges directly.

## Contract ownership and dependency order

Contributions owns ContributionDestination (nativePreview, htmlExport, pdfExport, quickLook) and representation-to-destination admission. Passive first-party HTML is static-destination-only; native specialized math/diagram views stay specialized. A user-settable trusted flag is not an admission mechanism. Unsupported contributions preserve source and return typed diagnostics.

MarkdownEngine owns HeadingAnchorIndex and its pure allocator. Its bounded authored-ID inventory adapter may depend on pinned SwiftSoup 2.13.9 as originally proposed, solely for non-executing HTML parsing/entity decoding. Confine parser objects to one worker and return immutable values; no fetching or unchecked Sendable DOM objects. The dependency must compile and pass the targeted parser corpus before use. Do not require DocumentPresentation just to build anchors.

The app owns ExportOrigin and immutable ExportSnapshot. Initially the snapshot carries the existing value-type Theme and effective post-E22 parse options. E23 later adapts that value into ResolvedPresentationPalette without changing snapshot timing or identity. This avoids the prior cycle where #117 required E23's palette and E23 required #117. #118 extends the SAME operation with progress/publication, and E23 moves only shared orchestration into DocumentPresentation.

## Heading index and deterministic allocation

Build one index from the immutable authored source/parse result. A heading record contains original-source identity, UTF-16 range/line, level, plain title and allocated fragment. Never identify repeated headings only by title or by index in a list of all rendered h-tags.

Anchor policy v1: parse plain heading text; normalize generated bases to NFC and locale-independent lowercase; keep Unicode letters/numbers/combining marks, `_` and `-`; collapse whitespace to `-`, remove other punctuation, trim hyphens and use section for an empty base. Initialize one global used-ID set with decoded authored IDs/named anchors, then try base, base-1, base-2, etc. This handles A/A/A-1 correctly. Bound generated IDs to 256 UTF-8 bytes with a grapheme-safe prefix and deterministic SHA-256-derived suffix, reserving suffix space; never use randomized Swift hashValue. Include allocator/Unicode policy version in reproducibility records.

Reserve authored HTML IDs; never rewrite them to make room. An authored `<div id="overview">` followed by `# Overview` produces the generated heading overview-1. Explicit IDs retain exact DOM string semantics, not generated-slug lowercasing/NFC. Native Markdown Preview must not silently route #overview to the different heading when it does not render the raw HTML element.

Index identity includes document/recovery lifetime, source generation/content identity and parse policy. Identical source yields identical allocation; insertion of an earlier duplicate may change later suffixes. This is deterministic naming, not permanent cross-edit identity. Generated TOCs use the allocated index and cannot introduce another heading inventory.

## Bounded raw-ID inventory and failure containment

Inspect authored raw-HTML blocks/inlines in correct parser context, excluding code/front matter/escaped markup. Coalesce fragments when a tag crosses runs. Use explicit HTML mode, not XML auto-detection. Include quoted/unquoted/entity IDs, comments/rawtext, legacy named anchors and malformed structures in the corpus. Static generated contributions/template IDs participate in collision validation without masquerading as authored headings.

After cmark emits the body and before resource-data-URI amplification, verify each generated target is uniquely the expected authored Markdown heading and each generated TOC link points to it. Do not reserialize the HTML through the validation parser. Map cmark source locations through front-matter offsets and SourceMap; reject a mismatched heading record instead of zipping all `<h1>`–`<h6>` elements. Resource rewriting after validation must not create/remove IDs.

Corrected failure policy:

- Documents without generated TOC/heading-link functionality do not acquire a new global DOM gate. Ordinary no-TOC HTML export retains existing admission limits and raw-markup behavior.
- Normal valid TOCs within the supported policy MUST be navigable. Tests may not accept source fallback for those fixtures.
- When malformed/ambiguous authored markup prevents a reliable generated target, ordinary HTML export must not claim a working generated TOC. Return an explicit anchor diagnostic and preserve prior output when that requested feature cannot be produced. The failure is specific, not a generic invalid-document claim.
- Quick Look and native Preview isolate the failed TOC contribution: preserve readable authored marker/source with a diagnostic and continue the rest of the document. They must not fail/blank the whole preview because the TOC cannot be admitted. Generated heading navigation is not published from an unverified index.
- A raw-HTML-only target that native Preview does not display is an unresolved internal target, not an external-navigation fallback.

The earlier unconditional 8 MiB final-HTML analysis ceiling is REMOVED. Use a distinct anchor-analysis policy: initially 8 MiB of actually analyzed markup and 4,096 explicit IDs, subject to #118's documented calibration. Exceeding that sub-budget follows the destination-specific contribution policy above; it is not a silent reduction of normal export's 32 MiB source/128 MiB prepared-body ceilings. Pure Markdown takes the direct node/index path without a full HTML DOM. Bound bytes, depth/work where the parser supports it and queued analysis; input-byte bounds alone do not establish a hard parser-time/RSS guarantee. A failed parser probe requires a focused alternative before claiming this policy is implemented.

Ordinary authored JavaScript may deliberately alter its own exported DOM later under that destination's existing policy; static TOC validation is not a promise about arbitrary subsequent scripts. Native Preview/Quick Look enable no such authored execution.

## TOC serialization and navigation

Retain top-level-paragraph-only [TOC] admission, nested heading hierarchy and no-heading placeholder. Escape labels as Markdown, encode fragment destinations once and HTML-escape attribute values at serialization; these are separate operations. Literal percent/entity/quote/CJK cases must reach the exact ID.

PreviewLinkAction is internalHeading(record, identity), unresolvedInternal(fragment), permittedExternal(URL) or denied. Bare fragments and verified same-current-file URLs are internal; compare complete file identity/path semantics rather than basename. A different query is not silently treated as the current document. Decode fragment once, reject malformed escapes/controls/unsafe schemes and never send unresolved internal anchors to NSWorkspace.

The document controller owns the navigation closure. Validate lifetime/generation again when executing, use existing scroll/source navigation, respect Reduce Motion and preserve focus deliberately. Rendering itself must not alter editor selections. Quick Look uses static HTML fragment links and no app controller.

## Export origin and snapshot timing

Resolve/capture the origin synchronously on MainActor at command dispatch and reserve its existing reentrancy guard before spawning async work. Store the window/controller lifetime, document ID/recovery epoch and operation ID. Menu validation can inspect focus; execution never retargets to whichever window later becomes key.

Present the panel on that exact origin. After acceptance, reread the live document from the captured controller and verify it is still the same logical lifetime and exportable. Do not use the stale FileDocument value captured before the panel. Obtain its source through the normal completed editor-publication boundary, then freeze source/generation, URL/resource grant, Theme, effective parse options, target policy and identity ONCE before renderer awaits. A newly substituted document cancels. A later edit is allowed but cannot splice itself into the frozen request.

Parse, anchor analysis, contributions and ExportRequest all consume this snapshot. Do not reread live source/theme/generation after suspension or consult Preview's stale parse. The root lease preserves actual admitted source access even if Save As changes the live window later. Destination collision rules belong to #118, not this source snapshot.

Origin closure requests cancellation and revokes subsequent sheets; it must not move a completion/error alert to another window. Release the operation guard exactly once for panel cancellation, origin loss, renderer failure and completion. Callback bridges cannot retain a closed window indefinitely solely to show stale UI.

## Extra parse disposition

Separate the fresh MarkdownEngine parse, optional ID analysis, cmark pass, contribution rendering and serialization in Release timings. Reuse the same immutable MarkdownDocument/index within an export whenever exact source/options identity agrees; do not parse identical MarkdownEngine input twice. Keep the distinct cmark rendering pass. Record absolute and relative costs on 1 MiB ordinary text and representative technical/raw-HTML documents; no 'negligible' assertion without data. A different rendering engine is not part of this issue.

## Implementation units and discriminating tests

A. Pure destination/anchor values, allocator and bounded raw-ID adapter. Probe real pinned HTML parsing/context with exact browser fragment outcomes; no generic sanitizer or network API. Tests: A/A/A-1, punctuation-only, combining/CJK/long headings, locale changes, front matter, raw ID/name/entity collisions and raw markup swallowing a heading.
B. cmark IDs/TOC output, target validation and native routing. Test valid navigation, unchanged authored bytes, ordinary no-TOC large export preservation and per-destination ambiguous/over-budget fallback. #113 consumes the same index, not a second slugger.
C. Explicit ExportOrigin/snapshot. Suspend controlled parse/render jobs; edit A, focus B, change A's theme, Save As, close A and cancel. Assert one snapshot and no B-directed sheet. Include current E22 primary/secondary caret invalidation on navigation.
D. Consume final E22 command-catalog proof; run current menu/palette consistency with explicit exclusions. No edits to current E22 are requested.
E. Release phase measurements, full regression and actual TOC/export UI evidence through #88.

Allowed areas: MarkdownEngine/Contributions values and tests; Preview internal-link adapter; ExportService node/TOC code; app export-origin integration and catalogs. No FileStore safety weakening, editor replacement or post-E22 feature expansion. Run serial format/strict lint, affected/full package/app suites and Release build. Stop on wrong-target navigation, unbounded parser behavior, weakened source preservation or necessary unplanned dependencies.

## Review disposition

Second review resolved the palette dependency cycle, stale pre-panel document capture, direct NSTextView selection writes, indiscriminate DOM analysis, silent export-cap reduction and Quick Look's contradiction with fatal TOC errors. The original collision decision remains, but now has destination-correct failure semantics. All issue areas still require executed evidence; E22's registry subset alone cannot close #117.
