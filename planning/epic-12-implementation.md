# Epic 12 Implementation Architecture — HTML/PDF Export

Status: **binding architecture for `epic/12-export`**  
Epic: **#13 — Export: HTML + PDF, templates, themes and derived-content contract**  
Baseline: **`master` @ `8d22f0e740a31b1d0afb64c5b781f7e983df50a1`**  
Architecture date: **2026-08-17**

This document follows `planning/EPIC_STANDARD.md` and reconciles the live repository with `planning/RELEASE_HARDENING.md` before implementation begins.

## 3.1 Owner summary

Epic 12 gives MacDown 2 one dependable export pipeline for ordinary Markdown now and for equations/diagrams later. A user will be able to export the text currently visible in the editor to a complete HTML document or a paginated PDF, choose an existing MacDown theme, and control whether managed HTML resources are copied beside the document or embedded into it. Export remains local/offline.

The main architectural decision is to keep **one composition path**. Markdown is parsed from a fresh immutable editor snapshot, rendered to a GFM-faithful HTML body through a narrowly wrapped `swift-cmark` adapter, combined with front-matter metadata, theme-derived CSS and managed assets into one `PreparedExportDocument`, then sent to either the HTML writer or the macOS PDF adapter. PDF is therefore not a second Markdown renderer.

The design deliberately minimises scattered hard-coding:

- formats/options are typed enums and value objects rather than string dictionaries;
- the default HTML template is behind a template catalog and typed context;
- export styling derives from the existing `Theme` value instead of maintaining a second color catalog;
- asset naming is content-addressed rather than based on counters/random IDs;
- resource limits live in one injected `ExportResourceBudget`;
- the future derived-content seam is generic and knows nothing about math, Mermaid, Graphviz or any other language;
- AppKit/WebKit are adapters at the app edge, not dependencies of export composition.

The most important risks are PDF pagination behavior in WebKit/AppKit, resource-path containment, and keeping the direct cmark export dialect aligned with the existing Markdown parser. Those risks receive explicit integration tests and stop conditions below.

Non-goals: production math/diagram rendering, user-authored template UI, ePub/DOCX, hosted rendering, fixing unrelated multi-format parsing issue #35, or building a plugin registry (Epic 14 owns contribution lifecycle/registry/isolation).

## 3.2 Baseline / repository reconciliation

### Live baseline

- `master` baseline: `8d22f0e740a31b1d0afb64c5b781f7e983df50a1`.
- Epic 11 is merged; HTML source/rendered preview and the format registry are real upstream capabilities, not assumptions.
- `ExportService` exists only as a scaffold at `MacDown2/Packages/MacDownKit/Sources/ExportService/ExportService.swift`.
- `ExportService` already depends on `MarkdownEngine` and `Themes`.
- `MarkdownEngine` exposes renderer-neutral `MarkdownDocument`, `MarkdownBlock`, `FrontMatter`, `SourceMap`, `MarkdownParseOptions` and injectable `ParseExecuting`.
- `ParseEngine` is an actor and is the production `ParseExecuting` implementation. Export must request a **fresh parse of the current editor snapshot** rather than reuse the debounced preview result.
- `ThemeController` is the app-wide source of available/current `Theme` values. Export will consume a copied `Theme`; it will not duplicate theme selection state.
- Epic 11 already contains a locked-down `WKWebView` pattern for HTML preview: JavaScript disabled, nonpersistent data store, navigation restrictions, local resource scope and CSP. PDF rendering should reuse the security policy concepts, not duplicate ad-hoc WebKit configuration.
- `FileDocument` exposes current text/file URL/format/mutation generation; `WindowCoordinator`/`WindowController` are the app orchestration boundary.

### Stale or changed assumptions reconciled

1. `planning/MIGRATION_PLAN.md` selects `swiftlang/swift-cmark` for HTML export. The live package currently declares `swift-markdown` 0.8.0, whose own package depends on `swift-cmark` and cmark-gfm. E12 will add an **explicit exact 0.8.0 `swift-cmark` dependency** to MacDownKit and only the `cmark-gfm` / `cmark-gfm-extensions` products to `ExportService`. This follows the approved roadmap, makes the C API dependency explicit rather than relying on an undeclared transitive import, and should resolve to one package version.
2. `swift-markdown` 0.8.0 has an `HTMLFormatter`, but its implementation is not the export contract. E12 uses cmark-gfm's mature HTML renderer instead of maintaining an app-owned Markdown-to-HTML renderer.
3. The current `MarkdownParseOptions` intentionally records per-feature intent for E12/E13 even though `swift-markdown` currently enables most GFM features together. The cmark adapter must consume these flags where cmark supports equivalent switches/extensions and document any semantic difference.
4. `AGENTS.md` describes `legacy-reference/` and Epic 12 mentions legacy `MPAsset` concepts, but no concrete `MPAsset` symbol was discoverable in the live baseline inspection. E12 therefore ports the **documented behavior concepts** (logical asset name, contents/source, deterministic lookup, template context, fallback/default) rather than inventing class compatibility. If implementation discovers a concrete legacy contract that materially changes behavior, stop and revise this architecture.
5. Open issue #35 still allows non-Markdown formats into the Markdown parse path. E12 does not expand that scope. `Export…` is enabled only for Markdown documents until a format explicitly owns an export adapter.

### Production versus scaffold

Production upstream: file/document model, Markdown parse/front matter/source mapping, themes, window coordination, format registry, HTML preview security policy.  
Scaffold only: `ExportService`.  
New in E12: export contracts, cmark adapter, HTML composition/template/style/assets, derived export destination contract, PDF adapter, export UI, evidence corpus.

## 3.3 User journeys

### J1 — HTML export, normal document

1. User invokes **File → Export…** on a Markdown document.
2. The export panel defaults to HTML and the current `Theme`.
3. The user chooses resource mode and stylesheet mode, then chooses a destination.
4. The app snapshots the **current editor text**, file URL, resource root, parse options, document revision and chosen theme into an immutable `ExportSourceSnapshot`/`ExportRequest`.
5. `ExportService` freshly parses that exact text, renders one HTML body, resolves managed resources, applies the template/theme and returns a `PreparedExportDocument`.
6. The writer stages all files and atomically promotes them to the selected destination.
7. Success is reported. Non-fatal diagnostics are surfaced; nothing is silently omitted.

