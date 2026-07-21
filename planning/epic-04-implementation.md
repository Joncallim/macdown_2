# EPIC-04 Implementation Plan — EditorCore (NSTextView + TextKit 2)

> **Issue:** #5 · **Branch:** `epic/04-editorcore` · **Base:** `master`
> **High-level spec:** `planning/epics/EPIC-04-editor-core.md` (scope/acceptance are binding).
> **Depends on:** E01 (`FileCore.FileDocument`), E03 (`Workspace.TabStore`, session schema).
> Read **§2 API contracts** and **§3 the two hard invariants** first — reviews reject on those.

---

## 1. Ground rules (binding, carried from E00–E03)

- **Swift 6.2, strict concurrency `complete`.** All editor UI types are `@MainActor`.
- **Package holds the logic; the app holds glue.** EditorCore is a package module.
  **Unlike `Workspace`, EditorCore MAY import AppKit** — it *is* the NSTextView wrapper.
  No other new third-party dependencies (no STTextView, no CodeEditSourceEditor).
- **`FileDocument` is a value type.** Every edit produces a new value that must be
  written back into `TabStore.tabs[i].document`. Never rely on reference semantics.
- **Tests: Swift Testing (`@Test`)** for logic + performance; temp-dir stores only;
  never the real session/UserDefaults suites. XCTest is used *only* where a Swift
  Testing equivalent does not exist (see §4.3).
- **CI reality (do not fight it):** `xcodebuild test` cannot *run* on the `macos-15`
  runner against a macOS 26 deployment target (E03 §2.8). `swift test` **does** run
  there (command-line test binaries bypass the OS-version gate). **Therefore every
  performance/behaviour gate that must run in CI lives in `EditorCoreTests` and is
  exercised by `swift test`.** The XCUITest is authored and `build-for-testing` only.

---

## 2. Architecture

### 2.1 Module boundaries

```
EditorCore  (NEW — imports AppKit, FileCore; SwiftUI for the representable)
  ├── EditorView            NSViewRepresentable — the SwiftUI entry point
  ├── EditorConfiguration   value-type prefs (wrap, insets, line height, overscroll, font)
  ├── EditorTextSystem      @MainActor reference type — owns ONE document's TK2 stack + undo
  ├── EditorTextSystemStore @MainActor cache: WorkspaceTab.id → EditorTextSystem
  ├── TextKitStack          TK2 assembly + a thin TextKit1 fallback seam
  └── EditorFind            NSTextFinder client wiring

Depends on:  FileCore (FileDocument, text)              [already a package dep]
Consumed by: Highlighting (E05) via EditorTextSystem    [keep its surface stable]
App target:  ContentAreaView replaces SourcePane with EditorView + write-back
```

`Highlighting` (E05) already declares a dependency on `EditorCore`. **The public
surface of `EditorTextSystem` (its `NSTextContentStorage` / `NSTextLayoutManager`
accessors) is the seam E05 will attach a highlighter to — design it deliberately
and do not churn it later.**

### 2.2 Public API contract (new EditorCore types)

```swift
// value-type configuration; identity-comparable so updateNSView can diff cheaply
public struct EditorConfiguration: Sendable, Equatable {
    public var font: NSFont
    public var lineHeightMultiple: CGFloat      // 1.0 = system default
    public var textInsets: NSSize               // textContainerInset
    public var wrapsLines: Bool                 // true = wrap to width; false = horizontal scroll
    public var scrollsPastEnd: Bool             // overscroll (cf. MPEditorView.scrollsPastEnd)
    public var showsInvisibles: Bool            // reserved; default false
    public static var `default`: EditorConfiguration { get }
}

// The SwiftUI entry point. Text binding is two-way; identity keys the cached text system.
public struct EditorView: NSViewRepresentable {
    public init(
        text: Binding<String>,                  // two-way — writes flow back on edit
        identity: String,                       // WorkspaceTab.id — keys the text-system cache
        configuration: EditorConfiguration,
        store: EditorTextSystemStore,           // owner of per-tab text systems (from the app)
        onSelectionChange: ((NSRange) -> Void)? = nil,
        onScrollChange: ((CGFloat) -> Void)? = nil
    )
    // makeNSView: pull-or-create store[identity]; return its scroll view.
    // updateNSView: reconcile configuration + reconcile EXTERNAL text changes only
    //               (see §2.3 — never echo the user's own keystroke back in).
}

// Owns exactly one document's live text system. Reference type; @MainActor.
@MainActor public final class EditorTextSystem {
    public let identity: String
    public var textView: NSTextView { get }         // TK2-backed
    public var contentStorage: NSTextContentStorage { get }   // E05 attaches here
    public var layoutManager: NSTextLayoutManager { get }     // E05 attaches here
    public var undoManager: UndoManager { get }               // per-tab, independent
    public func setText(_ text: String)             // external replace (reload/conflict); preserves nothing
    public func apply(_ configuration: EditorConfiguration)
    public var scrollOffset: CGFloat { get set }    // for session restore
    public var selectedRange: NSRange { get set }   // for session restore
}

@MainActor public final class EditorTextSystemStore {
    public init()
    public func system(for identity: String, initialText: String,
                       configuration: EditorConfiguration) -> EditorTextSystem
    public func evict(_ identity: String)           // MUST tear down on tab close (see §2.4)
    public var liveIdentities: Set<String> { get }  // test seam
}
```

