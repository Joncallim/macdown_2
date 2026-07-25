# EPIC-07 Implementation Plan — Native Markdown preview: Textual rendering, split view, scroll sync

> **Issue:** #8 — [EPIC-07] Native Markdown preview
> **High-level spec:** `planning/epics/EPIC-07-native-preview.md` (scope/acceptance are binding, including the #28 amendments).
> **Branch:** `epic/07-native-preview` → PR into `master`.
> **Depends on:** E06 as built (`MarkdownEngine` parse actor, `MarkdownDocument`, `SourceMap`), E04 as built (`EditorCore` TextKit 2 stack, `EditorView.onScrollChange`).
> **Intended pipeline:** implemented by **Kimi K2.7** in a single pass, reviewed by **DeepSeek**. Written so that **neither has to guess intent or fill gaps.** Read **§2 (native-first stance)**, **§3 (decisions)**, and **§4.2 (API contract)** before writing code — reviews reject on §3 and §4.
>
> **New third-party dependency (pinned, wrapped):** `gonzalezreal/textual` 0.5.0 (MIT). Textual types never appear in any public signature, and only **two files** in the package may `import Textual` (§3.D1), per `AGENTS.md`.
>
> **⚠️ Pre-flight:** `master` is currently **red on the lint job** — two SwiftLint `identifier_name` violations (`u`, `u8` in `MacDown2/Packages/MacDownKit/Tests/MarkdownEngineTests/FrontMatterTests.swift:128,131`, introduced by the E06 merge). **The first commit on this branch renames those two variables** (any descriptive ≥3-char names) so CI is green before epic work lands. Note it as a drive-by in the PR description.

---

## 1. Ground rules (binding, carried from E00–E06)

1. **macOS 26.0 only. No availability checks.** Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete`, zero warnings.
2. **Package holds the logic; the app holds glue.** Unlike E06 (package-only), this epic **does** touch the app target — the split view, commands, and store wiring live there. Everything testable headless (slicing, diffing, scroll-sync math, layout persistence, link resolution) lives in the package and runs under `swift test` in CI.
3. **Placeholders are deleted, not wrapped.** `Preview.MarkdownPreviewBody` and `MarkdownEngine/LegacyPlaceholderRenderer.swift` are removed in this epic (E06 D6 earmarked the renderer "deleted in E07"). The HTML `WKWebView` path and `PreviewSecurity` stay untouched.
4. **Tests: Swift Testing (`@Test`)** for everything in the package. The one XCUITest (`PreviewLayoutUITests`) is **build-for-testing only in CI** (`.github/workflows/ci.yml` precedent) and run locally on macOS 26; every acceptance gate that must run in CI is a `swift test`.
5. **Graceful totality.** A block Textual cannot render degrades to a plain-text block; an oversized block never reaches Textual at all. No crash path through third-party code is acceptable (§3.D10).
6. **Out of scope (hard):** HTML format preview changes (E11), export (E12), outline UI (E08 consumes `headings` independently), `PreviewContribution`/Mermaid (E14), settings UI (E13 — options/theme defaults are hardcoded here), column-precise sync (block-granular by design, E06 D4), chasing Textual versions (pin exact 0.5.0).
7. **Tabs are native windows (as-built E03).** One window = one document, so "per-tab layout state" means **per window/document**, persisted through the existing `WorkspaceSession`/`TabRecord` store. All stores (`MarkdownParseStore`, sync controller) are per-window, created and torn down with `WindowController` — mirroring `editorStore`/`highlightStore`.
8. **Strict-concurrency cleanliness extends to the new seams:** every new public type is `Sendable` or `@MainActor`-isolated; Textual's `@MainActor MarkupParser` is only ever invoked from view bodies (already main-actor).

---

## 2. Native-first stance (required reading)

| Concern | **Native API to use** | Third-party (only where native is absent) |
|---|---|---|
| Split container & divider | **SwiftUI `HStack` + `DragGesture`** with a fraction `Binding` (the existing `ContentAreaView` split is already hand-rolled). **Not** `NSSplitViewController`/`HSplitView` — neither exposes a divider-position binding or collapsible-mode switching without introspection, and we need both for persistence (D6). | — |
| Preview scrolling & anchors | **`ScrollView` + `LazyVStack` + `ScrollViewReader.scrollTo(_:anchor:)`**; **`scrollPosition(id:)` + `scrollTargetLayout()`** (macOS 14+, free on our macOS 26 floor) for top-visible-block observation. | — |
| Observation / reactivity | **Observation framework** (`@Observable`, `@MainActor`) — matches E02–E06. | — |
| Debounce / concurrency | **E06's `MarkdownParseSession`** (Task cancel-and-restart); no new timers, no Combine. | — |
| Timing (perf tests) | **`ContinuousClock`**. | — |
| Link opening | **SwiftUI `openURL` environment** + `NSWorkspace` for file/HTTP URLs. | — |
| Markdown rendering | *No native equivalent* — `AttributedString(markdown:)` alone retains no block structure or GFM tables; SwiftUI `Text(markdown:)` is inline-only. | **Textual 0.5.0** (`StructuredText`, Prism highlighting, math, attachment loaders). |

**Why Textual despite its limitations (re-verified 2026-07-24, D4 of the plan stands):** it is the only maintained native-SwiftUI Markdown renderer with GFM tables, code highlighting, math, and selection. MarkdownUI is maintenance-mode (rejected in MIGRATION_PLAN §5). Its three hard constraints **shape this architecture** (D2):

- **Full re-parse on the main actor on every string change** (Textual #47) — feeding it a whole document per keystroke blows the 150 ms budget and competes with typing.
- **~100 KB / ~200-block freeze-crash ceiling** (Textual #23, `EXC_BAD_ACCESS` in its eager block stack) — a daily editor cannot ship a crash path on ordinary READMEs.
- **No block-structure, source-range, or geometry API** — scroll sync cannot come from Textual at all (their own issue #25 shows no anchor mechanism).

---

## 3. Key architectural decisions (review anchors — do not silently deviate)

### D1 — Textual is confined to two files behind our own view protocol
`TextualMarkdownPreview.swift` (the view) and `PreviewMarkupParser.swift` (the parser-fallback conformance) are the **only** files that may `import Textual`. App code and the rest of `Preview` never see a Textual type; the `MarkdownPreviewing` protocol (§4.3) is the documented contract a future renderer swap must satisfy. **Rationale:** MIGRATION_PLAN §5 dependency policy + AGENTS.md wrapping rule; Textual is pre-1.0 with breaking renames between minors (0.3.0 already renamed public API). **Rejected:** re-exporting Textual views directly (leaks churn into the app target).

### D2 — Block-sliced rendering: our own `LazyVStack` of per-block `StructuredText`, NOT one whole-document `StructuredText`
The preview renders **one SwiftUI view per top-level `MarkdownBlock`** from the E06 parse. Each view receives that block's source, sliced from the **original full text** with `sourceMap.utf16Range(ofLines: block.lineRange)` (E06 D4: original-source lines, zero offset arithmetic — front matter included in the numbering, excluded from rendering because blocks never intersect it). Slicing is at **top-level block granularity only** — a list keeps its items, a quote its contents, inside one slice. This single decision is what lets Textual meet the acceptance criteria:

- **150 ms budget:** unchanged blocks keep equal `PreviewBlock` values → the `Equatable` block view skips body re-evaluation → Textual re-parses **only the slice that changed** (ms-scale). Laziness caps realization to the viewport either way.
- **Scroll sync:** every block has a stable `ScrollView` anchor id — something Textual cannot provide (§2).
- **Graceful degradation:** fallback is per block (D10); a pathological construct ruins one block, not the document.
- **Crash ceiling bounded:** each `StructuredText` sees a small slice; the §2 #23 ceiling is additionally hard-guarded by D10's size cap.

**Known trade-offs (accepted, flagged on the PR):** (a) text **selection is scoped per block** — cross-block selection is impossible with per-block `StructuredText` (Textual's selection is view-local); MacDown 1 allowed full-document selection. (b) Inter-block spacing is ours to tune (`.textual.blockSpacing` + own padding), so the preview may differ subtly from continuous typesetting. (c) Cross-block constructs (link reference definitions) need explicit handling — D3. **Rejected:** whole-document `StructuredText` + proportional scroll (fails the 150 ms budget at scale, hits the #23 crash ceiling, and "within one viewport" is unachievable with fraction-only mapping on code/image-heavy documents).

### D3 — Slice identity is ordinal; diffing is value-equality; laziness bounds the cost
`PreviewBlock.id` is the block's **ordinal index** in document order. Edit-in-place (the dominant keystroke) never changes ordinals, so only the edited block's value changes and only its view re-renders. Block insert/delete (Return key) shifts ordinals and ids — `LazyVStack` bounds realization to visible blocks, so even a full id shift costs one viewport's re-render, not the document's. `PreviewRenderModelBuilder` is a pure function `(text, MarkdownDocument) -> PreviewRenderModel` doing **one O(n) pass** over the text (incremental UTF-16 index advancement — never per-block `String.Index` rescans, which would be O(n·B)). It also collects **single-line link reference definitions** (`^[ ]{0,3}\[[^\]]+\]:\s*\S+`) from the whole document and appends them to every slice, so `[ref]`-style links resolve inside isolated block slices (documented limitation: single-line definitions only; multi-line title continuations are out of scope for v1). **Rejected:** content-hash ids (duplicate-content blocks collide; ordinal+laziness is simpler and sufficient), per-block String.Index conversion (quadratic).

### D4 — Scroll sync: block anchors + leader latch; pure math in `ScrollSyncMap`
- **Editor → preview (primary):** `EditorView.onScrollChange` → `EditorTextSystem.topVisibleUTF16Offset` (D5) → `sourceMap.line(atUTF16Offset:)` → `ScrollSyncMap.targetBlock(forEditorTopLine:)` → `ScrollViewReader.scrollTo(id:, anchor: .top)`, **non-animated**.
- **Preview → editor:** `scrollPosition(id:)` on the preview's `ScrollView` (+ `.scrollTargetLayout()` on the `LazyVStack`) yields the topmost visible block id → `ScrollSyncController.previewDidScrollToBlock` → `block.lineRange.lowerBound` → `sourceMap.utf16Range(ofLines:)` → `EditorTextSystem.scrollToVisible(utf16Range:)` (D5).
- **No feedback loops:** `ScrollSyncController` (§4.3) holds an `isApplyingSync` flag around every programmatic slave scroll (whose resulting callbacks are then ignored) **and** a **leader latch**: the pane that most recently produced a user scroll event owns sync for `leaderTimeout` (250 ms, injected clock); events from the other pane are suppressed meanwhile.
- **Monotonic:** both mapping functions are non-decreasing in their inputs (property-tested); block-granular alignment is what "within one viewport of the matching block" means.
- **No height measurement anywhere** in v1 — anchors + `scrollPosition` replace the preference-key/height-table design entirely. If `scrollPosition(id:)` observation proves too coarse on macOS 26 at implementation time, fall back to §10.2 — do not improvise a third design.

### D5 — EditorCore gains exactly two additive members
`EditorTextSystem.topVisibleUTF16Offset: Int` and `EditorTextSystem.scrollToVisible(utf16Range: NSRange)` (§4.4). Nothing else in EditorCore changes; `EditorView` is untouched (`onScrollChange` already exists). **Rejected:** routing scroll math through the app target with `NSView` introspection (breaks the module boundary the store pattern established).

### D6 — Layout state lives in Workspace, persisted as one additive optional `TabRecord` field
`PreviewLayoutMode` (`.editorOnly`, `.split(fraction:)`, `.previewOnly`) is defined in **Workspace** (session-persisted tab state is Workspace's job; Preview never sees it). `WorkspaceTab` gains a transient `previewLayout: PreviewLayoutMode?`; `TabRecord` gains `previewLayout: PreviewLayoutMode?`. **`WorkspaceSession.currentVersion` stays 1**: optional-field decode is nil on old JSON, unknown-key ignore on old app — both directions safe (write the compat test, §7). Live mutation goes through `TabStore.setPreviewLayout(_:)` which calls `persist()` (the existing 300 ms debounce short-circuits during drags). `WindowCoordinator.saveSession()` copies `tab.previewLayout` into its snapshot `TabRecord`s; `TabStore+Session.restoreTab` maps it back. Default when nil: `.split(fraction: 0.5)`. Fraction is clamped to `0.15...0.85` at the model layer so a restored or dragged value can never hide a pane. **Rejected:** persisting via `UserDefaults` (wrong granularity — state is per document), version bump (unnecessary for additive optionals).

### D7 — Parse wiring: per-window `MarkdownParseStore`, 100 ms debounce, paired text publication
`WindowController` creates a `MarkdownParseStore` next to `editorStore`/`highlightStore` and evicts all in `windowWillClose`. `ContentAreaView` feeds it: `parseNow(text)` on identity change (document open/switch), `session.textDidChange(newText)` from `.onChange(of: document.text)`. Two small additive `MarkdownEngine` changes:
1. `MarkdownParseSession` publishes `publishedText: String?` **in the same mutation** as `document` — consumers always slice the exact text that was parsed (a newer binding value would misalign `lineRange` slicing transiently).
2. `MarkdownParseStore` gains `debounce: Duration = .milliseconds(150)` in its initializer, passed to created sessions; production wiring uses **100 ms** (D8). Defaults preserve all E06 behavior/tests.

### D8 — The 150 ms budget is 100 ms debounce + ≤50 ms parse+slice+render
The issue's "typing updates preview within 150 ms" is impossible with a 150 ms debounce alone. Interpretation (flagged §10.1): **100 ms debounce (D7) + ≤50 ms engine-parse + slice-diff + changed-block render** on representative documents. CI gate follows the E05/E06 convention: `swift test` documentation ceilings with measured values logged (CI debug, contended); the real budget is verified locally in release and recorded on the PR. The §8 MIGRATION_PLAN measurement caveat applies — README claims must not exceed what was measured.

### D9 — Preview theme derives from editor theme chrome + appearance, approximately
`PreviewTheme` (our value type, §4.2) maps `Theme.chrome.background/foreground` + `ThemeAppearance`. The view layer applies: `.gitHub` structured style as the base, container background/foreground from the theme, appearance-matched highlighter theme (`.default`/`.plain`). This is an **approximation** — full preview themes are O4/E13 territory. **Rejected:** mapping tree-sitter token styles onto Prism `TokenType`s now (large surface, zero acceptance criteria need it).

### D10 — Degradation is per block and deterministic; oversized blocks never reach Textual
`PreviewMarkupParser` conforms to Textual's `MarkupParser`, wraps `AttributedStringMarkdownParser.markdown`, and on **any** throw returns the slice as a plain-text `AttributedString` (unstyled block, never a crash, never an empty hole). Independently, the builder flags slices **> 64 KB UTF-8** as `isOversized`; the block view renders those as plain monospaced wrapping `Text` — a hard, testable bound on the §2 #23 crash surface. **Rejected:** try/catch around view bodies (impossible), trusting Textual's internal `try? ?? .init()` (renders an invisible empty block — worse than plain text).

---

## 4. Architecture

### 4.1 Module boundary & dependency graph

```
Preview  (REWRITE of the markdown path; imports SwiftUI, MarkdownEngine, Themes, FileCore [existing],
          Textual [internal to 2 files, D1])
  ├── PreviewBlock / PreviewRenderModel / PreviewRenderModelBuilder   (slicing + diffing, pure, D3)
  ├── ScrollSyncMap                                                   (pure mapping math, D4)
  ├── ScrollSyncController                (@MainActor @Observable leader latch, D4)
  ├── PreviewLayoutMode → lives in **Workspace** (D6 — NOT here)
  ├── PreviewTheme                                                  (Theme → style values, D9)
  ├── PreviewLinkResolver                                            (pure URL resolution)
  ├── MarkdownPreviewing / PreviewScrollTarget                      (the seam, D1)
  ├── TextualMarkdownPreview                     (the SwiftUI view; imports Textual — file 1 of 2)
  ├── PreviewMarkupParser                        (MarkupParser fallback; imports Textual — file 2 of 2)
  ├── PreviewRouter / PreviewKind / PreviewSecurity                 (kept, unchanged)
  └── ~~MarkdownPreviewBody~~                                       (DELETED, ground rule 3)