### J2 — self-contained HTML

Same as J1, but managed local image resources and CSS are embedded. MacDown does **not** fetch remote resources. If the document contains a managed resource that cannot be embedded while self-contained mode is promised, export fails or explicitly reports that the guarantee cannot be met; it must never silently produce a falsely labelled self-contained file.

### J3 — PDF export

1. User chooses PDF and a theme.
2. E12 runs the same snapshot → parse → cmark body → metadata/theme/assets → `PreparedExportDocument` path as HTML.
3. The app gives that prepared document to the isolated `WebKitPDFRenderer`.
4. The renderer loads through a locked-down local scheme, waits for completion, creates an `NSPrintOperation` from the web view, applies a captured `PDFPageLayout`, saves to a temporary PDF, validates it, and the writer atomically promotes it to the chosen URL.
5. Remote loading and script execution stay disabled during PDF generation.

### J4 — front matter title

A scalar `title` in valid front matter becomes both the HTML `<title>` value and the visible document-title header according to the default metadata policy. Unknown front-matter keys are not guessed into arbitrary `<meta>` tags in E12.

### J5 — missing/bad local asset

Export resolves the reference relative to the supplied resource root and document URL. If it is missing/out of scope, the original reference/source remains represented and a typed diagnostic identifies the resource. Strict self-contained export fails; ordinary linked/copy export may complete with a warning according to the central policy.

### J6 — future derived block succeeds

A caller supplies a generic `DerivedExportResolution.rendered` for an opaque stable source identity and exact source line range. E12 replaces that exact cmark block with destination HTML and routes any derived resources through the same asset manifest. No language-specific branch exists in E12.

### J7 — future derived block fails

A caller supplies `DerivedExportResolution.failed`, or a rendered contribution does not match one exact block in the current snapshot. E12 keeps the authored Markdown block in the output and emits a diagnostic. It never silently drops the source.

### J8 — unsaved/dirty document

Export uses the text in the editor at invocation time. It does not save, normalise or mutate the source file. Relative resources that require a file/resource root but cannot be resolved from an untitled document produce diagnostics rather than hidden filesystem guesses.

## 3.4 Non-negotiable invariants

1. **One composition pipeline.** PDF consumes the same prepared HTML/CSS/assets as HTML export; no second Markdown renderer.
2. **Current text wins.** Export freshly parses the editor snapshot captured for the request. Debounced preview state is never authoritative for export.
3. **Source is immutable.** Export never changes document text, encoding, line endings, save state or file contents.
4. **Offline/local first-party behavior.** E12 performs no upload, remote render or network fetch.
5. **Renderer-neutral upstream boundary.** `MarkdownDocument` and E14's future core contribution result do not acquire SwiftUI/WebKit types.
6. **No format strings as architecture.** Public/request-facing format, resource, stylesheet, metadata and failure choices are typed.
7. **No language-specific derived logic.** `ExportService` contains no `math`, `mermaid`, `diagram`, `graphviz`, etc. switch.
8. **Derived failure preserves authored source.** A failed/missing/stale/ambiguous derived contribution cannot erase its source block.
9. **All generated companion resources use one resolver/manifest.** Markdown assets and future derived resources cannot bypass policy via side channels.
10. **Deterministic composition.** Given the same source snapshot, options, theme and derived resolutions, prepared HTML and logical resource names are byte-stable. No timestamps, random UUIDs or process-specific values enter generated content.
11. **No mutable global export registry/state.** Catalogs/policies are immutable values or injected dependencies.
12. **Platform APIs stay at the edge.** `ExportService` does not import SwiftUI, WebKit or AppKit.
13. **No silent security-scope expansion.** Local resource resolution never reads outside the request's explicit `resourceRootURL` after standardisation/symlink resolution.
14. **No false self-contained claim.** Strict self-contained mode either embeds every E12-managed resource or returns an explicit failure/unsupported diagnostic.
15. **C ownership is explicit.** Every cmark parser/node/buffer/list allocation is freed on every success/failure/cancellation path through one adapter.

## 3.5 Ownership and dependency boundaries

### `MarkdownEngine` — source interpretation

Owns current Markdown/front-matter parse semantics, source mapping and `ParseExecuting`. E12 uses it for the fresh authoritative snapshot parse. E12 does **not** expose cmark or WebKit types through MarkdownEngine.

### `Themes` — canonical visual tokens

Owns `Theme` and `ThemeController`. E12 consumes a `Theme` value. Export-specific CSS/layout semantics stay in `ExportService`; do not add CSS strings or PDF rules to `Theme`.

### `ExportService` — deterministic export composition

Owns:

- request/result/diagnostic contracts;
- cmark-gfm HTML-body adapter;
- template catalog + typed template context;
- metadata resolution;
- theme → CSS conversion;
- managed-resource resolution, rewriting and manifest;
- generic derived export destination contract;
- prepared HTML document used by both destinations;
- filesystem artifact writer protocol + production atomic implementation if it remains Foundation-only.

May depend on `MarkdownEngine`, `Themes`, Foundation, UniformTypeIdentifiers/CryptoKit as system frameworks if needed, and exact `swift-cmark` products. It must not depend on AppKit/WebKit/SwiftUI.

### App target — user interaction and macOS rendering

Owns:

- `ExportCoordinator` (`@MainActor`);
- File menu command enablement;
- `ExportPanelView` / model;
- snapshotting the active `FileDocument` and workspace resource root;
- save-panel interaction;
- `WebKitPDFRenderer` and `PDFPageLayout.systemDefaultSnapshot()`;
- user-facing diagnostic presentation.

### Epic 14 and later renderers

E14 owns contribution registration/lifecycle/isolation and the renderer-neutral result. E19/E20/E21 own concrete renderer implementations. They adapt successful renderer-neutral results into E12's generic destination value. E12 never reaches into their registries or knows their language IDs.

### Dependency rule

Do not create a new SwiftPM target for HTML export merely to hide cmark. The existing `ExportService` target already has the correct roadmap ownership. The cmark C API is hidden behind an internal `MarkdownHTMLBodyRendering` protocol within that target. Create a new target only if an implementation fact proves a real independent lifecycle/reuse boundary; that requires architecture revision.

## 3.6 Types and interfaces

