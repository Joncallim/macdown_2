# Epic 12 Implementation Architecture — HTML/PDF Export

> **Status:** Binding implementation contract for `epic/12-export`
> **Epic:** #13 — `[EPIC-12] Export: HTML + PDF, templates, themes and derived-content contract`
> **Baseline:** `master` at `8d22f0e740a31b1d0afb64c5b781f7e983df50a1`
> **Architecture date:** 2026-08-17
> **Review status:** Final adversarial architecture pass incorporated; no production E12 implementation may precede Slice 0

## Owner summary

Epic 12 will implement one local/offline export composition pipeline for Markdown. The pipeline prepares one complete HTML document, then either writes that document as HTML or prints that same document to PDF through a narrowly isolated macOS adapter. PDF does not get a second Markdown renderer.

The architecture deliberately keeps policy in a small number of owners and removes caller choices that do not exist in the product. In particular:

- the app supplies the current editor text, current `FileDocument.mutationGeneration`, file URL, parse options, selected theme, destination and any renderer-neutral derived results;
- `ExportService` derives metadata policy, resource root, template selection, output layout, cmark configuration and production resource limits internally;
- `swift-cmark` is the only Markdown-to-HTML engine used by E12, behind one internal adapter;
- themes remain theme data; E12 derives CSS from existing theme tokens rather than storing per-theme export stylesheets;
- resource references are resolved once through one manifest, one containment policy and one content-addressing policy;
- future E14/E19-E21 output enters through one generic source-range contract. It supports both **inline** and **block** replacements, so inline math does not force a later E12 redesign;
- derived source coordinates use the original document's UTF-16 coordinate space and `UInt` document generation. cmark source positions are not treated as document identity;
- successful derived ranges are replaced with deterministic sentinels before cmark parses the Markdown, then converted to cmark custom nodes. This prevents future math/diagram syntax from being accidentally interpreted as Markdown and lets the normal cmark renderer remain the only HTML renderer;
- companion resources use full SHA-256 content addresses. Output ownership is recorded in one versioned manifest. New resources are materialised before the primary HTML is replaced; cleanup can delete only resources explicitly owned by the previous manifest;
- self-contained HTML is a real closure guarantee. It embeds managed CSS/assets and refuses authored raw HTML or unresolved resource-bearing references that E12 cannot prove self-contained;
- PDF uses the same prepared HTML and managed resources through a locked-down local URL scheme. JavaScript, network loading, navigation, downloads and popups are disabled;
- there are no language-name switches for math, Mermaid, Graphviz, D2, WaveDrom or any future renderer in E12.

The final architecture pass removed four avoidable sources of implementation ambiguity from the previous draft: caller-supplied output layouts/budgets/metadata policy, an `Int` revision disconnected from `FileDocument.mutationGeneration`, duplicate resource state in `PreparedExportDocument`, and a complete-block-only derived contract that was incompatible with E19 inline math.

This document follows `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md`. Where this document says **must**, implementation workers should treat the statement as a contract rather than a suggestion.

---

## 3.1 Current repository state and dependency reconciliation

### Binding current-master facts

1. `MarkdownEngine.ParseEngine` is the only package implementation allowed to import `Markdown`/`Yams` for the app's renderer-neutral parse snapshot. Export must keep using `ParseExecuting` for the fresh E06 parse and must not leak `swift-markdown` types outside `MarkdownEngine`.
2. `MarkdownDocument` contains the body without front matter, `bodyLineOffset`, original-source `SourceMap`, block ranges, front matter, the parse revision and the actual `MarkdownParseOptions` used for that parse.
3. `FileDocument.mutationGeneration` is `UInt`. E12 must preserve this type at the app/export boundary rather than inventing an unrelated `Int` revision. Only the call into `ParseExecuting` converts it to `Int`, using an exact conversion.
4. `ThemeController`/`Theme` are the current theme source of truth. E12 must not add a parallel export-theme model.
5. E11's WebKit security policy demonstrates the required local/offline posture but belongs to Preview. Export must not depend on the Preview module. E12 owns an export-specific resource scope and the app-owned PDF host owns the PDF WebKit policy.
6. `ExportService` already exists as a MacDownKit target and currently depends on `MarkdownEngine` and `Themes`.
7. The migration plan deliberately selected `swiftlang/swift-cmark` 0.8.x for cmark HTML export. Slice 0 pins **exactly 0.8.0** and proves the C API/lifetime surface before any HTML composition work.
8. `swift-cmark`/cmark-gfm custom inline/block nodes are the intended AST post-processing seam for non-CommonMark derived output. E12 uses them only internally after parsing; no dynamic cmark plugin registry is introduced.
9. E14 owns contribution discovery/lifecycle/isolation. E12 owns only the export destination contract. E19 explicitly requires inline and display math; E20 requires block-oriented SVG diagrams. Therefore the E12 destination must support both source placements without knowing their languages.
10. Open issue #35 allows non-Markdown formats into the Markdown parse path. E12 does not fix that issue. The E12 export command is enabled only for Markdown documents until each other format owns an export adapter.

### Dependency additions

`MacDown2/Packages/MacDownKit/Package.swift` must add a direct exact dependency on:

```swift
.package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.8.0")
```

Only the `ExportService` target receives the required cmark products (`cmark-gfm` and `cmark-gfm-extensions`). No app target, Preview target or other package target may import those products.

Do not add another Markdown parser, another templating dependency, an HTML parser, a PDF library, a hashing package or a network client for E12.

System frameworks/modules (`Foundation`, `CryptoKit`, `UniformTypeIdentifiers`, and app-side `AppKit`, `WebKit`, `PDFKit`) are sufficient for the remaining work.

### Legacy migration rule

The concrete legacy `MPAsset` implementation is not available in the current MacDown 2 tree. E12 therefore ports useful tested **behavioural concepts**, not the obsolete class hierarchy:

- logical asset identity;
- source bytes + media type;
- deterministic lookup;
- embedding/bundling behaviour;
- template context concepts: title, style, content and assets;
- explicit default/fallback behaviour.

If implementation later discovers a material legacy contract that changes current acceptance behaviour, stop and revise this architecture. Do not recreate an old class solely because the name existed.

---

## 3.2 Representative user journeys

### Journey A — self-contained HTML

1. User edits a Markdown document and immediately chooses Export → HTML.
2. The app captures the current unsaved editor text and generation at that moment.
3. User chooses Self-contained.
4. E12 performs a fresh parse of that exact snapshot, resolves local images, derives CSS from the selected theme and embeds managed resources.
5. A complete UTF-8 HTML5 file is atomically promoted to the chosen destination.
6. The file opens without MacDown 2 and without requiring resource files beside it.

### Journey B — companion-file HTML

1. User chooses HTML with companion files and either embedded or linked CSS.
2. Local resources are copied to one deterministic sibling asset directory using content-addressed filenames.
3. Resource files are written before the primary HTML references them.
4. Existing unknown user files are never adopted or deleted.
5. Re-export replaces the primary HTML and only cleans stale files proved to be owned by the previous MacDown export manifest.

### Journey C — PDF

1. User chooses PDF.
2. E12 prepares the same HTML document used by HTML export, with managed resources addressed through the export-local URL scheme.
3. An app-owned isolated `WKWebView` loads only that prepared document/resources.
4. The app prints through the macOS print system using a frozen `PDFPageLayout` derived from `NSPrintInfo`, validates the temporary PDF with PDFKit, then atomically promotes it.
5. Text remains searchable/selectable and networking is never used to render first-party content.