Workspace  (+ PreviewLayoutMode; WorkspaceTab/TabRecord + previewLayout; TabStore.setPreviewLayout)
EditorCore (+ EditorTextSystem.topVisibleUTF16Offset / scrollToVisible(utf16Range:))
MarkdownEngine (+ MarkdownParseSession.publishedText; MarkdownParseStore debounce param)
App target (WindowController + parseStore; ContentAreaView split rewrite; WorkspaceCommands + layout
            commands; WindowCoordinator session snapshot field)
```

Dependency directions unchanged: `Preview → {MarkdownEngine, Themes, FileCore}`; `Workspace → FileCore`; app imports all. **Workspace must not depend on Preview** (hence D6's type placement).

### 4.2 Public API contract — value types (package, `Sendable` + `Equatable` throughout)

```swift
import Foundation
import MarkdownEngine
import Themes

/// One renderable slice: the source lines of one top-level MarkdownBlock.
public struct PreviewBlock: Identifiable, Equatable, Sendable {
    /// Ordinal index in document order (D3). Stable across edit-in-place.
    public let id: Int
    /// 1-based lines of the ORIGINAL source (E06 D4).
    public let lineRange: ClosedRange<Int>
    /// The block's source slice, with the document's single-line link
    /// reference definitions appended (D3) so `[ref]` links resolve.
    public let markdown: String
    /// True when the slice exceeds the 64 KB UTF-8 guard (D10): the view
    /// renders plain monospaced text and Textual never sees it.
    public let isOversized: Bool
}

