# Epic 12 Implementation Architecture — HTML/PDF Export

Status: **binding architecture for `epic/12-export`**  
Epic: **#13 — Export: HTML + PDF, templates, themes and derived-content contract**  
Baseline: **`master` @ `8d22f0e740a31b1d0afb64c5b781f7e983df50a1`**  
Architecture date: **2026-08-17**  
Review status: **orthogonal architecture review incorporated before implementation**

This document follows `planning/EPIC_STANDARD.md` and reconciles the live repository with `planning/RELEASE_HARDENING.md`. It is the engineering contract for Epic 12. Broad implementation must not begin by inventing behavior outside these boundaries.

## 3.1 Owner summary

Epic 12 gives MacDown 2 one dependable export pipeline for ordinary Markdown now and for equations/diagrams later. A user can export the text currently visible in the editor to complete HTML or a paginated, searchable PDF; select an existing MacDown theme; and choose either a normal companion-file HTML package or a genuinely self-contained HTML file. Export remains local/offline.

The core decision is **one composition pipeline**. MacDown snapshots the current editor text, freshly parses that immutable snapshot, renders a GFM-faithful HTML body through a narrowly wrapped `swift-cmark` adapter, combines front-matter metadata, theme-derived CSS, managed resources and optional renderer-neutral derived blocks into one `PreparedExportDocument`, then sends that prepared document to an HTML writer or the macOS PDF adapter. PDF is never a second Markdown renderer.

The architecture deliberately minimises hard-coding and future branching:

- destination/options are typed values that make invalid combinations unrepresentable;
- cmark extension names/options live in one adapter rather than being repeated across the app;
- the default HTML template is behind a typed template catalog, not an untyped dictionary/template engine;
- export styling derives from the existing `Theme` value instead of maintaining another color catalog;
- companion resource names are content-addressed by SHA-256 rather than counters, random IDs or caller-supplied paths;
- resource limits live in one injected `ExportResourceBudget`;
- output layout is computed from the selected destination by one layout value;
- the future derived-content seam is generic and knows nothing about math, Mermaid, Graphviz or any other renderer language;
- AppKit/WebKit stay at the app edge and never leak into `ExportService`.

The highest risks are WebKit/AppKit PDF pagination, local-resource containment, direct cmark export dialect parity with `MarkdownEngine`, and raw-HTML fidelity versus self-contained guarantees. Each has an explicit product decision, integration test and worker stop condition below.

Non-goals: production math/diagram rendering, user-authored template UI, ePub/DOCX, hosted rendering, fixing unrelated multi-format parsing issue #35, arbitrary raw-HTML resource crawling/sanitising, or building an extension registry (Epic 14 owns contribution lifecycle/registry/isolation).

## 3.2 Baseline / repository reconciliation

### Live baseline

- `master` baseline is `8d22f0e740a31b1d0afb64c5b781f7e983df50a1`.
- Epic 11 is merged; HTML source/rendered preview and the format registry are real upstream capabilities.
- `ExportService` is only a scaffold at `MacDown2/Packages/MacDownKit/Sources/ExportService/ExportService.swift`.
- `ExportService` already depends on `MarkdownEngine` and `Themes`.
- `MarkdownEngine` exposes renderer-neutral `MarkdownDocument`, `MarkdownBlock`, `FrontMatter`, `SourceMap`, `MarkdownParseOptions` and injectable `ParseExecuting`.
- `ParseEngine` is an actor and the production `ParseExecuting`. Export must request a **fresh parse of the current export snapshot** rather than reuse the debounced preview parse.
- `ThemeController` is the app-wide source of available/current `Theme` values. Export consumes a copied `Theme`; it does not duplicate theme-selection state.
- Epic 11 already contains a locked-down `WKWebView` policy for HTML preview: JavaScript disabled, nonpersistent data store, local custom scheme/CSP and navigation restrictions. PDF rendering reuses the policy concepts rather than inventing a second trust model.
- `FileDocument` exposes current text/file URL/format/mutation generation. `WindowCoordinator`/`WindowController` are the app orchestration boundary.

### Stale or changed assumptions reconciled

1. `planning/MIGRATION_PLAN.md` selects `swiftlang/swift-cmark` 0.8.x for export. The live package declares exact `swift-markdown` 0.8.0, whose package already depends on `swift-cmark`. E12 will add an **explicit exact 0.8.0 `swift-cmark` dependency** to MacDownKit and only the `cmark-gfm` and `cmark-gfm-extensions` products to `ExportService`. This avoids relying on undeclared transitive imports and should resolve to one package version.
2. `swift-markdown` 0.8.0 has an `HTMLFormatter`, but it is not the export contract. E12 uses cmark-gfm's renderer so Markdown escaping, links/code and GFM HTML behavior are not reimplemented in MacDown.
3. `MarkdownParseOptions` intentionally records feature intent for E12/E13 even where `swift-markdown` currently enables GFM features as a group. E12 maps those flags centrally to cmark extensions/options and has a parity corpus for the differences.
4. cmark-gfm's built-in core-extension registration is process-global and internally guarded by a thread-safe once primitive. This dependency-internal registration is the only global registration allowed here. MacDown does not own a mutable global export registry and E12 never loads custom/dynamic cmark plugins.
5. `AGENTS.md` and Epic 12 reference legacy `MPAsset` concepts, but no concrete `MPAsset` symbol was discoverable during baseline inspection. E12 ports the documented behavior concepts—logical identity, content source, deterministic lookup, template context and default/fallback—rather than inventing obsolete class compatibility. Discovery of a materially different legacy contract is a stop condition.
6. Open issue #35 still allows non-Markdown formats into the Markdown parse path. E12 does not expand that scope. `Export…` is enabled only for Markdown documents until another format explicitly owns an export adapter.

### Production versus scaffold

Production upstream: file/document model, Markdown parse/front matter/source mapping, themes, window coordination, format registry, HTML preview security policy.  
Scaffold only: `ExportService`.  
New in E12: export contracts, cmark adapter, HTML composition/template/style/assets, destination layout/writer, generic derived export destination, PDF adapter, export UI, fidelity/adversarial evidence corpus.

## 3.3 User journeys

### J1 — normal HTML export

1. User invokes **File → Export…** on a Markdown document.
2. The export panel defaults to HTML, the current theme and `HTMLExportOptions.standard`.
3. User chooses normal companion-file packaging or self-contained packaging, then a destination URL.
4. The app snapshots current text, file URL, explicit resource root, parse options, revision, chosen theme and the destination-derived `ExportOutputLayout` into immutable request values.
5. `ExportService` freshly parses that exact text, renders one HTML body, resolves managed resources, applies metadata/theme/template and returns `PreparedExportDocument`.
6. The writer materialises all content-addressed companion resources first, then atomically replaces the primary HTML file last.
7. Success/warnings are shown. Nothing is silently omitted.