### Journey D — future inline math

1. E19 later returns renderer-neutral output for `$E = mc^2$` with a stable source identity/range and the document generation that produced it.
2. E14 adapts that result into E12's `DerivedExportResolution` with placement `.inline`.
3. E12 validates the original UTF-16 range against the current export snapshot, substitutes a deterministic sentinel, lets cmark parse surrounding Markdown normally, then replaces only the sentinel with a cmark custom-inline node.
4. The same normal HTML/PDF pipeline continues; E12 contains no math branch.

### Journey E — future block diagram

The same path applies to a Mermaid fenced block with placement `.block`; E12 installs a custom-block node inside the existing cmark container structure. Diagram resources use the same manifest as ordinary Markdown images.

### Journey F — derived failure/staleness

If a contribution failed, is stale, overlaps another contribution, has an invalid range or cannot be safely injected, its authored source is left in the Markdown presented to cmark and a diagnostic is surfaced. Silent omission is prohibited.

---

## 3.3 Invariants and non-goals

### Invariants

1. **Current text wins.** Export snapshots the live editor, not the last disk save and not the debounced preview parse.
2. **Fresh parse.** Every export request performs a fresh `ParseExecuting.parse` for that immutable snapshot.
3. **One Markdown HTML renderer.** cmark-gfm is the only Markdown-to-HTML renderer in E12.
4. **One prepared document.** PDF prints the same prepared HTML model used by HTML export.
5. **No caller-built layout.** Callers choose a typed target URL/options; `ExportService` derives `ExportOutputLayout` internally.
6. **No caller-built production policy.** Metadata rules, template selection and production budgets are service configuration, not request fields.
7. **No invented revision domain.** Snapshot and derived result generation are `UInt`, matching `FileDocument.mutationGeneration`.
8. **Original-source coordinates.** Derived ranges are absolute UTF-16 half-open ranges into the original source snapshot, front matter included. cmark line/column positions are not identity.
9. **No overlapping successful derived replacements.** Overlapping rendered ranges fall back to authored source with diagnostics.
10. **Derived failure preserves source.** A failed/stale/invalid derived result never deletes source and never crashes export.
11. **No renderer-language branching.** E12 knows only inline/block placement, source identity, HTML fragment, diagnostics and resources.
12. **Local/offline first-party operation.** Export never fetches a network resource and never uploads source.
13. **Self-contained means closed.** All E12-managed resource-bearing references are embedded; authored raw HTML is rejected because E12 cannot prove arbitrary HTML closure without adding an HTML crawler/sanitizer.
14. **Path containment.** A Markdown relative file reference may read only a regular file whose canonical resolved path is under the saved Markdown file's canonical parent directory.
15. **Unsaved documents have no implicit resource root.** Relative local resources in an untitled/unsaved document cannot be resolved and are handled according to destination failure policy; E12 does not guess a working directory.
16. **Content-addressed resources.** Managed resource identity is full SHA-256 of snapshotted bytes; names are deterministic.
17. **Single resource owner.** `ExportManifest` is the only collection of prepared resources. `PreparedExportDocument` does not duplicate a second resource array.
18. **Primary-last HTML commit.** Companion resources required by new HTML exist before the new primary HTML becomes visible.
19. **Owned cleanup only.** E12 deletes only filenames listed in the previous valid E12 ownership manifest and no longer referenced by the new manifest.
20. **Byte determinism.** Identical complete `ExportRequest` + identical configured template/stylesheet/budget version produce identical prepared HTML and resource names. Timestamps, random UUIDs and process IDs must not enter durable output.
21. **No global export singleton.** Different windows may export concurrently. Export service state is immutable/injected; cmark trees are invocation-local.
22. **No `@unchecked Sendable` as a shortcut.** Actor/main-actor boundaries and C lifetime ownership must be real.
23. **No source mutation.** Export cannot save, reformat or edit the source document.
24. **No hand-edited Xcode project.** Use XcodeGen inputs and regenerate.

### Explicit non-goals

- production math, Mermaid, D2, Graphviz or WaveDrom rendering;
- custom per-user template UI;
- ePub/DOCX;
- hosted rendering;
- reusing SwiftUI preview views as export content;
- building a generic third-party plugin system;
- crawling/sanitising arbitrary raw HTML;
- solving non-Markdown export for issue #35;
- inventing custom paper sizes or a bespoke PDF paginator.

---

## 3.4 Module ownership and dependency boundaries

### `MarkdownEngine`

Owns Markdown/front-matter parsing and original-source map. No E12 export policy enters this module.

### `Themes`

Owns theme data. No CSS strings, HTML templates or PDF rules enter this module.

### `ExportService`

Owns all platform-neutral export composition:

- request/result contracts;
- exact conversion from `UInt` generation to parser `Int` revision;
- cmark configuration, AST mutation and HTML body render;
- fixed metadata rules;
- built-in template contract/catalog;
- base export stylesheet + theme-token-to-CSS mapping;
- local resource containment/snapshot/hash/media-type rules;
- resource reference generation;
- derived source-range validation/sentinel/custom-node adaptation;
- output-layout derivation;
- companion ownership manifest;
- Foundation-only atomic file promotion and HTML artifact writing;
- deterministic diagnostics and configured resource budgets.

`ExportService` must not import `AppKit`, `WebKit`, `PDFKit`, `Preview` or future renderer modules.

### App target

Owns:

- Export commands/menu/panel;
- `FileDocument`/editor snapshot capture;
- current `ThemeController` selection;
- save panels and target URLs;
- one task per window + progress/cancel UI;
- app-localised diagnostic presentation;
- `WebKitPDFRenderer` and `PDFPageLayout`;
- locked-down transient WebKit host + URL scheme handler;
- PDFKit validation;
- app composition root wiring.

### E14/E19-E21 later

These modules own contribution discovery, rendering, caching, cancellation and language-specific recognition. They adapt renderer-neutral results into E12 `DerivedExportResolution`. They do not get alternate Markdown export pipelines.

### Forbidden dependency directions

- `ExportService -> Preview`: forbidden.
- `ExportService -> FileCore`: not required for E12; app maps `mutationGeneration` and `fileURL` into the request.
- `ExportService -> E14/E19/E20/E21`: forbidden.
- `Themes -> ExportService`: forbidden.
- `MarkdownEngine -> ExportService`: forbidden.
- direct app/Preview imports of cmark: forbidden.

---

## 3.5 Interfaces and data contracts

The exact spelling may change for Swift style during implementation, but the **shape, ownership and invalid-state guarantees below are binding**.

### Request contracts

```swift
public struct ExportSourceSnapshot: Sendable {
    public let text: String
    public let fileURL: URL?
    public let parseOptions: MarkdownParseOptions
    public let generation: UInt
}

public enum ExportTarget: Sendable, Equatable {
    case html(url: URL, options: HTMLExportOptions)
    case pdf(url: URL)
}

public struct HTMLExportOptions: Sendable, Equatable {
    public let packaging: HTMLPackagingMode

    public static let standard = HTMLExportOptions(
        packaging: .companionFiles(stylesheet: .embedded)
    )
}

public enum HTMLPackagingMode: Sendable, Equatable {
    case selfContained
    case companionFiles(stylesheet: ExportStylesheetMode)
}

public enum ExportStylesheetMode: Sendable, Equatable {
    case embedded
    case linked
}

public struct ExportRequest: Sendable {
    public let source: ExportSourceSnapshot
    public let target: ExportTarget
    public let theme: Theme
    public let derived: [DerivedExportResolution]
}
```