/// The preview's render input. A new value per published parse.
public struct PreviewRenderModel: Equatable, Sendable {
    public let blocks: [PreviewBlock]
    /// The MarkdownDocument.revision this model was built from.
    public let revision: Int
}

/// Pure builder. One O(n) pass over `text` (D3) — incremental UTF-16 index
/// advancement, never per-block index conversion.
public enum PreviewRenderModelBuilder {
    /// `text` MUST be the exact string the document was parsed from
    /// (`MarkdownParseSession.publishedText`, D7). Slices are clamped by
    /// `SourceMap.utf16Range(ofLines:)`; malformed input clamps, never crashes.
    public static func makeModel(text: String, document: MarkdownDocument) -> PreviewRenderModel
}

/// Editor-theme-derived preview styling. Textual style mapping happens in
/// the view layer (D1/D9); this type never mentions Textual.
public struct PreviewTheme: Equatable, Sendable {
    public var background: ThemeColor
    public var foreground: ThemeColor
    public var isDark: Bool
    public init(theme: Theme)   // maps chrome.background/foreground + appearance
}

/// Pure link resolution for the preview's openURL handler.
public enum PreviewLinkResolver {
    /// Relative URLs resolve against `baseURL` (the document's directory).
    /// Returns nil for URLs that should not be opened (e.g. bare anchors —
    /// in-preview heading jumps are out of scope for v1).
    public static func resolve(_ url: URL, baseURL: URL?) -> URL?
}
```

```swift
// Workspace module (D6):