### J2 — self-contained HTML

Self-contained mode forces CSS and all E12-managed local resources into the HTML. It has no independent “linked CSS” option. MacDown does not fetch remote resources. If full closure cannot be guaranteed—for example a remote managed image, missing local managed resource, or raw authored HTML—export fails with a typed reason rather than producing a falsely labelled self-contained file.

### J3 — PDF export

1. User chooses PDF and a theme.
2. E12 uses the same fresh snapshot → parse → cmark body → metadata/theme/resources → `PreparedExportDocument` pipeline, with a PDF-local resource-reference strategy.
3. `WebKitPDFRenderer` loads the prepared document through a locked-down local scheme, waits for load completion, creates `WKWebView.printOperation(with:)`, applies a captured `PDFPageLayout`, saves to a temporary PDF and validates it.
4. The single PDF file is atomically promoted to the selected URL.
5. Remote loading and script execution remain disabled.

### J4 — front-matter title

A non-empty scalar `title` in valid front matter becomes the HTML `<title>` and, under `ExportMetadataPolicy.standard`, a visible semantic document title. Unknown front-matter keys are not guessed into arbitrary `<meta>` tags.

### J5 — missing or escaped local asset

A managed resource is resolved relative to the explicit `resourceRootURL` and current document context. Missing/out-of-root/symlink-escaped resources are never silently read from elsewhere. Companion HTML may complete with a visible warning and original authored reference; self-contained export fails because it cannot satisfy its guarantee.

### J6 — future derived block succeeds

A caller supplies a generic `DerivedExportResolution.rendered` for an opaque source identity, exact original block line range and the current source revision. E12 replaces exactly that block's cmark node with renderer-provided body HTML and routes any renderer-provided bytes through the same resource manifest. E12 contains no renderer-language switch.

### J7 — future derived block fails

A failed, stale, duplicate, overlapping, missing or partial-block derived resolution never deletes the authored source. Normal Markdown rendering remains and an `ExportDiagnostic` explains the failure.

### J8 — dirty/untitled document

Export uses the editor text at invocation time and never saves or normalises source. An untitled document has no invented filesystem root; unresolved relative resources produce deterministic diagnostics/failure by packaging mode.

## 3.4 Non-negotiable invariants

1. **One composition pipeline.** PDF consumes the same prepared HTML/CSS/resource model as HTML; no second Markdown renderer.
2. **Current text wins.** Export freshly parses the immutable request snapshot; debounced preview state is never authoritative.
3. **Source is immutable.** Export never changes source text, encoding, line endings, dirty state or file contents.
4. **Offline/local first-party behavior.** E12 performs no upload, hosted render or remote resource fetch.
5. **Invalid option states are unrepresentable.** PDF cannot carry irrelevant HTML packaging options; self-contained HTML cannot request linked CSS.
6. **Renderer-neutral upstream boundary.** `MarkdownDocument` and E14's future core result never acquire SwiftUI/WebKit types.
7. **No language-specific derived logic.** `ExportService` contains no math/Mermaid/Graphviz/etc. branch or enum.
8. **Derived failure preserves authored source.** No failure can silently erase source.
9. **One resource pipeline.** Markdown assets, linked CSS and future derived resources enter the same manifest/policy.
10. **Deterministic composition.** Same source/options/theme/derived inputs produce byte-stable prepared HTML and logical resource names. No timestamps/random IDs/process values enter generated content.
11. **No MacDown-owned mutable global export registry/state.** Catalogs/policies are immutable/injected. cmark's built-in thread-safe one-time core-extension registration is the explicit dependency-internal exception; no custom/dynamic cmark plugin loading.
12. **Platform APIs stay at the edge.** `ExportService` does not import SwiftUI, WebKit or AppKit.
13. **Explicit local scope.** Resource resolution never reads outside canonical `resourceRootURL` after standardisation and symlink resolution.
14. **No false self-contained claim.** Self-contained HTML either proves closure over all E12-managed content and has no raw authored HTML, or fails explicitly.
15. **C ownership is explicit.** Every cmark parser/tree/list/buffer allocation is freed on success, failure and cancellation paths by one adapter.
16. **Primary-file-last commit.** Multi-file HTML cannot be one filesystem transaction; companion resources are made safe first and the primary HTML is the only atomic commit point.

## 3.5 Ownership and dependency boundaries

### `MarkdownEngine` — source interpretation

Owns current Markdown/front-matter parse semantics, source mapping and `ParseExecuting`. E12 uses it for the fresh authoritative snapshot parse. No cmark/WebKit export type is added to `MarkdownEngine`.

### `Themes` — canonical visual tokens

Owns `Theme`/`ThemeController`. E12 consumes a `Theme` value. Export CSS/layout semantics stay in `ExportService`; do not add CSS strings/PDF rules to `Theme`.

### `ExportService` — deterministic composition and Foundation-only output model

Owns:

- request/result/diagnostic/policy contracts;
- cmark-gfm HTML-body adapter;
- typed template catalog/context;
- metadata resolution;
- theme → CSS conversion;
- managed-resource resolution/rewriting/manifest;
- output-layout value and content-addressed logical names;
- generic derived export destination contract;
- prepared complete HTML used by both destinations;
- Foundation-only HTML/PDF artifact writing where no AppKit/WebKit is required.

May depend on `MarkdownEngine`, `Themes`, Foundation, CryptoKit/UniformTypeIdentifiers where required, and exact `swift-cmark` products. It must not depend on AppKit/WebKit/SwiftUI.

### App target — user interaction and macOS PDF rendering

Owns:

- `ExportCoordinator` (`@MainActor`);
- File menu command enablement;
- `ExportPanelView`/model;
- snapshotting `FileDocument` and workspace/document resource root;
- save-panel interaction and destination selection;
- `WebKitPDFRenderer` and `PDFPageLayout.systemDefaultSnapshot()`;
- user-facing localised diagnostic presentation.

### Epic 14 and later renderers

E14 owns contribution registration/lifecycle/isolation and the renderer-neutral core result. E19/E20/E21 own concrete renderers. Those epics adapt a successful renderer-neutral result to E12's generic destination value. E12 never imports their implementation types or reaches into their registries.

### Dependency rule

Do not create a new SwiftPM target merely to hide cmark. Existing `ExportService` has the correct roadmap ownership; its cmark C API is hidden behind internal protocols. A new target/reversed module dependency requires architecture revision.

## 3.6 Types and interfaces