Names may move locally for Swift clarity, but workers must preserve these responsibilities and dependency directions.

```swift
public enum ExportFormat: String, CaseIterable, Sendable {
    case html
    case pdf
}

public struct ExportSourceSnapshot: Sendable {
    public let text: String
    public let fileURL: URL?
    public let resourceRootURL: URL?
    public let suggestedTitle: String?
    public let parseOptions: MarkdownParseOptions
    public let revision: Int
}

public struct ExportRequest: Sendable {
    public let source: ExportSourceSnapshot
    public let format: ExportFormat
    public let theme: Theme
    public let html: HTMLExportOptions
    public let metadata: ExportMetadataPolicy
    public let derived: [DerivedExportResolution]
    public let budget: ExportResourceBudget
}

public struct HTMLExportOptions: Sendable, Equatable {
    public let templateID: ExportTemplateID
    public let stylesheet: ExportStylesheetMode
    public let resources: ExportResourceMode
}

public enum ExportStylesheetMode: Sendable, Equatable {
    case embedded
    case linked
}

public enum ExportResourceMode: Sendable, Equatable {
    case copyAdjacent
    case selfContained
}
```

Do not add a generic `[String: Any]`/`[String: String]` options bag.

### Prepared document

```swift
public struct PreparedExportDocument: Sendable {
    public let html: String
    public let resources: [ExportResource]
    public let manifest: ExportManifest
    public let diagnostics: [ExportDiagnostic]
}
```

The HTML string is a complete UTF-8 HTML5 document. `resources` are logical companion resources that have not been written to arbitrary user paths yet.

### Parser injection

```swift
public struct ExportService: Sendable {
    public init(
        parser: any ParseExecuting,
        htmlRenderer: any MarkdownHTMLBodyRendering,
        templateCatalog: any ExportTemplateCatalog,
        resourceResolver: any ExportResourceResolving
    )

    public func prepare(_ request: ExportRequest) async throws -> PreparedExportDocument
}
```

Production composition injects `ParseEngine()` and the production adapters. Tests inject fakes. If the concrete Swift shape needs an actor because a dependency is not safely `Sendable`, that is acceptable; do not use `@unchecked Sendable` to silence a real ownership problem.

### cmark adapter

```swift
protocol MarkdownHTMLBodyRendering: Sendable {
    func render(
        document: MarkdownDocument,
        derived: [DerivedExportResolution],
        resourceRewriter: ExportResourceRewriting
    ) throws -> MarkdownHTMLBody
}
```

`CMarkHTMLBodyRenderer` is internal to `ExportService`. It:

- parses `MarkdownDocument.body` using cmark-gfm;
- registers/attaches supported GFM extensions according to `MarkdownParseOptions`;
- uses source positions plus `bodyLineOffset` to match derived anchors;
- rewrites managed image/resource nodes before render;
- renders through `cmark_render_html`;
- owns all C pointer/list/buffer cleanup;
- never leaks cmark types into a public API.

Use cmark-gfm renderer escaping for ordinary text/code/attributes. Raw authored HTML policy must be central and explicit; do not concatenate unescaped Markdown strings into output.

### Typed template layer

```swift
public struct ExportTemplateID: Hashable, Sendable, RawRepresentable { ... }

struct ExportTemplateContext: Sendable {
    let title: String?
    let visibleTitle: String?
    let bodyHTML: String
    let stylesheet: ExportStylesheetReference
    let theme: Theme
    let manifest: ExportManifest
}

protocol ExportTemplate: Sendable {
    var id: ExportTemplateID { get }
    func render(_ context: ExportTemplateContext) throws -> String
}

protocol ExportTemplateCatalog: Sendable {
    func template(id: ExportTemplateID) throws -> any ExportTemplate
    var descriptors: [ExportTemplateDescriptor] { get }
}
```

E12 ships one built-in default template. The catalog/seam exists so later built-ins do not require a central switch, **not** to introduce arbitrary user code/template execution. Template values are strongly typed; do not resurrect an untyped Handlebars-style variable dictionary.

### Theme/CSS

`ExportStyleSheetBuilder` is a pure value transformer from `Theme` + one centrally owned `ExportLayoutProfile` to CSS. It must derive colors from `Theme.chrome` rather than maintain a second palette. Structural typography/spacing/code/table/print CSS lives in this one builder/template, not throughout UI/service code.

Do not make `Theme` export-specific. If a later epic needs export-only typography themes, add a separate export-theme value and explicit conversion rather than growing unrelated fields on editor themes.

### Metadata

`ExportMetadataResolver` owns the only front-matter key interpreted by E12: scalar `title`. Resolution order:

1. valid non-empty scalar front-matter `title`;
2. `ExportSourceSnapshot.suggestedTitle`;
3. no title.

When present, the resolved title is HTML-escaped by the template and appears in both `<title>` and the visible document header under the default policy. Unknown front-matter keys are not emitted as arbitrary HTML metadata.

### Generic derived destination contract

```swift
public struct DerivedSourceID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
}

public struct DerivedExportAnchor: Hashable, Sendable {
    public let sourceID: DerivedSourceID
    public let originalLineRange: ClosedRange<Int>
    public let sourceRevision: Int
}

public enum DerivedExportResolution: Sendable {
    case rendered(DerivedExportContent)
    case failed(DerivedExportFailure)
}

public struct DerivedExportContent: Sendable {
    public let anchor: DerivedExportAnchor
    public let htmlFragment: String
    public let resources: [DerivedExportResource]
    public let diagnostics: [ExportDiagnostic]
}

public struct DerivedExportFailure: Sendable {
    public let anchor: DerivedExportAnchor
    public let diagnostic: ExportDiagnostic
}
```

Rules:

- E12 treats `sourceID` as opaque; no language parsing/switching.
- `sourceRevision` must equal the export snapshot revision.
- `originalLineRange` must match exactly one complete block node after applying `bodyLineOffset`.
- overlap, duplicate anchors, revision mismatch, absent block or partial-block match are deterministic failures; source stays rendered normally.
- rendered fragments enter only at the matched body location, never `<head>`/template metadata.
- derived resources enter the same resource manifest/policy as Markdown resources.
- this destination representation is **not** the E14 core renderer result. E14 later adapts its renderer-neutral result to this destination type.

### Resources and manifest

