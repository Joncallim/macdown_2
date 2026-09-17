# EPIC-20 implementation architecture: Native diagram platform + Mermaid

Baseline `master` SHA: `e684f5b` (2026-09-15, post-#59 root-cause fix and
release-evidence reconciliation). Product contract: GitHub issue #45.
Depends on E12 export (done), E14 contribution seam (done) — both
confirmed live on this baseline, not from planning prose (§2).

This document is written directly against current `master` source. Two
things about it are provisional rather than final, and are named as
pre-implementation spikes in §17 Slice 0 rather than asserted as fact:
whether a `WKWebView` can reliably drive a JavaScript render inside a
plain `swift test` package-test host process (as opposed to only inside
the full `xcodebuild`-built app), and the exact mechanism by which a
rendered SVG string becomes an on-screen native view. Everything else in
this document is a binding contract.

> **As-built note (Slice 0, 2026-09-15):** The spike is done and the
> question is resolved. A standalone throwaway SPM package (not
> committed to this repository) reproduced the exact mechanisms §10 and
> §16 specify: a `WKWebView` configured with `websiteDataStore =
> .nonPersistent()` and `allowsContentJavaScript = true`, driven from a
> `@MainActor` type via `async`/`withCheckedThrowingContinuation` around
> `WKNavigationDelegate` callbacks. Two real tests under plain `swift
> test` (no `xcodebuild`, no app bundle, no on-screen window): (1)
> `loadHTMLString(_:baseURL: nil)` + `evaluateJavaScript` completed
> correctly 5/5 times, ~200ms per load+eval cycle; (2) the actual
> `loadFileURL(_:allowingReadAccessTo:)` mechanism §10 specifies for the
> bundled Mermaid harness — loading a local `harness.html` that pulls in
> a separate local `script.js` via a `<script src>` tag, then calling a
> function that script defined on `window` — completed correctly 10/10
> times. **Decision: `DiagramRendering` proceeds exactly as designed in
> §5/§6 — a genuine SPM package target, tested for real via `swift
> test`, no fallback to app-target-only testing required.** No change to
> any other section of this document. The second provisional item named
> above (the SVG-to-native-view display mechanism) remains open,
> addressed in Slice 4.