Names may move locally for Swift clarity, but responsibilities and dependency directions are binding.

### Request types: make invalid states impossible

```swift
public struct ExportSourceSnapshot: Sendable {
    public let text: String
    public let fileURL: URL?
    public let resourceRootURL: URL?
    public let suggestedTitle: String?
    public let parseOptions: MarkdownParseOptions
    public let revision: Int
}

public enum ExportDestination: Sendable, Equatable {
    case html(HTMLExportOptions)
    case pdf
}

public struct ExportRequest: Sendable {
    public let source: ExportSourceSnapshot
    public let destination: ExportDestination
    public let theme: Theme
    public let metadata: ExportMetadataPolicy
    public let derived: [DerivedExportResolution]
    public let budget: ExportResourceBudget
    public let outputLayout: ExportOutputLayout
}

public struct HTMLExportOptions: Sendable, Equatable {
    public let templateID: ExportTemplateID
    public let packaging: HTMLPackagingMode

    public static let standard = HTMLExportOptions(
        templateID: BuiltInExportTemplateCatalog.defaultID,
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

public struct ExportMetadataPolicy: Sendable, Equatable {
    public let includeVisibleTitle: Bool
    public static let standard = ExportMetadataPolicy(includeVisibleTitle: true)
}
```

Do not add generic `[String: Any]`/`[String: String]` option bags.

`outputLayout` is derived from the destination selected by the user, not invented inside the renderer. For PDF it identifies the single primary file. For companion HTML it also defines the owned companion directory and relative public prefix. Self-contained HTML has no companion directory.

### Internal resource-reference strategy

One internal enum controls how cmark/resource rewriting represents resources for a destination:

```swift
enum ExportResourceReferenceMode: Sendable {
    case embeddedData
    case relativeCompanion
    case localScheme
}
```

Mapping is central:

- HTML `.selfContained` → `.embeddedData`;
- HTML `.companionFiles` → `.relativeCompanion`;
- PDF → `.localScheme`.

No caller/worker may add destination-specific resource rewriting elsewhere.

### Prepared document

```swift
public struct PreparedExportDocument: Sendable {
    public let html: String
    public let resources: [ExportResource]
    public let manifest: ExportManifest
    public let diagnostics: [ExportDiagnostic]
}
```

`html` is complete UTF-8 HTML5. `resources` are logical file/data-backed resources governed by the manifest; they are not arbitrary destination paths.

### Service injection

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

Production composition injects `ParseEngine()` and production adapters. Tests inject fakes. If concrete ownership needs an actor, use one; do not add `@unchecked Sendable` merely to silence concurrency errors.

### cmark adapter

```swift
protocol MarkdownHTMLBodyRendering: Sendable {
    func render(
        document: MarkdownDocument,
        derived: [DerivedExportResolution],
        resourceRewriter: any ExportResourceRewriting
    ) throws -> MarkdownHTMLBody
}
```

`CMarkHTMLBodyRenderer` is internal. It:

1. calls `cmark_gfm_core_extensions_ensure_registered()`;
2. parses `MarkdownDocument.body` with cmark-gfm;
3. attaches only the supported built-in extensions selected by one central mapping:
   - `table` iff `options.tables`;
   - `tasklist` iff `options.taskLists`;
   - `strikethrough` iff `options.strikethrough`;
   - `autolink` iff `options.autolinks`;
   - `tagfilter` **always** when rendering authored raw HTML;
   - footnotes via `CMARK_OPT_FOOTNOTES` iff `options.footnotes`;
4. treats `blockDirectives` as a documented parity limitation: cmark has no equivalent semantic block-directive renderer, so directive source remains ordinary Markdown text rather than being silently dropped;
5. uses cmark source positions plus `bodyLineOffset` to match derived anchors;
6. rewrites managed image/resource nodes before rendering;
7. renders through `cmark_render_html`;
8. owns all C pointer/list/buffer cleanup;
9. never leaks cmark types/names outside this adapter.

The literal cmark extension names and option-bit mapping appear in this adapter only.

### Raw authored HTML policy: exact decision

Normal companion HTML and PDF composition render with cmark `CMARK_OPT_UNSAFE` **plus the GFM `tagfilter` extension** so regular user-authored raw HTML is preserved while GFM-tagfilter behavior remains active. This option is an authored-output fidelity decision; it is not permission to concatenate generated unescaped strings.

Consequences are explicit and tested:

- ordinary Markdown text/code/link attributes still use cmark escaping;
- generated title/template attributes use E12's context-specific HTML escaper;
- user-authored raw HTML is preserved subject to GFM tagfilter;
- dangerous user-authored link schemes follow cmark's `UNSAFE` fidelity behavior in the exported user-owned HTML artifact;
- the transient in-app PDF WebKit never gains network/script privilege from this: JavaScript and remote loads remain blocked;
- **self-contained HTML rejects any raw HTML block/inline node** with `unmanagedRawHTMLInSelfContainedExport`, because E12 deliberately does not add an HTML parser/crawler that could prove closure over arbitrary authored resource attributes.

Do not replace this with regex-based raw-HTML resource discovery or a broad sanitizer in E12.

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
    var descriptors: [ExportTemplateDescriptor] { get }
    func template(id: ExportTemplateID) throws -> any ExportTemplate
}
```

E12 ships one built-in default template and `BuiltInExportTemplateCatalog.defaultID`. The catalog exists so additional first-party templates do not require a central switch. It is **not** a user-template execution API. Template values are typed; do not introduce a Handlebars-style dictionary or executable template script.

### Theme/CSS

`ExportStyleSheetBuilder` is a pure transformation from `Theme` + one centrally owned `ExportLayoutProfile` to CSS. Colors derive from `Theme.chrome`; no second palette exists. Structural typography, spacing, code, table and print rules live in the builder/default template, not in UI/service call sites.

If mappings from editor chrome to document semantics are required, keep them in one builder (for example foreground/background/accent/surface), not as repeated capture-name/color literals. Do not add export-only CSS fields to `Theme`; a future export-theme model must be an explicit separate architecture decision.

### Metadata

`ExportMetadataResolver` is the only E12 component interpreting front matter. Title resolution:

1. valid non-empty scalar front-matter `title`;
2. `ExportSourceSnapshot.suggestedTitle`;
3. no title.

When present, title is escaped by the template and appears in `<title>`. `ExportMetadataPolicy.standard.includeVisibleTitle == true` also emits it as a semantic visible heading. Unknown front-matter keys are not emitted as arbitrary HTML metadata.

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

public struct DerivedExportResource: Sendable {
    public let mediaType: String
    public let data: Data
}

public struct DerivedExportFailure: Sendable {
    public let anchor: DerivedExportAnchor
    public let diagnostic: ExportDiagnostic
}
```