```swift
public struct ExportResource: Sendable {
    public let logicalPath: String
    public let mediaType: String
    public let digest: SHA256Digest
    public let source: ExportResourceSource
}

public enum ExportResourceSource: Sendable {
    case file(URL)
    case data(Data)
}

public struct ExportManifest: Sendable {
    public let resources: [ExportResourceManifestEntry]
    public let isSelfContained: Bool
}
```

Local files should remain file-backed until a mode actually needs bytes; do not eagerly load every companion asset into memory.

Logical companion names use the full SHA-256 digest plus a MIME/UTType-derived extension under a single export asset directory. Do not use random UUIDs, counters or original arbitrary paths as collision control.

### Central resource budget

```swift
public struct ExportResourceBudget: Sendable, Equatable {
    public let maxManagedResourceCount: Int
    public let maxSingleResourceBytes: Int64
    public let maxAggregateResourceBytes: Int64
    public let maxDerivedFragmentBytes: Int64

    public static let standard = ExportResourceBudget(
        maxManagedResourceCount: 512,
        maxSingleResourceBytes: 32 * 1024 * 1024,
        maxAggregateResourceBytes: 128 * 1024 * 1024,
        maxDerivedFragmentBytes: 16 * 1024 * 1024
    )
}
```

These values are policy, not magic numbers: they live only here, are injectable in tests, are documented in UI error text without duplicating the literals, and may be changed by a later evidence-backed architecture decision.

## 3.7 State and data flow

```text
active FileDocument / workspace / ThemeController
                 |
                 | @MainActor immutable snapshot
                 v
          ExportSourceSnapshot
                 |
                 v
      ExportService.prepare(request)
                 |
         ParseExecuting.parse          <- fresh authoritative parse
                 |
          MarkdownDocument
                 |
                 +--> metadata resolver --> title/header metadata
                 |
                 +--> CMarkHTMLBodyRenderer
                 |        |
                 |        +--> parse body with cmark-gfm
                 |        +--> match generic derived anchors
                 |        +--> resolve/rewrite managed resources
                 |        +--> cmark_render_html
                 |
                 +--> theme -> ExportStyleSheetBuilder
                 |
                 +--> typed ExportTemplate
                 v
        PreparedExportDocument
          /                 \
         /                   \
 HTML destination        PDF destination
 atomic writer           locked WebKit loader
                          -> NSPrintOperation
                          -> temporary PDF
                          -> atomic writer
```

The app does not hand the service live mutable `FileDocument`, `ThemeController`, `WorkspaceModel` or view state. The export request is a value snapshot. This prevents a mid-export edit/theme change from creating a mixed artifact.

The prepared manifest is the single record of all managed resources. HTML and PDF adapters consume it; neither rescans the filesystem independently.

## 3.8 Concurrency and cancellation

- `@MainActor ExportCoordinator` performs only UI/state snapshotting, panels and WebKit/AppKit work.
- `ExportService.prepare` must execute parse/composition/resource hashing away from the main actor. The existing `ParseEngine` already runs off main. Any synchronous cmark/resource work must not be performed while main-actor isolated.
- Do not use `Task.detached` merely to silence isolation. Prefer actor/nonisolated async ownership that remains structured and inherits cancellation.
- A window owns at most one active export task. Starting another export for the same window cancels the prior task after user confirmation is no longer needed.
- `Task.checkCancellation()` is required at phase boundaries: before parse, after parse, before/after cmark work, between resource resolutions, before template composition and before write/render handoff.
- File hashing/copying is bounded and streaming where Foundation APIs permit. Cancellation is checked between chunks/resources.
- `WebKitPDFRenderer` is `@MainActor` because WebKit/AppKit require it. Cancellation before print starts aborts load and cleans temporary files. Once an AppKit print operation has entered a non-cancellable system phase, cancellation is best-effort: suppress promotion/result and clean the temporary artifact afterward.
- No process-wide export actor serialises unrelated windows. Mutable per-export state is request-local.

## 3.9 Failure model

Use typed errors for aborting failures and typed diagnostics for non-fatal fidelity issues.

Representative `ExportError` cases:

- `unsupportedDocumentFormat`
- `parseFailed`
- `templateUnavailable`
- `invalidTemplateOutput`
- `selfContainedResourceUnavailable`
- `resourceOutsideAllowedRoot`
- `resourceBudgetExceeded`
- `derivedConflict`
- `pdfRenderingFailed`
- `artifactWriteFailed`
- `cancelled`

Representative diagnostic codes:

- missing local resource;
- remote resource retained without fetch;
- remote resource blocked for PDF;
- raw HTML may contain unmanaged external references;
- derived contribution stale/ambiguous/failed;
- unresolved untitled-document relative resource;
- unsupported resource media type.

Rules:

1. Diagnostics carry stable machine-readable code + localisable structured arguments; user-visible sentences are created at the UI edge.
2. Strict self-contained mode fails if an E12-managed resource cannot be embedded. Do not downgrade silently.
3. Ordinary copy-adjacent HTML may complete with a broken/missing authored image reference **only with a visible diagnostic**; the Markdown source itself remains represented.
4. PDF may complete when an authored remote image is blocked if the document remains readable; it returns a warning. PDF generation itself never turns network access on to improve fidelity.
5. A failed derived result is normally a warning plus source fallback. Structural conflicts that make replacement ordering ambiguous never pick an arbitrary winner.
6. Writing uses staging + atomic promotion. A failed export must not leave a partially updated primary file or half-updated companion directory.

## 3.10 Security and trust model

### Local/offline

- No HTTP client and no hosted renderer are added to E12.
- Markdown remote URLs may be preserved as authored links in exported HTML, but MacDown does not fetch them.
- PDF WebKit blocks remote navigation/subresources and keeps JavaScript disabled.

### Local file scope

`ExportSourceSnapshot.resourceRootURL` is explicit:

- if the document belongs to an open workspace, use the workspace root;
- otherwise use the document's parent directory;
- for an untitled document, use `nil` unless the user has explicitly supplied a resource root through an existing file-selection flow.

For every local managed resource, standardise and resolve symlinks before containment checks. A path that escapes the canonical root is not read/copied/embedded. Do not weaken this because the current app is unsandboxed.

### HTML safety

