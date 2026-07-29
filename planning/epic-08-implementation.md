# EPIC-08 Implementation Plan — Content browser: heading outline of the active document

> **Issue:** #9 — [EPIC-08] Content browser: heading outline of the active document
> **High-level spec:** `planning/epics/EPIC-08-content-browser.md` (scope/acceptance are binding, including the #28 amendment that the sidebar is per window).
> **Branch:** `epic/08-content-browser` → PR into `master`.
> **Depends on:** E06 as built (`MarkdownDocument.headings` — E06 already flattens headings *for this epic*), E02 as built (`SidebarView`, `WorkspaceStateStoring`), E03 as built (native `NSWindow` tabs, per-window `WorkspaceModel`), E04/E07 as built (`EditorTextSystem` scroll seam).
> **Intended pipeline:** implemented by **Kimi K2.7** in a single pass, reviewed by **DeepSeek**. Written so that **neither has to guess intent or fill gaps.** Read **§2 (what E06 already gave us)**, **§3 (decisions)**, and **§4.2–4.4 (API contract)** before writing code — reviews reject on §3 and §4.
>
> **No new third-party dependencies.** The `OutlineUI` target and its `MarkdownEngine` dependency already exist in `Package.swift` and `project.yml` (E00 scaffolding); this epic fills the stub in. **No `Package.swift` change, no `project.yml` change, no `ci.yml` change.**
>
> **Pre-flight:** `master` is green — `swiftformat --lint MacDown2` and `swiftlint lint --strict MacDown2` both report 0 violations at `1be58c9`. No drive-by lint commit needed this time.
>
> **⚠️ Two latent defects on `master` block this epic's acceptance and are fixed here** (§2.2, §2.3). They are small, they are in-scope because E08 cannot meet its acceptance criteria without them, and they must land as their own early commits so review can see them separately from the feature.

---

## 1. Ground rules (binding, carried from E00–E07)

1. **macOS 26.0 only. No availability checks.** Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete`, zero warnings.
2. **Package holds the logic; the app holds glue.** Every decision the outline makes — tree shape, which section is current, what the keyboard traverses, what empty state to show — is pure, `Sendable`, headless, and tested under `swift test`. The app target owns only: view code, the wiring between the sidebar and the editor, and menu commands.
3. **Native controls, native behaviors.** `List` + `DisclosureGroup` + `ForEach.onMove`, `NSTextView.showFindIndicator(for:)` for the jump flash. No custom outline widget, no custom highlight overlay, no re-implementation of arrow-key traversal that AppKit already does.
4. **Tests are Swift Testing (`@Test`/`#expect`)**, not XCTest — except `MacDown2UITests`, where `XCUIApplication`-hosted bundles cannot `import Testing` (verified during E07; not a convention violation).
5. **Graceful totality.** Every input produces a defined outline state. There is no "this shouldn't happen" branch: a non-Markdown format, a zero-heading document, an unparsed document, and a stale line range all have named, tested outcomes.
6. **Tabs are native `NSWindow` tabs.** One window = one document = one outline. Do not reintroduce an in-app tab bar or a cross-window outline cache.

---

## 2. What E06 already gave us (required reading)

### 2.1 The outline is a *view* over an existing parse, not a new pipeline

E06 shipped `HeadingItem` with the comment *"A heading, flattened for E08."* `MarkdownDocument.headings` is already:

- **complete** — every `Heading` node in the tree, in document order, including Setext (swift-markdown produces the same `Heading` node type for `===`/`---` underlines as for `#`);
- **plain-text titled** — `heading.plainText`, markup stripped (`# Hello *world*` → `Hello world`), covered by `HeadingTests.headingTitlesArePlainText`;
- **code-block-free** — `HeadingTests.codeBlockDoesNotProduceHeadings` already proves acceptance box 1;
- **front-matter-free and original-source-lined** — `HeadingTests.headingLineRangesUseOriginalSource` proves a heading after 8 lines of YAML front matter reports `9...9`, i.e. **`lineRange` is already in ORIGINAL source lines** (E06 D4). **Never subtract `bodyLineOffset`.**

**Consequence:** this epic adds **no parse, no debounce, no store, no actor, and no new source-range index.** Acceptance box 2 ("outline updates within the same 150 ms debounce as the preview") is satisfied by construction because the outline reads the *same* `MarkdownParseSession` the preview reads. Any design that re-parses for the outline is wrong and will be rejected.

Acceptance box 3 ("switching tabs swaps outline instantly, cached per tab") is likewise satisfied by construction under the #28 amendment: a tab switch is a native window switch, and each window already owns its own `WorkspaceModel`, `MarkdownParseStore`, and view hierarchy. "Cached per tab" means "not recomputed on switch" — with per-window state there is nothing to recompute. State that must survive a switch (collapse set, navigation cursor) lives on a per-window controller, not in a shared dictionary.

### 2.2 Latent defect #1 — sidebar state does not persist at all today

`WorkspaceStateStore` (E02) persists `sidebarVisible` and `sidebarSectionExpanded` to `UserDefaults` and is fully tested. **The app never uses it.** `WindowCoordinator.makeWindowModel()` injects `NoOpStateStore()`, whose comment reads *"so sidebar state is independent per window"* — introduced by E03's native-tabs rewrite to stop windows fighting over one store. The result is that E02's persistence has been dead code since E03: sidebar visibility and section expansion reset on every relaunch.

E08's acceptance box 4 is **"Section order (folder above/below outline) persists across relaunch."** It cannot be met while the app writes to a no-op. The fix is one line at the injection site plus the read-through change in §4.5: **sidebar layout is an app-wide user preference, not per-window state.** Every window reads the same persisted values at construction; each window's *live* toggle stays independent (it is a stored `@Observable` property either way); the last window to change a value wins the persisted copy. That is the behavior a user expects, and it is exactly what the shared `UserDefaults` suite gives us for free.

`NoOpStateStore` is deleted in the same commit. (`NoOpSessionStore` stays — session persistence really is coordinator-owned, and that no-op is load-bearing.)

### 2.3 Latent defect #2 — `scrollToVisible(utf16Range:)` can raise on a stale range

```swift
// EditorCore/EditorTextSystem.swift — as built
public func scrollToVisible(utf16Range range: NSRange) {
    textView.scrollRangeToVisible(range)
}
```

The range is unclamped, and it is derived from the **parsed** document's `SourceMap` while `textView` holds the **live** text. Those disagree for up to one debounce interval. Delete a large trailing section and, inside that window, the parsed `SourceMap` still describes the longer document — an offset past `textView`'s current length reaches `NSTextContentStorage` and raises `NSRangeException`, which is not catchable in Swift.

Today this is hard to hit: E07's only caller is preview→editor scroll sync, and the user has to be scrolling the preview at the moment they delete text from the editor. **E08 makes it easy to hit** — an outline row is one click away at all times, and clicking one is the natural thing to do right after a big edit.

Fix in `EditorTextSystem` (§4.4): clamp against the live text length inside the seam, so *both* the E07 path and the new E08 path are covered, with a regression test that drives a deliberately-too-long range through the live method.

### 2.4 The always-on Markdown parse means the outline must be gated on format

`ContentAreaView`'s `.task(id: identity)` calls `parseSession.parseNow(text)` for **every** open document, regardless of format. A Python, Ruby, or shell file therefore has a populated `document.headings` in which every `# comment` line is an H1. Rendering that as an outline would be actively wrong, not merely useless.

Acceptance requires a *"graceful empty state for non-Markdown formats"* anyway, so the gate and the empty state are the same mechanism (D7). The gate is the app's, not the engine's: E08 does not change what gets parsed. (Whether non-Markdown documents should be Markdown-parsed at all is an E11 question — flagged in §10, not fixed here.)

---

## 3. Key architectural decisions (review anchors — do not silently deviate)

### D1 — `OutlineUI` depends on `MarkdownEngine` and nothing else
Not `Workspace`, not `Preview`, not `EditorCore`, not `FileCore`. The module receives `[HeadingItem]` and a format verdict, and publishes a tree, a current-item id, and a jump request. Every cross-module fact (what format the document is, how to move the caret, where to persist section order) is supplied by the app target. This keeps the module headless-testable and keeps `Package.swift` unchanged.

### D2 — Zero additional parsing; the outline is a pure function of `MarkdownDocument`
The outline reads the same `MarkdownParseSession` the preview reads (§2.1). No second `MarkdownParseStore`, no `parseNow` call from the sidebar, no separate debounce. If the implementation introduces any of those, the 150 ms acceptance box is being met by luck rather than by construction.

### D3 — Tree building is a stack fold; skipped levels attach, never synthesize
`H1 → H3` makes the H3 a child of the H1. No placeholder H2 node is invented, and the H3's `level` stays `3` (the authored level is preserved for display; only *nesting* is normalized). A document that opens at H3 and later has an H1 produces two roots — the H3 first, then the H1 — in document order. Depth is derived from position in the tree, never from `level`.

### D4 — Node identity is the flattened ordinal; per-node collapse state is in-memory only and **remapped** across re-parses
`OutlineItem.id` is the index of the heading in `MarkdownDocument.headings`. It is deterministic, allocation-free, and stable for the lifetime of a parse — which is all SwiftUI's diffing needs. Ordinals shift when a heading is inserted above, so **per-node collapse state is deliberately not persisted**: the epic requires the *sections* to persist their order, not each heading to remember its twist-down. Collapse state lives on the per-window controller and resets on relaunch. Do not invent slug-path identity to work around this; it collides on duplicate titles and buys nothing the acceptance criteria ask for.

Within a session, though, an ordinal is only meaningful relative to the parse that produced it. **Intersecting the old ids with the new tree's ids is not reconciliation** — insert one heading above a collapsed node and every id below it still exists, so nothing gets dropped and the collapse silently moves to the *next* section down. Same for the navigation cursor. So `update(...)` does a real remap, not a filter:

```swift
// OutlineUI/OutlineIdentityMap.swift — pure, no state, testable in isolation
/// Old ordinal → new ordinal across a re-parse. An old id maps to the new
/// heading with the same `(level, title)` whose ordinal is nearest to it;
/// each new ordinal is claimed at most once, and an old id with no match
/// is dropped.
public enum OutlineIdentityMap {
    public static func remap(
        _ ids: Set<Int>,
        from old: [HeadingItem],
        to new: [HeadingItem]
    ) -> Set<Int>

    public static func remap(_ id: Int?, from old: [HeadingItem], to new: [HeadingItem]) -> Int?
}
```

Nearest-ordinal match on `(level, title)` is a heuristic, and deliberately so: it is exact for the cases that actually happen while typing (insert above, delete above, edit a *different* heading's text), it degrades to "drop the id" rather than to "collapse the wrong section", and it costs one dictionary of candidate ordinals per rebuild. Retitling the collapsed heading itself still loses its collapse state — accepted, and the same thing every editor with an outline does. The controller therefore keeps the previous `[HeadingItem]` alongside its ids; that is the only new stored state this adds.

### D5 — "Current section" is one reference **offset**, last-event-wins
The current section is the **last heading whose `lineRange.lowerBound ≤ referenceLine`** — a binary search over the already-ordered heading list, `nil` when the line precedes every heading (a preamble before the first `#`). Where `referenceLine` comes from is the part that has to be got right.

The reference position is stored as a **UTF-16 offset, not a line**, and is translated to a line with the `SourceMap` of the *currently published* parse. This matters because the two disagree: the caret offset is live, the `SourceMap` is up to one debounce old, so translating at the event site (as an earlier draft of this plan did) freezes a line number that was computed against the previous document. Insert or delete lines above the caret and the tint sticks to the wrong section until the user happens to move the caret again. Storing the offset and re-translating inside `update(...)` costs one binary search per parse and is correct by construction.

Consequence for the app wiring (§4.7): the app forwards the raw UTF-16 offset it already has from both event sources and never calls `sourceMap.line(atUTF16Offset:)` itself.

`referenceOffset` is supplied by the app from whichever editor event fired most recently:
- **selection change** → `selectedRange.location`
- **scroll** → the top visible offset (the offset `EditorView.onScrollChange` already delivers)

Last-event-wins is the whole rule. There is no mode flag, no "is the caret on screen" heuristic, and no timer. The package tests the resolution as pure math; which offset arrives is app wiring.

**No echo latch is needed** (contrast E07's `ScrollSyncController`): clicking outline item *n* moves the caret into item *n*'s range, which resolves back to item *n*. The loop is idempotent and terminates in one hop. Do not port the latch pattern here — it would add state with nothing to suppress.

### D6 — The navigation cursor and the current section are two different things
`List`'s `selection` binding is the **user's** position — what arrow keys move and Return activates. The **current section** is where the caret happens to be, and it changes on every keystroke. Binding them together means typing yanks the user's arrow-key position out from under them mid-navigation.

They are separate properties on the controller and separate visual channels: `selection` gets the standard `List` selection highlight (free, native, correct); the current section gets a distinct non-selection treatment (accent-tinted, semibold label). Both may be on the same row; that is fine and expected.

### D7 — The outline is gated on format at the app layer, with typed empty states
`OutlineAvailability` is a four-case enum, not a `Bool` plus a nil check, so every state has an owned message and every state is testable:

| Case | Condition | Sidebar shows |
|---|---|---|
| `.ready` | Markdown, ≥1 heading | the tree |
| `.noHeadings` | Markdown, 0 headings | "No headings" |
| `.unsupportedFormat(name)` | non-Markdown | "No outline available" (issue's wording) |
| `.notParsed` | no document published yet | nothing (no flash of empty state on open) |

The Markdown verdict comes from `PreviewRouter.previewKind(for: document.format) == .markdown`, computed in the app (D1). It exists to keep `# comment` lines in source files out of the outline (§2.4), so it must gate the *tree*, not merely the label.

### D8 — `OutlineController` is per-window and owned by `WindowController`
Same lifetime and ownership shape as `editorStore` / `highlightStore` / `parseStore`: constructed in `WindowController.init`, passed into `WorkspaceShellView`, handed down to both `SidebarView` and `ContentAreaView`, torn down in `windowWillClose`.

It is **not** `@State` in a view (E07's `ScrollSyncController` gets away with that because only one subtree uses it; the outline is read by the sidebar and written by the content area, which are siblings), and it is **not** on `WorkspaceModel` (that would put SwiftUI view-state in the `Workspace` module and force `Workspace` to depend on `OutlineUI`). `WindowCoordinator` reaches it through the key `WindowController` for the ⌃⌘O command, exactly as `setPreviewLayout` reaches the key model today.

### D9 — Jump is one additive `EditorTextSystem` member; the flash is `showFindIndicator`
```swift
public func revealSelection(utf16Range range: NSRange, flash: Bool)
```
Select, ensure layout, scroll, then flash — in that order (§4.4). The "brief highlight" the issue asks for is `NSTextView.showFindIndicator(for:)`, the same animated callout AppKit's own Find uses. It is one line, it matches the platform, it respects Reduce Motion for free, and it disappears on its own. **Do not build a custom highlight overlay or a fading `NSLayoutManager` temporary attribute.**

Both this and `scrollToVisible(utf16Range:)` clamp against the live text length (§2.3).

### D10 — Section order persists as an ordered `[SidebarSection]`, reconciled against the enum
Persisted as `[String]` raw values. On read, the stored list is **reconciled**: unknown identifiers are dropped, and any `SidebarSection` case missing from the stored list is appended in `CaseIterable` order. A future epic adding a third section therefore gets a sane position without a migration, and a corrupt or truncated array can never hide a section. Reconciliation is a pure function in `Workspace` with its own tests.

### D11 — ⌃⌘O is a focus request counter, not a `@FocusState` reaching across modules
Menu commands live in the app's `Commands` tree; the outline `List` lives inside a window's view hierarchy. Rather than plumbing a `FocusState.Binding` across that gap, `OutlineController` exposes a monotonically-increasing `focusRequestID`; `SidebarView` observes it with `.onChange` and sets its local `@FocusState`. Same pattern as a one-shot event channel, no cross-module focus plumbing, trivially testable (the counter increments).

⌃⌘O is free in the current command table: ⌘O is Open, ⌘⇧O is Open Folder, ⌃⌘S is Toggle Sidebar.

---

## 4. Architecture

### 4.1 Module boundary & dependency graph

```
                 MarkdownEngine ────────────┐
                  (HeadingItem,             │
                   MarkdownDocument)        │
                                            ▼
                                       ┌─────────┐
                                       │OutlineUI│   ← this epic (fills the stub)
                                       └────┬────┘
                                            │  OutlineItem / OutlineTree /
                                            │  OutlineAvailability / OutlineController
                                            ▼
   Workspace ──────────────────▶  ┌──────────────────┐  ◀────────── EditorCore
   (SidebarSection order,         │   app target     │              (revealSelection)
    WorkspaceStateStoring)        │  SidebarView     │
                                  │  ContentAreaView │
                                  │  WorkspaceShell  │
                                  │  WindowController│
                                  │  WorkspaceCmds   │
                                  └──────────────────┘
                                            ▲
                                            │ previewKind(for:) — format verdict only
                                       Preview
```

`OutlineUI` imports `Foundation`, `Observation`, `SwiftUI` (for `OutlineController`'s `@Observable`), and `MarkdownEngine`. Nothing else. The arrows into the app target are one-way: no package module learns about the sidebar.

### 4.2 Public API contract — value types (`Sendable` + `Equatable` throughout)

```swift
// OutlineUI/OutlineItem.swift

/// One heading in the content browser. A value tree; children are copies.
public struct OutlineItem: Sendable, Equatable, Identifiable {
    /// Index of this heading in `MarkdownDocument.headings` (D4).
    public let id: Int

    /// The authored heading level, 1...6. Preserved for display; nesting depth
    /// is position in the tree, NOT this value (D3).
    public let level: Int

    /// Plain-text title from `HeadingItem.title`. May be empty (`##` alone);
    /// the view supplies the placeholder, the model does not invent one.
    public let title: String

    /// 1-based ORIGINAL-source lines (E06 D4). Jump targets use `lowerBound`,
    /// which for a Setext heading is the title line, not the underline.
    public let lineRange: ClosedRange<Int>

    public let children: [OutlineItem]

    public init(id: Int, level: Int, title: String, lineRange: ClosedRange<Int>, children: [OutlineItem] = [])
}

// OutlineUI/OutlineTree.swift

public enum OutlineTree {
    /// Stack fold over document-ordered headings (D3). O(n).
    /// - Skipped levels attach to the nearest shallower ancestor.
    /// - A heading shallower than everything before it starts a new root.
    /// - Empty input → empty output.
    public static func build(from headings: [HeadingItem]) -> [OutlineItem]

    /// Depth-first document order, honouring `collapsed`: a collapsed item is
    /// present, its descendants are not. This is exactly the sequence arrow
    /// keys traverse and the order `List` renders (D6).
    public static func visibleItems(_ items: [OutlineItem], collapsed: Set<Int>) -> [OutlineItem]

    /// Every id in the tree, depth-first. The *last* step of reconciling
    /// `collapsed` and the navigation cursor against a re-parse — it drops
    /// ids the new tree does not contain at all. It is **not** sufficient on
    /// its own; run `OutlineIdentityMap.remap` first (D4).
    public static func allIDs(_ items: [OutlineItem]) -> Set<Int>
}

// OutlineUI/OutlineSelection.swift

public enum OutlineSelection {
    /// The last heading starting at or before `line` (D5). Binary search over
    /// the document-ordered list. `nil` when `line` precedes every heading, or
    /// when `headings` is empty.
    ///
    /// Callers pass a line derived from the *current* parse's `SourceMap`;
    /// the controller owns that translation so a stale map can never leak in.
    public static func currentItemID(forLine line: Int, in headings: [HeadingItem]) -> Int?
}

// OutlineUI/OutlineAvailability.swift

/// Every outline state has a name and a message (D7, ground rule 5).
public enum OutlineAvailability: Sendable, Equatable {
    case notParsed
    case unsupportedFormat(formatName: String)
    case noHeadings
    case ready
}
```

### 4.3 Public API contract — controller

```swift
// OutlineUI/OutlineController.swift

/// Per-window outline state (D8). Main-actor isolated: it is written from
/// SwiftUI event handlers and read from view bodies.
@MainActor
@Observable
public final class OutlineController {
    public private(set) var items: [OutlineItem]
    public private(set) var availability: OutlineAvailability

    /// Where the caret/viewport is (D5). Distinct from `selectedItemID`.
    public private(set) var currentItemID: Int?

    /// The user's navigation cursor — bound to `List(selection:)` (D6).
    public var selectedItemID: Int?

    /// Collapsed nodes, by `OutlineItem.id`. In-memory only, and remapped
    /// through `OutlineIdentityMap` on every rebuild (D4).
    public var collapsedItemIDs: Set<Int>

    /// Set by `activate(_:)`; the app consumes it, drives the editor, and
    /// clears it. Same consume-and-clear contract as
    /// `ScrollSyncController.targetSourceLine`.
    public var pendingJumpLineRange: ClosedRange<Int>?

    /// Bumped by `requestFocus()` (D11). `SidebarView` observes and focuses.
    public private(set) var focusRequestID: Int

    public init()

    /// Rebuilds from a parse result. No-ops when `document.revision` matches
    /// the last applied revision AND the availability verdict is unchanged, so
    /// SwiftUI body evaluations are free.
    ///
    /// - Parameters:
    ///   - document: the session's latest `MarkdownDocument`, or nil.
    ///   - isMarkdown: the app's format verdict (D7). When false, `items` is
    ///     emptied and no tree is built, whatever `document.headings` holds.
    ///   - formatName: display name for `.unsupportedFormat`.
    ///
    /// On rebuild, in this order (D4, D5):
    /// 1. `collapsedItemIDs` and `selectedItemID` are **remapped** from the
    ///    previous headings to the new ones via `OutlineIdentityMap`, then
    ///    intersected with `OutlineTree.allIDs` as a backstop. Intersecting
    ///    alone is wrong: after an insert above, a stale ordinal still exists
    ///    and would hand the collapse to the section below it.
    /// 2. `currentItemID` is recomputed by translating the stored reference
    ///    **offset** through `document.sourceMap` — the map that just
    ///    arrived, never the one the offset was observed against.
    public func update(document: MarkdownDocument?, isMarkdown: Bool, formatName: String)

    /// Editor caret or viewport moved (D5) — a UTF-16 offset into the live
    /// text, *not* a line. Stored, translated through the current parse's
    /// `SourceMap`, and re-translated on the next `update(...)`.
    /// Cheap enough to call on every keystroke and every scroll tick.
    public func referenceOffsetDidChange(_ utf16Offset: Int)

    /// Outline row activated (click or Return). Publishes `pendingJumpLineRange`
    /// and moves `selectedItemID` to `id`.
    public func activate(_ id: Int)

    /// ⌃⌘O (D11).
    public func requestFocus()
}
```

**Threading:** everything above is `@MainActor`. The only concurrency in this epic is the parse that already exists in E06; E08 adds no `Task`, no actor, and no `await`. If the implementation reaches for one, that is a design error.

### 4.4 EditorCore addition contract (exact)

```swift
// EditorCore/EditorTextSystem.swift — one NEW member, one FIXED member

/// Places the selection at `range`, brings it on screen, and optionally
/// flashes the native find indicator over it (D9).
///
/// `range` is clamped to the live text (§2.3): the caller's range comes from a
/// parse that may lag the text view by one debounce interval, and an
/// out-of-bounds NSRange raises an uncatchable `NSRangeException`.
///
/// Order matters: select → ensure layout for the range → scroll → flash. The
/// indicator is drawn from laid-out geometry, so flashing before layout puts
/// it in the wrong place or drops it silently.
public func revealSelection(utf16Range range: NSRange, flash: Bool)

/// UNCHANGED SIGNATURE — now clamps `range` to the live text before
/// forwarding to `scrollRangeToVisible` (§2.3). This fixes the existing
/// E07 preview→editor path as well as feeding the new E08 path.
public func scrollToVisible(utf16Range range: NSRange)
```

Clamping is one shared private helper:

```swift
private func clamped(_ range: NSRange) -> NSRange {
    let length = (textView.string as NSString).length
    let location = min(max(range.location, 0), length)
    return NSRange(location: location, length: min(range.length, length - location))
}
```

Note `textView.string as NSString` for a UTF-16 length that matches the offsets `SourceMap` produces — `String.count` is the wrong unit and would under-clamp on any document containing emoji or CJK.

### 4.5 Workspace additions contract (exact)

```swift
// Workspace/WorkspaceModel.swift — SidebarSection gains ordering
public enum SidebarSection: String, Sendable, CaseIterable, Identifiable {
    case folder
    case outline
    public var id: String { rawValue }

    /// Order used on first launch and to fill gaps during reconciliation (D10).
    public static var defaultOrder: [SidebarSection] { allCases }

    /// Drops unknown identifiers, appends missing cases in `allCases` order.
    /// Total: any `[String]` maps to a complete, duplicate-free ordering.
    public static func reconcile(_ stored: [String]) -> [SidebarSection]
}

// Workspace/WorkspaceStateStore.swift — one added requirement
@MainActor
public protocol WorkspaceStateStoring {
    var sidebarVisible: Bool { get set }
    var sidebarSectionExpanded: [String: Bool] { get set }
    var sidebarSectionOrder: [String] { get set }   // NEW
}
```

No default implementation — all three conformers (`WorkspaceStateStore`, `NoOpStateStore` [deleted, §2.2], `FakeStateStore`) are updated explicitly. A protocol-extension default here would be a silent no-op trap for the next conformer.

`WorkspaceModel` mirrors the shape `sidebarVisible` already uses — **hydrate at init into a stored `@Observable` property, write through on mutation**:

```swift
public private(set) var sectionOrder: [SidebarSection]      // hydrated via reconcile()
public func moveSections(fromOffsets: IndexSet, toOffset: Int)   // writes through
```

`isSectionExpanded` / `setSectionExpanded` change from reading the store on every call to reading a stored dictionary hydrated at init. This is not gold-plating: the current implementation JSON-decodes a `UserDefaults` blob on **every SwiftUI body evaluation** of `SidebarView`, which the outline is about to make a much hotter path.

### 4.6 Failure matrix (graceful totality)

| Input | Outcome |
|---|---|
| Non-Markdown format | `.unsupportedFormat(name)`; `items` empty even though `headings` may be populated (§2.4) |
| Markdown, no headings | `.noHeadings`; "No headings" |
| No document published yet | `.notParsed`; sidebar section renders nothing (no empty-state flash on open) |
| Heading with empty title (`##`) | Item exists, `title == ""`; the **view** renders a dimmed "Untitled section" placeholder |
| Document opens at H3, later H1 | Two roots, document order preserved (D3) |
| H1 → H3 (skipped level) | H3 is a child of H1, `level` stays 3 (D3) |
| Heading inside a block quote / list item | **Included** — E06 emits them and has tests asserting so. Flagged as open decision §10.2 |
| Heading inside a fenced code block | Absent — guaranteed by E06, re-asserted in `OutlineTreeTests` as an E08-level regression |
| Jump range past live text end | Clamped in `EditorTextSystem`; caret lands at end of document, no raise (§2.3) |
| Re-parse drops the selected/collapsed id | Remapped, then intersected with `allIDs` in `update(...)`; no dangling selection |
| Re-parse *shifts* ordinals (heading inserted above) | `OutlineIdentityMap.remap` follows `(level, title)` to the new ordinal; collapse and cursor stay on the same heading, not the one below it (D4) |
| Collapsed heading is itself retitled | Its id drops; the node reopens. Accepted (D4) — the alternative is guessing |
| Caret moves, then the debounced parse lands | The stored reference **offset** is re-translated through the new `document.sourceMap`; the tint follows the caret without waiting for another editor event (D5) |
| `referenceOffset` before the first heading | `currentItemID == nil`; nothing tinted |
| `referenceOffset` past the live text end | `SourceMap.line(atUTF16Offset:)` already clamps to `lineCount`; last section stays current |
| Stored section order corrupt/partial | `reconcile` returns a complete ordering; no section can vanish (D10) |
| `moveSections` offset/indices out of range | `Workspace.reorder` ignores out-of-range sources and clamps the destination; a stale drag cannot trap (D10) |

### 4.7 App-target integration (exact wiring)

**`WindowController.swift`** — construct `let outlineController = OutlineController()` alongside the other stores; pass to `WorkspaceShellView`; nothing to evict in `windowWillClose` (it dies with the controller), but keep it in the same teardown block for symmetry with `parseStore`.

**`WorkspaceShellView.swift`** — accept `outlineController`; hand it to both `SidebarView` and `ContentAreaView`.

**`SidebarView.swift`** — rewritten around `model.sectionOrder`:
- `List(selection:)` bound to `outlineController.selectedItemID`, `.listStyle(.sidebar)`.
- `ForEach(model.sectionOrder)` + `.onMove { model.moveSections(fromOffsets:toOffset:) }` — on macOS, `onMove` inside a `List` enables drag reordering with no edit mode (acceptance box 4's "user-rearrangeable").
- Each section keeps its existing `DisclosureGroup` + `isSectionExpanded` binding.
- Outline rows: `OutlineGroup`-style recursive `DisclosureGroup` driven by `collapsedItemIDs`, indent by tree depth, `.tag(item.id)` for `List` selection, `.onTapGesture` → `activate(id)`, `.onKeyPress(.return)` on the `List` → activate `selectedItemID`.
- Current-section tint keyed off `outlineController.currentItemID` — **not** the selection (D6).
- `@FocusState private var outlineFocused: Bool` + `.onChange(of: outlineController.focusRequestID) { outlineFocused = true }` (D11).
- Accessibility identifiers for the UI test: `outlineSection`, `outlineRow-<id>`.

**`ContentAreaView.swift`** — the editor is here, so the wiring is here:
- `.onChange(of: parseSession.document)` already fires for the preview; extend the same handler to call `outlineController.update(document:isMarkdown:formatName:)` with `PreviewRouter.previewKind(for: document.format) == .markdown`.
- Add `onSelectionChange:` to the existing `EditorView(...)` call → `outlineController.referenceOffsetDidChange(range.location)`. **This callback is currently unwired**; adding it is the only editor-side change. Forward the raw offset — do **not** translate it here with the parsed `SourceMap` (D5); that map can be a debounce behind the caret and the frozen line is what makes the tint stick to the wrong section after an edit above.
- Extend the existing `handleEditorScroll(utf16Offset:)` to also call `referenceOffsetDidChange` with the same offset it already hands `scrollController` — one extra call, no new event source, no translation.
- `.onChange(of: outlineController.pendingJumpLineRange)` → `sourceMap.utf16Range(ofLines:)` → `editorStore.existingSystem(for: identity)?.revealSelection(utf16Range:flash: true)` → clear the pending value. Mirrors the existing `targetSourceLine` handler exactly.
- Jump target is `lineRange.lowerBound ... lineRange.lowerBound` (the heading line), not the whole `lineRange` — selecting the whole Setext heading including its underline reads as a bug.

**`WorkspaceCommands.swift`** — in the existing `CommandGroup(before: .sidebar)`, next to Toggle Sidebar:
```swift
Button("Focus Outline") { coordinator?.focusOutline() }
    .keyboardShortcut("o", modifiers: [.control, .command])
    .disabled(coordinator?.keyModel?.hasActiveDocument != true)
```

**`WindowCoordinator.swift`** — `func focusOutline()`: find the key `WindowController`, ensure `model.sidebarVisible` and the outline section are expanded (focusing a hidden list is a dead shortcut), then `outlineController.requestFocus()`.

**`NoOpStores.swift`** — delete `NoOpStateStore`; `makeWindowModel()` injects `WorkspaceStateStore()` (§2.2).

---

## 5. File layout (exact)

```
MacDown2/Packages/MacDownKit/Sources/OutlineUI/
  OutlineUI.swift              (keep the OutlineUI module enum; drop nothing else)
  OutlineItem.swift            (NEW)
  OutlineTree.swift            (NEW — build / visibleItems / allIDs)
  OutlineSelection.swift       (NEW — currentItemID(forLine:in:))
  OutlineIdentityMap.swift     (NEW — ordinal remap across a re-parse, D4)
  OutlineAvailability.swift    (NEW)
  OutlineController.swift      (NEW)

MacDown2/Packages/MacDownKit/Sources/Workspace/
  WorkspaceModel.swift         (SidebarSection + ordering; sectionOrder; moveSections;
                                reorder(_:fromOffsets:toOffset:);
                                hydrated expansion dictionary)
  WorkspaceStateStore.swift    (+ sidebarSectionOrder requirement + impl)

MacDown2/Packages/MacDownKit/Sources/EditorCore/
  EditorTextSystem.swift       (+ revealSelection; clamp both scroll members)

MacDown2/Packages/MacDownKit/Tests/
  OutlineUITests/Fixtures.swift             (NEW — inline heading corpora, mirrors
                                             MarkdownEngineTests/Fixtures.swift style)
  OutlineUITests/OutlineTreeTests.swift     (NEW)
  OutlineUITests/OutlineSelectionTests.swift(NEW)
  OutlineUITests/OutlineIdentityMapTests.swift (NEW)
  OutlineUITests/OutlineControllerTests.swift (NEW)
  OutlineUITests/OutlineUITests.swift       (existing stub test — keep or fold in)
  WorkspaceTests/SidebarSectionOrderTests.swift (NEW)
  WorkspaceTests/WorkspaceStateStoreTests.swift (extend: order round-trip, reconcile)
  WorkspaceTests/Fakes.swift                (+ sidebarSectionOrder)
  EditorCoreTests/EditorScrollAPITests.swift(extend: revealSelection, clamping regression)

MacDown2/MacDown2/
  WindowController.swift       (+ outlineController)
  WorkspaceShellView.swift     (+ pass-through)
  SidebarView.swift            (rewrite — the bulk of the app work)
  ContentAreaView.swift        (+ outline update / reference offset / jump handler)
  WorkspaceCommands.swift      (+ Focus Outline ⌃⌘O)
  WindowCoordinator.swift      (+ focusOutline(); real WorkspaceStateStore)
  NoOpStores.swift             (DELETE NoOpStateStore)
MacDown2/MacDown2UITests/OutlineNavigationUITests.swift  (NEW — build-for-testing in CI)

planning/epic-08-implementation.md   (this file)
README.md                            (status + module map: OutlineUI no longer a stub)
```

## 6. Build-config changes (exact)

**None.** `OutlineUI` is already a product in `Package.swift` with `dependencies: ["MarkdownEngine"]`, already an `OutlineUITests` test target, and already listed under the `MacDown2` app target in `project.yml`. The new UI test file joins the existing `MacDown2UITests` target. `ci.yml` needs no change — `swift test` and `build-for-testing` already cover everything added here.

If a `Package.swift` or `project.yml` diff appears in this PR, something has gone wrong.

## 7. Test plan (mapped to issue #9 acceptance)

| # | Issue acceptance box | Test (CI = `swift test` unless noted) |
|---|---|---|
| 1 | Headings inside fenced code blocks never appear in the outline | `OutlineTreeTests.codeBlockHeadingsAbsent`: real `ParseEngine` output for a corpus with `# Not a heading` inside a fence → `build(from:)` produces no matching item. Belt-and-braces over E06's own test — E08 owns the user-visible guarantee |
| 2 | Outline updates within the same 150 ms debounce as the preview | `OutlineControllerTests.sharesPreviewParseSession`: one `MarkdownParseSession` with an injected short debounce drives `update(...)`; assert exactly one parse produces both a populated `document` and a populated tree, and that `update` is a no-op when called again at the same `revision`. There is no second pipeline to time (D2) — the test proves *that*, which is the real acceptance |
| 3 | Switching tabs swaps outline instantly (cached per tab) | `OutlineControllerTests.perWindowStateIsIndependent`: two controllers, divergent collapse/selection/current state, no shared storage. Instantaneity is structural under #28 (D8/§2.1); `OutlineNavigationUITests` covers the observable behavior with a second tab |
| 4 | Section order (folder above/below outline) persists across relaunch | `SidebarSectionOrderTests`: `reconcile` totality — empty, unknown ids, duplicates, partial, full-reverse; `WorkspaceStateStoreTests` (in-memory `UserDefaults` suite, house rule: never the real one): order round-trips, missing key → `defaultOrder`. `WorkspaceModelTests`: `moveSections` writes through and re-reads on a fresh model. `OutlineNavigationUITests` (local): drag to reorder, terminate, relaunch, assert order |
| 5 | Full keyboard navigation works | `OutlineTreeTests.visibleItems*`: traversal order equals depth-first document order; collapsing a parent removes exactly its descendants; collapsing a leaf changes nothing; nested collapse. `OutlineControllerTests`: `activate` publishes the jump and moves the cursor; `requestFocus` increments. `OutlineNavigationUITests` (local): ⌃⌘O focuses, ↓↓ moves, Return scrolls the editor |
| — | Tree building (deliverable 2) | `OutlineTreeTests`: skipped levels H1→H3; document opening at H3; H6→H1 producing a second root; duplicate titles; empty title; Setext (`Title\n=====`) nests and reports the **title** line as `lowerBound`; front matter offset (heading after YAML reports original line, no `bodyLineOffset` subtraction); empty document; 5 000-heading corpus builds in O(n) with a documented ceiling |
| — | Current-section resolution (D5) | `OutlineSelectionTests`: line before the first heading → nil; exact heading line → that heading; line inside a section → that section; line inside a *nested* section → the nested heading, not its parent; last line → last heading; monotonicity property (non-decreasing ids over ascending lines); empty headings → nil |
| — | Jump correctness / defect #2 (§2.3) | `EditorScrollAPITests`: `revealSelection` sets `selectedRange` and moves `topVisibleUTF16Offset` to the target; **`revealSelection` and `scrollToVisible` with a range past the live text end do not raise and clamp to the document end** (the regression for the latent defect — drive a range built from a longer document through a text view holding a shorter one) |
| — | Availability gating (D7/§2.4) | `OutlineControllerTests`: `isMarkdown: false` with populated `headings` (a Python-comment corpus parsed as Markdown) yields `.unsupportedFormat` **and an empty `items`**; Markdown with zero headings yields `.noHeadings`; nil document yields `.notParsed` |
| — | Reconciliation on re-parse | `OutlineControllerTests`: collapse ids 3 and 7, re-parse a document with 4 headings → `collapsedItemIDs ⊆ allIDs`; selected id that vanishes clears |
| — | Ordinal remap across a re-parse (D4) | `OutlineIdentityMapTests`: insert a heading above a collapsed one → its id shifts by one, and the heading that *inherited* the old ordinal is **not** collapsed; delete a heading above → shifts back; duplicate titles at the same level resolve to the nearest ordinal and each new ordinal is claimed once; retitled heading drops. `OutlineControllerTests` asserts the same end-to-end through `update(...)` |
| — | Reference offset survives a re-parse (D5) | `OutlineControllerTests.currentSectionFollowsCaretAcrossReparse`: set a reference offset, publish a parse whose `SourceMap` has extra lines inserted above it, assert `currentItemID` moves to the section the offset now lands in **without** a second `referenceOffsetDidChange` call. Also: offset past `utf16Length` → last heading, no trap |
| — | `moveSections` offset convention (D10) | `ReorderTests`: three- and four-element cases pinning `ForEach.onMove` semantics (`toOffset` is an insertion point in the pre-move ordering), discontiguous sources, out-of-range source, negative/oversized destination, empty collection. `SidebarSection` has only two cases, so these are the only place the convention is observable |

House rules carried from E05–E07: `@Test`/`#expect` only; no `Task.sleep`-and-hope (await deterministic signals with the bounded polling helpers already in the test fixtures); no real `UserDefaults`; no fixture files on disk — inline builders in `Fixtures.swift`.

## 8. Implementation order (suite green at every step)

1. **Defect #2** (§2.3): clamp in `EditorTextSystem`, `revealSelection`, extended `EditorScrollAPITests`. Own commit — it fixes an E07 path and must be reviewable in isolation.
2. **Defect #1** (§2.2): `sidebarSectionOrder` on the protocol + store, `SidebarSection` ordering + `reconcile`, `WorkspaceModel.sectionOrder`/`moveSections`/hydrated expansion, delete `NoOpStateStore`, real store in `makeWindowModel`. Own commit. → `SidebarSectionOrderTests`, extended `WorkspaceStateStoreTests`/`WorkspaceModelTests`.
3. `OutlineItem` + `OutlineTree.build` → `OutlineTreeTests` (build cases).
4. `OutlineTree.visibleItems` / `allIDs` → traversal + collapse tests.
5. `OutlineSelection` → `OutlineSelectionTests`.
6. `OutlineIdentityMap` → `OutlineIdentityMapTests` (pure; land it before the controller so the controller can just call it).
7. `OutlineAvailability` + `OutlineController` → `OutlineControllerTests` (gating, remap + reconciliation, reference-offset re-translation, jump, focus, revision no-op).
8. App wiring: `WindowController`, `WorkspaceShellView`, `ContentAreaView` handlers.
9. `SidebarView` rewrite (sections reorderable, outline rows, focus, tint).
10. `WorkspaceCommands` ⌃⌘O + `WindowCoordinator.focusOutline()`.
11. `OutlineNavigationUITests`; local run. README module-map update.

## 9. Validation (must all pass before review)

```bash
cd MacDown2/Packages/MacDownKit && swift build && swift test
cd ../.. && xcodegen generate
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme macdown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build-for-testing
swiftformat --lint MacDown2 && swiftlint lint --strict MacDown2
# Locally on macOS 26 (UI test — recorded on the PR):
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' test -only-testing:MacDown2UITests/OutlineNavigationUITests
```

**Push and check CI before declaring any concurrency-touching change verified.** CI runs Xcode 26.0.1, which rejected code the newer local toolchain accepted during E07. This epic adds no concurrency, so the risk is low — but "low" is not "checked".

## 10. Open decisions (flag on the PR — do not silently resolve)

1. **Sidebar state becoming app-wide (§2.2).** The fix restores persistence by making sidebar visibility/expansion/order shared across windows rather than per-window. That is a deliberate behavior change from today's (broken) per-window-and-forgotten state. If product wants genuinely per-window sidebar layout, the answer is per-window records in `session.json`, not `UserDefaults` — a bigger change, and out of scope here. **Confirm the app-wide reading on the PR.**
2. **Headings inside block quotes and list items.** E06 emits them and has passing tests asserting so (`headingsInsideBlockQuotesIncluded`, `headingsInsideListsIncluded`). They will therefore appear in the outline. Defensible (they *are* headings) but debatable for a navigation aid — a `> # quoted heading` in a code review snippet becomes a top-level outline entry. This plan includes them; if review disagrees, the filter belongs in `OutlineTree.build`, not in E06.
3. **Current section on scroll vs caret (D5).** Last-event-wins is the simplest rule that satisfies "as you scroll/edit". Xcode's jump bar follows scroll; VS Code's outline follows the caret. If the mixed behavior reads as jitter in practice, the fallback is caret-only — record which shipped and why.
4. **Per-node collapse state is not persisted *across relaunch* (D4).** The acceptance criteria do not ask for it and ordinal identity cannot support it across a process boundary. If it is wanted later, it needs stable heading identity (a real design question, not a one-liner). Confirm it is not expected for v1. Distinct from — and not an excuse for skipping — the **in-session** remap: within a session, collapse and cursor must follow their heading across re-parses, which `OutlineIdentityMap` does on a `(level, title)` nearest-ordinal basis. If review would rather see the simpler "clear collapse state whenever the heading list changes", say so; it is a smaller change but it makes the twist-downs pop open while you type.
5. **⌃⌘O binding.** Free today, and it reads as "Outline". Verify against system-wide shortcuts on the reviewer's machine before sign-off.
6. **Non-Markdown documents are still Markdown-parsed** (§2.4). E08 gates the *outline*, but `ContentAreaView` still runs a full Markdown parse on every Python/JSON/YAML file on open and on every keystroke. That is wasted work and arguably an E11 (multi-format) concern. **Flagged, not fixed here** — fixing it means changing what E07's preview path receives, which is outside this epic's scope.
7. **`showFindIndicator` under TextKit 2 (D9).** The indicator needs laid-out geometry; §4.4 specifies ensure-layout-then-scroll-then-flash. Confirm on a real 500 KB document that the flash lands correctly when jumping far off screen, and record the finding.

## 11. Hand-off notes / known pitfalls (condensed — mirrored to the PR inline comment)

- **Do not parse anything.** The outline reads `parseSession.document.headings` (D2). A `parseNow` call, a second `MarkdownParseStore`, or a debounce in `OutlineController` is a rejection.
- **`HeadingItem.lineRange` is already ORIGINAL-source lines** (E06 D4, proven by `headingLineRangesUseOriginalSource`). **Never subtract `bodyLineOffset`.** Front matter simply has no headings.
- **`level` is display-only; depth is tree position** (D3). Indent by depth. Do not indent by `level` — H1→H3 would render a phantom gap.
- **Gate on format before building the tree** (D7/§2.4), not just before choosing a label. A Python file's `# comment` lines *will* be in `headings`; the gate is what keeps them out of the UI.
- **Selection ≠ current section** (D6). `List(selection:)` is the user's arrow-key cursor. Binding it to `currentItemID` makes typing steal the user's position mid-navigation.
- **Clamp every range that crosses the parse/live-text boundary** (§2.3). `textView.string as NSString` length — `String.count` is the wrong unit and under-clamps on emoji and CJK.
- **Jump to `lineRange.lowerBound` only**, never the full `lineRange` — a Setext heading's range includes its `=====` underline, and selecting that reads as a bug.
- **`update(...)` must no-op on an unchanged revision.** It is called from a SwiftUI `onChange` on a hot path; rebuilding the tree per body evaluation is the quadratic trap here.
- **Remap `collapsedItemIDs` and `selectedItemID` on every rebuild — do not merely intersect them with `allIDs`** (D4). Insert a heading above a collapsed node and every old ordinal still exists, so an intersection drops nothing and the collapse silently slides onto the section below. Run `OutlineIdentityMap.remap` first; the intersection is only the backstop for ids that vanished outright.
- **Store the reference position as a UTF-16 offset, translate it inside `update(...)`** (D5). The caret offset is live; the `SourceMap` is up to one debounce behind. Translating at the event site freezes a line computed against the previous document, and the tint then sticks to the wrong section until the user moves the caret again. The app forwards `range.location` raw and never calls `sourceMap.line(atUTF16Offset:)` itself.
- **`OutlineUI` imports `MarkdownEngine` and nothing else** (D1). If you write `import Workspace`, `import Preview`, `import EditorCore`, or `import FileCore` in this module, stop.
- **No `Package.swift` / `project.yml` / `ci.yml` diff** (§6). The targets already exist.
- **`NoOpSessionStore` stays; only `NoOpStateStore` is deleted** (§2.2). They look alike and do very different jobs — the session one is load-bearing.