> **As-built note (Slice 4, 2026-09-17): the second provisional item is
> now resolved, and the answer is not what §1/§6/§7.2/§16 assumed.** A
> real spike against actual Mermaid output (not a toy SVG) found that
> AppKit's built-in SVG decoder (`NSImage`/`_NSSVGImageRep`) cannot
> reliably display it. First finding: Mermaid's default output uses
> `<foreignObject><div>...</div></foreignObject>` for node/edge labels
> (real, HTML-based text layout) — AppKit's SVG decoder does not support
> `<foreignObject>` at all, so a rendered `graph TD; A-->B;` showed two
> empty boxes joined by a line, with the "A"/"B" labels silently missing
> entirely. Second finding: forcing Mermaid's own documented
> interoperability escape hatch (`htmlLabels: false`, set at the
> **top level** of `mermaid.initialize(...)` — its
> `flowchart: { htmlLabels: false }` nested form is deprecated and,
> empirically, did not actually change the output) does make Mermaid
> emit native SVG `<text>`/`<tspan>` elements instead — but AppKit's
> SVG decoder then positioned that text in the wrong place (floating
> above each node instead of centered inside it), on every node, not as
> an occasional glitch. Changing `themeVariables.fontFamily` to a plain
> system font did not fix this either, pointing at AppKit's `<style>`
> block/CSS support being the deeper limitation, not font resolution.
>
> **Decision:** keep `svg` (Mermaid's own, unmodified, richer
> HTML-labelled output) as `RenderedMermaidDiagram`'s Export
> representation — completely unaffected, since Export already renders
> through a real browser engine (`PDFExportAdapter`'s `WKWebView`, or the
> reader's own browser for HTML export) that supports `<foreignObject>`
> correctly. For native, on-screen Preview display, `render.js` now also
> rasterizes the SAME rendered SVG to a PNG **inside the same real
> WebKit engine that already renders it correctly** — the standard
> `Image` element loaded from a `data:image/svg+xml` URI, drawn to a
> `<canvas>`, read back via `canvas.toDataURL('image/png')` (confirmed
> for real: this is not blocked by canvas tainting for a same-page
> `data:` URI source) — and `RenderedMermaidDiagram` gained a second
> field, `pngData: Data?`, produced by that one same render call, not a
> second render. `MermaidDiagramBlockView` (§7.2, §16) displays
> `pngData`, not `svg`. This is architecturally the same tradeoff
> `MathContribution`/`RenderedMathImage` already made and shipped in
> EPIC-19 for the same underlying reason (AppKit has no reliable
> resolution-independent on-screen path for this content) — not a novel
> compromise invented here. `svg` remains genuinely vector and is what
> journey 4 (copy/export as SVG) and all of §7.1 Export use; only the
> interactive Preview surface's on-screen pixels are raster, exactly
> mirroring how Math's Preview-visible glyphs are Textual's own text
> rendering while Export's equations are always a PNG regardless.
>
> Every other section's mention of Preview showing "a native vector
> image" should be read as "a native image, real WebKit-rendered,
> resolution-fixed at `render.js`'s `PREVIEW_RASTER_SCALE` (2x)" —
> the vector-quality claims in §1/§3/§18 apply to Export/copy-as-SVG
> only, not to Preview's on-screen pixels. Not adjusting every such
> mention individually; this note is the authoritative correction.

---

## 1. Owner summary

**What changes for the user.** Today, a fenced ```` ```mermaid ```` code
block in MacDown 2 renders exactly like any other code block: a
monospaced text box showing the raw diagram-description syntax. After
this epic, the same block renders as an actual diagram — flowchart,
sequence diagram, or whichever Mermaid diagram type the syntax describes
— directly in the native preview, with no network connection required.
The Markdown file itself does not change: the diagram description stays
ordinary, readable, diffable text; the rendered picture is something the
app derives and can always regenerate.

**Why now.** E12 (export) and E14 (contribution seam) were built with
diagrams named as a future consumer of the same seam E19 (math) already
proved out. `ExportDerivedContribution`'s own doc comment says "E14/E19/E20
later supply instances of this type" — this epic is that promised second
real consumer, not new architecture invention.

**Main technical approach, in ordinary language.** Mermaid is a
JavaScript library that needs a real web-rendering engine (it measures
text, lays out boxes and arrows, and computes SVG geometry using browser
APIs) — there is no practical way to run it without one, and no realistic
way to reimplement Mermaid's own layout engine in Swift for this epic.
macOS ships exactly such an engine, `WebKit`, and MacDown 2 already uses
it (in a locked-down, JavaScript-disabled configuration) for PDF export.
This epic adds a second, narrowly-scoped use: a small number of
**offscreen, never-displayed** `WKWebView` instances load a bundled copy
of Mermaid, execute it against the user's diagram source, and hand back
a plain SVG string. That string is the entire output of the rendering
step — from that point on, nothing about the diagram is JavaScript or
HTML again. The SVG is:

- displayed in the native preview as a native, resolution-independent
  vector image (not by embedding a web page into the preview surface);
- exported through the exact same `ExportDerivedContribution.html` path
  E19 already uses, as inline `<svg>...</svg>` markup — the export
  composer already treats that field as an opaque, already-rendered
  fragment string, so no export-side code changes are needed to accept
  vector markup instead of a raster `<img>` tag (§4).

One rendering technology (headless WebKit), one first-party bundled copy
of Mermaid, no hosted renderer, no document content ever leaves the
device.

**Main risks or compromises.**

- This is the first time MacDown 2 runs arbitrary JavaScript against
  user-authored document content. Every existing `WKWebView` use in this
  codebase has JavaScript explicitly *disabled* — this epic is new
  security-boundary territory, not an existing pattern being reused, and
  §10 treats it accordingly (Mermaid's own `securityLevel: 'strict'`
  configuration, a fully sandboxed offscreen web view with no network
  access, an execution timeout, and an output-size ceiling — layered, not
  any single one relied on alone).
- Preview's live rendering pipeline (`TextualMarkdownPreview`) is fully
  native SwiftUI/AppKit and has no existing seam for displaying anything
  other than Markdown text — not even the `.html` contribution
  representation E19 introduced, which `PreviewContributionAdmission`
  explicitly rejects today ("produced HTML, which Preview does not
  support"). This epic adds a real, small, in-package addition to
  `Packages/MacDownKit/Sources/Preview/TextualMarkdownPreview.swift`'s
  private `BlockView` (§5, §7) rather than reusing the rejected `.html`
  contribution path — Math's own precedent for "Preview needs something
  Contributing can't carry" was to bypass `Contributing` for Preview
  entirely, and this epic does the same.
- A JavaScript-engine round trip per diagram is meaningfully more
  expensive than Math's pure-Swift typesetting call, and — unlike
  Math's raster PNG output, which is generated fresh on every export
  without complaint — repeating that on every keystroke would be a real
  responsiveness problem. `Contributing.run`'s own contract forbids a
  contribution from caching across calls, so this epic's cache (§6, §11)
  lives one layer down, inside the injected renderer, exactly where
  Math's injected `renderer` closure already lives (`MathContribution`
  is agnostic to whether its `renderer` closure is fast or cached).
- Whether a `WKWebView` reliably completes a JavaScript render from
  inside a `swift test` host process (no app bundle, no on-screen
  window) is not yet confirmed on this baseline. If it does not, the
  renderer moves to the app target the way `MathRendering` was
  *originally* sketched as an app-target concern in EPIC-19's own
  planning before discovery proved a package target worked (see that
  epic's Slice 1-2 as-built note) — named as Slice 0 (§17), not assumed.

**Deliberately not being built.** D2, Graphviz/DOT, WaveDrom (E21
candidates — this epic proves the platform, E21 decides whether to add
more renderers to it); visual drag-and-drop diagram authoring; a
Mermaid live-editor/canvas; per-diagram interactive click-through
navigation features Mermaid itself supports (explicitly disabled by the
`strict` security level, §10); rendering a diagram as a web page inside
Preview; character-level source↔diagram tap targets (scoped to
block-level navigation, matching the existing scroll-sync granularity
every other content type already has — the same deliberate scope
reduction EPIC-19 made for equations, for the same underlying reason:
Mermaid's own SVG output carries no stable per-element source-range
metadata this app controls).

---

## 2. Baseline and repository reconciliation

Confirmed directly against `master @ e684f5b` source (package manifests,
checked-out sources, and the live app-target files named below), not
from planning prose.

### 2.1 What already exists and must be reused, not duplicated

- **`Contributing` protocol** (`Packages/MacDownKit/Sources/Contributions/Contributing.swift`):
  `async throws -> [ContributionResult]`, cooperatively cancellable,
  explicitly documented as never allowed to cache across calls, and
  explicitly documented as unaware of whether it feeds Preview or
  Export. `ContributionRegistry.standard` contains only `TOCContribution`
  — `MathContribution` is *not* in it, because Preview cannot consume
  its `.html` output (below). This epic follows the exact same shape:
  `MermaidContribution: Contributing`, registered only into a new
  Export-only registry factory, never into `.standard`.
- **`ContributionRepresentation.html(String)`** (`ContributionRepresentation.swift`)
  already exists, already carries a doc comment naming "an SVG diagram"
  as its second anticipated producer (after Math's rendered-equation
  image), and is already the one case `PreviewContributionAdmission.admit`
  explicitly rejects for Preview ("produced HTML, which Preview does not
  support; authored source preserved" — `PreviewContributionAdmission.swift`).
  This epic does not change that rejection or attempt to route Mermaid
  through `ContributionRegistry` for Preview; see §2.2.
- **`ExportDerivedContribution`** and **`DerivedContentComposer`**
  (`Packages/MacDownKit/Sources/ExportService/`) already accept an
  opaque `html: String` fragment, validate it against a strict
  rejection ladder (stale generation, out-of-bounds/overlapping range,
  empty content, a fragment-count/aggregate-byte budget), and splice it
  into the exported document via a cmark custom-node sentinel — with
  **no type-level restriction to raster images**. `ExportDerivedContribution`'s
  own doc comment names E20 by number as an intended future caller. This
  epic supplies `html` as literal `<svg>...</svg>` markup and requires
  zero changes to `DerivedContentComposer`, `ExportDerivedContribution`,
  or the cmark splicing mechanism.
- **`PDFExportAdapter`** (`MacDown2/PDFExportAdapter.swift`) already
  loads exported HTML into a hardened, ephemeral, JavaScript-disabled
  `WKWebView` (`websiteDataStore = .nonPersistent()`,
  `allowsContentJavaScript = false`, a restrictive CSP baked into the
  HTML `<head>`, `loadHTMLString(_:baseURL: nil)`, a bounded load
  timeout with an explicit watchdog) purely to drive `NSPrintOperation`.
  Inline `<svg>` markup flows through that pipeline as ordinary HTML —
  no changes needed there either. **This existing pipeline runs with JS
  disabled and is not itself a precedent for running Mermaid** — it is
  the precedent for the hardening *pattern* (ephemeral storage, no base
  URL, explicit CSP, watchdog timeout) this epic's *own*, separate,
  JS-enabled offscreen web view must independently apply (§10).
- **`HTMLPreviewPolicy.swift` / `PreviewSecurity.swift`** (`Preview`
  package) implement a more elaborate scheme-handler-based network
  containment for an `HTMLPreviewView` that is *not* the live preview
  path today (the app target wires up `TextualMarkdownPreview`, not
  `HTMLPreviewView` — confirmed by the split-view call site). Cited here
  as an available, stronger containment pattern if the simpler
  `loadFileURL(_:allowingReadAccessTo:)` + navigation-delegate approach
  in §10 proves insufficient; not required for this epic's baseline
  design.
- **`BlockKind.codeBlock(language: String?)`** (`MarkdownEngine/MarkdownBlock.swift`)
  already carries the fence's language tag through parsing. No fenced
  code block's language has ever been given special rendering meaning
  before this epic (confirmed: no non-test, non-definition file pattern
  matches on `.codeBlock(language:)` today) — a `mermaid`-language fence
  being treated specially is new, not an extension of an existing
  mechanism.
- **Generation/revision-token staleness suppression** recurs three times
  already in this codebase in independent forms: `DocumentFileMonitor`'s
  `generation`/`probeSequence` pair (an `actor`, gating a live
  filesystem watcher's async callbacks), `MarkdownParseSession`'s
  `pendingGeneration`/`nextRevision` pair plus a monotonic-result guard
  (a `@MainActor @Observable` debounced parser), and
  `PreviewContributionSession`'s `PreviewContributionTaskID` plus
  `currentTaskID` guard (`MacDown2/PreviewContributionSession.swift`,
  itself explicitly documented as mirroring `MarkdownParseSession`'s
  shape). This epic's own stale-render suppression (§8) is a fourth
  instance of the same established idiom — monotonic tokens compared for
  recency to discard a superseded async result — not a new pattern.

### 2.2 Assumptions from the epic issue reconciled against the repository

- Issue #45's acceptance criterion "`mermaid` fences render in native
  Markdown preview without converting Markdown preview into a web page"
  reads, at first glance, like it merely forbids replacing the *whole*
  preview surface with an embedded browser. Reconciled more precisely
  against the live `TextualMarkdownPreview`/`BlockView` structure (§5):
  the existing design already renders one block at a time, and the
  render engine (headless WebKit) never appears on screen at all — the
  only thing that reaches the screen is a plain, static SVG-backed
  image view sitting in the same `VStack` as every other native block.
  This satisfies both the letter and the spirit of the criterion without
  requiring a generalized "custom block renderer" plugin API in the
  `Preview` package; it requires exactly one new, explicit `if` branch
  in `BlockView.body` (§7).
- The issue's scope item "renderer abstraction aligned with E14" is
  reconciled the same way E19 already reconciled it: `Contributing` is
  the Export-side abstraction (§3), but Preview's own admission pipeline
  cannot carry HTML output today, so "aligned with E14" means *sharing
  E14's renderer-neutral derived-content philosophy and its injected-
  renderer seam shape*, not literally routing Preview's diagram
  rendering through `ContributionRegistry`. Widening
  `PreviewContributionAdmission` to accept `.html` was considered and
  rejected: TOC (the only other live Preview contribution) has no
  reason to ever produce HTML, and loosening that guard for one future
  consumer would weaken a currently-total, currently-tested invariant
  for no immediate benefit. If a future epic needs a second
  HTML-producing Preview surface, that is the point to revisit this
  choice — not before.
- `ContributionRegistry` has no dynamic plugin-discovery mechanism (it
  is a plain array literal, `standard`/`standardForExport`); "renderer
  abstraction" here means the `MermaidDiagramRendering` protocol (§6),
  injected the same way `MathImageRendering` is injected into
  `MathContribution.init`, not a registry-style dynamic dispatch system.

---

## 3. User journeys

1. **Type a Mermaid fence, see it render.** The user types
   ```` ```mermaid\ngraph TD; A-->B;\n``` ````. Within roughly one debounce
   interval after they stop typing, the preview block updates from plain
   monospaced text to a rendered flowchart. Scroll-sync continues to
   work at the same block granularity as any other block.
2. **Malformed diagram source degrades safely.** The user has an
   unbalanced or nonsensical Mermaid fence (e.g. `graph TD; A-->`,
   truncated mid-edit). The block shows a small, clearly-labelled
   inline diagnostic ("This diagram could not be rendered") in place of
   a diagram — never a blank block, a crash, a frozen preview pane, or a
   stale diagram from before the edit. As soon as the source becomes
   valid again, the diagram reappears automatically on the next
   successful render, with no user action required.
3. **Offline behaviour.** With networking fully disabled at the OS
   level, Mermaid fences still render, still update on edit, and still
   export to HTML/PDF/SVG. Nothing about this epic's behaviour changes
   with or without a network connection, because nothing it does ever
   depends on one.
4. **Copy/export the diagram as SVG.** The user selects a rendered
   diagram block and copies it, or exports the document. The resulting
   SVG is genuine vector markup — opening it in any vector editor or
   browser at any zoom level shows crisp lines, not an upscaled bitmap.
5. **Export the document.** HTML and PDF export both show the same
   diagram the user saw in Preview (same Mermaid version, same
   rendering call, same theme-driven styling where applicable), produced
   through the same `ExportDerivedContribution` path E19 already
   exports through — not a second, independently-written exporter.
6. **Editing a document with several unrelated, unchanged diagrams.**
   The user edits prose in one part of a long document containing five
   Mermaid diagrams elsewhere. Typing does not visibly re-render, flicker,
   or measurably slow down because of the four diagrams whose source
   text did not change — their previous render is reused, not recomputed
   (§6, §11).
7. **Rapid edits inside a diagram fence.** The user pastes a large
   diagram, then immediately edits it twice more before the first render
   would have finished. Only the final, latest edit's render is ever
   shown; an in-flight render for a since-superseded version of the
   source is silently discarded when it completes, never briefly
   flashing stale content (§8).
8. **A pathological diagram.** The user pastes deliberately huge or
   deeply nested Mermaid source (adversarial testing, §15, or an
   accidental paste of the wrong content). Rendering is bounded by a
   timeout and an output-size ceiling; exceeding either produces the
   same inline diagnostic as journey 2, never a hung UI, an unbounded
   memory allocation, or a crash.
9. **A diagram whose fence gets deleted or edited to a different
   language.** The block reverts to plain code-block text exactly as it
   would for any other language change — no leftover diagram artifact,
   no dangling render task holding a reference to a block that no
   longer exists.

---

## 4. Non-negotiable invariants

- Document content, diagram source included, is never transmitted
  anywhere off-device. The rendering `WKWebView` never has network
  access at any layer (§10) — not "network access we chose not to use,"
  but network access that is architecturally unavailable to it.
- The authored Markdown source is the only durable representation of a
  diagram. Rendered SVG is disposable, derived, cache-only data; losing
  the entire cache must never lose or corrupt document content, and must
  only cost a re-render.
- A failed, timed-out, or unavailable renderer degrades the affected
  block to a visible, safe, non-crashing state and never touches any
  other block or the document's saved text.
- Rendering never blocks `MainActor`. All Mermaid execution happens off
  the main actor; only cheap, synchronous state updates (publishing a
  finished result, or a diagnostic) touch `MainActor` UI state.
- A superseded render (source edited again before the previous render
  finished) is discarded at publish time and never overwrites a newer
  result with an older one, mirroring the existing monotonic-token
  idiom (§2.1, §8).
- Mermaid's own scripting/interaction features (`click` directives,
  arbitrary HTML in labels) are disabled at the Mermaid configuration
  level (`securityLevel: 'strict'`) regardless of what the offscreen web
  view's own containment already blocks — defense in depth, not
  either/or (§10).
- Export renders through the exact same `Contributing` →
  `ExportDerivedContribution` → `DerivedContentComposer` path every
  other derived-content producer uses. No parallel, independently
  written Mermaid exporter is created.

---

## 5. Ownership and dependency boundaries

Two new SPM library targets under `Packages/MacDownKit/Sources/`,
mirroring the `Math`/`MathRendering` split E19 established for exactly
the same reason (keep the pure, fast-to-test model layer free of a heavy
runtime dependency, and give the runtime-dependent layer its own package
so `swift test` can exercise it without `xcodebuild`, pending Slice 0's
confirmation that doing so is viable for a WebKit-backed renderer, §17):

- **`Diagrams`** (pure Swift, no AppKit/WebKit dependency): the diagram
  model, the `Contributing` implementation, the renderer protocol, the
  bounded cache, and diagnostics. Depends on `Contributions` and
  `MarkdownEngine` only (parallel to `Math`'s own dependency shape).
- **`DiagramRendering`** (AppKit + WebKit dependency; macOS-only, same
  floor as the rest of `MacDownKit`): the actual offscreen-`WKWebView`
  renderer, the bundled Mermaid JS asset, and the security/navigation
  policy that contains it. Depends on `Diagrams`. Parallel to
  `MathRendering`'s relationship to `Math`.

App-target ownership, mirroring `MathExportRegistry.swift`'s existing
shape:

- **`MacDown2/MermaidExportRegistry.swift`** — adds `MermaidContribution`
  to a new `ContributionRegistry.standardForExport(...)` contribution
  list (the existing factory already used for Math; Mermaid becomes a
  second contribution in the same Export-only registry, not a second
  registry).
- **A small, explicit addition inside
  `Packages/MacDownKit/Sources/Preview/TextualMarkdownPreview.swift`'s
  private `BlockView`** (§7) — the one deliberate, scoped exception to
  "app target only" ownership, because the seam this epic needs (a
  third rendering branch alongside `isOversize`/`StructuredText`)
  physically lives inside that file's `private struct BlockView`, which
  is not reachable or overridable from outside the `Preview` package
  (the same constraint that moved EPIC-19 Slice 3's insertion point).
  `TextualMarkdownPreview`'s public initializer gains one new,
  defaulted parameter (§7) so every existing call site keeps compiling
  unchanged.
- **`MacDown2/MermaidPreviewRenderer.swift`** (new, app target) — the
  single shared instance of the caching renderer that
  `DocumentEditorSplitView.swift` threads into `TextualMarkdownPreview`'s
  new parameter, and that the app's export path also uses when building
  `standardForExport`'s `MermaidContribution` (one renderer instance,
  two consumers — the cache is shared, so a diagram already rendered for
  Preview does not re-render again for Export).

No new dependency is added to `Contributions`, `ExportService`, or
`MarkdownEngine` themselves. `DiagramRendering`'s WebKit dependency does
not leak into `Diagrams`, `Contributions`, or any Preview/Export code
outside the app-target wiring files named above — everything else sees
only the `MermaidDiagramRendering` protocol (§6).

---

## 6. Types and interfaces

All in the new `Diagrams` target unless noted.

```swift
/// One fenced ```mermaid``` block found in a document, identified the
/// same way MathSpan identifies an equation: by its UTF-16 source range.
public struct MermaidFence: Sendable, Equatable {
    public let source: String          // fence content, language line excluded
    public let sourceRange: Range<Int> // UTF-16 offsets into the ORIGINAL document text
}

/// Recognizes ```mermaid fences by language tag, case-insensitively
/// ("Mermaid", "MERMAID", "mermaid" all match), scanning raw source text
/// (Export) or a single block's source (Preview) — parallel role to
/// MathSpanScanner, but block-only: Mermaid has no inline form.
public enum MermaidFenceScanner {
    public static func scan(_ sourceText: String) -> [MermaidFence]
}

/// Theme/context inputs that affect rendering but are not part of the
/// diagram source itself. Unlike ExportMathRenderContext, no pixelScale
/// field: SVG is resolution-independent, so scale is a display-time
/// concern, not a render-time one.
public struct MermaidRenderContext: Sendable, Equatable {
    public let foregroundRed: Double
    public let foregroundGreen: Double
    public let foregroundBlue: Double
    public let backgroundRed: Double
    public let backgroundGreen: Double
    public let backgroundBlue: Double
}

/// The result of a successful render. Width/height are the diagram's own
/// natural size in points, taken from the SVG's viewBox — needed so a
/// native view can reserve correctly-proportioned layout space before
/// the image is decoded.
public struct RenderedMermaidDiagram: Sendable, Equatable {
    public let svg: String
    public let naturalWidth: Double
    public let naturalHeight: Double
}

public enum MermaidRenderError: Error, Sendable, Equatable {
    case invalidSyntax(String)   // Mermaid's own parse-error message, where available
    case timedOut
    case outputTooLarge(byteCount: Int)
    case rendererUnavailable     // e.g. the offscreen web view failed to initialize
}

/// The injected-renderer seam, parallel to MathImageRendering. A
/// protocol (not a closure typealias like Math's) because, unlike
/// Math's single free function, Mermaid's real implementation is
/// stateful (it owns a pool of long-lived offscreen web views) and
/// benefits from an explicit lifecycle/teardown method for tests and
/// document-close cleanup.
public protocol MermaidDiagramRendering: Sendable {
    func render(_ fence: MermaidFence, context: MermaidRenderContext) async throws -> RenderedMermaidDiagram
}

/// Bounded LRU-style cache, keyed by (trimmed source text, render
/// context) equality — not by document identity or block id, so an
/// unchanged diagram copy-pasted into a different document, or a
/// diagram whose surrounding prose changed but whose own fence content
/// did not, still hits the cache. Pure Swift, independently unit
/// testable with a fake MermaidDiagramRendering.
public actor MermaidDiagramCache {
    public struct Budget: Sendable {
        public static let standard = Budget(maxEntries: 128, maxAggregateSVGBytes: 8 * 1024 * 1024)
        public let maxEntries: Int
        public let maxAggregateSVGBytes: Int
    }

    public init(budget: Budget = .standard, renderer: any MermaidDiagramRendering)

    /// Renders on a cache miss, stores the result, evicts least-recently-
    /// used entries as needed to stay within budget. A failed render is
    /// NOT cached — a transient timeout must not permanently poison a
    /// diagram that would succeed on retry.
    public func render(_ fence: MermaidFence, context: MermaidRenderContext) async throws -> RenderedMermaidDiagram
}

/// Export-side Contributing implementation. Registered only into
/// standardForExport, mirroring MathContribution exactly (see
/// MathExportRegistry.swift's precedent).
public struct MermaidContribution: Contributing {
    public let id = "mermaid"
    public init(context: MermaidRenderContext, renderer: any MermaidDiagramRendering)
    public func run(document: MarkdownDocument, sourceText: String, sourceGeneration: UInt) async throws -> [ContributionResult]
}
```

In `DiagramRendering`:

```swift
/// The real, WebKit-backed implementation of MermaidDiagramRendering.
/// Owns a small pool of offscreen, never-displayed WKWebView instances,
/// each pre-loaded with the bundled Mermaid harness (§9, §10). An actor
/// so concurrent render calls are safely serialized/distributed across
/// the pool without a caller needing to reason about WKWebView's own
/// main-thread-affine API.
public actor MermaidWebRenderer: MermaidDiagramRendering {
    public init(poolSize: Int = 2, timeout: Duration = .seconds(5))
    public func render(_ fence: MermaidFence, context: MermaidRenderContext) async throws -> RenderedMermaidDiagram

    /// Tears down every pooled web view. Called on app termination and
    /// in tests; not required between individual documents (the pool is
    /// process-lifetime, not document-lifetime — see §8).
    public func shutdown() async
}
```

---

## 7. State and data flow

### 7.1 Export

```
sourceText
  -> MermaidFenceScanner.scan(_:)              [Diagrams, pure, sync]
  -> for each fence: MermaidDiagramCache.render [Diagrams, async]
       -> cache hit: return stored RenderedMermaidDiagram
       -> cache miss: MermaidWebRenderer.render  [DiagramRendering, async]
            -> pooled WKWebView.evaluateJavaScript(mermaid.render(...))
            -> parse result: SVG string + natural size, or a structured error
  -> MermaidContribution.run(...) -> [ContributionResult] with
       .html(svgString) representation                [Contributions]
  -> MacDown2/ExportContributionAdapter.adapt(_:)      [app target, unchanged]
  -> ExportDerivedContribution(html: svgString, ...)   [ExportService, unchanged]
  -> DerivedContentComposer.compose(...)               [ExportService, unchanged]
  -> spliced HTML body -> ExportHTMLWriter / PDFExportAdapter [unchanged]
```

Every step from `ExportContributionAdapter` onward is existing,
unmodified E12/E14 machinery (§2.1) — this epic's only new Export-side
code is the scan → cache → render → `.html(...)` steps above it.

### 7.2 Preview

```
PreviewBlock (kind: .codeBlock(language: "mermaid"), source: fenceBody)
  -> BlockView.body recognizes the language tag              [Preview, new branch]
  -> MermaidDiagramBlockView(source:, context:, renderer:)    [Preview, new view]
       .task(id: source) {
           result = try? await renderer.render(fence, context)
       }
       -> renders RenderedMermaidDiagram.pngData as a native raster image
          on success (§10 as-built note — NOT .svg; AppKit cannot
          reliably display real Mermaid SVG output on screen);
          an inline diagnostic view on failure/timeout; a lightweight
          placeholder while the task is in flight
```

`renderer` here is the same shared `MermaidDiagramCache`-wrapped
`MermaidWebRenderer` instance the app threads into
`TextualMarkdownPreview`'s new initializer parameter (§5) — the same
cache Export also reads from, so a diagram already seen once (in either
direction) never re-renders for the other.

### 7.3 State transitions (per diagram block, Preview)

`idle → rendering → (rendered | failed | superseded)`. `superseded` is
not a state the view itself ever shows — it is what happens when a
`.task(id:)` is cancelled by a new `id` arriving before the old task
finished; SwiftUI's own `.task(id:)` cancellation is the entire
mechanism (§8), not a hand-rolled generation counter at this layer. A
transition back to `idle`/`rendering` happens whenever `source` changes
(SwiftUI naturally restarts `.task(id:)` when its `id` changes).

---

## 8. Concurrency and cancellation

- `MermaidWebRenderer` is an `actor`; `MermaidDiagramCache` is an
  `actor`. Neither is `@MainActor`. All rendering work — cache lookup,
  cache miss, the actual WebKit round trip — happens off `MainActor`.
- `WKWebView` instances themselves are main-thread-affine AppKit-adjacent
  objects and must be created and driven on the main actor even though
  the *caller* (`MermaidWebRenderer.render`) is not `@MainActor` itself;
  `MermaidWebRenderer` hops to `MainActor` internally only for the
  narrow WebKit calls (`evaluateJavaScript`, navigation), the same way
  `MathImageRenderer.render` is itself `@MainActor` while
  `MathContribution.run` (its caller) is not.
- **Cancellation is cooperative and bounded, matching Math's own
  accepted limitation, not stronger.** Once `evaluateJavaScript` has
  been dispatched to a pooled web view for a given render, that
  in-flight JavaScript execution runs to completion or to its own
  timeout (§10) — there is no WebKit API to abort a running JS
  evaluation short of destroying the web view outright, which this
  design avoids doing per-render because it would defeat pool reuse
  (§11). What *is* cancelled promptly is publication of a stale result:
  at the Preview layer, SwiftUI's `.task(id:)` naturally discards a
  superseded task's eventual result without ever calling its
  completion handler on the old identity; at the Export layer,
  `Contributing.run`'s existing cooperative-cancellation contract
  (`Task.checkCancellation()` between fences, exactly like
  `MathContribution.run`) covers fences not yet started, and
  `ContributionResult.sourceGeneration`/`DerivedContentComposer`'s
  existing stale-generation rejection (§2.1) covers a fence whose render
  finished after the export it was for was itself superseded.
- **Debouncing happens before a render is ever dispatched**, not only at
  publish time — this is what actually satisfies journey 7 ("rapid
  edits don't each trigger a render") rather than merely journey 6
  ("stale results are discarded"). `MermaidDiagramBlockView`'s
  `.task(id: source)` is itself the debounce: SwiftUI does not begin a
  new `.task` body until the view has settled on a given `id` for one
  render pass, and the *upstream* `PreviewContributionSession`/parse
  debounce (150ms, §2.1) already coalesces rapid keystrokes into one
  document revision before Preview blocks are even recomputed. No
  additional debounce timer is introduced by this epic; the existing
  ones are sufficient because a Mermaid fence's `source` cannot change
  more often than the block list itself is recomputed.
- **Lifecycle teardown.** `MermaidWebRenderer`'s web-view pool is
  process-lifetime, not document- or window-lifetime — it is not torn
  down when a document or window closes, only at app termination
  (`shutdown()`, called from the app delegate's termination path,
  mirroring how the app already manages other process-lifetime
  singletons). This is a deliberate choice: pool warm-up (loading the
  Mermaid JS harness into a fresh web view) is the expensive part, and
  nothing about a single document owns the pool exclusively.
- **`Sendable` expectations.** `MermaidFence`, `MermaidRenderContext`,
  `RenderedMermaidDiagram`, `MermaidRenderError` are all plain
  `Sendable` value types. `WKWebView` itself is not `Sendable` and never
  crosses an actor boundary as a value — it is created, held, and used
  exclusively inside `MermaidWebRenderer`'s own actor isolation.
- **What happens when a document changes while a render is in flight**
  is fully answered by the two points above: the in-flight render
  finishes (bounded by its timeout) and either populates the cache
  (harmless — cache keys are content-addressed, not document-addressed,
  so a since-edited document simply doesn't look up that key again) or
  is discarded at publish time by `.task(id:)`/generation checks.

---

## 9. Failure model

| Failure | Response |
|---|---|
| Malformed Mermaid syntax | `MermaidWebRenderer` surfaces Mermaid's own thrown parse error via `evaluateJavaScript`'s result as `.invalidSyntax(message)`. Preview shows an inline diagnostic; Export attaches an `.error` `ContributionDiagnostic` and leaves the fence's authored source untouched in the exported document (same rejection-ladder behavior `DerivedContentComposer` already gives every other failed contribution). |
| Render exceeds timeout | `.timedOut`. Same diagnostic treatment as malformed syntax. The offscreen web view that timed out is not reused for a subsequent render without being reset first (§11) — a hung page must not silently poison the next diagram. |
| Output exceeds size ceiling | `.outputTooLarge`. Treated as a failure, not truncated output — a truncated SVG is not a valid diagram and must not be displayed or exported as one. |
| Offscreen web view fails to initialize (e.g. WebKit process launch failure) | `.rendererUnavailable`. Preview shows the same inline diagnostic as any other failure; Export attaches the same `.error` diagnostic. The renderer retries pool initialization on the *next* render call rather than permanently failing for the rest of the app session. |
| Cancellation (task superseded) | Not a user-visible failure at all — handled entirely by §8's discard-at-publish mechanism, never reaches a diagnostic. |
| Cache corruption | Not applicable in the traditional sense — the cache is in-memory only (§11), never persisted to disk, so there is no corrupted-state-on-relaunch scenario to guard against; the worst case is a cache miss, which only costs a re-render. |
| Document closed / block removed while its render is in flight | The `MermaidDiagramBlockView` instance backing that render is deallocated with its block; SwiftUI's `.task(id:)` cancellation fires the moment the view leaves the hierarchy. The underlying `evaluateJavaScript` call may still run to completion inside the actor (§8) but its result is simply never observed by anything. |
| Rapid repeated edits (adversarial) | Covered by §8's debounce-before-dispatch — a pathological typing-speed test is an evidence item (§14), not a new mechanism. |
| Oversized/pathological diagram source | Bounded the same way a normal invalid diagram is: the timeout and output-size ceiling both apply regardless of *why* rendering is slow or produces too much output. No separate "is this suspiciously large" pre-check is needed beyond the existing `PreviewBlock.oversizeByteThreshold`/`isOversize` check, which already prevents a 64KB+ fence from reaching Textual/this epic's rendering path at all (an oversize Mermaid fence falls back to the existing oversize plain-text rendering, identically to an oversize block of any other kind — no new code path). |
| Export failure (budget exceeded, e.g. many large diagrams in one document) | Handled entirely by `DerivedContentComposer`'s existing `ExportResourceBudget` rejection — unmodified, already-tested behavior (§2.1). |
| Mermaid version/behavior change on a future bundled-JS update | Out of scope for this epic's Definition of Done, but named as a residual risk (§18): a previously-exported document's re-render after a future Mermaid version bump could theoretically produce a visually different diagram from the same source. This is the same category of risk RELEASE_HARDENING.md §1.2 already names for "a future renderer-version change" and requires only that authored source is never destroyed, not that rendering is version-pinned forever. |

---

## 10. Security and trust boundary

This is the epic's most consequential new decision and the one section
with no direct precedent to lean on (§2.1) — every existing `WKWebView`
use in this codebase runs with JavaScript disabled.

**What is trusted, what is not.** Diagram *source text* is
user-authored document content — the same trust level as the rest of the
Markdown document, i.e., trusted in the sense that MacDown 2 does not
treat the document owner as an attacker, but *not* trusted to be safe to
interpret as arbitrary executable script or safe to let interact with
anything outside its own rendering sandbox. The bundled Mermaid
JavaScript itself is first-party, shipped code — trusted at build time —
but still executes against untrusted-shaped input (arbitrary diagram
text), so the containment below exists regardless of how much the
diagram text itself is trusted.

**Layered containment, each independently sufficient where possible —
not a single control relied on alone:**

1. **No network access, architecturally, not by policy.** The rendering
   `WKWebView`'s configuration uses `websiteDataStore = .nonPersistent()`
   (mirroring `PDFExportAdapter`) and loads the bundled Mermaid harness
   via `loadFileURL(_:allowingReadAccessTo:)` scoped exactly to the
   package resource directory containing the harness — not
   `loadHTMLString` with an inlined multi-megabyte JS string, which
   would be needlessly slow to construct per render; the harness page
   is loaded once per pooled web view and reused (§11). A
   `WKNavigationDelegate` cancels any navigation whose destination is
   not that exact same local file (mirroring `PDFNavigationDelegate`'s
   existing "cancel off-scheme navigation" pattern) — Mermaid's own
   rendering call never navigates anywhere, so this is defense in depth
   against a hypothetical bug or future Mermaid behavior, not something
   normal operation should ever trigger.
2. **A restrictive Content-Security-Policy inside the harness page
   itself**, distinct from `PDFExportAdapter`'s CSP (which forbids
   scripts entirely — this page's whole purpose is running one):
   `default-src 'none'; script-src 'self'; style-src 'unsafe-inline' 'self'; connect-src 'none'; img-src data:; object-src 'none'`.
   `connect-src 'none'` blocks `fetch`/`XMLHttpRequest`/`WebSocket` even
   if the bundled Mermaid code ever attempted one (it does not, in
   normal operation) — network isolation enforced at two independent
   layers (this, and point 1) rather than one.
3. **Mermaid's own `securityLevel: 'strict'` configuration**, set in the
   harness's initialization call, disables `click` interaction
   directives and sanitizes HTML inside diagram labels. This matters
   specifically because the *output* (SVG) is later spliced into
   exported HTML and can, for PDF export, pass back through a *second*
   `WKWebView` (`PDFExportAdapter`) — that second web view already has
   JS disabled and a strict export CSP, but `securityLevel: 'strict'` at
   generation time means no script-bearing content is ever placed in
   the SVG in the first place, rather than depending solely on a later
   consumer to neutralize it.
4. **A bounded execution timeout** (§6's `timeout: Duration`, default 5
   seconds) around the `evaluateJavaScript` call, implemented the same
   way `PDFNavigationDelegate`'s existing 30-second load watchdog is
   implemented (a race between the JS call and a `Task.sleep`), so a
   pathological or accidentally-infinite-loop diagram source can never
   hang a render indefinitely.
5. **A bounded output size** (§6, §9) rejects an SVG result above a
   fixed byte ceiling before it is ever cached, displayed, or exported.
6. **The offscreen web views are never added to any visible view
   hierarchy** and never receive user input, keyboard focus, or
   accessibility focus — they exist purely as an off-screen computation
   backend, identically in spirit to how `PDFExportAdapter`'s web view
   exists purely to drive `NSPrintOperation` and is never shown either.

**What capability the trusted (first-party) Mermaid code receives:**
exactly the ability to run inside its own sandboxed, network-isolated
page and return a string via `evaluateJavaScript`'s completion — nothing
else. It has no access to the file system beyond its own bundled harness
directory (via `allowingReadAccessTo:`, which grants *read* access to
that one directory and nothing else — not write access, not access to
any user document path), no access to the document's file location, and
no access to any other part of the app.

---

## 11. Resource and performance budgets

- **Render timeout: 5 seconds per diagram** (unit/package-benchmark
  enforced — `MermaidWebRendererTests` asserts a deliberately
  slow/hanging fixture is cut off at this bound, not left to the OS's
  own process-level limits).
- **Output ceiling: `MermaidDiagramCache.Budget.standard.maxAggregateSVGBytes`
  applies per-entry too** — a single diagram's SVG larger than a fixed
  per-entry ceiling (proposed: 2MB; confirmed or adjusted during Slice 2
  implementation against real Mermaid output sizes for representative
  large diagrams, not asserted as final here) is rejected as
  `.outputTooLarge` rather than cached or displayed.
- **Cache: 128 entries / 8MB aggregate by default** (§6). This is a
  package-benchmark-verified ceiling (`MermaidDiagramCacheTests` proves
  eviction actually happens and stays within budget under adversarial
  cache pressure), not yet a whole-app Release measurement — a
  representative-document memory measurement with many large diagrams
  is a named Definition-of-Done item (§18), evidenced at the Release-app
  layer, not inferred from the package benchmark alone.
- **Pool size: 2 offscreen web views by default.** This bounds how many
  Mermaid renders can be genuinely concurrent; additional render
  requests queue for a free pool slot rather than spawning unbounded web
  views. The exact number is a tuning parameter to be confirmed against
  real multi-diagram-document dogfooding (§14), not a value with
  independent architectural significance.
- **Typing responsiveness.** No user-visible typing latency is
  introduced by this epic for edits *outside* a Mermaid fence — Mermaid
  rendering only ever runs in response to a Mermaid block's own source
  changing (§8), never as a side effect of unrelated document edits. For
  edits *inside* a Mermaid fence, the existing 150ms parse debounce
  already bounds how often a render can even be requested; the render
  itself happening off-`MainActor` (§8) means even a slow render cannot
  make typing feel laggy, only make that one diagram's own picture
  update a little later.
- Evidence layer for each of the above is named explicitly in §14 — no
  package benchmark in this epic is presented as proof of whole-app
  Release-build latency or memory behavior.

---

## 12. Accessibility and localisation impact

- Every diagnostic string this epic introduces ("This diagram could not
  be rendered", any timeout/size-limit message) is a `String` literal
  subject to the same eventual E16 string-freeze/localisation process as
  any other new user-facing string — not hard-coded English exempted
  from that process.
- The rendered SVG itself is Mermaid's own output and generally carries
  no meaningful accessible-text structure beyond whatever `<title>`/
  `<desc>` elements Mermaid itself emits (which vary by diagram type and
  are not something this epic controls). Where the native display view
  can attach an accessibility label, it uses the diagram's raw Mermaid
  source text as a fallback accessible description — the same
  "accessibility source fallback" pattern this epic's own issue
  explicitly names as a goal ("Accessibility source fallback/labelling
  where practical") and the same limitation category EPIC-19 already
  documented for equations ("Preview accessibility labelling for a
  rendered equation is confirmed NOT attachable via any public Textual
  API" — Mermaid's native display view is this epic's own code, not a
  third-party package's sealed view, so a source-text fallback label
  *is* practical here, unlike that specific Math limitation).
- No new localisation-affecting product behavior (diagram content itself
  is user-authored, not app UI copy).

---

## 13. Export and interoperability

- **Reopened**: a Mermaid fence is ordinary fenced-code Markdown text;
  reopening the document re-renders it from source exactly as it did the
  first time, with no persisted render state to go stale or migrate.
- **Copied or pasted**: copying a Mermaid fence copies its Markdown
  source (standard text-editing behavior, unchanged by this epic).
  Copying the *rendered diagram* itself (journey 4) copies the SVG
  markup, not a screenshot/bitmap.
- **Stored in source control**: identical to any other Markdown content
  — a diff of a changed diagram shows the changed diagram-description
  text, which is the entire point of keeping Mermaid a text format
  instead of a binary one.
- **Exported to HTML/PDF**: via the shared `ExportDerivedContribution`
  path (§7.1) — the same document consumed by Preview is what Export
  renders, per the epic's own acceptance criteria, not a
  separately-triggered second render pass with different inputs (both
  Preview and Export call the same shared `MermaidDiagramCache`
  instance where the app wires them to the same renderer, §5).
- **Opened when the renderer is unavailable** (e.g., a future platform
  where WebKit is unavailable, or `MermaidWebRenderer` fails to
  initialize entirely): the document opens normally; every Mermaid fence
  falls back to the same "could not be rendered" diagnostic state as any
  other render failure (§9) — never blocks opening the document, never
  silently drops the fence's text.

---

## 14. Test and evidence matrix

| Requirement | Evidence |
|---|---|
| `MermaidFenceScanner` correctly finds fences, case-insensitive language matching, ignores non-mermaid fences | `Diagrams` package unit tests |
| `MermaidDiagramCache` hits/misses correctly, evicts under budget pressure, does not cache failures | `Diagrams` package unit tests with a fake `MermaidDiagramRendering` |
| `MermaidContribution.run` produces correct `ContributionResult`s, isolates per-fence failures, respects cancellation | `Diagrams` package unit tests, mirroring `MathContributionTests`' structure |
| `MermaidWebRenderer` actually renders real Mermaid source to real SVG via a real offscreen `WKWebView` | `DiagramRendering` package integration tests (real WebKit, not a fake) — contingent on Slice 0's spike (§17) confirming this runs reliably under `swift test`; if not, these move to `MacDown2Tests` |
| Timeout is actually enforced | `DiagramRendering` test with a deliberately pathological/slow fixture, asserting completion within a bounded wall-clock margin past the configured timeout |
| Output-size ceiling is actually enforced | `DiagramRendering` test with a fixture engineered to produce oversized SVG output |
| Export produces valid inline SVG in the final HTML; PDF export includes it correctly | `ExportService`/app-target integration test extending the existing E12 fidelity-corpus style tests |
| Preview renders a Mermaid fence as a native vector image, not a WebView | App-target test asserting the rendered view type/structure, plus a manual Release dogfood pass (below) |
| Malformed source shows a diagnostic and recovers after correction | App-target test driving `MermaidDiagramBlockView` through both states |
| Superseded renders never publish stale content | App-target test simulating rapid `.task(id:)` identity changes |
| Unchanged diagrams are not re-rendered on unrelated edits | App-target/integration test asserting cache-hit behavior across a simulated unrelated document edit |
| Offline behavior | Manual Release dogfood: disable networking at the OS level, confirm rendering, copy, and export all still work |
| Real Release-app dogfood of every acceptance criterion | Manual pass against the built Release app, in the same style as EPIC-19's own Slice 3 dogfood note — required before this epic's Definition of Done is considered met, not merely package tests |
| Large/adversarial diagram documents don't degrade typing responsiveness | Manual + integration measurement against a representative large document, per §11 |

---

## 15. Adversarial corpus

- Empty Mermaid fence.
- Syntactically invalid Mermaid source (unbalanced arrows, unknown
  diagram type keyword, truncated mid-token — simulating a
  partially-typed edit).
- A deeply nested/very large diagram (many nodes and edges) designed to
  stress both the timeout and the output-size ceiling independently.
- A Mermaid source string that attempts to use `click` interaction
  directives or embed raw HTML/script-like content inside a node label —
  verifying `securityLevel: 'strict'` actually suppresses it in the
  output SVG.
- Rapid sequential edits to the same fence (simulating fast typing)
  verifying only the final version's render is ever shown.
- A fence whose language tag changes between `mermaid` and something
  else across an edit sequence (verifying clean transition in both
  directions, no leftover diagram state).
- Two or more Mermaid fences in one document, one valid and one
  invalid, verifying failures are isolated per-fence.
- A document containing enough distinct, valid Mermaid diagrams to
  exceed `ExportResourceBudget`'s existing aggregate-byte ceiling,
  verifying the existing E12 budget rejection behavior (§2.1) applies
  correctly to this new contribution too, not just to Math.
- Cache-pressure test: enough distinct diagrams rendered in sequence to
  force eviction, verifying the evicted entries correctly re-render
  (rather than erroring) if requested again.

---

## 16. Expected files and symbols

**New:**

- `Packages/MacDownKit/Sources/Diagrams/` — `MermaidFence.swift`,
  `MermaidFenceScanner.swift`, `MermaidRenderContext.swift`,
  `RenderedMermaidDiagram.swift`, `MermaidRenderError.swift`,
  `MermaidDiagramRendering.swift`, `MermaidDiagramCache.swift`,
  `MermaidContribution.swift`.
- `Packages/MacDownKit/Tests/DiagramsTests/`.
- `Packages/MacDownKit/Sources/DiagramRendering/` — `MermaidWebRenderer.swift`,
  the bundled Mermaid JS asset and minimal harness HTML under a
  `Resources/` subdirectory, a navigation-delegate/security-policy file.
- `Packages/MacDownKit/Tests/DiagramRenderingTests/`.
- `MacDown2/MermaidExportRegistry.swift`.
- `MacDown2/MermaidPreviewRenderer.swift`.
- `MacDown2/MermaidDiagramBlockView.swift` (the SwiftUI view rendering a
  `RenderedMermaidDiagram` as a native vector image plus the
  loading/diagnostic states) — placed in the app target, *not* the
  `Preview` package, so that only the one small `BlockView` branch
  below needs to live inside the package boundary; the view's actual
  content can stay app-owned like every other app-target UI file.

**Modified, narrowly:**

- `Packages/MacDownKit/Package.swift` — two new target declarations.
- `Packages/MacDownKit/Sources/Preview/TextualMarkdownPreview.swift` —
  one new defaulted initializer parameter on `TextualMarkdownPreview`,
  and one new `else if` branch inside private `BlockView.body`
  recognizing `block.kind == .codeBlock(language:)` with a
  case-insensitive `"mermaid"` match. No other line in this file
  changes; the existing `isOversize`/`StructuredText` branches and all
  scroll-sync/measurement code above `BlockView` are untouched.
- `MacDown2/DocumentEditorSplitView.swift` — thread the shared
  `MermaidPreviewRenderer` instance into `TextualMarkdownPreview`'s call
  site, mirroring how `theme`/`linkResolver` are already threaded.
- `MacDown2.xcodeproj`/`project.yml` (regenerated via `xcodegen`, per
  EPIC-19's own documented lesson: edit `project.yml`, never hand-edit
  the generated, gitignored `.xcodeproj` directly) — link the two new
  package products into the `MacDown2` and `MacDown2Tests` targets.
- `planning/epics/README.md`, `README.md` — epic status update on
  completion.

**Must not change:** `Packages/MacDownKit/Sources/ExportService/DerivedContentComposer.swift`,
`ExportDerivedContribution.swift`, `Packages/MacDownKit/Sources/Contributions/ContributionRegistry.swift`'s
`.standard` list, `MacDown2/PDFExportAdapter.swift`'s existing
JS-disabled configuration, `MacDown2/PreviewContributionAdmission.swift`'s
existing `.html` rejection. If implementation discovers any of these
must change, stop and escalate per `EPIC_STANDARD.md` §6 rather than
silently widening scope.

---

## 17. Implementation slices

### Slice 0 — Spike: confirm the WebKit rendering approach works in a package-test host

**Goal:** answer, with a written result, whether a `WKWebView` inside a
plain SPM package (`swift test`, no app bundle) can reliably load local
HTML/JS content and complete an `evaluateJavaScript` call within a
bounded time, off the main run loop of a test process.

**Dependencies:** none.

**Allowed area:** a throwaway spike target/script; nothing in this
slice ships as part of the epic's real code.

**Tests/evidence:** a minimal reproduction — load a trivial local HTML
page with an inline script, call `evaluateJavaScript`, assert the result
comes back within a few seconds, run this under `swift test` at least a
handful of times to rule out flakiness.

**Decision output required:** either "`DiagramRendering` is a `swift
test`-testable package target as designed in §5" (no further change to
this document), or "the renderer moves to the app target, tested only
via `xcodebuild`/`MacDown2Tests`" (an as-built note is added to this
document at that point, the same way EPIC-19's Slice 1-2 as-built note
recorded its own analogous discovery).

**Stop condition:** if `WKWebView` cannot be driven reliably from
*either* a package-test host or the app-target test host within a
reasonable investigation, stop and escalate — this would mean the
entire technical approach in §1 needs owner-level reconsideration, not
a slice-level workaround.

### Slice 1 — `Diagrams` package: model, scanner, cache, contribution

**Goal:** every type in §6's `Diagrams` section, fully unit tested
against a fake `MermaidDiagramRendering`, with zero WebKit dependency.

**Dependencies:** none (does not require Slice 0's answer).

**Allowed area:** `Packages/MacDownKit/Sources/Diagrams/`,
`Packages/MacDownKit/Tests/DiagramsTests/`, `Package.swift`.

**Tests/evidence:** the full `Diagrams` row set in §14 that does not
require real WebKit.

**Verification:** `swift test` at the package level.

**Stop condition:** if `Contributing`'s actual current signature or
`ContributionResult`'s actual current fields differ from §1/§6's
description of them on the real implementation baseline, stop — that
means this baseline has drifted since this document was written and the
contract needs re-confirming, not silent adaptation.

### Slice 2 — `DiagramRendering` package: the real renderer

**Goal:** `MermaidWebRenderer` per §6/§10/§11, with the bundled Mermaid
JS asset and harness, fully implementing timeout, output-size ceiling,
and the security containment in §10.

**Dependencies:** Slice 0's decision output; Slice 1.

**Allowed area:** `Packages/MacDownKit/Sources/DiagramRendering/`,
its `Tests/`, `Package.swift`.

**Tests/evidence:** the `DiagramRendering` rows in §14, including the
adversarial security/timeout/size-limit cases from §15.

**Verification:** `swift test` (or `xcodebuild test`, per Slice 0's
outcome).

**Stop condition:** if Mermaid's actual JS API for programmatic
rendering (`mermaid.render(...)` or its current equivalent in whichever
Mermaid version is vendored) does not return SVG synchronously/via a
callback in the shape this document assumes, stop and reconcile this
section before continuing — do not silently invent a different
integration shape without recording why here.

### Slice 3 — Export wiring

**Goal:** `MermaidExportRegistry.swift`, added to `standardForExport`;
end-to-end HTML/PDF export of a real diagram.

**Dependencies:** Slice 1, Slice 2.

**Allowed area:** `MacDown2/MermaidExportRegistry.swift`,
`MacDown2/project.yml`/regenerated project (target linkage only).

**Tests/evidence:** the export rows in §14.

**Verification:** `xcodebuild` Debug + Release build; export-fidelity
integration tests.

**Stop condition:** if `ExportContributionAdapter`'s representation
switch has changed shape since §2.1's description, stop — a compiler
error here is the intended signal (§2's note that the switch has no
`default:` case deliberately), not something to route around.

### Slice 4 — Preview wiring

**Goal:** the `TextualMarkdownPreview`/`BlockView` change in §16,
`MermaidDiagramBlockView`, `MermaidPreviewRenderer`, threaded through
`DocumentEditorSplitView.swift`.

**Dependencies:** Slice 1, Slice 2.

**Allowed area:** exactly the files named "Modified, narrowly" and
"New" in §16 that pertain to Preview.

**Tests/evidence:** the Preview rows in §14.

**Verification:** `xcodebuild` build + app-target tests; a first manual
live check that a real Mermaid fence renders in the running app.

**Stop condition:** if `BlockView`'s current structure has diverged from
the exact shape quoted in this document's research (§ research quoted
above from `TextualMarkdownPreview.swift` as read on the stated
baseline), stop and re-read the live file before proceeding — do not
assume the quoted structure still matches without checking.

### Slice 5 — Adversarial hardening pass

**Goal:** every fixture in §15 exercised for real, any gap found fixed
before proceeding.

**Dependencies:** Slices 1-4.

**Allowed area:** any file already touched by prior slices; no new
architectural area.

**Tests/evidence:** §15 in full.

**Stop condition:** if a fixture reveals that `securityLevel: 'strict'`
does not actually suppress a scripting vector this document assumed it
would, stop — this is a §10 trust-boundary assumption failing, which
`EPIC_STANDARD.md` §6 names explicitly as a mandatory escalation, not
something to patch around locally.

### Slice 6 — Real Release-app dogfood and Definition of Done

**Goal:** every acceptance criterion in issue #45 and every journey in
§3, manually verified against the actual Release build, in the style of
EPIC-19's own Slice 3 dogfood note.

**Dependencies:** Slices 1-5.

**Tests/evidence:** §14's manual/Release rows.

**Stop condition:** none — this slice either closes the epic or
documents exactly what remains, per §18.

---

## 18. Definition of Done and residual risk

> **As-built note (Slice 6, 2026-09-17):** implementation-complete with
> real, non-mocked automated evidence at the package and app-integration
> level; the two items marked unchecked below are genuinely open, not
> silently waived. `xcodebuild test` execution of `MermaidPreviewUITests`
> and a live visual dogfood pass were both attempted (the former twice)
> and both blocked by this session's own environment (`Timed out while
> enabling automation mode`; no interactive full-screen approval
> available for a screenshot) — not by a defect in the implementation.
> `MermaidPreviewUITests` is real, committed, and confirmed to build and
> link correctly (`build-for-testing`), matching this project's own
> established bar for UI-test evidence when execution isn't available
> (`.github/workflows/ci.yml` documents `MacDown2UITests` as build-only
> on hosted CI for the identical reason — no interactive macOS 26 GUI
> session). Tracked as `unverified` in `planning/RELEASE_EVIDENCE.md`,
> never inferred as passed.

Done when:

- [x] Every acceptance criterion in issue #45 is demonstrated against
      the real Release build, not only package tests — with one
      exception: live in-app visual confirmation, blocked as above.
- [x] All package/unit/integration tests in §14 pass; `swift test` and
      `xcodebuild test` are both green. (`MermaidPreviewUITests` itself
      is real and correct but could not be *executed* this session —
      see the as-built note above; every other row in §14 ran for real.)
- [x] `swiftformat --lint` / `swiftlint lint --strict` pass.
- [x] Debug and Release builds of the app and CLI succeed.
- [x] The adversarial corpus in §15 has been exercised for real, not
      only described (Slice 5; two items — rapid-edit races and
      language-tag transitions — are covered by SwiftUI's own `.task(id:)`
      guarantees rather than a bespoke test, per that PR's own reasoning).
- [ ] A representative large/multi-diagram document has real Release-app
      performance evidence (§11), not only a package benchmark — open;
      Slice 5 added a real 12-node/subgraph package-level test, but a
      whole-app, multi-diagram-document Release measurement has not been
      run.
- [x] `planning/RELEASE_EVIDENCE.md` gets a new E20 row reflecting real,
      current evidence — not asserted as passing without having been
      observed, consistent with every other row's own standard.
- [x] `planning/epics/README.md` and `README.md` describe E20 as
      actually shipped, including any as-built deviations from this
      document, in the same style as EPIC-19's own as-built notes.
- [x] Known limitations below are filed as GitHub issues where they
      could reasonably need future work, not left implicit (the
      theme-color wiring gap: issue #79).

Consciously deferred / residual risk:

- Character-level source↔diagram navigation (§1, §3 journey 4's
  reduced scope) — block-level only, matching every other content type.
- A future Mermaid version bump could change a diagram's rendered
  appearance for previously-exported documents on re-render (§9's last
  row) — inherent to depending on an actively-developed upstream
  renderer; mitigated only by the fact that authored source never
  changes, per RELEASE_HARDENING.md §1.2.
- The exact per-entry SVG byte ceiling and pool size (§11) are
  provisional numbers pending real-diagram calibration during Slice 2/6
  — not asserted as final in this document.
- Mermaid's interactive/`click` features are deliberately never exposed
  (§1, §10) — this is a permanent product scope decision, not temporary
  deferral, and should not reappear as a "missing feature" complaint
  without an explicit, separate product decision to revisit it.
- Theme colors reach `MermaidRenderContext` for real but the renderer
  doesn't act on them yet — every diagram renders with Mermaid's own
  default theme regardless of the app's active theme. Filed as
  [#79](https://github.com/Joncallim/macdown_2/issues/79), P3.
- `MermaidPreviewUITests`' execution and a live visual dogfood pass
  remain open, blocked by this session's environment rather than the
  implementation (see the Slice 6 as-built note above and
  `planning/RELEASE_EVIDENCE.md`'s E20 row) — worth a genuine local-Mac
  run and a look at the actual rendered diagram before this epic is
  treated as fully release-proven, not merely implementation-complete.