There is deliberately no request field for:

- `resourceRootURL` — derived only from saved `fileURL.parent`;
- `suggestedTitle` — fixed metadata fallback is derived from front matter/file URL;
- `revision: Int` — generation remains `UInt` at this boundary;
- `ExportMetadataPolicy` — there is one E12 policy;
- `ExportResourceBudget` — service configuration owns policy;
- `ExportOutputLayout` — target URL/options derive it;
- template ID — macOS 1.0 has one built-in template; custom template selection is out of scope.

This is intentional. Call sites must not be able to assemble contradictory destination/layout/policy states.

### Derived-content contracts

```swift
public struct DerivedSourceID: Hashable, Sendable {
    public let rawValue: String
}

public struct ExportSourceRange: Hashable, Sendable {
    public let lowerUTF16Offset: Int
    public let upperUTF16Offset: Int   // half-open
}

public enum DerivedExportPlacement: Sendable, Equatable {
    case inline
    case block
}

public struct DerivedExportAnchor: Hashable, Sendable {
    public let sourceID: DerivedSourceID
    public let range: ExportSourceRange
    public let placement: DerivedExportPlacement
    public let generation: UInt
}

public struct DerivedExportResource: Sendable {
    public let id: String
    public let mediaType: String
    public let data: Data
}

public struct DerivedExportFragment: Sendable {
    public let html: String
    public let resources: [DerivedExportResource]
}

public enum DerivedExportResolution: Sendable {
    case rendered(anchor: DerivedExportAnchor, fragment: DerivedExportFragment)
    case failed(anchor: DerivedExportAnchor, diagnostic: ExportDiagnostic)
}
```

`ExportSourceRange` initialisation must reject negative offsets, inverted/empty ranges and integer overflow. The service additionally validates upper bounds against the current snapshot and verifies that both UTF-16 boundaries map to valid Swift `String.Index` boundaries.

`DerivedSourceID` is opaque identity. It is never interpreted as a renderer/language name.

`DerivedExportFragment.html` is **trusted first-party destination HTML**, not arbitrary third-party/user plugin input. E14 remains responsible for admitting first-party contributions. E12 does not add an HTML sanitizer. Derived fragments must be passive/offline output: no script requirement, no remote-fetch requirement, and no complete `<html>`, `<head>`, `<body>` or `<base>` document wrapper.

A derived fragment may refer to its declared resources only through the canonical string returned by one E12 helper (`DerivedExportResourceReference.reference(for:)`). The implementation may use an internal `macdown-derived-resource:` URL form, but that literal exists in exactly one helper. E12 rewrites only those declared references to the destination-specific managed reference and rejects a rendered contribution if:

- resource IDs duplicate within the fragment;
- a declared resource has no canonical reference in the fragment when the contract requires one;
- a canonical derived-resource prefix remains unresolved after rewriting;
- a resource exceeds the central budget.

The adapter does **not** let a future renderer choose companion filenames or PDF scheme paths.

### Sentinel/custom-node contract

E12 must support inline and block derived ranges without teaching cmark a new Markdown extension and without maintaining a second Markdown renderer.

For each valid successful derived range:

1. Build a deterministic ASCII sentinel from source ID + range + generation using SHA-256. No random UUID.
2. If that exact sentinel already exists in source, deterministically append the smallest numeric collision suffix not present in source.
3. Convert the original-source UTF-16 range to the `MarkdownDocument.body` UTF-16 coordinate space using `bodyLineOffset`/`SourceMap`.
4. Apply all non-overlapping substitutions from highest source offset to lowest so earlier offsets do not shift.
5. Parse the transformed body with cmark.
6. Locate each sentinel exactly once in the cmark tree.
7. `.inline`: sentinel must be reachable as replaceable inline literal text. Split the text node if necessary and insert `CMARK_NODE_CUSTOM_INLINE` whose `on_enter` is the rewritten derived fragment and whose `on_exit` is empty.
8. `.block`: find the nearest replaceable block ancestor for which the sentinel is the only semantic content contributed by that derived source position, replace that block with `CMARK_NODE_CUSTOM_BLOCK`, and preserve outer list/quote/container structure.
9. If a candidate cannot satisfy the structural rule, remove that candidate from substitution and reparse so authored source remains. If a second structural pass becomes unstable, do one final ordinary-source parse with all derived candidates preserved as source and emit diagnostics. Export must never loop indefinitely trying to inject contributions.

The cmark custom-node seam is internal to `CMarkHTMLBodyRenderer`. It is not exposed as a public extension API.

This pre-parse sentinel design is deliberate: future inline math syntax is removed before cmark can misinterpret TeX characters as Markdown, while surrounding Markdown still parses normally.

### cmark adapter

```swift
protocol MarkdownHTMLBodyRendering: Sendable {
    func render(
        document: MarkdownDocument,
        originalSource: String,
        derived: [DerivedExportResolution],
        resources: ExportResourceResolver,
        referenceMode: ExportResourceReferenceMode,
        budget: ExportResourceBudget
    ) async throws -> RenderedHTMLBody
}
```

The renderer takes `MarkdownDocument.options` from the fresh parse; call sites do not pass a second potentially divergent option value.

`CMarkConfiguration.swift` is the **only** file that maps `MarkdownParseOptions` to cmark option bits/extensions and the **only** file that names cmark GFM extensions. No extension names/options appear in tests or call sites except through that configuration API.

Normal authored raw HTML policy is exactly:

- render with `CMARK_OPT_UNSAFE` so ordinary authored HTML is retained;
- attach cmark-gfm `tagfilter` so its filtered dangerous tag set is still applied;
- do not build an independent sanitizer.

Self-contained HTML adds one stricter rule: after cmark parses the transformed source but before derived custom nodes are installed, any remaining authored `CMARK_NODE_HTML_BLOCK` or `CMARK_NODE_HTML_INLINE` is a fatal `selfContainedRawHTMLUnsupported` error.

The dependency's one-time core extension registration is accepted only behind `CMarkConfiguration`. E12 may call `cmark_gfm_core_extensions_ensure_registered()` through a small once-wrapper if needed. Do not create a MacDown dynamic/global registry.

Every parser tree, iterator and renderer-owned C string is freed on every success/error path. Slice 0 proves repeated render lifetime behaviour before other work builds on it.

### Prepared document — one source of resource truth

```swift
public struct PreparedExportDocument: Sendable {
    public let html: String
    public let manifest: ExportManifest
    public let diagnostics: [ExportDiagnostic]
    public let outputLayout: ExportOutputLayout
}

public struct ExportManifest: Sendable {
    public let resources: [ExportResource]

    public func resource(for id: ExportResourceID) -> ExportResource?
}
```

`PreparedExportDocument` must **not** also contain `[ExportResource]`, `isSelfContained`, a second target URL or any other state derivable from `outputLayout`/`manifest`.

`ExportOutputLayout` has no public general-purpose initializer. It is constructed only by `ExportOutputLayout.make(for: ExportTarget)` after validating the target URL. It owns:

- primary target URL;
- output kind (`html`/`pdf`);
- HTML packaging/reference mode when applicable;
- deterministic companion directory URL/prefix when applicable.

### Result and diagnostic contracts

Fatal preparation/write errors are typed `ExportError` values. Non-fatal conditions are typed `ExportDiagnostic` values containing a machine-readable code, severity and structured context; localised prose is created in the app target.

Package tests assert codes/context, never English error sentences.

---

## 3.6 End-to-end data flow

### Phase 0 — app snapshot

Immediately before work starts, `ExportCoordinator` on the main actor captures:

