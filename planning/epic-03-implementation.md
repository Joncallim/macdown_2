# EPIC-03 Implementation Plan — Tab System

> **Issue:** [#4 — [EPIC-03] Tab system: TabStore, tab bar UI, session restore](https://github.com/Joncallim/macdown_2/issues/4)
> **Branch:** `epic/03-tab-system` → PR into `master` (mainline since PR #23; `rewrite/main` is deleted)
> **Depends on:** E01 (FileCore), E02 (Workspace shell) — both on `master` at `f354ab3`.
> **Result:** Xcode/VS Code-style in-app tabs: `TabStore` with dedupe/pin/reorder, tab bar UI, per-tab dirty-close flow with batch queue, session restore, full keyboard tab navigation.

---

## 1. Ground rules (binding, carried from E00–E02)

1. macOS 26.0 deployment target. No availability checks.
2. Swift 6 + strict concurrency. Zero warnings.
3. SPM only. **No new third-party dependencies this epic.**
4. Do not touch the legacy tree (`MacDown/`, `Dependency/`, `macdown-cmd/`, `Tools/`).
5. `@Observable` (Observation framework), not Combine/`ObservableObject`.
6. All testable logic lives in the SPM `Workspace` module. **No AppKit imports in the package** — platform panels stay behind `FilePanelProviding`.
7. One window. **No drag-out-to-new-window, no native `NSWindow` tabbing** (rejected by D2).
8. The tab bar is the most visible custom control: keep it stock-looking (plain `HStack` in a `ScrollView`, system materials only). Liquid Glass treatment is E15.
9. Tests use Swift Testing (`@Test`). App-target UI code is not unit-tested; `TabStore` and session logic are.
10. Session restore is **best-effort**: it never throws to the user, never blocks launch, and tolerates missing files and corrupted state.

---

## 2. Architecture

### 2.1 Module boundaries

```
App target (MacDown2/MacDown2/)
  MacDown2App            @main, WindowGroup, .commands, willTerminate save hook,
                         -UITesting launch-argument handling
  WorkspaceCommands      File menu set + NEW tab navigation commands (⌘T, ⌃⇥, ⌘1…9)
                         + DEBUG-only "Mark Active Tab Dirty" test hook
  WorkspaceShellView     NavigationSplitView; detail = VStack { TabBarView; ContentAreaView }
                         dirty-close alert driven by tabStore.pendingCloseTabID
  TabBarView             NEW — tab bar: items, dirty dot, close button, context menu,
                         drag-to-reorder, overflow scrolling
  ContentAreaView        UNCHANGED (takes optional FileDocument)
  SidebarView            UNCHANGED (Reveal-in-Sidebar expands .folder)
  NSFilePanelProvider    UNCHANGED
        │ imports Workspace
SPM Workspace module (MacDown2/Packages/MacDownKit/Sources/Workspace/)
  TabStore               NEW — @MainActor @Observable: tabs, active tab, close flows,
                         pin, move, navigation, session save/restore
  WorkspaceTab           NEW — value type: id (UUID), document (FileDocument), isPinned
  WorkspaceSession       NEW — Codable session schema + WorkspaceSessionStoring protocol +
                         WorkspaceSessionStore (JSON file, atomic write)
  WorkspaceModel         CHANGED — composes TabStore; activeDocument forwarded; shell state
                         (sidebar, folder, panels, lastError) unchanged
  Workspace.swift        extend doc comment
        │ imports FileCore (E01) — unchanged
  FileDocument state machine · FileStore · FileFormatRegistry · RecoveryBuffer
```

**Why this split:** `TabStore` is pure tab-state logic — unit-testable with no window, menu, or AppKit. `WorkspaceModel` keeps shell responsibilities (panels, sidebar, folder) and delegates every document-slot concern to `TabStore`. The tab bar is app-target SwiftUI, exactly as `ContentAreaView` was in E02.

### 2.2 Public API contract (new Workspace types)

```swift
// TabStore.swift
/// One open tab. `id` is a stable UUID assigned at creation — it does NOT track
/// `document.id` (which is the fileURL string for file-backed docs and the
/// recovery-buffer key for untitled ones). Keeping the two apart lets the
/// session schema stay stable across save-as and lets untitled docs keep a
/// distinct recovery key.
public struct WorkspaceTab: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var document: FileDocument
    public var isPinned: Bool
}

@MainActor @Observable
public final class TabStore {
    // MARK: State
    public private(set) var tabs: [WorkspaceTab]
    public private(set) var activeTabID: WorkspaceTab.ID?
    /// Non-nil while the dirty-close alert should be shown for this tab.
    /// The view presents one alert for this tab; batch closes walk a queue.
    public private(set) var pendingCloseTabID: WorkspaceTab.ID?

    // MARK: Derived (used by command enablement; unit-tested)
    public var activeTab: WorkspaceTab? { get }
    public var activeDocument: FileDocument? { get }
    public var hasActiveDocument: Bool { get }
    public var canSave: Bool { get }            // dirty / untitled-with-content (E02 rule)
    public var canCloseActiveTab: Bool { get }  // active exists && !active.isPinned

    public init(sessionStore: WorkspaceSessionStoring = WorkspaceSessionStore())

    // MARK: Intents — lifecycle
    public func newTab()                                 // untitled Markdown FileDocument
    public func openFileInTab(_ url: URL) async          // dedupes: activates existing tab
    public func requestClose(_ id: WorkspaceTab.ID)      // clean → closes; dirty → prompts
    public func requestCloseActiveTab()
    public func requestCloseOthers(of id: WorkspaceTab.ID)       // batch; skips pinned
    public func requestCloseToTheRight(of id: WorkspaceTab.ID)   // batch; skips pinned
    public func resolveClose(_ resolution: CloseResolution) async

    // MARK: Intents — arrangement & navigation
    public func activate(_ id: WorkspaceTab.ID)
    public func selectNextTab()                          // wraps
    public func selectPreviousTab()                      // wraps
    public func selectTab(at index: Int)                 // 0-based; index 8 (⌘9) = LAST tab
    public func togglePin(_ id: WorkspaceTab.ID)
    public func moveTab(from source: Int, to destination: Int)  // clamped within pin group

    // MARK: Document write-back
    /// FileDocument is a value type; mutations return a new instance that must be
    /// written back. Views/commands never mutate a document in place.
    public func updateActiveDocument(_ transform: (FileDocument) -> FileDocument)

    // MARK: Session
    public func restoreSessionIfNeeded() async  // guard-once; never throws; never blocks launch
    public func saveSession() async             // autosaves dirty tabs, then writes JSON
}
```

Behavioral contract the implementer must honor:

- **Dedupe.** `openFileInTab` dedupes on `url.standardizedFileURL` against every tab's `document.fileURL`. A hit activates the existing tab and never creates a second one. Untitled tabs (nil fileURL) never dedupe.
- **Pin invariants.** All pinned tabs precede all unpinned tabs at all times. `togglePin(true)` moves the tab to the end of the pinned block; `togglePin(false)` moves it to the start of the unpinned block. `moveTab` clamps the destination into the tab's own pin group. Batch closes (`Close Others`, `Close to the Right`) **skip pinned tabs**. `canCloseActiveTab == false` when the active tab is pinned — ⌘W on a pinned tab is a no-op (enablement, not "unpin then close").
- **Single close flow.** `requestClose` on a clean tab removes it immediately. On a dirty tab it runs `FileDocument.requestClose()` (E01 machine) and sets `pendingCloseTabID`. `resolveClose(.save)` saves (untitled → save-panel flow; cancel/failure aborts the close and keeps the tab), `.discard` closes, `.cancel` returns the tab to `.dirty` via `FileDocument.resolveClose(.cancel)`.
- **Batch close queue.** `requestCloseOthers` / `requestCloseToTheRight` remove clean in-scope tabs immediately and enqueue dirty ones (FIFO). `pendingCloseTabID` shows the queue head; each `resolveClose` applies and advances. `.cancel` **empties the entire queue and keeps all remaining tabs** — cancel aborts the batch, not just the current tab.
- **Active-tab handoff.** Closing the active tab activates its left neighbor, else its right neighbor, else none. Closing a non-active tab never changes the active tab.
- **Save-as recovery rule (carried from E02).** After a successful `saveAs` on an untitled tab, call `clearRecovery()` so the buffer does not resurrect the document on next launch.
- **`newTab` / `openFileInTab` never prompt on a dirty active tab.** Tabs replace E02's interim single-slot "close before replace" flow. The E02 `pendingAction` continuation for new/open is **removed**; the prompt only guards *close* operations. (E02 tests asserting prompt-on-open are updated per §4.)

### 2.3 WorkspaceModel delta (small)

- Gains `public let tabStore: TabStore`. Both are `@Observable`, so views observe through it directly.
- `activeDocument` becomes a **computed forwarder** to `tabStore.activeDocument`. `ContentAreaView(document: model.activeDocument)` and the preview split are untouched.
- `pendingClose: Bool` is **removed**; the shell alert binds to `tabStore.pendingCloseTabID`.
- `newDocument()` → `tabStore.newTab()`. `openFile()` → panel → `tabStore.openFileInTab(url)`. `save()` / `saveAs()` operate on the active tab and write the returned `FileDocument` back via `updateActiveDocument`; failures still land in `lastError`. `requestCloseDocument()` → `tabStore.requestCloseActiveTab()`.
- `canSave` / `canClose` / `hasActiveDocument` forward to `tabStore` (enablement source stays `WorkspaceModel`, so `WorkspaceCommands` barely changes).
- Sidebar visibility, section expansion, `folderURL`, `FilePanelProviding` injection: **unchanged**.

### 2.4 Session persistence

```swift
// WorkspaceSession.swift
public struct WorkspaceSession: Codable, Sendable, Equatable {
    public var version: Int                 // current schema = 1
    public var tabs: [TabRecord]
    public var activeTabID: UUID?
}

public struct TabRecord: Codable, Sendable, Equatable {
    public var id: UUID
    public var fileURL: URL?                // nil for untitled
    public var untitledDocumentID: String?  // recovery-buffer key, untitled only
    public var isPinned: Bool
    public var cursorPosition: Int?         // UTF-16 offset — schema seam for E04
    public var scrollOffset: Double?        // schema seam for E04
}

public protocol WorkspaceSessionStoring: Sendable {
    func loadSession() -> WorkspaceSession?
    func saveSession(_ session: WorkspaceSession)
}

/// JSON at ~/Library/Application Support/MacDown 2/session.json (same
/// app-support folder RecoveryBuffer already uses). Atomic: write .tmp, rename.
public struct WorkspaceSessionStore: WorkspaceSessionStoring { … }
```

- **Save triggers:** every structural mutation (new/open/close/move/pin/activate) — debounced ~300 ms inside `TabStore`; plus `scenePhase == .background` and `NSApplication.willTerminateNotification` in the app target. Save failures are swallowed (logged) — restore is best-effort both ways.
- **Dirty-text autosave.** `saveSession()` first writes every dirty tab's text into `RecoveryBuffer` (E01's actor already sanitizes arbitrary IDs, so file-backed `document.id`s are safe). This extends E01's untitled-only autosave to all dirty tabs and is what lets a force-quit lose nothing.
- **Restore** (`restoreSessionIfNeeded`, called once from the shell's `.task`):
  - `fileURL` tab → `FileDocument(fileURL:).load()`; any failure (deleted/moved file) → **drop the tab, continue** (acceptance criterion).
  - Untitled tab → `RecoveryBuffer.load(for: untitledDocumentID)`; no buffer → drop the tab.
  - File-backed tab with a `RecoveryBuffer` entry that differs from disk content → restore recovery text, state `.dirty` (crash / quit-with-unsaved path).
  - Corrupted JSON or unknown `version` → empty session, no crash.
  - Restore runs off the critical launch path: the window appears empty first, tabs pop in as they load.
- **Cursor/scroll fields:** schema v1 carries `cursorPosition` + `scrollOffset` so no migration is needed later, but capture/apply is **deferred to E04** — the E02 content pane is read-only `Text` in a `ScrollView` with no cursor to persist. This is the one acceptance bullet partially deferred; flagged on the PR and in §8. Tabs, order, pin state, and active tab all restore fully.

### 2.5 App-target view tree

```
WorkspaceShellView
  NavigationSplitView(columnVisibility:)          // E02, unchanged
    sidebar: SidebarView                          // unchanged
    detail:  VStack(spacing: 0) {
        TabBarView(model: model)                  // NEW
        Divider()
        ContentAreaView(document: model.activeDocument)   // unchanged
    }
  .alert("Unsaved Changes", isPresented: pendingCloseBinding)  // per-tab; names the tab
```

`TabBarView` requirements:

- `ScrollView(.horizontal)` + `LazyHStack(spacing: 0)`, fixed height ~28 pt, stock background. Overflow = scroll; a `ScrollViewReader` keeps the activated tab visible (`scrollTo` on activate).
- `TabItemView`: pin glyph when pinned · title (`fileURL.lastPathComponent ?? "Untitled"`) · dirty dot (`●` when `.dirty`/`.conflict`) · close `×` button. Active tab: subtle `RoundedRectangle` fill (`.quaternary`); inactive clear. Tap → `activate`.
- Context menu (per epic): **Close**, **Close Others**, **Close to the Right**, **Reveal in Sidebar**. Reveal is enabled only when `folderURL != nil` and the tab's file lives under it; the action sets `sidebarVisible = true` + `setSectionExpanded(.folder, true)` — actual tree selection is the E09 seam; leave a `// TODO(E09)` comment.
- Drag-to-reorder: `.draggable(String(tab.id.uuidString))` on the item + `.dropDestination(for: String.self)` computing the target index → `tabStore.moveTab(from:to:)`. Pin-group clamping lives in `TabStore`, not the view.

### 2.6 Commands & shortcuts

`WorkspaceCommands` additions (existing File commands stay as-is):

| Command | Shortcut | Placement | Enabled when |
|---|---|---|---|
| New Tab | ⌘T | `CommandGroup(replacing: .newItem)`, after New File | always |
| Close Tab | ⌘W (existing) | existing save group | `tabStore.canCloseActiveTab` |
| Show Next Tab | ⌃⇥ | `CommandGroup(before: .windowArrangement)` | `tabs.count > 1` |
| Show Previous Tab | ⌃⇧⇥ | same | `tabs.count > 1` |
| Select Tab 1…8 | ⌘1…⌘8 | same group | index < tabs.count |
| Select Last Tab | ⌘9 | same group | tabs.count > 0 |

- **⌘N "New File" and ⌘T "New Tab" both create an untitled tab.** Each tab owns exactly one document; there is no document-without-tab state, so the two intents are identical here. (Noted on the PR.)
- `KeyboardShortcut(.tab, modifiers: [.control])` / `[.control, .shift]` — same chord browsers use; no macOS system conflict.
- ⌘1…8 jump to tab 1…8; **⌘9 always jumps to the last tab** (browser convention).

### 2.7 UI-test seam (project.yml + launch arguments)

EPIC-03 deliverable 3 requires XCUITest, but the content pane is read-only until E04 — a UI test cannot make a document dirty by typing. Resolve with test-mode hooks, all gated on the `-UITesting` launch argument in `MacDown2App`:

1. `-UITesting` → `WorkspaceModel` is built with isolated stores (temp-dir `WorkspaceSessionStore`, unique UserDefaults suite) so tests never touch the real session.
2. `-openFiles <a.md,b.md,c.md>` → open these fixture files into tabs at launch (bypasses the open panel, which XCUITest cannot drive).
3. `#if DEBUG` menu item **"Mark Active Tab Dirty"** (Debug menu) → `tabStore.updateActiveDocument { $0.updatingText($0.text + " ") }`.

`project.yml` gains a `MacDown2UITests` target (`type: bundle.ui-testing`, sources `MacDown2UITests/`) and the `MacDown2` scheme gains a test action. Regenerate with `xcodegen generate`. **No `Package.swift` change.** Fixture .md files live in `MacDown2UITests/Fixtures/` (bundle resources).

### 2.8 CI trigger fix (required by the branch move)

`.github/workflows/ci.yml` triggers only on `rewrite/main`, which is deleted. Both triggers (`push`, `pull_request`) change to `master`. Also add an app-test step to `build-and-test`:

```yaml
      - name: App + UI tests
        run: xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' test
```

If UI tests prove flaky on the `macos-15` runner, mark the step `continue-on-error: true` with a tracking comment rather than blocking the epic — decision flagged on the PR.

---

## 3. File layout (exact)

New / changed in the package:

```
MacDown2/Packages/MacDownKit/Sources/Workspace/
    Workspace.swift                  # extend doc comment (tabs + session)
    TabStore.swift                   # NEW — WorkspaceTab + TabStore
    WorkspaceSession.swift           # NEW — schema + protocol + JSON store
    WorkspaceModel.swift             # CHANGED — composes TabStore (see §2.3)
MacDown2/Packages/MacDownKit/Tests/WorkspaceTests/
    TabStoreTests.swift              # NEW
    WorkspaceSessionStoreTests.swift # NEW
    WorkspaceModelTests.swift        # UPDATED — enablement forwards; prompt-on-open removed
    WorkspaceModelFileTests.swift    # UPDATED — open/save now multi-tab
    WorkspaceStateStoreTests.swift   # unchanged
    Fakes.swift                      # + FakeSessionStore
```

New / changed in the app target:

```
MacDown2/MacDown2/
    MacDown2App.swift                # -UITesting hooks, willTerminate/session save
    WorkspaceShellView.swift         # detail = VStack { TabBarView; ContentAreaView }; per-tab alert
    TabBarView.swift                 # NEW
    WorkspaceCommands.swift          # + tab navigation commands; DEBUG dirty hook
    ContentAreaView.swift            # unchanged
    SidebarView.swift                # unchanged
    NSFilePanelProvider.swift        # unchanged
MacDown2/MacDown2UITests/            # NEW target
    TabLifecycleUITests.swift
    Fixtures/ (a.md, b.md, c.md)
MacDown2/project.yml                 # + MacDown2UITests target, scheme test action
.github/workflows/ci.yml             # triggers → master; + app/UI test step
```

`Package.swift`: **no changes** (Workspace already depends on FileCore; RecoveryBuffer is already public).

---

## 4. Test plan (Workspace module, Swift Testing)

Fakes: `FakeSessionStore` (in-memory), `FakePanel` (existing), temp-dir `WorkspaceSessionStore` for round-trips, temp files for fixtures.

1. `newTab` → untitled tab active; two `newTab()` → two distinct tabs, latest active.
2. `openFileInTab` twice with the same URL (incl. `standardizedFileURL` variants with `..` segments) → one tab, activated. Untitled tabs never dedupe.
3. `openFileInTab` while another tab is dirty → **no prompt**; new tab opens (supersedes E02; the two E02 prompt-on-open tests are rewritten to this).
4. `requestClose` on clean tab → removed; closing active activates left neighbor, else right, else nil; closing non-active leaves active unchanged.
5. `requestClose` on dirty tab → `pendingCloseTabID` set, tab retained. `resolveClose(.cancel)` → tab dirty and active, prompt cleared. `resolveClose(.discard)` → removed. `resolveClose(.save)` untitled + fake panel URL → saved, closed, recovery cleared; panel cancel → close aborted, tab open and dirty.
6. Batch: 5 tabs (2 dirty) → `requestCloseOthers` → clean ones removed immediately; dirty ones queued; `pendingCloseTabID` walks the queue; cancel mid-queue → remaining tabs retained, queue cleared, `pendingCloseTabID == nil`.
7. Pins: `togglePin` moves to end of pinned block / start of unpinned; `moveTab` cannot cross the pin boundary; `canCloseActiveTab == false` when active is pinned; batch closes skip pinned; pin state survives session round-trip.
8. Navigation: `selectNextTab`/`selectPreviousTab` wrap both directions; `selectTab(at: 8)` → last tab regardless of count; out-of-range indices are no-ops.
9. Session round-trip: tabs + order + active + pins serialize → restore into a fresh `TabStore` → identical structure. Untitled tab restores text from `RecoveryBuffer`. Dirty file-backed tab restores recovery text with state `.dirty`.
10. Corrupted session JSON → empty, no crash. Unknown `version` → empty, no crash. Missing file → tab dropped, others unaffected. Missing recovery buffer for untitled → tab dropped.
11. `saveSession` autosaves dirty tabs: `RecoveryBuffer` ends up with entries for every dirty tab, including file-backed document IDs.
12. `WorkspaceModel`: `canSave`/`canClose`/`hasActiveDocument` forward correctly across tab switches; `openFolder` unchanged; E02 enablement matrix re-run against the active tab.
13. `WorkspaceSessionStore`: file round-trip in a temp dir; atomic write leaves no `.tmp` behind; corrupt file → `loadSession() == nil`.

Keep `moduleLoads()` and all E02 tests that remain valid. Suite must stay green under `swift test` before any app-target work starts.

---

## 5. Implementation order

1. `WorkspaceSession.swift` (schema + protocol + JSON store) + `WorkspaceSessionStoreTests` → `swift test`.
2. `TabStore.swift` core — tabs/active/new/open/dedupe/activate/navigation + tests → `swift test`.
3. Close flows — single + batch queue + `resolveClose` + tests.
4. Pin + move + tests.
5. Session save/restore + `RecoveryBuffer` autosave + tests.
6. `WorkspaceModel` rewire (compose TabStore, forward enablement, remove `pendingClose`/`pendingAction`) + updated E02 tests → package suite green.
7. App: `TabBarView` + shell integration + per-tab alert.
8. App: commands (⌘T, ⌃⇥/⌃⇧⇥, ⌘1…9) + DEBUG dirty hook + `-UITesting`/`-openFiles` launch args + termination/background save.
9. `project.yml` UITest target + `xcodegen generate` + `TabLifecycleUITests`.
10. `ci.yml` branch triggers → `master`, + app/UI test step.
11. Validate (§6), manual acceptance pass (§7), mark PR ready for review.

---

## 6. Validation (must all pass before review)

```bash
cd MacDown2/Packages/MacDownKit && swift build && swift test   # all green incl. §4
cd ../../..                                                     # repo root
swiftformat --lint MacDown2                                     # clean
swiftlint lint --strict MacDown2                                # clean
cd MacDown2 && xcodegen generate
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme macdown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' test
```

## 7. Manual acceptance pass (map to issue #4 checkboxes)

| #4 checkbox | How to verify |
|---|---|
| Opening the same file twice never creates a second tab | ⌘O same file twice → one tab, re-activated |
| Closing a dirty tab always prompts; cancel aborts | Dirty a tab (post-E04 typing; now via Debug hook), ⌘W → alert; Cancel → tab stays dirty |
| Quit with 5 tabs → relaunch restores all 5, active tab, scroll/cursor | Restore of tabs/order/pins/active ✓; cursor+scroll are schema fields wired in E04 (§2.4) |
| ⌘1…⌘9 and ⌃⇥ navigation match the order shown in the bar | Open 9+ tabs, exercise every shortcut against the visible order |
| Restore with a deleted file: tab dropped, others unaffected, no crash | Quit with tabs open, delete one file, relaunch |

## 8. Handoff notes / known pitfalls

- **Do not** build drag-out-to-new-window, native window tabs, split editor, or touch `ContentAreaView` — all out of scope (E04/E07).
- **Do not** reintroduce prompt-on-open/new. Tabs supersede E02's single-slot flow; the dirty prompt guards close operations only.
- `FileDocument` is a value type: always write the returned instance back into `tabs[i].document`. Forgetting this is the easiest bug to introduce (E02's `WorkspaceModel.save` shows the pattern).
- `pendingCloseTabID` drives exactly one alert. Batch closes must walk the queue via `resolveClose`, never present concurrent prompts.
- `moveTab` clamping lives in `TabStore`, fully unit-tested; the view must not reimplement pin rules.
- `selectTab(at:)` interprets index 8 (⌘9) as "last tab", not "ninth tab".
- Never write `session.json` to the real app-support dir from tests — always inject temp-dir stores.
- The cursor/scroll acceptance bullet is **partially deferred**: schema v1 carries the fields; capture/apply lands with E04's editor. State this explicitly in the PR description.
- ⌃⇥ uses `KeyboardShortcut(.tab, modifiers: [.control])`; verify visually that macOS 26 delivers it to the menu command (browsers use the same chord, so it is safe).
- AGENTS.md still says PRs target `rewrite/main`; the repo moved to `master` after PR #23. Follow-up: update AGENTS.md + MIGRATION_PLAN.md §7 (tracked in the PR, not silently rewritten here).