/// Editor/preview arrangement for one document. Codable for session
/// persistence; fraction is clamped so no pane can vanish.
public enum PreviewLayoutMode: Codable, Sendable, Equatable {
    case editorOnly
    case split(fraction: Double)   // editor width fraction, clamped 0.15...0.85
    case previewOnly

    public static let defaultMode: PreviewLayoutMode = .split(fraction: 0.5)
    public var showsEditor: Bool { get }
    public var showsPreview: Bool { get }
    /// Returns a copy with any fraction clamped to 0.15...0.85.
    public func clamped() -> PreviewLayoutMode { get }
}
```

### 4.3 Public API contract — sync + view seam

```swift
/// Pure scroll-sync mapping (D4). No SwiftUI/AppKit — fully unit-testable.
/// Built from the render model (lineRanges only; no heights in v1).
public struct ScrollSyncMap: Equatable, Sendable {
    public struct BlockLayout: Equatable, Sendable {
        public let blockID: Int                     // == PreviewBlock.id
        public let lineRange: ClosedRange<Int>    // original-source lines
    }
    public let layouts: [BlockLayout]

    public init(model: PreviewRenderModel)

    /// Editor → preview: block to align to the preview top when the editor's
    /// top visible ORIGINAL-source line is `line`. The block containing
    /// `line`, else the nearest PRECEDING block, else the first block; nil
    /// iff there are no blocks. Non-decreasing in `line` (property-tested).
    public func targetBlock(forEditorTopLine line: Int) -> Int?

    /// Preview → editor: the original-source line a block starts at
    /// (clamped to known blocks); the caller scrolls the editor to it.
    public func editorTopLine(forBlockID id: Int) -> Int?
}

/// Owns sync direction and feedback suppression (D4). One per window.
@MainActor @Observable
public final class ScrollSyncController {
    public enum Leader: Sendable, Equatable { case editor, preview }

    public private(set) var activeLeader: Leader?
    /// True around programmatic slave scrolls; callbacks re-entrantly return nil.
    public private(set) var isApplyingSync: Bool

    /// `now` is injectable for leader-timeout tests; production uses Date.init.
    public init(leaderTimeout: Duration = .milliseconds(250),
                now: @escaping @Sendable () -> Date = Date.init)

    public private(set) var map: ScrollSyncMap
    /// Rebuilds the map when a new render model is published.
    public func renderModelDidChange(_ model: PreviewRenderModel)