No derived resource can choose its final filesystem path. E12 hashes bytes and assigns the manifest logical path.

Rules:

- `sourceID` is opaque; E12 never parses it as a language/type;
- `sourceRevision` must equal export snapshot revision;
- `originalLineRange` must match exactly one complete cmark block after `bodyLineOffset` conversion;
- duplicate source IDs/anchors, overlaps, revision mismatch, absent block or partial-block matches are deterministic failure cases; no arbitrary winner;
- rendered fragments enter only at matched body position, never `<head>` or template metadata;
- derived resources use the same budget/manifest/reference policy as Markdown resources;
- this is the E12 destination representation, **not** E14's core renderer result. E14 later adapts its renderer-neutral result into this type.

### Structured diagnostics

```swift
public enum ExportDiagnosticSeverity: Sendable {
    case warning
    case error
}

public enum ExportDiagnosticCode: String, Sendable {
    case missingLocalResource
    case resourceOutsideAllowedRoot
    case remoteResourceNotEmbedded
    case remoteResourceBlockedForPDF
    case unresolvedUntitledResource
    case unsupportedResourceMediaType
    case unmanagedRawHTMLInSelfContainedExport
    case derivedStale
    case derivedConflict
    case derivedFailed
}

public struct ExportDiagnostic: Sendable {
    public let code: ExportDiagnosticCode
    public let severity: ExportDiagnosticSeverity
    public let sourceRange: ClosedRange<Int>?
    public let resourceReference: String?
    public let derivedSourceID: DerivedSourceID?
}
```

The exact field set may be narrowed/expanded with typed optional context, but do not add a free-form argument dictionary. User-facing/localised sentences are built at the app edge from code + typed context.

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

Local files remain file-backed until bytes are required. Do not eagerly read every file into memory.

Logical companion names use the **full SHA-256 digest** plus a MIME/UTType-derived extension under one MacDown-owned companion directory. Linked CSS is also a content-addressed manifest resource. No random UUID, counter or original arbitrary path provides collision control.

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

These are policy values, not magic numbers: they occur only here, are injected in tests, and UI error text derives from the actual budget value rather than repeating literals. Changing production limits later is one local policy edit plus evidence, not a codebase search.

## 3.7 State and data flow

```text
active FileDocument / workspace / ThemeController / user destination
                 |
                 | @MainActor immutable capture
                 v
 ExportSourceSnapshot + ExportDestination + ExportOutputLayout
                 |
                 v
          ExportService.prepare
                 |
         ParseExecuting.parse           <- fresh authoritative parse
                 |
          MarkdownDocument
            /       |        \
           /        |         \
 metadata      cmark body      theme -> CSS
 resolver       renderer
                 |
          resource resolver
          + derived adapter
                 |
            template render
                 v
       PreparedExportDocument
          /                 \
         /                   \
 HTML artifact writer      WebKitPDFRenderer
 resources first           locked local scheme
 primary HTML last         -> NSPrintOperation
                            -> temporary PDF
                            -> atomic file replace
```

The app never hands live mutable `FileDocument`, `ThemeController`, `WorkspaceModel` or view state to `ExportService`. The request is a value snapshot so a mid-export edit/theme change cannot create a mixed artifact.

`ExportOutputLayout` is computed only after the user has chosen the final URL. For companion HTML it owns a deterministic sibling directory name derived from the primary filename (for example by one central layout formatter); no other component constructs companion paths.

The manifest is the sole list of managed resources. HTML writer and PDF scheme handler consume it rather than rescanning the filesystem independently.

## 3.8 Concurrency and cancellation

- `@MainActor ExportCoordinator` performs only UI/state snapshotting, panels and WebKit/AppKit work.
- `ExportService.prepare` must keep parse/cmark/hashing/resource work off the main actor. Existing `ParseEngine` already does so.
- Do not use `Task.detached` merely to silence isolation. Use structured tasks/actors and inherit cancellation.
- One active export task per window. A new export request cancels an existing cancellable export for that window only; unrelated windows are not serialised behind a process-wide export actor.
- `Task.checkCancellation()` is required before parse, after parse, before/after cmark work, between resource resolutions/hashes, before template composition and before write/render handoff.
- File hashing/copying is chunked/streamed where practical and checks cancellation between chunks/resources.
- `WebKitPDFRenderer` is `@MainActor`. Cancellation before print starts aborts loading and cleans temporary resources. Once AppKit enters a non-cancellable print phase, cancellation is best-effort: suppress promotion/result, then clean the temporary PDF afterward.
- No `@unchecked Sendable` for WebKit/C wrappers unless a separately documented proof justifies it; prefer actor/main-actor isolation.

## 3.9 Failure model

Use typed `ExportError` for aborting failures and `ExportDiagnostic` for non-fatal fidelity issues.

Representative `ExportError` cases:

- `unsupportedDocumentFormat`
- `parseFailed`
- `templateUnavailable`
- `invalidTemplateOutput`
- `selfContainedResourceUnavailable`
- `unmanagedRawHTMLInSelfContainedExport`
- `resourceOutsideAllowedRoot`
- `resourceBudgetExceeded`
- `derivedConflict`
- `companionDirectoryNotOwned`
- `pdfRenderingFailed`
- `artifactWriteFailed`
- `cancelled`

Rules:

1. Diagnostic codes/typed context are stable; localised text is UI-owned.
2. Self-contained HTML fails if any managed resource cannot be embedded, any remote managed resource exists, or any raw authored HTML is present. No downgrade.
3. Companion HTML may complete with a missing authored image only with a visible warning; the original source remains represented.
4. PDF may complete when a remote authored image is blocked if the document remains readable; it returns a warning. PDF generation never turns network access on.
5. Failed derived output normally becomes source fallback + warning. Structural ambiguity never picks a winner.
6. The writer never overwrites an unrecognised pre-existing companion directory. MacDown ownership/manifest must be proven before reuse/cleanup.
7. A failed export never replaces the primary target with incomplete content.

## 3.10 Security and trust model

### Local/offline

- E12 adds no HTTP client, hosted renderer or telemetry path for document/resource content.
- Remote URLs may remain authored links in normal exported HTML; MacDown never fetches them.
- PDF WebKit blocks remote subresources/navigation and disables JavaScript.

### Local file scope

`ExportSourceSnapshot.resourceRootURL` is explicit:

- document inside an open workspace → workspace root;
- otherwise saved document → parent directory;
- untitled document → `nil` unless an existing explicit user file-selection flow supplies a root.