- current editor text;
- current saved file URL if any;
- current `FileDocument.mutationGeneration` (`UInt`);
- current Markdown parse options;
- selected theme;
- target URL/options from the save/export panel;
- latest E14-compatible derived resolutions available for that same document.

The request becomes immutable. Later editor changes do not mutate an in-flight export.

### Phase 1 — validate target and generation

1. `ExportOutputLayout.make(for:)` requires a file URL and the correct output extension (`.html` for HTML, `.pdf` for PDF, case-insensitive).
2. HTML companion directory for `/dir/report.html` is **exactly** `/dir/report.assets`.
3. Convert generation to parser revision with `Int(exactly: generation)`. Failure is a typed `generationOverflow` error; never clamp/wrap.
4. Enforce source-size budget before entering cmark.

### Phase 2 — fresh MarkdownEngine parse

Call the injected `ParseExecuting` instance with the immutable source text/options/exact revision. Do not reuse preview state.

Metadata policy is fixed:

- front-matter `title` that resolves to a non-empty scalar string becomes browser `<title>` and the default template's visible document `<h1>` exactly once;
- no front-matter title: browser `<title>` falls back to the saved Markdown filename stem if available;
- no front-matter title: **do not** synthesize a visible `<h1>` from filename;
- untitled unsaved source without front-matter title uses an empty `<title>`;
- unsupported/non-scalar title values emit a warning and behave as absent;
- unknown front-matter keys are ignored by E12.

### Phase 3 — derive output/resource policy

`ExportService` maps target to one internal `ExportResourceReferenceMode`:

- HTML self-contained → `.embeddedData`;
- HTML companion → `.relativeCompanion`;
- PDF → `.localScheme`.

The source resource root is computed only when `fileURL` exists and is a file URL: canonical parent directory of that saved file. No current working directory fallback exists.

### Phase 4 — validate derived results and substitute sentinels

1. Sort rendered candidates deterministically by `(range.lower, range.upper, sourceID.rawValue)`.
2. Failed resolutions become diagnostics and remain source.
3. Reject stale generation, invalid/out-of-bounds/non-String-boundary ranges, front-matter ranges, duplicate identities/ranges and overlapping rendered ranges. Rejected entries remain source.
4. Rewrite declared derived-resource references through `ExportResourceResolver` and the same manifest/budget used for normal assets.
5. Apply deterministic sentinel substitution to the body, back-to-front.

No renderer language is consulted.

### Phase 5 — cmark parse/mutation/render

1. Register built-in cmark-gfm extensions through the bounded one-time configuration seam.
2. Parse transformed body.
3. Apply the central GFM option/extension mapping.
4. Enforce self-contained raw HTML rule before custom derived nodes are installed.
5. Resolve/rewrite ordinary Markdown image/resource URLs through the manifest policy.
6. Replace derived sentinels with cmark custom inline/block nodes using the bounded fallback algorithm.
7. Render with cmark HTML renderer + exact raw-HTML/tagfilter policy.
8. Free all C ownership.

The produced body HTML is renderer output, not input to an ad-hoc string Markdown renderer.

### Phase 6 — stylesheet and template

`ExportStyleSheetBuilder` loads one bundled structural stylesheet from:

`Sources/ExportService/Resources/default-export.css`

The `ExportService` SwiftPM target declares it as a processed resource. Structural layout/print rules live there, not scattered through Swift strings.

Theme-derived values are emitted as CSS custom properties in one deterministic `:root` block by one mapper. Theme values are not copied into template conditionals.

Packaging:

- self-contained: generated stylesheet embedded in `<style>`;
- companion + embedded stylesheet: same embedded `<style>`;
- companion + linked stylesheet: full generated stylesheet becomes one content-addressed manifest resource and template receives its relative managed reference.

There is one built-in Swift template/catalog for macOS 1.0. It consumes a typed context, never `[String: Any]`:

```swift
struct ExportTemplateContext: Sendable {
    let browserTitle: String
    let visibleTitle: String?
    let bodyHTML: String
    let stylesheet: ExportStylesheetPlacement
}
```

The template is responsible only for complete HTML5 document structure/escaping the text/title slots and placing already-rendered body/style content. Do not add Handlebars or user template discovery.

### Phase 7 — produce `PreparedExportDocument`

The prepared value contains exactly:

- complete UTF-8 HTML5 string;
- one manifest of snapshotted managed resource bytes;
- non-fatal diagnostics;
- derived output layout.

Before returning:

- enforce prepared-HTML budget;
- ensure manifest resource IDs/names are unique and sorted deterministically;
- assert no unresolved derived-resource marker remains;
- for self-contained HTML, assert the manifest has no external file/local-scheme references and no managed resource-bearing reference remains unembedded.

### Phase 8A — HTML writer

`HTMLExportArtifactWriter` is Foundation-only and package-owned.

For self-contained HTML or companion HTML with no companion resources, atomically promote the primary HTML file. Do not delete a stale sibling `.assets` directory merely because a new export no longer references it.

For companion resources:

1. Derive `/dir/report.assets` only from `ExportOutputLayout`.
2. Ownership marker filename is exactly `.macdown-export-manifest.json`.
3. Marker schema v1 is deterministic JSON containing only:
   - integer schema version `1`;
   - producer string `MacDown2.ExportService`;
   - sorted list of resource filenames owned by that export.
   No timestamps, UUIDs or machine paths.
4. If directory does not exist, create it and atomically create an empty valid ownership marker before writing resource files.
5. If directory already exists, it is manageable only if its marker parses, has producer/version above and every listed owned filename is a simple child filename. Otherwise fail **before changing the directory**. Never adopt an unknown directory.
6. Materialise every new content-addressed resource first. If a destination filename already exists, verify its bytes hash to the expected digest; otherwise fail rather than overwrite an unexpected collision.
7. Write primary HTML to sibling temporary file and atomically replace/promote the target HTML.
8. Atomically replace ownership marker with the new sorted owned-resource list.
9. Only after step 8 succeeds, best-effort delete prior-manifest filenames that are absent from the new manifest and still satisfy the content-address filename grammar. Never delete unknown/unlisted files. Cleanup failure becomes a warning; primary output stays successful.
10. If the process dies after step 7 but before step 8, the primary remains valid because new resources already exist. A later export may leave an orphaned content-address file rather than guessing ownership. Durability wins over aggressive cleanup.

Do not describe companion export as a multi-entry atomic transaction; filesystems do not provide that contract here.

### Phase 8B — PDF writer

The app-owned `WebKitPDFRenderer` consumes the same `PreparedExportDocument`:

1. Create an ephemeral `WKWebViewConfiguration` on `@MainActor`.
2. JavaScript disabled; non-persistent website data store; no service workers or injected scripts.
3. Register exactly one E12 local resource scheme handler. It maps a managed resource URL to bytes/media type from `PreparedExportDocument.manifest` only.
4. Block all network schemes, external navigation, downloads, new windows and popups.
5. Load the prepared document and wait for terminal navigation completion/cancellation.
6. Freeze `PDFPageLayout` from a copied `NSPrintInfo`; do not hard-code A4/Letter dimensions.
7. Use `WKWebView.printOperation(with:)` / `NSPrintOperation` rather than screenshots/viewport capture.
8. Print to a sibling temporary PDF.
9. Open the temporary result with PDFKit; require a non-zero page count and readable document object. Fidelity corpus additionally asserts searchable text.
10. Atomically promote the validated PDF to the target.
11. Tear down WebKit state/scheme handler on every path.