    /// User scrolled the EDITOR. Returns the preview target blockID, or nil
    /// when suppressed (preview-led within the timeout, or applying sync).
    @discardableResult
    public func editorDidScroll(topLine: Int) -> Int?

    /// User scrolled the PREVIEW to top block `blockID`. Returns the editor
    /// target original-source line, or nil when suppressed.
    @discardableResult
    public func previewDidScrollToBlock(_ blockID: Int) -> Int?

    /// Wrap every programmatic slave scroll in begin/end (scrollTo /
    /// scrollToVisible). Non-reentrant: begin while applying is a no-op.
    public func beginApplyingSync()
    public func endApplyingSync()
}
```

**Latch semantics (exact, testable):** an event is *suppressed* iff `isApplyingSync`, or `activeLeader` is the other pane and `now() - lastEventTime < leaderTimeout`. Otherwise the event's pane becomes `activeLeader`, `lastEventTime` updates, and the mapped target is returned. `renderModelDidChange` resets `activeLeader` to nil (document edits re-open sync).

```swift
/// A programmatic scroll request for the preview. `nonce` makes repeated
/// targets for the same block distinct (Equatable views would otherwise
/// skip the onChange).
public struct PreviewScrollTarget: Equatable, Sendable {
    public let blockID: Int
    public let nonce: Int
    public init(blockID: Int, nonce: Int)
}

/// The preview pane contract (D1). The only conformer in this epic is
/// TextualMarkdownPreview; the app constructs the concrete type and never
/// imports Textual. The protocol exists so a renderer swap touches Preview
/// internals only.
public protocol MarkdownPreviewing: View {
    init(model: PreviewRenderModel,
         theme: PreviewTheme,
         baseURL: URL?,
         scrollTarget: PreviewScrollTarget?,
         onUserScroll: @escaping @MainActor (Int) -> Void)
}

/// The Textual-backed preview (D2). Public so the app can construct it;
/// every Textual reference stays inside this file + PreviewMarkupParser.swift.
public struct TextualMarkdownPreview: MarkdownPreviewing { ... }
```

**View internals (binding, implement exactly):**
- `ScrollViewReader` → `ScrollView { LazyVStack(alignment: .leading, spacing: 0) { ForEach(model.blocks) { PreviewBlockView(block:theme:baseURL:) } } .scrollTargetLayout() }`, `.scrollPosition(id:)` observed → `onUserScroll(topBlockID)` **after** controller suppression is checked at the call site (the view always reports; the controller decides).
- `.onChange(of: scrollTarget)`: `beginApplyingSync()` → `proxy.scrollTo(target.blockID, anchor: .top)` via a non-animated `Transaction` → `endApplyingSync()`.
- `PreviewBlockView` **must be `Equatable`** (`==` on block, theme, baseURL only — D2's re-render avoidance depends on it; never capture the controller or other changing state).
- Per block: `isOversized` → plain `Text(block.markdown)` monospaced, wrapping; else `StructuredText(block.markdown, parser: PreviewMarkupParser())` with `.textual.structuredTextStyle(.gitHub)`, `.textual.textSelection(.enabled)`, `.textual.highlighterTheme(theme.isDark ? .default : .default)` (map in one place; record the 0.5.0 preset names actually used), `.textual.imageAttachmentLoader(.image(relativeTo: baseURL))` **only when baseURL != nil**, math via `syntaxExtensions: [.math]` (verify the 0.5.0 spelling; record on PR).
- Links: `.environment(\.openURL, OpenURLAction { url in … PreviewLinkResolver.resolve(url, baseURL: baseURL) … NSWorkspace.shared.open(resolved) … })`. http(s) and resolved file URLs open externally; unresolved → `.handled` no-op.

### 4.4 EditorCore addition contract (exact)

```swift
extension EditorTextSystem {
    /// UTF-16 offset of the first character at the top of the clip view.
    /// 0 when the text view is not mounted in a scroll view.
    /// Implementation: convert the clip-view bounds origin into text-view
    /// coordinates (accounting for textContainerInset), then
    /// `layoutManager.textLayoutFragment(for: point)` → fragment start
    /// location → UTF-16 offset via the content storage. Ensure viewport
    /// layout first (`ensureLayout(for:)` on the visible frame). If the
    /// point lookup returns nil (fragment not yet laid out), fall back to a
    /// proportional estimate: scrollOffset / contentHeight × utf16Length —
    /// sync prefers an approximate line over none. Verify the macOS 26
    /// TextKit 2 spelling at implementation time (§10.6).
    public var topVisibleUTF16Offset: Int { get }

    /// Scrolls so `utf16Range`'s start sits at the top of the viewport,
    /// clamped to content. Used for preview → editor sync; never animated.
    public func scrollToVisible(utf16Range: NSRange)
}
```

### 4.5 Threading / concurrency model

- `ScrollSyncController`, `MarkdownParseSession/Store`, `TextualMarkdownPreview`: `@MainActor` (UI-adjacent, per-window lifetime).
- `PreviewRenderModelBuilder`, `ScrollSyncMap`, `PreviewTheme`, `PreviewLinkResolver`, `PreviewBlock`: pure value types/functions, `Sendable`, callable anywhere (builder runs on the main actor in practice — it is sub-ms on typical documents and the 1 MB perf test guards the ceiling).
- Textual's `@MainActor MarkupParser` is only constructed/called from view bodies (D1/D10). No Textual type crosses an isolation boundary.
- No locks, no queues, no Combine, no timers beyond the existing session debounce.

### 4.6 Failure matrix (graceful totality)

| Failure | Behaviour |
|---|---|
| Textual throws on a slice | `PreviewMarkupParser` returns plain-text `AttributedString` (D10) |
| Slice > 64 KB UTF-8 (pathological block) | `isOversized` → plain monospaced `Text`; Textual never invoked (D10) |
| `session.document == nil` (pre-first-parse) | Empty preview (transient — `parseNow` runs on open) |
| Empty document | Empty preview, no blocks |
| lineRange/text mismatch (defensive) | `utf16Range(ofLines:)` clamps; worst case a clamped slice, never a crash |
| Scroll target for a deleted block | `ScrollViewReader.scrollTo` on a missing id is a no-op; map is rebuilt on publish (D4) |
| Malformed image URL / missing baseURL | No attachment loader → alt-text rendering (Textual default) |
| Link that must not open (bare `#anchor`) | `PreviewLinkResolver` returns nil → `.handled` no-op |
| Restored layout fraction out of range | `PreviewLayoutMode.clamped()` at model layer (D6) |