For each local managed resource, standardise and resolve symlinks before containment checks. Anything escaping canonical root is not read/copied/embedded. Current unsandboxed app status does not weaken this rule.

### HTML trust

- cmark owns escaping for ordinary Markdown text/code/link attributes.
- generated title/template attributes are context-escaped by `HTMLEscaper`.
- raw authored HTML uses the exact `CMARK_OPT_UNSAFE + tagfilter` policy from §3.6.
- self-contained export rejects raw authored HTML rather than attempting regex/resource crawling.
- derived HTML is renderer output inserted only into body position; it is not granted app privileges.

### PDF WebKit sandbox

Reuse Epic 11 concepts:

- nonpersistent `WKWebsiteDataStore`;
- JavaScript disabled;
- local custom scheme/resource handler rather than broad `file://` access;
- navigation/download/new-window denial;
- no remote subresource load;
- CSP appropriate to the transient PDF-render document;
- scheme handler serves only resources present in the manifest.

The exported HTML file is user-owned and may preserve user-authored HTML. The in-app PDF renderer does not execute it as privileged content.

### Dependency surface

`swift-cmark` is exact-pinned and wrapped internally. Only built-in GFM extensions are attached. Dynamic cmark plugin discovery/loading is never invoked.

## 3.11 Resource, output and performance budgets

### Multi-file HTML commit protocol

A primary HTML file plus companion directory cannot be made one atomic filesystem transaction. The production writer therefore uses **content-addressed additive resources + primary-file-last commit**:

1. Compute `ExportOutputLayout` once from the selected primary URL.
2. If companion directory exists, require MacDown ownership/manifest evidence. Do not adopt arbitrary user directories.
3. Stage/hash each required companion resource and atomically materialise its full-digest filename. Existing identical digest resources are reusable.
4. Do not delete resources referenced by the currently installed primary HTML before primary replacement.
5. Write the new primary HTML to a sibling temporary file.
6. Atomically replace/move the primary HTML **last**. Until this point the old primary remains valid and references old content-addressed resources.
7. After successful primary replacement, optional cleanup may delete only orphaned files proven MacDown-owned by old/new manifests. Cleanup failure is non-fatal and never deletes unknown files.

This is the durability contract; do not claim multi-entry atomicity.

Single-file self-contained HTML/PDF uses temporary sibling + atomic replace/move.

### Memory/resource bounds

- `ExportResourceBudget.standard` is the sole production source of managed-resource limits.
- Companion mode keeps local assets file-backed and streams copies/hashes; no `[Data]` mirror of the whole set.
- Self-contained mode processes assets one at a time and enforces aggregate budget before final composition; account for base64 expansion in evidence.
- cmark tree/buffers are freed immediately after body HTML materialisation.
- `PreparedExportDocument` must not retain redundant equivalent full-document strings or an AST after composition.

### Performance evidence gates

Record hardware, macOS and Release build configuration.

1. **1 MiB Markdown, no assets:** HTML preparation median of 5 warm Release runs ≤ 1.0 s; no main-thread stall attributable to parse/cmark/resource work > 16 ms.
2. **25 MiB aggregate local images, companion mode:** no eager 25 MiB in-memory mirror; peak RSS delta attributable to export ≤ 128 MiB.
3. **25 MiB aggregate local images, self-contained:** peak RSS delta ≤ final HTML byte size + 128 MiB; no unbounded temporary duplication.
4. **100-page PDF fixture:** median of 3 Release runs ≤ 10 s on recorded reference Mac and no page truncation. If macOS print behavior cannot meet this reliably, record evidence and revise budget/adapter explicitly.
5. Cancellation before the non-cancellable print phase becomes observable within 250 ms at cancellable phase boundaries.

Do not trade correctness/security for a benchmark without architecture revision.

## 3.12 Accessibility and localisation

### Export panel

- All controls keyboard reachable in logical order.
- Format/theme/packaging/stylesheet controls have VoiceOver labels/values; no icon-only meaning.
- When self-contained packaging is selected, the linked/embedded stylesheet control is not presented because that state cannot exist.
- Conditional controls must not strand keyboard/VoiceOver focus when format/packaging changes.
- Progress/cancellation/error/warning states are announced accessibly.
- Use standard macOS controls/hit areas rather than custom tiny controls.

### Localisation

- User-facing export strings enter the app String Catalog when introduced.
- Enum raw values and diagnostic codes are never displayed directly.
- Template-generated document content contains user/source content, not incidental localised MacDown UI phrases.
- Do not infer document language from Mac UI locale; E12 does not hard-code `lang="en"`.

### Generated document accessibility

- Default template uses semantic `<main>`/`<article>`; cmark retains heading/list/table/code semantics and authored image alt text.
- Visible resolved title is a semantic heading.
- CSS maintains readable foreground/background use across bundled themes; automated contrast/fidelity checks cover theme exports where practical.
- PDF text remains selectable/searchable; whole-page rasterisation is forbidden.

## 3.13 Export and interoperability contract

### HTML

- Complete UTF-8 HTML5 document, never a fragment.
- `<meta charset="utf-8">` and viewport metadata.
- Resolved title in `<title>` and visible heading when policy enables it.
- Body from cmark-gfm with the single option mapping in §3.6.
- Default template/style rules are screen + print aware; long code/table content remains readable rather than clipping off page.
- No timestamps/random values in generated output.

### Packaging

`HTMLPackagingMode.selfContained`:

- CSS embedded;
- all E12-managed local resources embedded;
- no raw authored HTML;
- no remote managed resources;
- `manifest.isSelfContained == true` only after those conditions are proven.

`HTMLPackagingMode.companionFiles(stylesheet:)`:

- local managed resources use content-addressed relative companion references;
- stylesheet `.embedded` stays in HTML;
- stylesheet `.linked` becomes a content-addressed manifest resource;
- writer follows resource-first/primary-last protocol.

### GFM mapping

One internal cmark configuration table owns all extension names/options. No other module duplicates them. `blockDirectives` has no cmark semantic equivalent in this pinned library and is preserved as literal Markdown behavior with a regression fixture rather than silently invented semantics.

### Raw HTML

Normal companion HTML/PDF body composition uses `CMARK_OPT_UNSAFE + tagfilter` exactly as defined in §3.6. Self-contained HTML rejects raw authored HTML. Adversarial tests cover script/style/event-handler input, dangerous schemes, ordinary text escaping and generated metadata escaping.

### Managed assets

Markdown image/resource references:

- relative/local + canonical inside root → copy or embed/local-scheme by destination;
- local outside root → never read, typed diagnostic/failure by destination;
- missing → warning for companion HTML/PDF if readable, failure for self-contained;
- remote → never fetched; retained as authored URL in normal HTML, blocked with warning in PDF, failure for self-contained.