- cmark-gfm owns escaping of ordinary Markdown text/code/link attributes.
- The raw authored HTML policy is one explicit renderer policy. If preserving authored raw HTML requires cmark's unsafe-render option, document/test that this preserves **authored** HTML/links in the exported artifact; do not use the option as permission to bypass escaping for generated metadata/template strings.
- Template title/attributes are escaped by a small context-specific HTML escaper owned by the template layer.
- Derived HTML enters only the body replacement point and is considered renderer output, not trusted executable app content. It is never executed with privileged app capabilities.

### PDF WebKit sandbox

Reuse the Epic 11 policy concepts:

- nonpersistent `WKWebsiteDataStore`;
- JavaScript disabled;
- local custom scheme/resource handler rather than broad `file://` access;
- navigation/download/window-open denial;
- no remote subresource loading;
- CSP appropriate for the transient PDF-render document;
- only manifest resources are served by the scheme handler.

The exported HTML file itself is a user-owned artifact and may preserve raw HTML the user authored. The in-app PDF renderer must not execute it as privileged/trusted content.

### Dependency surface

`swift-cmark` is exact-pinned and wrapped internally. No dynamic cmark plugin loading is used; only built-in GFM extensions are registered/attached.

## 3.11 Resource and performance budgets

### Memory/resource bounds

- `ExportResourceBudget.standard` is the sole production source for managed-resource limits.
- Linked/copy mode keeps local assets file-backed and streams copies; no `[Data]` mirror of the whole resource set.
- Self-contained mode may require base64 expansion. Process one asset at a time and enforce the aggregate input budget before composition.
- cmark tree/buffers are freed immediately after body HTML is materialised.
- `PreparedExportDocument` should not keep both multiple equivalent full HTML strings and the source AST.

### Performance evidence gates

Record hardware/OS/build configuration with results. Measure Release builds.

1. **1 MiB Markdown, no external assets:** HTML preparation median of 5 warm runs ≤ 1.0 s; no main-thread stall attributable to parse/cmark/resource work > 16 ms.
2. **25 MiB aggregate local images, copy-adjacent:** preparation must not eagerly duplicate the 25 MiB into an in-memory resource array; peak RSS delta attributable to export ≤ 128 MiB.
3. **25 MiB aggregate local images, self-contained:** peak RSS delta ≤ final HTML byte size + 128 MiB; no unbounded temporary duplication.
4. **100-page PDF fixture:** median of 3 Release runs ≤ 10 s on the recorded reference Mac, with no page truncation. If the platform print stack cannot meet this reliably, record measured evidence and revise the budget explicitly rather than hiding the regression.
5. Cancellation before PDF print phase becomes user-observable within 250 ms at cancellable phase boundaries.

Performance failures stop the owning slice; do not trade correctness/security for benchmark compliance without architecture revision.

## 3.12 Accessibility and localisation

### Export panel

- All controls are keyboard reachable in logical order.
- Format/theme/resource/style controls have VoiceOver labels and values; do not rely on icon-only meaning.
- Conditional HTML options remain discoverable when format changes; focus is not discarded into nowhere.
- Export progress/cancellation and error/warning states are announced accessibly.
- Minimum hit areas/layout follow macOS controls rather than custom tiny buttons.

### Localisation

- User-facing export strings go through the app String Catalog from the first implementation slice that introduces them.
- Enum raw values/diagnostic codes are never displayed directly.
- Template-generated document text is limited to user/source content; do not inject localised MacDown UI phrases into exported content unless they are intentionally part of the document.
- Do not infer document language from the Mac UI locale. E12 does not hard-code `lang="en"`.

### Generated document accessibility

- Use semantic `<main>`/`<article>`, heading/list/table/code elements emitted by cmark, and existing image alt text.
- Visible front-matter title is a semantic heading under the default template.
- Theme CSS must maintain readable foreground/background usage; automated contrast checks cover bundled theme exports where practical. A failing bundled theme export requires a documented style adjustment, not silent color replacement in one destination.
- PDF text must remain selectable/searchable; rasterising the whole page is not acceptable.

## 3.13 Export and interoperability contract

### HTML

- UTF-8 HTML5 complete document, not a fragment.
- `<meta charset="utf-8">` and viewport metadata.
- Resolved title in `<title>` and visible header when present.
- Body generated from cmark-gfm with GFM extensions matching `MarkdownParseOptions` where supported.
- CSS either embedded or written as a manifest companion resource.
- Companion asset paths are relative and deterministic.
- No timestamps/random values in generated HTML.
- Default template/CSS has explicit screen and print rules; code blocks wrap/readably break for print rather than clipping off-page.

### GFM option mapping

`CMarkHTMLBodyRenderer` owns one mapping table from `MarkdownParseOptions` to cmark parser/extensions. At minimum cover tables, task lists, strikethrough, autolinks and footnotes with the pinned library's supported mechanisms. `blockDirectives` has no equivalent cmark-gfm semantic renderer; preserve directive source as ordinary Markdown text rather than silently dropping it and add a parity test documenting the behavior. No other module duplicates extension-name strings or cmark option bits.

### Raw HTML

Default export favors authored-source fidelity. The exact cmark option used to preserve raw HTML must be isolated in the adapter and covered by adversarial tests for ordinary text escaping, code escaping, attribute escaping and dangerous authored URLs. PDF uses the locked-down renderer regardless of HTML fidelity policy.

### Assets

E12-managed Markdown image references:

- relative/local and inside root → copy or embed;
- local but outside root → never read, diagnostic/failure by mode;
- missing → diagnostic/failure by mode;
- remote → never fetched; preserve URL in ordinary HTML, fail strict self-contained guarantee, block during PDF rendering.

Arbitrary raw HTML resource graphs are **not** fully crawled/re-written in E12. If raw HTML exists, strict self-contained export must not claim complete closure over unknown raw-HTML references without proof; emit the defined diagnostic and either block strict mode or explicitly scope the guarantee to managed resources in UI copy. Preferred E12 behavior is to block the strict guarantee when raw HTML includes external resource-bearing attributes that cannot be proven local/embedded.

### PDF