If macOS 26 WebKit printing cannot meet readable/searchable pagination acceptance, stop Slice 4 and change only the PDF adapter. Do not fork Markdown composition and do not rasterise the document as a workaround.

---

## 3.7 State ownership, concurrency and cancellation

### Service shape

`ExportService` is an immutable `Sendable` value (or equivalent immutable final type) with injected dependencies/configuration. It is **not** a global actor/singleton and does not serialise exports across windows.

Recommended production construction:

- injected `ParseExecuting`;
- internal/default `CMarkHTMLBodyRenderer`;
- built-in template catalog;
- resource resolver factory/filesystem dependency if tests need fault injection;
- `ExportResourceBudget.standard`.

Tests may inject smaller budgets/fakes. `ExportRequest` never changes budgets.

### Window task ownership

Each document window owns at most one export task. Starting a replacement export cancels the previous task for that window. Closing the window cancels its task. Other windows may continue independently.

### Main actor

Only UI state, snapshot capture, save panels and WebKit/AppKit/PDFKit work are `@MainActor`.

Markdown parsing, cmark composition, hashing/resource reads and Foundation file writing must not be forced onto the main actor.

### Cancellation checkpoints

Check `Task.checkCancellation()` at minimum:

- before parse;
- after fresh parse;
- before/after derived transformation;
- before/after cmark render;
- between resource reads/hashes;
- before template composition;
- before each companion resource write;
- before primary promotion;
- before PDF load/print/promotion.

A single cmark C call cannot necessarily be interrupted mid-call. Source/prepared-resource budgets plus Release performance evidence bound that synchronous interval.

Cancellation before primary promotion leaves existing primary output untouched. Cancellation after primary promotion but during best-effort companion cleanup may leave stale owned resources; it must not roll back/delete the valid primary.

---

## 3.8 Failure semantics

### Fatal preparation/write errors

Fatal errors include:

- invalid/non-file target URL or wrong target extension;
- generation cannot convert exactly to parser revision;
- fresh parse failure;
- source/prepared output exceeds configured hard budget;
- self-contained authored raw HTML;
- self-contained unresolved/remote resource-bearing reference;
- PDF remote/unresolved resource-bearing reference that would make the printed result knowingly incomplete;
- companion asset directory exists but lacks a valid E12 ownership marker when E12 needs to write there;
- filesystem read/write/hash/atomic-promotion failure;
- cmark lifecycle/invariant failure;
- PDF navigation/print/validation failure.

Fatal errors do not replace the existing destination.

### Non-fatal diagnostics

Non-fatal conditions include:

- invalid/non-scalar front-matter title;
- failed/stale/invalid/overlapping derived contribution (source preserved);
- companion HTML remote image/resource reference preserved without fetching;
- ordinary HTML authored raw HTML retained under cmark raw-HTML policy;
- post-commit stale companion cleanup failure;
- PDF authored raw HTML warning (the locked-down print host blocks network/script behaviour it cannot support).

### Resource-bearing reference policy

E12 distinguishes navigation from fetched rendering resources:

- ordinary hyperlinks (`<a href>`) may remain local/remote authored navigation targets; exporter never follows them;
- Markdown image/resource references are rendering resources and follow the rules below.

**HTML companion:** local in-root resources are packaged. Remote resource URLs are preserved exactly but never fetched and generate a warning. Missing/out-of-root local resource references generate a warning and remain authored references; E12 does not copy them.

**HTML self-contained:** every E12-visible resource-bearing reference must resolve to managed bytes and be embedded. Remote, missing, out-of-root or unsupported references are fatal. Authored raw HTML is fatal because its arbitrary resource references cannot be proven closed.

**PDF:** every E12-visible resource-bearing reference required for rendering must resolve to managed local bytes. Remote, missing or out-of-root references are fatal. Hyperlinks remain navigation annotations where the print system preserves them. Authored raw HTML is rendered best-effort under the locked-down host and produces a warning because E12 does not add an HTML crawler in this epic.

### Derived fallback

A `.failed` resolution or rejected `.rendered` resolution never makes export fatal by itself. The original authored range remains in source and a diagnostic identifies the source ID/range/reason. This is the E12 contract E14/E19-E21 can rely on.

---

## 3.9 Security, privacy and trust boundaries

1. No `URLSession`, `WKWebsiteDataStore.default()`, hosted renderer or network fetch is permitted in first-party export.
2. Companion/PDF resource reads begin only from the saved Markdown file's canonical parent directory.
3. Canonicalise/standardise file URL and resolve symlinks before containment comparison.
4. Reject directories/non-regular files as resource bytes.
5. Snapshot accepted file bytes immediately after validation; hashes/output use the snapshot, not a later path reread.
6. The containment policy protects path traversal/symlink escape in the normal local-file threat model. Like the current Preview seam, it does not claim race-free protection against a hostile process mutating the local filesystem between validation and read; this remains a documented local TOCTOU residual risk rather than an excuse to weaken containment.
7. Content address is SHA-256 via CryptoKit, full 64 lowercase hexadecimal characters. Never truncate the digest for durable filenames.
8. Media type comes from validated `UTType`/system knowledge with one deterministic binary fallback (`application/octet-stream`); do not scatter extension switches.
9. cmark raw authored HTML is trusted authored document content, not app UI HTML. `tagfilter` remains attached; E12 does not claim a sanitizer.
10. Derived HTML is trusted first-party output admitted by E14's later contribution boundary. It bypasses authored-raw-HTML filtering through cmark custom nodes and therefore must remain passive/offline by contract.
11. PDF WebKit is a hostile-output containment boundary anyway: no JS/network/navigation/download/popups and only manifest-backed local scheme responses.
12. Never expose arbitrary filesystem paths through the PDF local scheme. URLs identify only manifest resource IDs.
13. Ownership marker parsing treats path separators, `..`, absolute paths, unsupported schema/producer and duplicate owned filenames as invalid; invalid marker means do not modify that directory.

---

## 3.10 Resource and performance budgets

All implementation limits live in one `ExportResourceBudget` value. No call-site literals.

Initial `.standard` policy:

```swift
public struct ExportResourceBudget: Sendable, Equatable {
    public let maxSourceUTF8Bytes: Int              // 32 MiB
    public let maxResourceCount: Int                // 512
    public let maxSingleResourceBytes: Int          // 32 MiB
    public let maxAggregateResourceBytes: Int       // 128 MiB
    public let maxDerivedFragmentCount: Int         // 4,096
    public let maxAggregateDerivedHTMLBytes: Int    // 32 MiB
    public let maxPreparedHTMLUTF8Bytes: Int        // 128 MiB
}
```

The numeric values are initial safety gates, not product semantics. Slice 6 may change them **only from measured Release evidence**, in this one definition, with the final values documented in the PR. No API/call-site changes should be required to tune them.

Rules:

- count each unique content-addressed resource once after deduplication;
- validate individual size before accumulating total using overflow-checked arithmetic;
- derived resources consume the same resource count/byte budgets as Markdown assets;
- derived HTML count/aggregate size are additional bounds;
- do not add a hard-coded PDF page-count limit;
- performance gates are measured in Release on the documented reference Mac, not encoded as arbitrary runtime timeouts for normal local export;
- test budgets may be tiny injected values to cover boundaries without huge fixtures.

Slice 6 records Release evidence for at least:

- ordinary medium document;
- asset-heavy document near practical expected usage;
- 100+ page PDF corpus;
- many derived fake contributions;
- cancellation during expensive phases;
- peak memory observation for the asset-heavy/PDF cases.