No arbitrary raw HTML resource crawling in E12.

### PDF

- `WebKitPDFRenderer` consumes only `PreparedExportDocument` + value `PDFPageLayout`.
- Capture system-default paper size/imageable bounds/margins once into `PDFPageLayout`; do not hard-code A4/Letter by geography.
- Tests inject fixed page layouts.
- Use `WKWebView.printOperation(with:)` / `NSPrintOperation`, not viewport screenshot/canvas capture.
- Hide print/progress panels for export; save to temporary URL, validate with PDFKit, atomically promote.
- PDFKit integration tests verify page count/text extraction.

### Legacy asset concepts

Port behavior rather than classes:

- typed logical asset identity;
- file/data-backed source;
- deterministic catalog/manifest lookup;
- duplicate logical-path rejection;
- explicit default template behavior;
- no implicit mutable global asset registry.

Name tests so acceptance mapping remains visible to reviewers.

## 3.14 Test and evidence matrix

| Requirement | Automated evidence | Manual/dogfood evidence |
|---|---|---|
| ordinary Markdown → HTML | golden corpus + structural assertions | export representative README and open in Safari |
| GFM tables/tasks/strike/autolinks/footnotes | per-option cmark adapter tests | representative visual corpus |
| front-matter title | metadata/template tests | browser tab + visible heading |
| dirty current text | coordinator test with deliberately stale preview parse | type then immediately export without saving |
| theme reuse | CSS tests across bundled themes | light/dark readability |
| companion embedded CSS | structural test | move package and reopen |
| companion linked CSS | manifest/hash/path test | move package and reopen |
| self-contained closure | embedded content + manifest assertion | move HTML alone; offline open |
| raw HTML self-contained rejection | cmark/raw-node fixture | explicit UI reason |
| no network fetch | network sentinel | export offline |
| path traversal/symlink block | resolver adversarial tests | — |
| deterministic output/names | repeated byte equality | — |
| resource-first/primary-last durability | fault-injected writer tests | replace existing export |
| derived success | generic fake contribution | inspect exact source replacement |
| derived failure fallback | stale/conflict/failure tests | — |
| no language-specific export logic | review/source assertion | — |
| paginated PDF | PDFKit integration tests fixed layout | inspect 100-page fixture |
| PDF no JS/network | WebKit resource/navigation sentinel | offline export |
| PDF searchable/selectable | PDFKit text extraction | Preview.app selection/search |
| cancellation | phase-controlled fake tests | cancel large export |
| localisation/a11y | String Catalog + UI/accessibility tests | keyboard/VoiceOver pass |
| performance | Release benchmark evidence | reference-Mac run |

Golden tests compare stable semantic output. Do not normalise away meaningful escaping/resource/pagination differences merely to make snapshots pass.

## 3.15 Adversarial corpus

Fixtures must include at least:

1. plain ASCII Markdown;
2. emoji, CJK, combining marks and non-BMP Unicode;
3. `<`, `>`, `&`, quotes in text/code/title/link labels/URLs;
4. fenced/indented code with very long lines and HTML-looking content;
5. nested lists/quotes;
6. tables, task lists, strikethrough, autolinks and footnotes;
7. duplicate/reference links and complex URLs;
8. raw HTML blocks/inlines including script/style/event-handler examples;
9. dangerous authored schemes (`javascript:`, `data:`, `file:`) locking raw-HTML/link fidelity policy;
10. valid/invalid/empty/non-string front-matter title;
11. local image in root, nested path, Unicode filename, missing file;
12. `..` escape and symlink escape;
13. absolute local path;
14. remote image/link with network sentinel proving zero fetch;
15. oversized single resource and aggregate budget breach;
16. 512-resource boundary and 513th-resource rejection;
17. duplicate identical assets deduping to one full-digest companion object;
18. raw HTML + self-contained request → deterministic rejection;
19. generic derived exact-block success with HTML + resource;
20. derived failure with authored source retained;
21. stale revision, duplicate source ID/anchor, overlapping ranges, missing range, partial-block range;
22. directive syntax with `blockDirectives` on/off documenting parity behavior;
23. untitled dirty document with relative image;
24. all bundled light/dark themes;
25. 100+ page print corpus with headings, tables, images and code crossing page boundaries;
26. cancellation during parse/resource hashing/pre-PDF load;
27. existing destination + recognised/unrecognised companion directory;
28. injected failure before resources, midway through resource materialisation, after resources/before primary swap and during optional cleanup;
29. linked stylesheet dedupe/hash naming;
30. cmark C-wrapper repeated/cancelled rendering suitable for leak/lifetime tooling where available.

Property/fuzz tests should target template escaping, URL/resource classification, path containment and output-layout validation where practical.

## 3.16 Expected files and symbols

Exact filenames may be locally adjusted if ownership remains obvious. Do not create a giant `ExportService.swift`.

### MacDownKit

`MacDown2/Packages/MacDownKit/Package.swift`
- add exact `swift-cmark` 0.8.0 declaration aligned with `swift-markdown`;
- add only `cmark-gfm` and `cmark-gfm-extensions` to `ExportService`.

`Sources/ExportService/`
- `ExportService.swift` — orchestration only;
- `ExportRequest.swift` — source/destination/options/policy;
- `ExportResult.swift` — prepared document/manifest;
- `ExportDiagnostic.swift` — typed error/diagnostic codes/context;
- `ExportResourceBudget.swift` — central limits;
- `ExportOutputLayout.swift` — one destination/companion path authority;
- `Metadata/ExportMetadataResolver.swift`;
- `Templates/ExportTemplate.swift`;
- `Templates/BuiltInExportTemplateCatalog.swift`;
- `HTML/CMarkHTMLBodyRenderer.swift`;
- `HTML/CMarkConfiguration.swift` — sole cmark extension/option-name mapping;
- `HTML/ExportStyleSheetBuilder.swift`;
- `HTML/HTMLDocumentComposer.swift` or built-in template implementation;
- `HTML/HTMLEscaper.swift` — generated template context only, never competing Markdown renderer;
- `Assets/ExportResource.swift`;
- `Assets/ExportResourceResolver.swift`;
- `Assets/ExportManifest.swift`;
- `Derived/DerivedExportDestination.swift`;
- `Writing/ExportArtifactWriter.swift` if Foundation-only writer remains package-owned.

`Tests/ExportServiceTests/`
- focused suites mirroring components;
- `Fixtures/` golden/adversarial corpus.

### App target