- `WebKitPDFRenderer` consumes only `PreparedExportDocument` + a value `PDFPageLayout`.
- Capture system-default paper size/imageable bounds/margins once into `PDFPageLayout`; do not hard-code A4/Letter by geography.
- Tests inject fixed page layouts for deterministic pagination assertions.
- Use WebKit's print operation/AppKit print pipeline rather than a viewport screenshot/canvas capture.
- Hide print/progress panels for export; save to a temporary URL, validate a readable PDF, then atomically promote.
- Use PDFKit in integration tests to assert page count/text extractability where appropriate.

### Legacy asset concepts

The old acceptance language around `MPAsset` is implemented as modern behavior, not class recreation:

- typed logical asset identity;
- data/file-backed content source;
- deterministic catalog/manifest lookup;
- duplicate logical-path rejection;
- explicit default/fallback template behavior;
- no implicit global mutable asset registry.

Tests must name these behaviors so later reviewers can see the acceptance mapping even if the old concrete source remains unavailable.

## 3.14 Test and evidence matrix

| Requirement | Automated evidence | Manual/dogfood evidence |
|---|---|---|
| ordinary Markdown → HTML | golden fixture corpus + structural assertions | export representative README and open in Safari |
| GFM tables/tasks/strike/autolinks/footnotes | per-option cmark adapter tests | visual check corpus |
| front-matter title | metadata/template tests | title shown in browser tab + header |
| current dirty text | coordinator test with preview parse intentionally stale | type then immediately export without saving |
| theme reuse | CSS builder tests across all bundled themes | light/dark exports readable |
| embedded CSS | exact structural test | open file after moving it alone |
| linked CSS | manifest/path test | move primary + companion folder together |
| self-contained local images | data-URI/content test | disconnect network and open moved file |
| no network fetch | fake URL protocol/network sentinel tests | export while offline |
| path traversal/symlink escape blocked | asset resolver adversarial tests | — |
| deterministic names/output | repeat export byte equality | — |
| derived success | fake generic rendered contribution | inspect source replacement |
| derived failure preserves source | fake failure/stale/ambiguous tests | — |
| no language-specific export logic | source-level test/search assertion where useful + review | — |
| paginated PDF | PDFKit integration tests with fixed layout | inspect 100-page fixture/code blocks |
| PDF no JS/network | WebKit navigation/resource sentinel tests | offline export |
| PDF selectable text | PDFKit text extraction | Preview.app selection/search |
| atomic write | fault-injected writer tests | existing destination replacement |
| cancellation | phase-controlled fake tests | cancel large export |
| localisation/a11y | String Catalog coverage + accessibility identifiers | VoiceOver/keyboard pass |
| performance | Release benchmark harness/evidence record | reference-Mac run |

Golden tests should compare stable semantic output. Do not normalise away meaningful differences merely to make snapshots pass.

## 3.15 Adversarial corpus

The fixture corpus must include at least:

1. plain ASCII Markdown;
2. emoji/CJK/combining marks/non-BMP Unicode;
3. `<`, `>`, `&`, quotes in text, code, titles, link labels and URLs;
4. fenced/indented code with very long lines and HTML-looking content;
5. nested lists/quotes;
6. tables, task lists, strikethrough, autolinks and footnotes;
7. duplicate/reference links and complex URLs;
8. raw HTML block/inline content, including script/style/event-handler examples;
9. dangerous authored link schemes (`javascript:`, `data:`, `file:`) to lock the chosen fidelity policy;
10. valid/invalid/empty/non-string front-matter title values;
11. local image in root, nested path, Unicode filename, missing file;
12. `..` path escape and symlink escape;
13. absolute local path;
14. remote image/link with a network sentinel proving zero fetch;
15. oversized single resource and aggregate resource budget breach;
16. 512-resource boundary and 513th-resource rejection;
17. duplicate identical assets resolving to one content-addressed companion resource;
18. raw HTML external resource under self-contained request;
19. derived exact-block success with HTML + resource;
20. derived failure with authored source retained;
21. stale revision, duplicate source ID, overlapping ranges, missing range and partial-block range;
22. directive syntax with `blockDirectives` on/off to document cmark parity behavior;
23. untitled dirty document with relative image;
24. dark/light bundled themes;
25. 100+ page print corpus with headings, tables, images and code crossing page boundaries;
26. cancellation during parse/resource hashing/pre-PDF load;
27. destination collision/existing companion directory and injected write failure.

Fuzz/property tests should target template escaping, URL/resource classification, path containment and cmark wrapper lifetime where practical.

## 3.16 Expected files and symbols

Exact filenames may be locally adjusted if the same ownership remains obvious. Do not create a giant `ExportService.swift`.

### MacDownKit

`MacDown2/Packages/MacDownKit/Package.swift`
- add exact `swift-cmark` declaration aligned to 0.8.0;
- add `cmark-gfm` and `cmark-gfm-extensions` products only to `ExportService`.

`Sources/ExportService/`
- `ExportService.swift` — orchestration only.
- `ExportRequest.swift` — source/request/options.
- `ExportResult.swift` — prepared document/manifest.
- `ExportDiagnostic.swift` — typed diagnostic/error codes.
- `ExportResourceBudget.swift` — central limits.
- `Metadata/ExportMetadataResolver.swift`.
- `Templates/ExportTemplate.swift`.
- `Templates/BuiltInExportTemplateCatalog.swift`.
- `HTML/CMarkHTMLBodyRenderer.swift`.
- `HTML/ExportStyleSheetBuilder.swift`.
- `HTML/HTMLDocumentComposer.swift` or template implementation.
- `HTML/HTMLEscaper.swift` — template-context escaping only; never a competing Markdown renderer.
- `Assets/ExportResource.swift`.
- `Assets/ExportResourceResolver.swift`.
- `Assets/ExportManifest.swift`.
- `Derived/DerivedExportDestination.swift`.
- `Writing/ExportArtifactWriter.swift` if the Foundation-only writer stays in package ownership.

`Tests/ExportServiceTests/`
- focused suites mirroring the components above;
- `Fixtures/` golden/adversarial corpus.

### App target

`MacDown2/MacDown2/ExportCoordinator.swift`.
`MacDown2/MacDown2/ExportPanelView.swift`.
`MacDown2/MacDown2/WebKitPDFRenderer.swift`.
`MacDown2/MacDown2/PDFPageLayout.swift` if not colocated.