### 2.3 Two-way binding & value-type write-back (HARD INVARIANT #1)

The editor is the source of truth for `text` *while focused*; the model is the
source of truth on load/reload/conflict. Reconciliation rules:

1. **User keystroke →** NSTextView delegate (`textDidChange`) pushes the new string
   into the `Binding<String>`. The app's binding setter writes it back:
   `tabStore.tabs[i].document = tabStore.tabs[i].document.edited(text: newText)`
   (see §2.3.1) — moving `.clean → .dirty`. **Never** mutate `document` in place.
2. **`updateNSView` guard —** compare the binding's value to the text view's current
   string; **only** call `setText` when they differ *and* the change did not originate
   from the text view (track a `isApplyingModelText` flag). This prevents the
   keystroke-echo feedback loop (the #1 NSViewRepresentable-text bug).
3. **External reload / conflict resolution →** model text changes without a keystroke;
   `updateNSView` detects the mismatch and calls `setText` (cursor/scroll reset is
   acceptable here — the document changed underneath).

#### 2.3.1 FileDocument edit helper (add to FileCore)

`FileDocument.text`/`state` are `var`, but edits must go through one funnel so the
state machine stays correct. Add:

```swift
public extension FileDocument {
    /// Returns a copy with new text, transitioning clean → dirty (idempotent when
    /// already dirty; a no-op-content edit still marks dirty — match NSTextView).
    func edited(text newText: String) -> FileDocument
}
```

Add matching `FileCoreTests` (edit marks dirty; preserves id/format/url; save then
edit re-dirties). This is the *only* FileCore change E04 introduces.

### 2.4 Per-tab text-system lifecycle (HARD INVARIANT #2)

SwiftUI rebuilds `ContentAreaView` on every active-tab switch. A naïve
representable would rebuild the NSTextView each time — losing undo/selection/scroll
and forcing a full relayout (fatal for the 10 MB budget). Instead:

- `EditorTextSystemStore` (owned by the **window**, see §2.6) caches one
  `EditorTextSystem` per `WorkspaceTab.id`. `EditorView.makeNSView` returns the
  cached system's scroll view; switching tabs re-mounts the *same* NSTextView, so
  **undo history, selection, and scroll position persist for free.**
- **Teardown:** when `TabStore` closes a tab, the app calls `store.evict(tab.id)`,
  which removes the text system and breaks the NSTextView ↔ layoutManager ↔
  contentStorage graph so it deallocates. Acceptance criterion "closing a tab
  releases its text system" is verified by a **weak-reference test** in
  `EditorCoreTests` (create → evict → `#expect(weakRef == nil)`), which runs in CI
  (no Instruments needed; Instruments is an optional manual cross-check).

### 2.5 TextKit 2 stack + large-document layout

- Build the stack explicitly: `NSTextContentStorage` → `NSTextLayoutManager` →
  `NSTextContainer`; create the view with `NSTextView(usingTextLayoutManager: true)`
  inside an `NSScrollView`. Let AppKit drive `NSTextViewportLayoutController`.
- **Never force whole-document layout on open.** Do not call
  `ensureLayout(for: documentRange)` or read `usageBoundsForTextContainer` eagerly.
  The 10 MB budget depends on only the viewport region laying out.
- `TextKitStack` exposes a `useLegacyTextKit1: Bool` seam. Default TK2. The TK1 path
  is a *stub adapter* for now (see §7 open decision) — do **not** build a second full
  editor.

### 2.6 App-target view tree integration

- `EditorTextSystemStore` is created once per window and injected via the SwiftUI
  `Environment` (or held by `WindowCoordinator`), so all tabs in that window share
  one cache. **Do not** make it a global singleton (breaks multi-window from E03).
- `ContentAreaView.DocumentEditorSplitView.SourcePane` (currently a read-only
  `Text` in a `ScrollView`, `ContentAreaView.swift:135`) is **replaced** by
  `EditorView(text:identity:configuration:store:)`. The preview pane keeps reading
  the same `document.text` so edits render live (already wired).
- Thread a write-back from `WorkspaceShellView`/`ContentAreaView` down: the view
  needs the active tab's `id` and a `Binding<String>` onto
  `tabStore.tabs[i].document.text` (via §2.3.1). `ContentAreaView`'s signature
  changes from `let document` to also take `identity` + the binding + the store.
- **Session restore (closes an E03 gap):** E03 left `cursorPosition`/`scrollOffset`
  schema-only. Wire `EditorTextSystem.selectedRange`/`.scrollOffset` to the E03
  session capture/restore so reopening a tab restores caret + scroll. Keep it
  best-effort: never throw, never block launch.

### 2.7 Behaviours

- **Word wrap toggle:** `wrapsLines` → container tracks the scroll view width
  (`widthTracksTextView = true`, container width = clip width); off → very wide
  container + horizontal scroller.
- **Overscroll:** `scrollsPastEnd` → add bottom `textContainerInset` (or extra
  content height) so the last line can scroll to the top. Match old
  `MPEditorView.scrollsPastEnd` feel.
- **Insets / line height:** `textInsets` → `textContainerInset`; `lineHeightMultiple`
  → default paragraph style applied as a typing attribute (do not stomp attributes
  E05 will add — apply as the *base* typing attribute only).
- **Find-in-file:** stock `NSTextFinder` bound to the NSTextView + scroll view
  (`EditorFind`). No custom find UI for v1.

### 2.8 Performance harness (the acceptance gates)

In `EditorCoreTests`, exercised by `swift test` (so they run in CI):

| Test | Budget | How to measure (deterministic, headless) |
|---|---|---|
| `open1MB` | text laid out for the viewport < **300 ms** | build 1 MB fixture; time `system(for:)` + layout of a 800×1000 viewport rect via `layoutManager.enumerateTextLayoutFragments(from:options:)` |
| `keystroke` | insert-one-char + viewport relayout < **50 ms** | after open, `contentStorage.performEditingTransaction` inserting a char; time viewport relayout |
| `open10MBLazy` | fragments laid out ≪ total lines | build 10 MB fixture; assert enumerated fragment count for one viewport is bounded (e.g. < 500), proving laziness |
| `undoIsPerTab` | — | two systems; undo on A does not affect B; undo survives an evict-less re-`system(for:)` |
| `evictReleasesSystem` | — | weak ref nil after `evict` |

Budgets are **provisional** — calibrate on the CI runner (§7). Use
`ContinuousClock().measure { }`; assert with a documented headroom factor, and
`log`/skip (not silently pass) if a fixture can't be built.

### 2.9 UI-test seam

- `MacDown2UITests/EditorTypingUITests.swift`: launch with `-UITesting`, type into a
  tab, assert the string round-trips (visible in the source pane / retrievable).
  Reuse E03's `-UITesting`/`-openFiles` launch hooks.
- This target is **`build-for-testing` only in CI** (E03 §2.8). It runs locally on
  macOS 26. **No `ci.yml` change is required** — the existing UI-test build step and
  `swift test` step already cover E04.

---

## 3. File layout (exact)

```
Packages/MacDownKit/Sources/EditorCore/
  EditorConfiguration.swift
  TextKitStack.swift
  EditorTextSystem.swift
  EditorTextSystemStore.swift
  EditorView.swift
  EditorFind.swift
  # delete EditorCore.swift stub (or keep only a namespace enum if lint needs a file)
Packages/MacDownKit/Sources/FileCore/
  FileDocument+Edit.swift          # the `edited(text:)` helper (§2.3.1)
Packages/MacDownKit/Tests/EditorCoreTests/
  EditorTextSystemTests.swift      # binding echo-guard, undo-per-tab, setText, evict/leak
  EditorConfigurationTests.swift   # wrap/inset/overscroll application
  EditorPerformanceTests.swift     # §2.8 budgets
  Fixtures.swift                   # deterministic N-MB markdown generator
Packages/MacDownKit/Tests/FileCoreTests/
  FileDocumentEditTests.swift      # edited(text:) transitions
App:
  MacDown2/ContentAreaView.swift        # SourcePane → EditorView + write-back
  MacDown2/WorkspaceShellView.swift     # thread identity + binding + store (Environment)
  MacDown2/WindowCoordinator.swift      # own the per-window EditorTextSystemStore; evict on close
  MacDown2UITests/EditorTypingUITests.swift
```

## 4. Test plan

- **4.1 Behaviour (Swift Testing, `swift test`):** binding echo-guard; external
  `setText` replaces; per-tab undo isolation + persistence across re-mount;
  wrap/inset/overscroll take effect; `evict` releases (weak ref).
- **4.2 Performance (Swift Testing, `swift test`):** the §2.8 table. These are the
  CI-enforced acceptance gates.
- **4.3 UI (XCUITest, `build-for-testing` in CI, run locally on 26):** type-round-trip.
- **4.4 FileCore:** `edited(text:)` transitions.

## 5. Implementation order (package first, app second)

1. `EditorConfiguration` + `TextKitStack` (TK2 assembly, TK1 seam) + config tests
2. `EditorTextSystem` (owns stack + undo; `setText`; selection/scroll) + tests
3. `EditorTextSystemStore` (cache + `evict` teardown) + weak-ref leak test
4. `FileDocument.edited(text:)` in FileCore + tests
5. `EditorView` representable (make/update + echo-guard) + behaviour tests
6. Wrap / overscroll / insets / line-height + tests
7. `EditorFind` (NSTextFinder)
8. `EditorPerformanceTests` — **must be green via `swift test`**
9. App wiring: `ContentAreaView` write-back; per-window store in `WindowCoordinator`;
   `evict` on tab close; cursor/scroll → E03 session restore
10. `EditorTypingUITests` (+ `xcodegen generate`; runs under existing UI-test build step)

**The package suite must be green before touching the app target.**

## 6. Validation (must all pass before review)

```bash
cd MacDown2/Packages/MacDownKit && swift build && swift test
cd ../../.. && swiftformat --lint MacDown2 && swiftlint lint --strict MacDown2
cd MacDown2 && xcodegen generate
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build build-for-testing
xcodebuild -project MacDown2.xcodeproj -scheme macdown2 -destination 'platform=macOS' build
```

## 7. Open decisions (flag on the PR — do not silently resolve)

1. **Perf budgets vs CI hardware.** 300 ms / 50 ms are dev-machine targets. Calibrate
   against the `macos-15` runner; if tight, apply a *documented* headroom multiplier —
   never loosen a budget silently. State the measured CI numbers in the PR.
2. **TextKit 1 fallback depth.** Ship the `TextKitStack` seam + a stub only. Wire a
   real TK1 path *only* if a concrete pathological file is found to misbehave on TK2.
   Don't gold-plate a second editor.
3. **Undo granularity.** Default to NSTextView's per-insertion coalescing. If product
   wants word-level undo, flag it — don't invent a policy here.
4. **Store ownership.** `EditorTextSystemStore` per window via `Environment` is the
   plan. If multi-window sharing of a document surfaces a conflict, raise it rather
   than promoting the store to a singleton.

## 8. Handoff notes / known pitfalls

- **Keystroke echo loop** is the classic bug: guard `updateNSView` with an
  `isApplyingModelText` flag and a value compare (§2.3.2). Get this right first.
- **Don't eagerly measure the document.** Any call that forces full layout on open
  (`ensureLayout(for: documentRange)`, eager `usageBoundsForTextContainer`) breaks the
  10 MB budget. Viewport-only.
- **Value-type write-back:** always `tabs[i].document = tabs[i].document.edited(...)`.
- **Keep the E05 seam stable:** `contentStorage`/`layoutManager` are what Highlighting
  attaches to — name and expose them deliberately now.
- **Perf tests belong in the package**, not the XCUITest target, or they won't run in CI.
- Map the five acceptance boxes on issue #5 to: `open1MB`, `open10MBLazy`,
  `undoIsPerTab`, config tests, `evictReleasesSystem` + the XCUITest round-trip.