- `MacDown2/MacDown2/ExportCoordinator.swift`;
- `MacDown2/MacDown2/ExportPanelView.swift`;
- `MacDown2/MacDown2/WebKitPDFRenderer.swift`;
- `MacDown2/MacDown2/PDFPageLayout.swift` if not colocated.

Expected edits:

- `WorkspaceCommands.swift` — File → Export… and enablement;
- `WindowCoordinator.swift`/`WindowController.swift` — active-window route/task lifetime;
- app composition root — inject theme/export/PDF dependencies;
- String Catalog/project-generation inputs as required.

Never hand-edit `.xcodeproj`; regenerate with XcodeGen.

## 3.17 Implementation slices

Each slice is a worker execution contract. A worker stops when live reality requires a changed cross-module/product/security decision.

### Slice 0 — dependency and type-contract gate

**Goal:** prove cmark dependency/import/lifetime and compile the invalid-state-free export contracts before broad work.

**Dependencies:** baseline only.  
**Files:** `Package.swift`, request/result/diagnostic/budget/output-layout/derived contracts, cmark smoke wrapper test.  
**Types:** `ExportSourceSnapshot`, `ExportDestination`, `HTMLExportOptions`, `HTMLPackagingMode`, `ExportMetadataPolicy`, `PreparedExportDocument`, `ExportResourceBudget`, `ExportOutputLayout`, derived destination values, internal `MarkdownHTMLBodyRendering`.

**Behavior:**

- exact direct `swift-cmark` 0.8.0 resolves without duplicate-version conflict;
- only ExportService imports cmark products;
- cmark built-in registration + parse/render/free smoke works repeatedly;
- public types cannot represent PDF-with-HTML-options or self-contained-with-linked-CSS;
- output layout validation rejects arbitrary companion paths.

**Tests/evidence:** package resolution/build; escaping/lifetime smoke; type-level option tests; dependency graph recorded.

**Verification:** `(cd MacDown2/Packages/MacDownKit && swift build && swift test)`.

**Stop condition:** incompatible cmark resolution, unavailable required GFM extension API, unsafe lifecycle that cannot be contained, or a required new dependency. Revise architecture; do not add a second Markdown library.

### Slice 1 — deterministic HTML body, metadata, template and theme CSS

**Goal:** ordinary Markdown + front matter + chosen theme becomes complete deterministic HTML without external local assets.

**Dependencies:** Slice 0.  
**Files:** cmark config/renderer, metadata resolver, template/catalog, stylesheet builder, composer, fixtures/tests.  
**Types:** `CMarkConfiguration`, `CMarkHTMLBodyRenderer`, `ExportMetadataResolver`, `ExportTemplateContext`, `BuiltInExportTemplateCatalog`, `ExportStyleSheetBuilder`.

**Behavior:**

- `ExportService.prepare` always freshly invokes `ParseExecuting.parse` on request text;
- exact GFM mapping in one config;
- exact `CMARK_OPT_UNSAFE + tagfilter` raw-HTML policy;
- front-matter title mapping;
- complete HTML5 + theme CSS;
- deterministic output with no time/random data;
- self-contained request with raw HTML fails before false closure claim.

**Tests/evidence:** syntax/Unicode/escaping/raw HTML/front-matter/theme golden corpus; repeated byte equality; fake parser proves fresh parse.

**Verification:** package tests + lint/format.

**Stop condition:** supported ordinary Markdown materially disagrees with current parse/product semantics and cannot be corrected in central cmark mapping; do not patch drift in templates.

### Slice 2 — managed resources, output layout and durable HTML writing

**Goal:** local resources work after export without network, unsafe filesystem reach or a fragile multi-file commit.

**Dependencies:** Slice 1.  
**Files:** resource resolver/manifest/output layout/writer + tests.  
**Types:** `ExportResource`, `ExportManifest`, `ExportResourceResolver`, `ExportOutputLayout`, `ExportArtifactWriter`.

**Behavior:**

- explicit root containment after symlink resolution;
- local images companion/self-contained behavior;
- remote resources never fetched;
- full SHA-256 logical names; identical byte dedupe;
- UTType/system media-type resolution rather than scattered extension switch;
- file-backed streaming in companion mode;
- central budget enforcement;
- recognised ownership before companion-directory reuse;
- resources materialised first, primary HTML atomically replaced last; no false multi-file atomicity claim;
- self-contained raw HTML/remote/missing resource rejects deterministically.

**Tests/evidence:** missing/escape/symlink/Unicode/remote/size/count/dedupe/collision/ownership/fault-injection corpus; network sentinel untouched.

**Verification:** package tests + manual offline move/open.

**Stop condition:** implementation needs out-of-root reads, network fetch, adoption/deletion of unknown user files, or cannot preserve old primary validity until commit. Do not silently relax policy.

### Slice 3 — generic derived-content destination

**Goal:** prove E12 accepts a future E14/E19/E20 result without language knowledge or another export path.

**Dependencies:** Slices 1–2.  
**Files:** derived matcher/destination + cmark integration/tests only; **no production math/diagram renderer**.  
**Types:** `DerivedSourceID`, `DerivedExportAnchor`, `DerivedExportContent`, `DerivedExportResource`, `DerivedExportResolution`, `DerivedExportFailure`.

**Behavior:**

- exact complete-block source-position match;
- current revision required;
- successful fake HTML/resource replacement;
- derived resource enters same budget/manifest/reference strategy;
- failure/stale/duplicate/overlap/missing/partial match preserves source + diagnostic;
- no language-specific production branch.

**Tests/evidence:** deterministic fake contribution and all conflict/fallback cases; review confirms no renderer-language logic.

**Verification:** package tests/lint/format.

**Stop condition:** requires importing E14 implementation types or adding renderer-specific enum/switch. Keep E12 generic.

### Slice 4 — macOS PDF adapter

**Goal:** turn the same prepared export document into readable paginated searchable PDF locally.

**Dependencies:** Slices 1–3; Epic 11 WebKit security patterns.  
**Files:** `WebKitPDFRenderer.swift`, `PDFPageLayout.swift`, integration fixtures/tests.  
**Types:** `WebKitPDFRenderer`, `PDFRenderRequest`, `PDFPageLayout`.

**Behavior:**

- `@MainActor` WebKit/AppKit adapter;
- local scheme serves only manifest resources;
- JS off, nonpersistent store, navigation/download/pop-up/remote loads blocked;
- system print geometry captured into a value; tests inject fixed layout;
- `WKWebView.printOperation(with:)` / `NSPrintOperation`, not screenshot/viewport capture;
- save temporary PDF, validate via PDFKit, atomically replace primary;
- print CSS keeps long code/table content readable and text searchable/selectable.