If evidence shows the in-memory resource snapshot model is unsafe at approved limits, stop and revise the resource representation rather than silently increasing limits or adding unbounded reads.

---

## 3.11 Accessibility and localisation

### Export UI

- Export command/panel is fully keyboard reachable.
- Standard controls receive useful labels/VoiceOver names.
- Self-contained selection removes/disables the linked-CSS choice structurally; do not leave contradictory hidden state.
- Progress/cancel state is announced using normal SwiftUI accessibility semantics.
- All user-visible strings are in app localisation resources before E16 string freeze.

### Exported document

The default template uses semantic HTML5 structure:

- one document language fallback only if the app has an authoritative value; do not invent a locale metadata field from machine locale;
- visible front-matter title is a real `<h1>`;
- cmark heading/list/table/code/link semantics remain intact;
- images retain cmark-generated alt text;
- CSS preserves visible focus indication and printable contrast;
- derived output may add accessibility metadata but E12 does not invent language-specific labels.

PDF acceptance includes selectable/searchable text, not raster-only pages.

Package diagnostics remain machine-readable; app maps them to localised prose.

---

## 3.12 Interoperability and future-epic boundaries

### E14

E14 may define richer renderer-neutral lifecycle/capability types, but its Export adapter must map them into E12's narrow destination types rather than importing E12 implementation details into the contribution core.

Required common information is already represented generically:

- stable source identity;
- original-source UTF-16 range;
- `UInt` source generation;
- inline vs block placement;
- passive derived representation;
- diagnostics;
- resources.

### E19 math

Inline `$...$` maps to `.inline`; display math can map to `.block` when its recognised source range owns a block, otherwise the E19/E14 adapter selects the structural placement that matches its actual range. E12 never parses TeX delimiters.

The sentinel-before-cmark rule ensures TeX characters inside a successful math range are not reparsed as Markdown.

### E20/E21 diagrams

Fenced diagrams map to `.block` and normally supply SVG as renderer-neutral derived bytes/HTML. E12 never inspects fence language names. SVG resources/embedded dependencies must be represented through the same derived-resource contract; hosted URLs are not an escape hatch.

### E11 Preview

Preview and Export deliberately do not share a WebKit host. They share architectural security principles only. E12 must not import Preview just to reuse `HTMLPreviewResourceScope`.

### E06 MarkdownEngine

E12 consumes immutable `MarkdownDocument` + `SourceMap`; it does not add export fields to MarkdownEngine. If later source identity needs richer column APIs, E14 can own a source-range type or a narrowly reusable source mapping utility can be proposed then. E12 does not broaden MarkdownEngine pre-emptively.

---

## 3.13 Automated test strategy

Use Swift Testing for MacDownKit tests and the current app test conventions for app-owned components.

### Contract/type tests

- `HTMLPackagingMode` makes self-contained + linked CSS unrepresentable.
- PDF target cannot carry HTML options.
- request has no public layout/budget/metadata/template override.
- output layout derives correct target/asset directory and rejects wrong extensions/non-file URLs.
- `UInt` generation exact conversion and overflow path.
- source range validation including surrogate-pair boundaries.

### cmark adapter tests

Permanent parity/golden corpus for:

- paragraphs/headings/emphasis/strong/code/quotes/lists;
- GFM table/task/strikethrough/autolink/footnote options used by the app;
- links/images and URL escaping;
- raw HTML + tagfilter behaviour;
- Unicode/emoji/CJK/combining/non-BMP;
- repeated render/free lifecycle;
- option combinations;
- block directives preserve authored source rather than inventing export semantics.

Only `CMarkConfiguration` tests assert configured extension identifiers.

### Derived injection tests

Must prove both placements before E14 exists:

- inline fake inside plain paragraph;
- inline fake inside emphasis/link text;
- inline fake whose source contains Markdown-significant characters, proving successful source is shielded before cmark parse;
- block fake at top level;
- block fake nested in list/blockquote where outer container survives;
- deterministic token collision with authored sentinel-like text;
- stale generation;
- out-of-bounds/invalid UTF-16 boundary;
- front-matter range;
- duplicate/overlap;
- failed result;
- custom-node structural rejection and bounded fallback to authored source;
- resource reference rewrite/deduping;
- unresolved derived resource marker;
- deterministic order independent of input array order.

No fixture names a future language as an E12 implementation condition; math/diagram-shaped source is only test data.

### Template/metadata/theme tests

- front-matter title -> escaped `<title>` + one visible `<h1>`;
- absent title -> saved filename browser-title fallback, no invented visible heading;
- unsaved absent title -> empty browser title;
- invalid title diagnostic;
- every bundled theme maps through the same CSS builder;
- generated CSS/template output byte-stable;
- linked CSS is one content-addressed managed resource.

### Resource tests

Use temporary directories and real symlinks:

- in-root relative image;
- Unicode/spaces path;
- `..` escape;
- symlink escape;
- absolute/out-of-root path;
- missing file;
- directory instead of file;
- remote URL sentinel proving zero network call;
- media type fallback;
- duplicate identical bytes dedupe to one SHA-256 resource;
- single/count/aggregate budget boundaries;
- unsaved document relative asset;
- self-contained closure failure;
- companion remote/missing warning behaviour;
- PDF remote/missing fatal behaviour.

### Companion writer tests

- new directory + empty ownership marker then resources/HTML/new marker;
- valid prior ownership marker;
- unknown directory rejection before mutation;
- malformed/unsupported marker rejection;
- content-address collision bytes mismatch rejection;
- fault before first resource;
- fault mid-resource set;
- fault before primary promotion;
- fault after primary before marker update;
- marker update failure leaves valid primary/resources and skips cleanup;
- cleanup deletes only previous manifest-owned stale names;
- unknown files survive;
- cancellation boundaries.

### PDF adapter tests

At app/integration level:

- local resource scheme serves only manifest IDs;
- http/https requests fail and network sentinel observes zero requests;
- JS disabled;
- navigation/download/new-window blocked;
- copied `NSPrintInfo` maps to `PDFPageLayout` without paper-size literals;
- generated PDF opens in PDFKit, page count > 0;
- representative text searchable;
- local image present;
- 100+ page fixture paginates;
- long code/table fixtures remain usable;
- cancellation tears down transient web view and does not replace old target.

---

## 3.14 Verification and evidence plan

Architecture/code inspection is not acceptance evidence by itself.

From repository root, final implementation must run:

```bash
(cd MacDown2 && xcodegen generate)
(cd MacDown2/Packages/MacDownKit && swift build && swift test)
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -configuration Release build
swiftlint lint --strict MacDown2
swiftformat --lint MacDown2
```

The PR must additionally record:

1. package dependency resolution proving direct `swift-cmark` 0.8.0 compatibility;
2. Debug and Release app build evidence;
3. full package test summary;
4. automated offline/network sentinel result;
5. HTML self-contained browser dogfood for representative docs/assets/themes;
6. companion HTML dogfood including re-export/ownership behaviour;
7. PDF Preview.app/PDFKit dogfood, pagination and searchable text;
8. Release performance/resource evidence required by §3.10;
9. keyboard/VoiceOver/export-panel review;
10. localisation/string review;
11. remaining known limitations linked to issues where appropriate.

Do not mark PR ready merely because generated fixtures “look plausible” to an agent. Human visual review is required for representative HTML/PDF output.

---

## 3.15 Adversarial fidelity corpus

The corpus must cover at least these categories. Small cases may share fixture files, but every behaviour needs an explicit assertion/evidence row.