Expected edits:
- `WorkspaceCommands.swift` — File → Export… command/enablement.
- `WindowCoordinator.swift` and/or `WindowController.swift` — active-window export routing and task lifetime.
- app composition root — inject `ThemeController`, export service/writer/PDF renderer.
- String Catalog / project generation inputs as required.

Do not hand-edit `.xcodeproj`; regenerate with XcodeGen.

## 3.17 Implementation slices

Each slice is a worker execution contract. Workers stop if a required dependency/behavior differs from this architecture.

### Slice 0 — dependency and contract gate

**Goal:** make the export boundary compile and prove the chosen cmark dependency shape before broad implementation.

**Dependencies:** baseline only.  
**Files:** `Package.swift`, new request/result/diagnostic/budget/derived contract files, cmark adapter smoke test.  
**Types:** `ExportSourceSnapshot`, `ExportRequest`, `HTMLExportOptions`, `ExportFormat`, `PreparedExportDocument`, `ExportResourceBudget`, derived destination values, internal `MarkdownHTMLBodyRendering`.

**Behavior:**
- exact direct `swift-cmark` 0.8.0 resolves without duplicate-version conflict with `swift-markdown`;
- ExportService imports cmark products internally only;
- smoke parse/render proves GFM cmark can render expected input and free all C-owned memory.

**Tests/evidence:** package resolves/builds; ordinary text/code escaping smoke cases; cancellation/lifetime smoke; dependency graph recorded in this document/PR evidence.

**Verification:** `cd MacDown2/Packages/MacDownKit && swift build && swift test`.

**Stop condition:** dependency resolution produces incompatible cmark versions, required GFM extension API is unavailable from Swift, or the C wrapper requires unsafe global mutable lifecycle that cannot be contained. Revise architecture rather than adding a second Markdown library.

### Slice 1 — deterministic HTML body, metadata, template and theme CSS

**Goal:** ordinary Markdown + front matter + chosen theme becomes a complete deterministic HTML document without external assets.

**Dependencies:** Slice 0.  
**Files:** cmark renderer, metadata resolver, template/catalog, stylesheet builder, HTML composer + tests/fixtures.  
**Types:** `CMarkHTMLBodyRenderer`, `ExportMetadataResolver`, `ExportTemplateContext`, `BuiltInExportTemplateCatalog`, `ExportStyleSheetBuilder`.

**Behavior:**
- fresh `ParseExecuting.parse` inside `ExportService.prepare`;
- per-option GFM mapping centralised in cmark adapter;
- front-matter title mapping;
- HTML5 document with embedded/linked stylesheet representation;
- theme colors derived from `Theme.chrome`;
- deterministic output with no random/time data;
- raw HTML policy explicitly tested.

**Tests/evidence:** golden corpus for syntax/Unicode/escaping/raw HTML/front matter/themes; byte equality across repeated runs; fake parser proves service performs fresh parse of request text.

**Verification:** package tests + lint/format check.

**Stop condition:** exported GFM materially disagrees with live Markdown semantics on ordinary supported Markdown and cannot be corrected with one documented option mapping; do not paper over drift in templates.

### Slice 2 — managed assets, manifest and atomic HTML writing

**Goal:** local images/resources work after export without network or unsafe filesystem reach.

**Dependencies:** Slice 1.  
**Files:** resource resolver/manifest/writer + tests.  
**Types:** `ExportResource`, `ExportManifest`, `ExportResourceResolver`, `ExportArtifactWriter`.

**Behavior:**
- explicit root containment after symlink resolution;
- local images copy-adjacent or self-contained;
- remote resources never fetched;
- full SHA-256 logical names; dedupe identical content;
- UTType/system MIME resolution rather than a scattered extension switch;
- file-backed resources remain streaming in copy mode;
- budget enforcement from injected `ExportResourceBudget`;
- primary + companion output staged and promoted atomically;
- raw HTML limitation handled honestly for strict self-contained mode.

**Tests/evidence:** missing/escape/symlink/Unicode/remote/size/count/dedupe/collision/fault-injection corpus; network sentinel remains untouched.

**Verification:** package tests; manual offline HTML move/open check.

**Stop condition:** implementation needs to read outside supplied root, fetch network content, or cannot guarantee atomic replacement for a multi-file export. Do not silently relax policy.

### Slice 3 — generic derived-content export destination

**Goal:** prove E12 can accept a future E14/E19/E20 contribution without adding a second export path or language knowledge.

**Dependencies:** Slices 1–2.  
**Files:** derived destination implementation/matcher + cmark adapter integration + tests only; **no production math/diagram renderer**.

**Types:** `DerivedSourceID`, `DerivedExportAnchor`, `DerivedExportContent`, `DerivedExportResolution`, `DerivedExportFailure`.

**Behavior:**
- exact block-level source-position match;
- current revision required;
- successful fake HTML/resource replacement;
- derived resources use same manifest;
- failure/stale/ambiguous/overlap preserves original Markdown rendering + diagnostic;
- no language-specific production branches.

**Tests/evidence:** deterministic fake contribution, stale/duplicate/overlap/missing/partial cases; source fallback assertions; source scan/review confirms no math/diagram language logic in ExportService.

**Verification:** package tests/lint/format.

**Stop condition:** destination contract requires importing E14 implementation types or a renderer-specific enum. E12 must remain the generic destination.

### Slice 4 — macOS PDF adapter

**Goal:** turn the exact prepared export document into readable paginated PDF locally.

**Dependencies:** Slices 1–3; Epic 11 WebKit security patterns.  
**Files:** `WebKitPDFRenderer.swift`, `PDFPageLayout.swift`, PDF integration tests/fixtures.  
**Types:** `WebKitPDFRenderer`, `PDFRenderRequest`, `PDFPageLayout`.

**Behavior:**
- `@MainActor` WebKit/AppKit adapter;
- serve only prepared HTML/manifest resources through local scheme;
- JS off, nonpersistent store, navigation/download/pop-up/network blocked;
- capture system default print geometry into a value request; tests inject fixed layout;
- use `WKWebView.printOperation(with:)` / `NSPrintOperation` save-to-temp path, not screenshot or viewport PDF capture;
- validate final PDF, then writer promotes atomically;
- print CSS keeps long code/table content readable and text selectable.

**Tests/evidence:** PDFKit page count/text extraction, 100-page corpus, code across page boundary, local image, remote network sentinel, cancellation/temp cleanup; Release timing evidence.