### 4.7 App-target integration (exact wiring)

- **`WindowController`**: new `let parseStore = MarkdownParseStore(debounce: .milliseconds(100))` beside `editorStore`/`highlightStore`; pass into `WorkspaceShellView` → `ContentAreaView`; `parseStore.evictAll()` in `windowWillClose`.
- **`ContentAreaView`** (the `DocumentEditorSplitView` rewrite):
  - `let session = parseStore.session(for: identity)`; `.task(id: identity) { await session.parseNow(document.text) }`; `.onChange(of: document.text) { _, t in session.textDidChange(t) }`.
  - `@State private var renderModel`, updated in `.onChange(of: session.document)`: `renderModel = PreviewRenderModelBuilder.makeModel(text: session.publishedText ?? "", document: doc)`; `syncController.renderModelDidChange(renderModel)`.
  - `@State private var syncController = ScrollSyncController()` (per window — tab id is stable across Save As).
  - Layout `Binding`: `get { tab.previewLayout?.clamped() ?? .defaultMode }`, `set { model.tabStore.setPreviewLayout($0.clamped()) }`.
  - Split: `HStack` + `GeometryReader`; editor `EditorView(..., onScrollChange: { _ in editorScrolled() })` where `editorScrolled()` reads `editorStore.existingSystem(for: identity)?.topVisibleUTF16Offset` → `session.document?.sourceMap.line(atUTF16Offset:)` → `syncController.editorDidScroll(topLine:)` → on non-nil target, bump a `@State scrollTarget` (nonce++) consumed by the preview view. Divider: 5-pt hit strip, `DragGesture` → fraction = `x / width` clamped, written through the binding live; `onTapGesture(count: 2)` resets to `.defaultMode`. Modes conditionally include panes (the `EditorTextSystem` persists in the store, so unmount/remount is state-safe).
  - Preview pane switch stays on `PreviewRouter.previewKind(for:)`: `.markdown` → `TextualMarkdownPreview(model:theme:baseURL:scrollTarget:onUserScroll:)` with `baseURL = document.fileURL?.deletingLastPathComponent()`, `onUserScroll` → `syncController.previewDidScrollToBlock` → non-nil line → `editorStore…scrollToVisible(utf16Range: sourceMap.utf16Range(ofLines: line...line))` wrapped in `begin/endApplyingSync`. `.html` / `.none` unchanged.
  - Accessibility identifiers: `editor-pane`, `preview-pane`, `preview-divider` (the UI test depends on them).