**Tests/evidence:** PDFKit page/text assertions, 100-page corpus, page-boundary code, local image, remote sentinel, cancellation/temp cleanup, Release timing evidence.

**Verification:** app build + targeted integration tests + manual Preview.app inspection.

**Stop condition:** AppKit/WebKit path cannot reliably create paginated/searchable PDF on macOS 26. Re-architect only the isolated PDF adapter; never fork Markdown composition or rasterise as shortcut.

### Slice 5 — export panel and window integration

**Goal:** expose a native accessible File → Export… workflow with no duplicate state source.

**Dependencies:** Slices 1–4.  
**Files:** coordinator/panel, command/window composition, strings/UI tests.  
**Types:** `ExportCoordinator`, `ExportPanelModel`, `ExportPanelView`.

**Behavior:**

- enabled only for active Markdown document;
- themes come from `ThemeController.available`, current theme default;
- HTML/PDF destination state uses typed request values;
- self-contained selection removes stylesheet-link control rather than disabling an impossible state in the service;
- output URL chosen before immutable snapshot/layout is finalised;
- current text/revision/file/resource root captured immediately before work begins;
- one export task per window; progress/cancel;
- structured warnings/errors localised at UI edge;
- no source save/mutation.

**Tests/evidence:** command enablement across formats, dirty immediate export, theme/packaging choices, HTML/PDF, warning/cancel, keyboard/VoiceOver, localisation keys.

**Verification:** XcodeGen, Debug + Release app builds, UI tests, keyboard/VoiceOver pass.

**Stop condition:** requires global current-document state/mutable singleton or exposes a format without an owned adapter.

### Slice 6 — hardening, evidence and documentation reconciliation

**Goal:** satisfy issue #13 and release-hardening evidence, not merely unit tests.

**Dependencies:** all slices.  
**Files:** adversarial/golden corpus, performance evidence, PR verification notes, necessary durable docs.

**Evidence:**

- full matrix/corpus complete;
- package suites green;
- SwiftLint/SwiftFormat clean;
- Debug + Release app builds;
- browser HTML dogfood and Preview.app PDF dogfood;
- offline/no-transmit evidence;
- a11y/localisation pass;
- performance budgets recorded;
- residual risks current;
- issue #13 closed only when implementation acceptance evidence is complete.

**Required commands from repo root:**

```bash
(cd MacDown2 && xcodegen generate)
(cd MacDown2/Packages/MacDownKit && swift build && swift test)
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -configuration Release build
swiftlint lint --strict MacDown2
swiftformat --lint MacDown2
```

Run any new targeted UI/integration schemes as well; targeted tests never replace repository-wide gates.

**Stop condition:** any acceptance item is supported only by code inspection/agent assertion instead of executable/manual evidence. Record/fix evidence before completion.

## 3.18 Definition of Done and residual risk

Epic 12 is done only when all are true:

- [ ] File → Export… supports HTML and PDF for Markdown documents.
- [ ] Export always uses a fresh immutable current-editor snapshot and never mutates/saves source.
- [ ] Public option types cannot represent irrelevant/contradictory destination states.
- [ ] HTML is complete deterministic UTF-8 with GFM fidelity, front-matter title, selected theme and normal/self-contained packaging.
- [ ] Self-contained means CSS + all managed local resources embedded and no raw authored HTML/remote managed resource remains.
- [ ] Companion resources use one canonical output layout, full-digest names and resource-first/primary-last durability.
- [ ] No first-party export path fetches/transmits document/resource content over network.
- [ ] Path traversal/symlink escape and central resource budgets are enforced.
- [ ] Raw authored HTML follows the exact `CMARK_OPT_UNSAFE + tagfilter` policy in normal export; generated metadata remains separately escaped.
- [ ] PDF consumes the same prepared composition, is paginated/readable/searchable/selectable and uses locked-down WebKit/AppKit rendering.
- [ ] A generic fake derived contribution replaces exactly one block and contributes a resource without renderer/language-specific export logic.
- [ ] Failed/stale/ambiguous derived content preserves authored source and surfaces diagnostics.
- [ ] Relevant legacy `MPAsset` behavior concepts are represented by typed asset/template/manifest tests without recreating obsolete class architecture.
- [ ] Full automated test/evidence matrix and adversarial corpus pass.
- [ ] `swift build`, `swift test`, SwiftLint and SwiftFormat pass.
- [ ] Xcode project regenerates and Debug + Release app builds pass.
- [ ] Release performance evidence meets budgets or an explicit architecture revision records the accepted change.
- [ ] Manual HTML/PDF dogfood, offline behavior, accessibility and localisation evidence is recorded in PR.
- [ ] PR remains owner-readable: what changed, why, how, what to test, risks/limits and verification.

### Residual risks

1. **cmark dialect parity.** `MarkdownEngine` and direct cmark export remain separate adapters. The central mapping + parity corpus is a permanent gate for dependency upgrades.
2. **Block directives.** Pinned cmark-gfm lacks `swift-markdown`'s semantic block-directive model. E12 preserves authored directive text; a future directive feature must own an explicit export adapter.
3. **Raw HTML.** Authored-output fidelity and in-app execution trust are separate. Normal exported HTML may preserve active authored markup; transient PDF WebKit stays locked down. Self-contained mode rejects raw HTML because E12 does not prove arbitrary HTML resource closure.
4. **Legacy MPAsset source availability.** Concrete legacy symbol was not discoverable at architecture baseline. If found/restored with a materially missing acceptance behavior, stop and reconcile.
5. **Issue #35.** Non-Markdown documents still enter Markdown parsing elsewhere. E12 gates export to Markdown and does not solve that issue.
6. **System print stack.** Pagination relies on macOS 26 WebKit/AppKit. Isolation of `WebKitPDFRenderer` keeps any future platform correction from infecting export composition.
7. **Companion cleanup.** Content-addressed resources can leave safe orphaned files if post-commit cleanup fails. Correctness/durability wins over aggressive deletion; cleanup remains ownership-bounded and best-effort.

### Worker stop rule

Workers may make ordinary local implementation choices within a slice. Stop and revise/escalate if discovery requires:

- any third-party package beyond exact cmark already selected by the migration plan;
- a new SwiftPM target or reversed module dependency;
- network/hosted rendering;
- a second Markdown/PDF composition path;
- language-specific derived-content logic in E12;
- source mutation during export;
- filesystem reads outside explicit resource scope;
- adoption/deletion of unrecognised companion files/directories;
- regex-based raw-HTML resource crawling or a new sanitizer;
- weakened tests or changed user-visible failure policy;
- edits outside authorised slice that materially change another epic's ownership.