1. empty document;
2. ASCII prose/headings;
3. emoji/CJK/combining/non-BMP;
4. HTML text escapables;
5. very long code line/block;
6. nested lists/quotes;
7. tables/tasks/strikethrough/autolinks/footnotes;
8. duplicate/reference links and unusual valid URLs;
9. authored inline/block raw HTML;
10. dangerous raw tags covered by tagfilter;
11. dangerous link schemes as handled by cmark policy;
12. front-matter title valid/empty/non-string/escaped;
13. local images including Unicode filenames;
14. missing image;
15. `..` traversal;
16. symlink escape;
17. absolute local path;
18. remote image with zero-network sentinel;
19. single/aggregate resource budget edge;
20. resource count exactly 512 and 513 using tiny injected/generative fixtures as appropriate rather than committing huge blobs;
21. content deduplication;
22. raw HTML + self-contained rejection;
23. inline fake derived success;
24. block fake derived success + resource;
25. derived failure preserves source;
26. stale generation;
27. duplicate/overlap/invalid UTF-16 derived anchors;
28. derived sentinel collision;
29. nested block derived placement;
30. directives enabled/disabled;
31. untitled dirty document with relative image;
32. every bundled theme;
33. companion linked stylesheet dedupe;
34. existing known/unknown companion directory;
35. write fault injection at each commit stage;
36. 100+ page PDF;
37. PDF local image + remote-block sentinel;
38. cancellation during parse/resource/hash/PDF phases;
39. repeated/cancelled cmark render lifetime stress;
40. same complete request repeated -> byte-identical prepared HTML/resource names.

---

## 3.16 Expected files and symbol ownership

The implementation worker should create/edit this shape. Do not collapse it into one giant `ExportService.swift`.

### MacDownKit manifest

`MacDown2/Packages/MacDownKit/Package.swift`

- direct exact `swift-cmark` 0.8.0;
- cmark products only on `ExportService`;
- `ExportService` processes `Sources/ExportService/Resources`.

### `Sources/ExportService/`

- `ExportService.swift` — orchestration/prepare only.
- `ExportRequest.swift` — source/target/options request contracts.
- `ExportResult.swift` — prepared/result value types if not small enough to colocate cleanly.
- `ExportDiagnostic.swift` — typed codes/context/errors.
- `ExportResourceBudget.swift` — all central hard limits.
- `ExportOutputLayout.swift` — internal construction from typed target; exact companion naming.
- `Metadata/ExportMetadataResolver.swift` — fixed title policy.
- `Templates/ExportTemplate.swift` — typed template/context protocol/value.
- `Templates/BuiltInExportTemplateCatalog.swift` — one default template and no user discovery.
- `HTML/CMarkHTMLBodyRenderer.swift` — cmark tree lifecycle/render only.
- `HTML/CMarkConfiguration.swift` — sole cmark options/extensions/registration owner.
- `HTML/DerivedCMarkInjector.swift` — source-range validation, deterministic sentinels, custom-node mutation/fallback.
- `HTML/ExportStyleSheetBuilder.swift` — base CSS + Theme -> CSS variables.
- `HTML/HTMLTextEscaper.swift` — generated template text/attribute slots only; not a Markdown renderer/sanitizer.
- `Resources/default-export.css` — one structural/print stylesheet.
- `Assets/ExportResource.swift` — ID/content/media type.
- `Assets/ExportManifest.swift` — sole resource collection/index.
- `Assets/ExportResourceResolver.swift` — root containment/snapshot/hash/dedupe/budget.
- `Assets/ExportResourceReference.swift` — all embedded/relative/local-scheme/derived logical reference literals.
- `Derived/DerivedExportDestination.swift` — public generic anchor/placement/fragment contracts.
- `Writing/AtomicArtifactWriter.swift` — single-file sibling-temp promotion utility reusable by HTML/PDF app adapter.
- `Writing/HTMLExportArtifactWriter.swift` — companion ownership/write sequencing.
- `Writing/ExportOwnershipManifest.swift` — exact v1 marker encode/decode/validation.

If one of these files would contain only a trivial wrapper, it may be colocated with its direct owner, but ownership must not migrate into unrelated layers.

### `Tests/ExportServiceTests/`

Mirror the production units plus:

- `Fixtures/Markdown/`
- `Fixtures/ExpectedHTML/`
- generated temporary resource fixtures rather than committing huge binary limits.

### App target

- `ExportCoordinator.swift` — main-actor snapshot/task/UI orchestration only.
- `ExportPanelView.swift` — destination/theme/package options.
- `WebKitPDFRenderer.swift` — isolated print adapter.
- `PDFPageLayout.swift` — immutable captured system print geometry.
- app composition root wiring to construct standard service/writers.
- workspace command/menu routing edits.
- localisation strings.
- XcodeGen source inputs if required; regenerate project, never hand-edit `.xcodeproj`.

### Symbols that must not exist

- `MathExporter`, `MermaidExporter`, `DiagramExporter` in E12;
- renderer-language enum/switch in E12;
- global `ExportManager.shared`;
- a second resource list beside `ExportManifest`;
- public arbitrary `ExportOutputLayout(...)` initializer;
- request-level resource budgets/metadata policy/resource root;
- Handlebars/custom template loader;
- network-fetch helper;
- screenshot/raster PDF exporter.

---

## 3.17 Serial implementation slices and stop conditions

Implementation is deliberately serial. A lower-tier worker should implement **only the current slice**, make its verification green, then review before advancing.

### Slice 0 — dependency and type-contract gate

**Goal:** prove dependency/lifetime feasibility and freeze invalid-state-free public contracts before real composition.

**Implement only:**

- `Package.swift` direct exact cmark dependency/products/resource declaration if needed for build structure;
- `ExportRequest.swift`;
- `ExportDiagnostic.swift` minimal codes/errors needed by slice;
- `ExportResourceBudget.swift`;
- `ExportOutputLayout.swift`;
- `Derived/DerivedExportDestination.swift`;
- minimal `CMarkConfiguration` + C lifetime smoke wrapper/test.

**Exact acceptance:**

1. package resolves exactly cmark 0.8.0 without conflicting duplicate graph;
2. only ExportService imports cmark products;
3. built-in extension registration + parse + render + free succeeds repeatedly;
4. request has `UInt generation`; no public `Int revision`;
5. target owns URL and HTML-only options; contradictory target/layout states cannot compile;
6. request contains no budget/metadata/resource-root/output-layout/template override;
7. inline and block derived anchors compile with original-source UTF-16 range + `UInt generation`;
8. output-layout builder derives `report.assets` and rejects arbitrary/wrong paths.

**Verify:**

```bash
(cd MacDown2/Packages/MacDownKit && swift build && swift test)
```

**Stop/revise if:**

- direct cmark 0.8.0 resolution conflicts with current swift-markdown graph;
- required GFM/custom-node/lifetime APIs are unavailable from the pinned products;
- C ownership cannot be contained without unsafe shared mutable state;
- another dependency appears necessary.

Do not advance by adding a second Markdown library.

### Slice 1 — deterministic ordinary HTML composition

**Depends on:** Slice 0 green.

**Implement:**

- fresh parser orchestration;
- generation exact conversion;
- central cmark GFM/raw HTML mapping;
- metadata resolver;
- default CSS resource/theme variable builder;
- typed built-in template;
- complete prepared document with empty/simple manifest;
- no filesystem companion writes yet beyond test-safe primary if needed.

**Acceptance:** ordinary Markdown/GFM/front matter/theme corpus produces deterministic complete HTML5; raw HTML policy exact; every export uses fresh parse; no app/WebKit dependency.