- **`WorkspaceCommands`**: View-menu group — `Editor Only` / `Split` / `Preview Only` (set mode through the key window's tab store; checkmark on current) + `Toggle Preview` (cycles split ↔ editorOnly). Shortcut: record the final choice on the PR after checking conflicts against the existing table (⌘N/T/O/⇧O/S/⇧S/W, ⌃⇥, ⌘1-9, ⌃⌘S, ⌘⇧⌥D) — suggestion: ⌘⌥P (§10.4).
- **`WindowCoordinator.saveSession()`**: snapshot `TabRecord(..., previewLayout: tab.previewLayout)`. `TabStore.currentSession()` also maps it (the value is on the tab, unlike cursor/scroll). `restoreTab` maps record → tab. `WorkspaceSession.currentVersion` stays 1 (D6).
- **Deletion (same commit as the ContentAreaView rewrite):** `Preview.MarkdownPreviewBody` and `MarkdownEngine/LegacyPlaceholderRenderer.swift` (ground rule 3 — nothing may reference them afterwards).

---

## 5. File layout (exact)

```
MacDown2/Packages/MacDownKit/Sources/Preview/
  Preview.swift                  (keep PreviewModule/PreviewKind/PreviewRouter; DELETE MarkdownPreviewBody)
  PreviewSecurity.swift          (unchanged)
  PreviewBlock.swift             (PreviewBlock, PreviewRenderModel, PreviewRenderModelBuilder)
  ScrollSyncMap.swift
  ScrollSyncController.swift
  PreviewTheme.swift
  PreviewLinkResolver.swift
  MarkdownPreviewing.swift       (protocol + PreviewScrollTarget)
  TextualMarkdownPreview.swift   (view + PreviewBlockView; imports Textual — file 1 of 2)
  PreviewMarkupParser.swift      (imports Textual — file 2 of 2)

MacDown2/Packages/MacDownKit/Sources/Workspace/
  PreviewLayoutMode.swift        (NEW)
  WorkspaceSession.swift         (TabRecord + previewLayout)
  TabStore.swift                 (WorkspaceTab + previewLayout; setPreviewLayout)
  TabStore+Session.swift         (record ↔ tab mapping)

MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorTextSystem.swift   (+ D5 API)
MacDown2/Packages/MacDownKit/Sources/MarkdownEngine/
  MarkdownParseSession.swift     (+ publishedText)
  MarkdownParseStore.swift       (+ debounce init param)

MacDown2/Packages/MacDownKit/Tests/
  PreviewTests/Fixtures.swift              (inline builders: sync corpus, oversized, link-def variants,
                                            1 MB generator — mirror MarkdownEngineTests style)
  PreviewTests/PreviewBlockTests.swift
  PreviewTests/ScrollSyncMapTests.swift
  PreviewTests/ScrollSyncControllerTests.swift
  PreviewTests/PreviewLinkResolverTests.swift
  PreviewTests/PreviewThemeTests.swift
  PreviewTests/PreviewMarkupParserTests.swift
  PreviewTests/PreviewPerformanceTests.swift
  WorkspaceTests/PreviewLayoutModeTests.swift
  WorkspaceTests/TabStoreSessionTests.swift     (extend: layout round-trip, old-JSON compat)
  EditorCoreTests/EditorScrollAPITests.swift
  MarkdownEngineTests/SessionDebounceTests.swift (extend: publishedText pairing, store debounce pass-through)

MacDown2/MacDown2/
  WindowController.swift         (+ parseStore)
  ContentAreaView.swift          (split rewrite — the bulk of the app work)
  WorkspaceCommands.swift        (+ layout commands)
  WindowCoordinator.swift        (+ snapshot field)
MacDown2/MacDown2UITests/PreviewLayoutUITests.swift   (NEW — build-for-testing in CI)

README.md                        (status + module map: E06 engine and E07 preview no longer placeholders —
                                  fixes the E06-stale lines too)
```

---

## 6. Build-config changes (exact)

`MacDown2/Packages/MacDownKit/Package.swift`:

```swift
// dependencies: — ADD (pin exact per policy; MIGRATION_PLAN §5 says 0.5.x):
.package(url: "https://github.com/gonzalezreal/textual", exact: "0.5.0"),

// targets: — CHANGE Preview:
.target(name: "Preview", dependencies: [
    "MarkdownEngine", "Themes", "FileCore",
    .product(name: "Textual", package: "textual"),
]),
```

Textual's transitive deps (`swift-concurrency-extras`, `swiftui-math`) resolve automatically; record all resolved versions on the PR. **No `project.yml` change** (no new targets; the UITest file joins the existing target). **No `ci.yml` change** (`swift test` + build-for-testing already cover everything).

---

## 7. Test plan (mapped to issue #8 acceptance)

| # | Issue acceptance box | Test (CI = `swift test` unless noted) |
|---|---|---|
| 1 | Typing updates preview within 150 ms (measured, CI) | `PreviewPerformanceTests.pipelineWithinBudget`: session (`debounce: .milliseconds(100)`) + real engine, 1 MB fixture; measure `textDidChange` → document published → `makeModel` done; **documentation ceiling 10 s debug-CI** (E06 measured 2.34 s parse under contention; this adds slicing), duration logged. `swift test -c release` locally asserts the real ≤150 ms (D8) — numbers recorded on the PR. Plus `renderModelBuild1MB` (ceiling 2 s) and `renderModelDiffAfterEdit` (only the edited ordinal differs; ceiling 1 s) |
| 2 | Scrolling editor keeps preview within one viewport of the matching block on the fidelity corpus | `ScrollSyncMapTests`: synthetic corpus fixture (varied heights — tall code blocks, tables, image paragraphs); for EVERY original line, `targetBlock`'s lineRange contains the line or is the nearest preceding block; **monotonicity property** (sorted lines → non-decreasing targets); clamp tests (line 1, last line, blank-between-blocks, inside-front-matter). `ScrollSyncControllerTests`: latch suppression both directions, timeout expiry via injected `now`, `isApplyingSync` re-entrancy, leader reset on `renderModelDidChange` |
| 3 | Preview-only / editor-only / split persist per tab and across relaunch | `PreviewLayoutModeTests` (Codable round-trip, clamping, `showsEditor/showsPreview`); `TabStoreSessionTests` (record→tab→record; **old-JSON-without-field decodes to nil → `.defaultMode`**; version stays 1). `PreviewLayoutUITests` (local): toggle modes via menu, drag divider, terminate + relaunch, assert pane identifiers + restored fraction |
| 4 | Text selection, link clicking, and images work in preview | `PreviewLinkResolverTests` (absolute http(s), relative→baseURL, bare-anchor→nil, mailto). Selection/math/image-loader wiring: asserted by code-level review against §4.3's binding list + a manual verification checklist on the PR (Textual provides the mechanics; our package tests cannot drive its internals) + UI-test smoke: preview pane exists and shows rendered heading after typing fixture text |
| 5 | Textual failure degrades gracefully (plain block), never crashes | `PreviewMarkupParserTests`: parser wrapping a throwing input path returns the slice's plain text (inject a throwing parser at the seam; assert content equality, no throw). `PreviewBlockTests.oversizedSliceFlagged`: >64 KB slice sets `isOversized`, oversized content absent from any Textual-bound path (assert flag + view branch by inspection) |
| — | Slicing correctness | `PreviewBlockTests`: front-matter doc (first block slice excludes `---` lines, original line numbers), CRLF, emoji/surrogate pairs, no-trailing-newline, link-def collection (single-line only; appended to every slice), empty doc, doc that is only front matter |
| — | Engine additions | `SessionDebounceTests` additions: `publishedText == parsed text` after `parseNow` and after debounced publish; store passes injected debounce to new sessions (spy-timed) |
| — | EditorCore additions | `EditorScrollAPITests`: mount scroll graph exactly as `EditorView.makeNSView` does; assert `topVisibleUTF16Offset` tracks `scrollOffset` on a known document, and `scrollToVisible(utf16Range:)` moves the offset so the range start is at/near the viewport top |

House rules carried from E05/E06: `@Test`/`#expect` only; no `Task.sleep`-and-hope — await deterministic signals with bounded polling helpers in `Fixtures.swift`; no real `UserDefaults`; no fixture files on disk (inline builders).

## 8. Implementation order (suite green at every step)

1. **Lint fix** (§header): rename the two `FrontMatterTests` variables; confirm `swiftlint lint --strict` clean.
2. Workspace: `PreviewLayoutMode` + `TabRecord`/`WorkspaceTab`/`setPreviewLayout`/session mapping → WorkspaceTests.
3. MarkdownEngine: `publishedText` + store debounce param → extended SessionDebounceTests.
4. Package.swift dep (§6); resolve + record pins.
5. `PreviewBlock` + builder → `PreviewBlockTests` (slicing, link defs, oversized, perf fixture builders).
6. `ScrollSyncMap` → tests; `ScrollSyncController` → tests.
7. `PreviewTheme`, `PreviewLinkResolver` → tests.
8. `PreviewMarkupParser` + `TextualMarkdownPreview` + `MarkdownPreviewing` (the only Textual files) → parser tests; app builds against the concrete view.
9. EditorCore scroll API → `EditorScrollAPITests`.
10. App wiring: WindowController, ContentAreaView rewrite (+ placeholder deletions), WorkspaceCommands, WindowCoordinator.
11. `PreviewPerformanceTests`; local release run → record numbers. `PreviewLayoutUITests`; local run. README update.

## 9. Validation (must all pass before review)

```bash
cd MacDown2/Packages/MacDownKit && swift build && swift test        # §7 gates
cd ../.. && xcodegen generate
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme macdown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build build-for-testing
swiftformat --lint MacDown2 && swiftlint lint --strict MacDown2
# Locally on macOS 26 (release budget + UI test — recorded on the PR):
swift test -c release --filter PreviewPerformanceTests
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' test -only-testing:MacDown2UITests/PreviewLayoutUITests
```

## 10. Open decisions (flag on the PR — do not silently resolve)

1. **Budget interpretation (D8):** 100 ms debounce + ≤50 ms pipeline = the issue's 150 ms. If review reads the box as "0 ms debounce", the only honest fix is reducing debounce further and re-measuring — surface the release numbers and decide on the PR.
2. **`scrollPosition(id:)` granularity (D4):** if observation proves too coarse for preview→editor on macOS 26, fall back to a height-preference-key + cumulative-offset binary search (sketched in the architecture pass, not built). Record which shipped.
3. **Remote images:** v1 allows http(s) images via Textual's loader (MacDown 1 parity). Privacy review may restrict to `file:` — flag on the PR.
4. **Toggle Preview shortcut** (suggest ⌘⌥P; verify no conflict with the existing command table).
5. **Textual 0.5.0 API spellings** used (`syntaxExtensions: [.math]`, highlighter preset names, `.image(relativeTo:)`): record the verified spellings + resolved transitive versions on the PR.
6. **TextKit 2 point-lookup spelling** for `topVisibleUTF16Offset` (§4.4) and whether the proportional fallback ever fires in practice — record findings.
7. **Cross-block selection limitation (D2):** per-block selection is a visible behavior change vs a hypothetical whole-document renderer. Product sign-off requested on the PR; if rejected, the alternative is whole-document `StructuredText` with the §2 constraints (150 ms + crash ceiling) unresolved.

## 11. Hand-off notes / known pitfalls (condensed — mirrored to the PR inline comment)

- **Textual is confined to two files** (D1). If you write `import Textual` in a third file, stop.
- **Slice from the ORIGINAL text via `sourceMap.utf16Range(ofLines:)`** — never subtract `bodyLineOffset` yourself (E06 D4); front matter simply has no blocks.
- **One O(n) slicing pass** with incremental index advancement (D3) — per-block `String.Index(utf16Offset:)` conversion is the quadratic trap the perf test guards.
- **`PreviewBlockView` must stay `Equatable`** on (block, theme, baseURL) exactly — capturing the controller or scroll state silently re-enables whole-document re-parse per keystroke (D2).
- **Pair slicing with `session.publishedText`, never the live binding** (D7) — the binding can be a revision ahead of the published document.
- **Every programmatic scroll is wrapped in `begin/endApplyingSync` and non-animated** (D4) — animated slave scrolls outlast the suppression window and re-trigger the latch as user events.
- **`WorkspaceSession.currentVersion` stays 1** (D6) — the compat test (old JSON → nil → default) is the proof; do not bump.
- **Fraction clamps to 0.15...0.85 at the model layer**, not just in the drag gesture (D6) — a restored value must never hide a pane.
- **Perf gates use the E05/E06 convention**: debug documentation ceilings in CI (measured values logged), real budgets verified locally in release and recorded on the PR (D8).
- **Delete the placeholders in the same commit as the ContentAreaView rewrite** (ground rule 3): `MarkdownPreviewBody` references `LegacyPlaceholderRenderer`; leaving either behind fails the build or the review.