**Verification:** app build + targeted integration tests + manual Preview.app inspection.

**Stop condition:** chosen AppKit/WebKit print path cannot reliably create paginated/searchable PDF on macOS 26. Stop and re-architect the PDF adapter; do not fork Markdown rendering or rasterise pages as a shortcut.

### Slice 5 — Export panel and window integration

**Goal:** expose the architecture through a native, accessible File → Export… workflow.

**Dependencies:** Slices 1–4.  
**Files:** export coordinator/panel, command/window composition edits, strings/UI tests.  
**Types:** `ExportCoordinator`, `ExportPanelModel`, `ExportPanelView`.

**Behavior:**
- command enabled only for active Markdown document;
- panel lists `ThemeController.available`; no second theme registry;
- typed options for format/theme/stylesheet/resource mode;
- snapshot current text/revision/file/resource-root after choices are confirmed and before work starts;
- save destination appropriate to format;
- one task per window; cancellation/progress;
- user-visible structured warnings/errors;
- no source save/mutation.

**Tests/evidence:** command enablement across formats, dirty text immediate export, theme selection, HTML/PDF path, warnings, cancel, keyboard/VoiceOver identifiers, localisation keys.

**Verification:** XcodeGen, app Debug build, app Release build, UI tests, manual keyboard/VoiceOver pass.

**Stop condition:** integration needs global current-document state or mutable singletons, or exposes export for a format without an owned adapter. Keep window-local routing.

### Slice 6 — hardening, evidence and documentation reconciliation

**Goal:** satisfy Epic #13 acceptance and release-hardening gates rather than stopping at green unit tests.

**Dependencies:** all prior slices.  
**Files:** adversarial/golden corpus, performance evidence, PR verification notes, any documentation updates proven necessary.

**Behavior/evidence:**
- full test/evidence matrix complete;
- exact package + app test suites green;
- SwiftLint/SwiftFormat clean;
- Debug and Release app builds;
- HTML manual browser dogfood and PDF Preview.app dogfood;
- offline/no-transmit evidence;
- accessibility/localisation pass;
- performance budgets recorded on reference hardware;
- residual risks in PR are current;
- issue #13 is referenced but closed only when acceptance evidence is complete.

**Required commands from repo root:**

```bash
cd MacDown2 && xcodegen generate
cd ../MacDown2/Packages/MacDownKit && swift build && swift test
cd ../../../..
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -configuration Release build
swiftlint lint --strict MacDown2
swiftformat --lint MacDown2
```

Run any new targeted UI/integration schemes required by the implementation as well; do not replace the repository-wide gates with targeted tests.

**Stop condition:** any acceptance item remains evidenced only by code inspection or agent assertion. Record/fix the missing evidence before declaring the epic complete.

## 3.18 Definition of Done and residual risk

Epic 12 is done only when all of the following are true:

- [ ] HTML and PDF are both available from File → Export… for Markdown documents.
- [ ] Export is based on a fresh immutable current-editor snapshot and does not mutate/save source.
- [ ] HTML is a complete deterministic UTF-8 document with GFM fidelity, front-matter title, selected theme and embedded/linked CSS support.
- [ ] Local managed images work under copy-adjacent and supported self-contained modes with one resource policy/manifest.
- [ ] No first-party export path fetches or transmits document/resource content over the network.
- [ ] Path traversal/symlink escape and resource budgets are enforced.
- [ ] PDF consumes the same prepared HTML composition, is paginated/readable/searchable and uses locked-down WebKit/AppKit rendering.
- [ ] A generic fake derived contribution can replace one exact source block and contribute a resource without any renderer/language-specific export logic.
- [ ] Failed/stale/ambiguous derived contributions preserve authored source and surface diagnostics.
- [ ] Relevant legacy `MPAsset` behavior concepts are represented by typed asset/template/manifest tests without recreating obsolete class architecture.
- [ ] All automated test/evidence matrix items and adversarial fixtures pass.
- [ ] `swift build`, `swift test`, SwiftLint and SwiftFormat pass.
- [ ] Xcode project regenerates and Debug + Release app builds pass.
- [ ] Release performance evidence is within the stated budgets or an explicit architecture update records an accepted change.
- [ ] Manual HTML/PDF dogfood, offline behavior, accessibility and localisation checks are recorded in the PR.
- [ ] PR description remains owner-readable: what changed, why, how, what to test, risks/limits and verification.

### Residual risks to carry explicitly

1. **cmark dialect parity:** `MarkdownEngine` and direct cmark export are intentionally separate adapters. Per-feature settings and future Markdown parser upgrades can drift. The option-mapping/parity corpus is a permanent regression gate; any dependency upgrade must run it.
2. **block directives:** cmark-gfm does not provide the same semantic block-directive model as `swift-markdown`. E12 preserves authored directive text rather than inventing export semantics. A future feature that owns directives must add an explicit adapter contract.
3. **raw HTML:** fidelity and active-content safety have different concerns. Exported user-owned HTML may preserve authored active markup; in-app PDF rendering remains locked down. Do not conflate the two policies.
4. **raw HTML assets:** E12 can guarantee closure only for resources it can identify/manage. Strict self-contained claims must remain conservative around arbitrary raw HTML.
5. **legacy `MPAsset` source availability:** the concrete legacy symbol was not discoverable at architecture baseline. If restored/found and it contains a required behavior not represented here, stop and reconcile before claiming acceptance.
6. **issue #35:** non-Markdown documents still enter Markdown parsing elsewhere. E12 mitigates by gating export to Markdown; it does not fix the upstream issue.
7. **system print stack:** PDF pagination depends on macOS 26 WebKit/AppKit behavior. The adapter is isolated specifically so a platform correction does not force a second Markdown/export architecture.

### Worker stop rule

A worker may make ordinary local implementation choices inside a slice. Stop and escalate/revise this architecture if any discovery requires:

- a new third-party package beyond the exact cmark dependency already selected by the migration plan;
- a new SwiftPM target or reversed module dependency;
- network/hosted rendering;
- language-specific derived-content logic in E12;
- source mutation during export;
- filesystem reads outside explicit resource scope;
- weakened tests or a different user-visible failure policy;
- a second Markdown/PDF composition path;
- edits outside the authorised slice that materially change another epic's ownership.