**Stop/revise if:** material ordinary Markdown divergence cannot be fixed in `CMarkConfiguration`/central AST handling. Do not patch individual syntax in templates.

### Slice 2 — resource manifest, packaging and durable HTML writer

**Depends on:** Slice 1 green.

**Implement:**

- canonical source root derivation;
- containment/symlink/regular-file checks;
- byte snapshot + SHA-256 + UTType media type;
- single manifest and destination reference builder;
- self-contained data references;
- companion relative resources/linked CSS;
- exact ownership manifest and write/cleanup sequence;
- resource/fault/budget tests.

**Acceptance:** full resource matrix in §§3.8/3.13, content dedupe, self-contained closure, primary-last durability and unknown-file preservation.

**Stop/revise if:** implementation needs reads outside source root, network access, adoption/deletion of unknown files, truncated content hashes or cannot keep the new primary from referencing not-yet-written resources.

### Slice 3 — generic inline/block derived destination

**Depends on:** Slices 1-2 green.

**Implement:**

- deterministic source-range validation/sort/overlap policy;
- UTF-16/body mapping;
- deterministic sentinel generation/collision handling;
- pre-cmark substitution;
- cmark custom-inline/custom-block mutation;
- derived-resource rewrite through same manifest;
- bounded structural fallback/reparse;
- fake inline + block contributions only.

**Acceptance:** all derived tests in §3.13 pass, including inline Markdown-significant source, nested block, stale/overlap/failure and deterministic input-order independence. Failed/rejected contribution source remains visible in output.

**Stop/revise if:** implementation needs to import E14 types, parse math/diagram syntax, switch on renderer language, or build a second Markdown renderer. Do not defer inline support; E19 requires it.

### Slice 4 — macOS PDF adapter

**Depends on:** Slices 1-3 green.

**Implement in app target:**

- immutable `PDFPageLayout` from copied `NSPrintInfo`;
- locked-down transient WebKit config/scheme handler;
- prepared-document load;
- `WKWebView.printOperation(with:)` / `NSPrintOperation`;
- temp PDF + PDFKit validation + atomic promotion;
- network/JS/navigation/cancellation tests and 100+ page corpus.

**Stop/revise if:** macOS 26 print path cannot reliably preserve searchable text/pagination. Change the PDF adapter only; no composition fork, no screenshot PDF.

### Slice 5 — export UI/window integration

**Depends on:** Slices 1-4 green.

**Implement:**

- Markdown-only command enablement;
- save panels with HTML/PDF allowed types;
- selected theme from ThemeController;
- typed HTML packaging controls;
- current live text/fileURL/generation/options captured immediately before request creation;
- one task per window, progress/cancel, replacement cancellation;
- localised diagnostics;
- no source/save mutation.

**Acceptance:** dirty immediate export proves current editor snapshot, package/theme choices work, HTML/PDF success/failure/cancel states are accessible/localised, non-Markdown export remains disabled.

**Stop/revise if:** integration requires a global current document, global export singleton or makes an unowned format use Markdown export.

### Slice 6 — release hardening and evidence

**Depends on:** all functional slices green.

**Run/record:**

- full adversarial corpus;
- package/build/lint/format commands from §3.14;
- Debug + Release app builds;
- browser HTML dogfood;
- Preview.app/PDFKit dogfood;
- network sentinel/offline test;
- Release performance/memory evidence;
- accessibility/localisation review;
- remaining-risk review;
- owner-readable PR summary.

**Stop:** issue #13/PR implementation is not done if acceptance relies only on code inspection, synthetic assertions or agent judgement without required evidence.

---

## 3.18 Definition of Done and residual risks

Epic 12 implementation is done only when all of the following are true:

- [ ] Markdown HTML export uses a fresh immutable current-editor snapshot.
- [ ] `UInt` document generation is preserved at the boundary and exact-converted only for `ParseExecuting`.
- [ ] typed target/options make contradictory destination states unrepresentable.
- [ ] request does not expose output layout, production budget, metadata policy, resource root or template selection.
- [ ] direct exact cmark 0.8.0 dependency is isolated to ExportService and lifetime tests pass.
- [ ] ordinary Markdown/GFM fidelity corpus is reviewed and deterministic.
- [ ] front-matter title policy is implemented exactly.
- [ ] all bundled themes flow through one CSS variable mapper + one structural stylesheet.
- [ ] self-contained HTML embeds all E12-managed resources and rejects cases it cannot prove closed.
- [ ] companion resources use full SHA-256 names and exact ownership-manifest/write ordering.
- [ ] unknown companion files/directories are never adopted/deleted.
- [ ] export performs no network fetch/upload.
- [ ] local resource containment/symlink/budget tests pass.
- [ ] `ExportManifest` is the only prepared resource collection.
- [ ] fake `.inline` and `.block` derived output use one language-neutral source-range/sentinel/custom-node path.
- [ ] derived failure/staleness/invalidity/overlap preserves authored source.
- [ ] derived resources use the same manifest/reference/budget path as Markdown assets.
- [ ] E12 contains no production math/diagram logic and no renderer-language switch.
- [ ] PDF consumes the same prepared HTML, blocks network/JS and uses system print geometry.
- [ ] PDF corpus is searchable/selectable and visually reviewed, including 100+ pages/local images.
- [ ] Export UI snapshots dirty text at invocation, is Markdown-only, cancellable, keyboard accessible and localised.
- [ ] source document is never mutated by export.
- [ ] XcodeGen + package tests + Debug/Release builds + strict lint/format are green.
- [ ] Release performance/memory and offline evidence are recorded in the PR.
- [ ] owner-readable PR sections explain changes, why, how, test steps, risks and verification.

### Residual risks accepted by this architecture

1. **cmark dialect parity.** E06 uses swift-markdown while E12 directly uses the underlying cmark-gfm path. The permanent parity corpus is the upgrade gate; individual drift must not be patched with a second renderer.
2. **Block directives.** cmark may not reproduce swift-markdown block-directive interpretation. E12 preserves authored directive source rather than inventing export semantics until a dedicated owner exists.
3. **Authored raw HTML.** Normal HTML preserves authored raw HTML under cmark `UNSAFE + tagfilter`; tagfilter is not a full sanitizer. Self-contained rejects raw HTML. PDF locks down JavaScript/network but cannot statically crawl every resource reference inside arbitrary raw HTML without a new HTML parser; it warns and renders best-effort.
4. **Legacy MPAsset evidence.** Useful behaviour is migrated from available concepts/tests, but no current concrete MPAsset source contract was found. Material later discovery is an architecture stop condition.
5. **Issue #35.** Non-Markdown files entering the Markdown parse path remains outside E12; export stays Markdown-only.
6. **System PDF stack.** WebKit/AppKit print behaviour is platform-owned. The adapter is intentionally isolated so a verified replacement does not fork composition.
7. **Local filesystem TOCTOU.** Canonical containment + immediate byte snapshot protects normal path traversal/symlink cases but does not claim adversarial race-free filesystem semantics.
8. **Crash or marker-update orphan resources.** Primary correctness is prioritised over aggressive cleanup. Content-addressed orphan files can remain after a crash; E12 never guesses ownership to remove them.
9. **Initial resource limits.** `.standard` values are safety defaults pending Slice 6 Release evidence. They are centralised so evidence-based tuning does not alter architecture or callers.

No residual risk above is permission to weaken the invariant that first-party export remains local/offline, source-preserving and single-pipeline.