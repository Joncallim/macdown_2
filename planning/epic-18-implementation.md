# EPIC-18 Implementation Architecture — Live external-file changes

> **Issue:** #30 — `[EPIC-18] Live external-file changes: watcher, auto-reload, conflict flow`
>
> **Status:** Implemented in the Epic 18 working tree. FileCore now provides
> stable snapshots, conditional-save reconciliation, recovery buffering, and
> parent/file monitoring; the app integrates those contracts through the
> external-file controller, native windows, and status UI. Local package and
> app validation remains a required proof gate before publication; hosted CI,
> release dogfooding, and full UI-runner evidence must not be inferred from
> this document.
>
> **Branch:** `epic/18-external-file-changes` → draft PR into `master`.
>
> **Depends on:** E01 as built (`FileDocument`, `FileStore`, recovery), E03 as built (one document per native `NSWindow` tab), E04 as built (`EditorTextSystem`), and E09 only as evidence for the repository's accepted `DispatchSource` style. **E18 must not depend on, modify, or reuse the `FileTree` module.**
>
> **Priority decision:** implement E18 before E10. E10 improves editing feel; E18 closes a data-safety gap and is an explicit checkpoint/dogfooding gate. A daily-use editor must not silently ignore or overwrite external edits.
>
> **No new third-party dependencies. No `Package.swift`, `project.yml`, or CI workflow changes are expected.** FileCore may use Foundation, Dispatch, Darwin, and CryptoKit supplied by the platform.

---

## 1. Binding product behaviour

The implementation is complete only when all of these behaviours hold:

1. A clean open document reloads promptly when its backing file changes.
2. A dirty open document never loses local text when its backing file changes; it enters the existing `.conflict` state.
3. A MacDown 2 save never creates a false external conflict.
4. Atomic replacement (`temp file` → rename/replace over destination) is detected.
5. A same-directory rename follows the original file when identity proves the move.
6. Deletion, permission loss, parent-directory loss, and ambiguous identity preserve the in-memory text and make it recoverable.
7. Rapid writes coalesce; only the latest stable result is reconciled.
8. Selection and scroll position are preserved and clamped on clean reload where possible.
9. Monitoring stops when the window closes and stale callbacks cannot mutate a replacement document.
10. The watcher never writes, saves, closes, blanks, or directly mutates a document. It reports typed observations only.

### User-visible policy

- **Clean external change:** reload automatically and show a transient, non-modal “Reloaded from disk” status.
- **Dirty external change:** keep local text and show a persistent inline conflict banner.
- **Conflict actions:**
  - **Use Disk Version** — probe again, then replace with the latest stable disk snapshot.
  - **Keep My Changes** — acknowledge the latest observed disk revision and leave the document dirty; no write occurs until the user saves.
  - **Not Now** — make no state change. The conflict indication remains.
- **Backing file unavailable:** keep the text, make it dirty/recoverable, and offer **Save As…**. Never recreate or overwrite the old path implicitly.

---

## 2. Non-negotiable architecture rules

1. **One monitor per file-backed `WindowController`.** A native window is the lifetime owner of the editor, parser, highlighter, and this monitor.
2. **`FileDocument` remains a value type.** Reconciliation is expressed as pure synchronous transitions returning a new document and a named disposition.
3. **Kernel notifications are invalidations, not truth.** A vnode event means “probe the current state”; event flags do not decide reload/conflict directly.
4. **Watch the parent directory and the bound file.** Atomic replacement destroys the watched inode, while in-place writes may only notify the file vnode. Keep both watches armed and re-arm both after parent recreation.
5. **No modification-date-only comparison.** Stable content digests are authoritative; modification date and size are supporting metadata.
6. **No timing-window self-save suppression.** Do not use `ignoreNextEvent`, `Date()` windows, or event counts. A successful save returns the exact new revision; later observations reconcile against content and that revision.
7. **No polling loop.** There must be no periodic idle wake-up. A one-shot delayed confirmation after an event is allowed.
8. **No FileTree coupling.** Do not move E09’s watcher into FileCore, import FileTree, or route document events through folder-tree models.
9. **No second conflict truth.** `FileDocument.state == .conflict` is authoritative. Controllers may cache the latest external snapshot for presentation/action, but not a parallel conflict boolean.
10. **All ranges are UTF-16.** Use `NSString.length`/`NSRange`; never clamp editor selections with `String.count`.

---

## 3. Data flow

```text
parent-directory DispatchSource
        │ coarse invalidation
        ▼
DocumentFileMonitor actor
        │ debounce + binding/request generation guard
        ▼
DocumentFileProber
        │ stable read + identity classification
        ▼
DocumentFileObservation
        │ typed immutable value (expected URL + binding/request generations)
        ▼
ExternalFileController (@MainActor, one per WindowController)
        │ pure FileDocument transition
        ├── Workspace/TabStore value replacement
        ├── EditorTextSystem external replacement
        ├── recovery/session persistence
        └── inline status/conflict UI
```

Disk reads, directory scans, and SHA-256 calculation must not run on the main actor. `FileDocument` transition logic and app-model mutation must not run on a DispatchSource queue.

---

## 4. FileCore contracts

### 4.1 New `FileSnapshot.swift`

Add these public values:

```swift
import Foundation

public struct FileRevision: Sendable, Equatable {
    public let url: URL
    public let modificationDate: Date?
    public let fileSize: Int
    public let fileObjectID: PhysicalFileIdentity.FileObjectID?
    public let sha256: String

    public init(
        url: URL,
        modificationDate: Date?,
        fileSize: Int,
        fileObjectID: PhysicalFileIdentity.FileObjectID?,
        sha256: String
    )
}

public struct FileSnapshot: Sendable, Equatable {
    public let text: String
    public let encodingRawValue: UInt
    public let revision: FileRevision

    public var encoding: String.Encoding {
        String.Encoding(rawValue: encodingRawValue)
    }

    public init(text: String, encoding: String.Encoding, revision: FileRevision)
}
```

Digest format is lowercase hexadecimal SHA-256 over the exact file bytes read from disk. `fileSize` is byte count, not character count.

Add an internal metadata value used to prove read stability:

```swift
struct FileMetadata: Sendable, Equatable {
    let modificationDate: Date?
    let fileSize: Int
    let fileObjectID: PhysicalFileIdentity.FileObjectID?
    let isRegularFile: Bool
}
```

### 4.2 Modify `FileStore.swift`

Extend `FileStoreError` with explicit cases:

```swift
case fileChangedDuringRead
case notRegularFile
case fileMissing
case permissionDenied
```

Preserve existing cases for source compatibility where practical.

Required public APIs:

```swift
public func readSnapshot(from url: URL) throws(FileStoreError) -> FileSnapshot

@discardableResult
public func write(
    _ content: String,
    to url: URL,
    encoding: String.Encoding = FileStore.defaultEncoding
) throws(FileStoreError) -> FileRevision
```

`read(from:)` may delegate to `readSnapshot(from:)` and return its text/encoding.

#### Stable-read algorithm

For at most two attempts:

1. Read pre-I/O metadata with resource keys for modification date, file size, regular-file status, volume identifier, and file resource identifier.
2. Reject a non-regular file.
3. Read `Data` from the path.
4. Read post-I/O metadata.
5. Accept only when:
   - pre/post file object identity match when both are available;
   - pre/post size and modification date match;
   - post size equals `data.count`.
6. Decode using the existing BOM/UTF fallback order.
7. Calculate SHA-256 over the accepted `Data`.
8. Return one `FileSnapshot` whose revision is built from post-I/O metadata.

If the two metadata reads disagree, retry once. If the second attempt is also unstable, throw `.fileChangedDuringRead`; never return a torn snapshot.

Map Cocoa/POSIX errors to `.fileMissing` and `.permissionDenied` where determinable. Preserve the underlying error in existing failure cases for other failures.

#### Write algorithm

Keep the existing sibling-temp + replacement design. After replacement completes, call `readSnapshot(from:)` or a metadata/digest helper against the destination and return that exact revision. Mark the method `@discardableResult` so unchanged call sites may ignore it during migration.

The returned revision is the self-save suppression mechanism. Do not add an “ignore next watcher event” flag. At the write boundary, ordinary saves revalidate the acknowledged baseline; if the disk changed during monitor debounce, the write fails closed into the existing conflict flow. FileStore also verifies the post-publication bytes so a replacement racing the final read cannot be reported as the revision MacDown wrote.

### 4.3 Modify `FileDocument.swift`

Replace the mtime-only baseline with a content-aware baseline:

```swift
public private(set) var lastKnownRevision: FileRevision?
public private(set) var pendingExternalRevision: FileRevision?
public private(set) var backingState: FileBackingState

public var lastKnownModificationDate: Date? {
    lastKnownRevision?.modificationDate
}
```

`lastKnownModificationDate` remains as a compatibility readout, not independent mutable state.

Add:

```swift
public enum FileBackingIssue: Sendable, Equatable {
    case missingOrMoved
    case permissionDenied
    case parentUnavailable
    case notRegularFile
    case ambiguousMove
    case moveCollidesWithOpenDocument
    case readFailed(String)
}

public enum FileBackingState: Sendable, Equatable {
    case untitled
    case available
    case unavailable(FileBackingIssue)
}
```

Initialization:

- `fileURL == nil` → `.untitled`.
- `fileURL != nil` → `.available` until a load/probe establishes otherwise.

Update lifecycle methods:

- `load()` uses `readSnapshot`, sets text/revision/available/clean.
- `save()` uses the returned revision, sets revision/available/clean, clears pending conflict.
- `saveAs(_:)` must update **fileURL, id, format, revision, backing state, pending conflict, and clean state**. Reuse the identity/format logic in `renamed(to:)`; do not duplicate format fallback code.
- `renamed(to:)` must update the URL in `lastKnownRevision` only when the caller supplies a proven new revision. The existing in-app rename path may keep content metadata but must rewrite the revision URL.
- Remove or replace the old mtime-only `detectExternalChange()` implementation. It must not remain an apparently authoritative API.
- Replace the old I/O-performing `resolveConflict(.useExternal)` path with pure transitions fed a `FileSnapshot` by the controller.

### 4.4 New `FileDocument+ExternalChanges.swift`

Add:

```swift
public enum ExternalReconciliationDisposition: Sendable, Equatable {
    case noChange
    case metadataAdvanced
    case reloaded
    case localNowMatchesDisk
    case conflicted
    case conflictUpdated
    case conflictClearedToDirty
    case backingUnavailable
}

public struct ExternalReconciliation: Sendable {
    public let document: FileDocument
    public let disposition: ExternalReconciliationDisposition
}
```

Required pure methods:

```swift
public func reconcilingExternalSnapshot(_ snapshot: FileSnapshot) -> ExternalReconciliation

public func keepingLocalChanges(
    acknowledging revision: FileRevision
) -> FileDocument

public func reloadedFromExternal(_ snapshot: FileSnapshot) -> FileDocument

public func markingBackingUnavailable(_ issue: FileBackingIssue) -> FileDocument

public func rebindingExternalMove(to snapshot: FileSnapshot) -> FileDocument
```

#### Snapshot reconciliation — exact order

Run these checks before switching on document state:

**Check 1 — disk equals current in-memory text**

When `snapshot.text == text`:

- retain the text;
- set `.clean`;
- set `lastKnownRevision = snapshot.revision`;
- clear `pendingExternalRevision`;
- set backing `.available`;
- return `.localNowMatchesDisk` unless every lifecycle field was already equal, then `.noChange`.

This handles own-save notifications, an external tool writing exactly the local text, and a missing file reappearing unchanged.

**Check 2 — disk still equals the acknowledged baseline**

When `snapshot.revision.sha256 == lastKnownRevision?.sha256`:

- advance baseline metadata to `snapshot.revision`;
- set backing `.available`;
- preserve `.dirty` and `.promptingClose`;
- convert `.conflict` to `.dirty` and clear pending revision because the external divergence disappeared;
- do not change text;
- return `.conflictClearedToDirty` or `.metadataAdvanced`.

**Check 3 — disk text differs from both local and baseline**

| Current state | Required transition |
|---|---|
| `.clean` | replace text with snapshot; remain `.clean`; set new baseline; `.reloaded` |
| `.dirty` | keep local text; set `.conflict`; retain old baseline; set pending revision; `.conflicted` |
| `.conflict` | keep local text; remain `.conflict`; replace pending with newest revision; `.conflictUpdated` |
| `.promptingClose` | keep local text; set `.conflict`; set pending revision; `.conflicted` |

`keepingLocalChanges(acknowledging:)` keeps text, sets baseline to the supplied latest external revision, clears pending, sets backing available, and sets state dirty. It performs no I/O.

`reloadedFromExternal(_:)` sets snapshot text/revision, backing available, clears pending, and sets state clean. It is not `updatingText(_:)`; user-edit semantics must never be used for a disk-matching reload.

`markingBackingUnavailable(_:)`:

- never changes text or fileURL;
- sets backing unavailable;
- clears pending revision;
- converts `.clean`, `.conflict`, and `.promptingClose` to `.dirty` so the in-memory copy is recoverable and cannot close silently;
- preserves `.dirty`.

### 4.5 New `DocumentDirectoryWatcher.swift`

Internal watcher seam:

```swift
enum DocumentDirectorySignal: Sendable, Equatable {
    case changed
    case parentVanished
}

protocol DocumentDirectoryWatcherHandle: Sendable {
    func cancel()
}

protocol DocumentDirectoryWatching: Sendable {
    func watch(
        _ directoryURL: URL,
        onSignal: @escaping @Sendable (DocumentDirectorySignal) -> Void
    ) throws -> any DocumentDirectoryWatcherHandle
}
```

Concrete implementation uses `open(path, O_EVTONLY)` and one `DispatchSourceFileSystemObject` on the parent directory.

Event mask:

```swift
[.write, .rename, .delete, .revoke, .attrib, .extend, .link]
```

Classification:

- `.delete`, `.rename`, or `.revoke` affecting the watched parent → `.parentVanished`.
- all other masks → `.changed`.

The file descriptor is closed only from the dispatch source cancel handler. `cancel()` is lock-protected and idempotent. The source callback contains no disk reads and no model mutation.

Use a dedicated utility queue with a stable label, for example `com.macdown.filecore.document-watcher`.

### 4.6 New `DocumentFileProbe.swift`

Public observation:

```swift
public enum DocumentFileObservation: Sendable, Equatable {
    case available(FileSnapshot)
    case moved(FileSnapshot)
    case missing(URL)
    case unavailable(URL, FileBackingIssue)
}
```

Internal seam:

```swift
protocol DocumentFileProbing: Sendable {
    func observe(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?
    ) async -> DocumentFileObservation
}
```

The real prober performs blocking FileManager/FileStore work in a detached utility task, never on the main actor.

#### Identity-classification algorithm

1. Attempt a stable snapshot at `expectedURL`.
2. If it exists and either:
   - no prior object ID is known; or
   - its object ID matches the prior object ID;
   return `.available`.
3. If it exists but its object ID differs from the prior object ID, scan the immediate parent directory for entries matching the prior object ID:
   - exactly one different-path match → read it stably and return `.moved`;
   - multiple matches → `.unavailable(expectedURL, .ambiguousMove)`;
   - no match → treat the path as an atomic replacement and return `.available` for the new object.
4. If `expectedURL` is missing and a prior object ID exists, scan the immediate parent:
   - exactly one match → stable-read it and return `.moved`;
   - multiple matches → ambiguous;
   - no match → missing.
5. If the parent cannot be read, return `.parentUnavailable` or `.permissionDenied` as appropriate.
6. Never recursively search outside the immediate parent. Cross-directory moves are surfaced as missing.

This ordering handles the difficult sequence “rename original, then create another file at the old path”: the open document follows the proven original object, not the replacement path.

### 4.7 New `DocumentFileMonitor.swift`

Public actor:

```swift
public actor DocumentFileMonitor {
    public init(debounce: Duration = .milliseconds(150))

    public func bind(
        to fileURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        onObservation: @escaping @Sendable (DocumentFileObservation) -> Void
    ) async throws

    public func updatePriorFileObjectID(
        _ id: PhysicalFileIdentity.FileObjectID?
    )

    public func snapshotNow() async -> DocumentFileObservation

    public func cancel()
}
```

Provide an internal initializer accepting fake watcher, prober, and sleeper seams for tests.

Internal state:

```swift
private var generation: UInt = 0
private var boundURL: URL?
private var priorFileObjectID: PhysicalFileIdentity.FileObjectID?
private var handle: (any DocumentDirectoryWatcherHandle)?
private var debounceTask: Task<Void, Never>?
private var callback: (@Sendable (DocumentFileObservation) -> Void)?
```

#### Bind

1. Increment generation.
2. Cancel debounce and old handle.
3. Standardize the URL; store identity/callback.
4. Watch its parent directory.
5. Capture the generation in the watcher callback.
6. Trigger one immediate probe after the watcher is armed. This closes the load→watch race.

#### Signal handling

On either signal:

1. Capture current generation.
2. Cancel prior debounce task.
3. Sleep 150 ms.
4. Probe.
5. If result is `.missing`, sleep an additional 75 ms and probe once more. Emit missing only if confirmed. This absorbs the transient gap in temp-file replacement.
6. Before every emission, require generation and bound URL still match.
7. Emit only the latest observation through the stored closure.

`parentVanished` still goes through the probe; do not infer that the file itself vanished solely from the source flags.

#### Rebind/cancel safety

- Every bind/cancel increments generation.
- A callback from an old handle, a cancelled sleep, or an old probe is ignored.
- `cancel()` clears callback and URL after cancelling work.
- There is no repeating task and no idle timer.

---

## 5. Workspace and recovery contracts

### 5.1 Modify `WorkspaceError.swift`

Add named errors:

```swift
case unresolvedExternalConflict
case backingFileUnavailable(FileBackingIssue)
```

Their UI text must be actionable and must not expose raw POSIX diagnostics unless no classified message exists.

### 5.2 Modify `TabStore.canSave`

Rules:

- conflict → false for ordinary Save;
- dirty + available saved path → true;
- dirty + unavailable backing → true because Save routes to Save As;
- untitled with content → true;
- clean → false.

Save As remains enabled whenever a document exists, including conflict state.

### 5.3 Modify `WorkspaceModel.save()`

Exact order:

1. No active document → existing no-document error.
2. Conflict → set `.unresolvedExternalConflict`; do not write.
3. Untitled or backing unavailable → call `saveAs()`.
4. Otherwise call `document.save()`.
5. Replace active document with returned clean document.
6. Immediately remove any recovery buffer under the document’s current ID.
7. Clear error.

### 5.4 Modify `WorkspaceModel.saveAs()`

1. Capture `oldID` and old URL before the panel/write.
2. Allow Save As from dirty, conflict, unavailable, and untitled states.
3. Write through corrected `FileDocument.saveAs`.
4. Replace active document.
5. Remove recovery buffers under both old and new IDs.
6. Clear error.

The caller then rebinds the monitor to the new path. Workspace must not own monitor lifecycle.

### 5.5 Recovery invariants

Every transition to clean removes stale recovery content:

- ordinary save;
- Save As;
- clean external reload;
- disk becoming identical to local text;
- Use Disk Version.

Every conflict/unavailable transition persists local text promptly, without waiting solely for the 300 ms session debounce.

When a dirty/conflicted document follows a proven external rename, migrate recovery from old ID to new ID before removing the old key.

### 5.6 Modify `TabStore+Session.swift`

When restoring a file-backed tab:

- load disk and establish baseline first;
- if a different recovery snapshot exists, apply it as a dirty local edit while retaining the disk baseline;
- if disk load fails but recovery exists, restore the recovery text and mark backing unavailable/missing;
- never present a missing restored file as clean/available.

Do not persist the cached external snapshot. After restore, the monitor probes again and any recovered local copy begins as dirty.

### 5.7 Close semantics

Do not let a conflict silently degrade to ordinary dirty state on Cancel.

Change `FileDocument.requestClose()` so `.conflict` remains `.conflict` while requesting UI attention. Existing `resolveClose(.cancel)` must preserve conflict unless the prior state was genuinely `.promptingClose` from dirty state.

`WindowController.windowShouldClose` must branch:

- `.clean` → close;
- `.dirty` / unavailable → existing Save / Cancel / Discard flow, with Save routing to Save As when unavailable;
- `.conflict` → conflict-specific sheet:
  - **Keep My Changes and Save**: acknowledge latest external revision, save, close only if save succeeds;
  - **Use Disk Version and Close**: fresh probe, reload, close only if clean;
  - **Cancel**: preserve conflict and window.

Every asynchronous completion re-reads the current document state before closing. A second external change may arrive while the sheet is open.

---

## 6. EditorCore contracts

### 6.1 New `EditorViewportSnapshot.swift`

```swift
import AppKit

public struct EditorViewportSnapshot: Equatable {
    public let selectedRange: NSRange
    public let scrollOffset: CGFloat

    public init(selectedRange: NSRange, scrollOffset: CGFloat)
}
```

### 6.2 Modify `EditorTextSystem`

Add:

```swift
public func viewportSnapshot() -> EditorViewportSnapshot

public func replaceTextFromExternal(
    _ text: String,
    preserving snapshot: EditorViewportSnapshot,
    clearUndo: Bool
)
```

Exact replacement order:

1. Set an internal `isPerformingProgrammaticTextUpdate` flag.
2. Replace the text.
3. Increment content revision and invalidate frame measurements.
4. Clamp selection against `(text as NSString).length`.
5. Restore clamped selection.
6. Set pending scroll offset to `max(0, snapshot.scrollOffset)`.
7. If `clearUndo`, call `undoManager.removeAllActions()`.
8. Schedule frame-height sync; after sync, apply pending scroll offset.
9. Clear programmatic-update flag with `defer`.

`EditorView.Coordinator.textDidChange` must return immediately when the system is performing a programmatic update. The model replacement is written separately by `ExternalFileController`; this prevents a disk reload from flowing through `edited(text:)` and becoming dirty.

A keep-local/conflict path does not call this method and therefore preserves undo history.

---

## 7. App-target ownership and wiring

### 7.1 New `ExternalFileController.swift`

```swift
@MainActor
@Observable
final class ExternalFileController {
    enum Notice: Equatable {
        case none
        case reloaded
        case moved(URL)
        case conflict
        case unavailable(FileBackingIssue)
        case monitorFailed(String)
    }

    private(set) var notice: Notice
    private(set) var latestExternalSnapshot: FileSnapshot?

    @ObservationIgnored private let monitor: DocumentFileMonitor
    @ObservationIgnored private weak var model: WorkspaceModel?
    @ObservationIgnored private let editorStore: EditorTextSystemStore
    @ObservationIgnored private let identity: String
    @ObservationIgnored private weak var coordinator: WindowCoordinator?
    @ObservationIgnored private weak var owner: WindowController?
    @ObservationIgnored private var boundURL: URL?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var disposed = false
}
```

Required methods:

```swift
func start()
func synchronize(with document: FileDocument?)
func handle(_ observation: DocumentFileObservation)
func resolveConflict(_ resolution: ConflictResolution) async
func dispose()
```

#### `start` / `synchronize`

- Untitled document → cancel monitor and clear bound URL.
- File-backed document whose URL differs from bound URL → bind using its baseline object ID.
- Same URL with a newer baseline after save/reload → update monitor’s prior object ID.
- Binding failure → show `.monitorFailed`; do not alter document text/state.

#### `handle(.available(snapshot))`

1. Reject when disposed, current document is absent, or snapshot URL no longer matches current bound URL.
2. Run `reconcilingExternalSnapshot`.
3. For `.reloaded` or `.localNowMatchesDisk` where text changes:
   - capture editor viewport;
   - call `replaceTextFromExternal(..., clearUndo: true)`;
   - replace the active `FileDocument` value;
   - remove stale recovery;
   - show transient `.reloaded` for two seconds.
4. For `.conflicted`/`.conflictUpdated`:
   - keep editor untouched;
   - cache the latest snapshot;
   - replace document state;
   - immediately persist local recovery;
   - show persistent `.conflict`.
5. For metadata/no-change:
   - replace document only when lifecycle metadata changed;
   - clear stale transient/conflict presentation as appropriate.
6. Update known file object ID and schedule session persistence.

#### `handle(.moved(snapshot))`

1. Ask coordinator whether another window already owns the destination, excluding this owner.
2. Collision → preserve text; mark unavailable `.moveCollidesWithOpenDocument`; do not rebind.
3. Otherwise:
   - capture old ID;
   - rebind document URL/id/format to snapshot URL;
   - reconcile snapshot using the old content baseline;
   - migrate recovery when local work remains dirty/conflicted;
   - update represented URL/title via normal model observation;
   - rebind monitor to the new parent/path;
   - show transient `.moved` if no conflict, otherwise the conflict banner.

Do **not** call `WindowCoordinator.documentWasRenamed(from:to:)`; that method describes an in-app FileTree operation and would incorrectly mutate folder roots/recent roots for an externally observed document move.

#### `handle(.missing/.unavailable)`

- apply `markingBackingUnavailable`;
- keep editor text untouched;
- clear cached external snapshot;
- immediately persist local recovery;
- show persistent unavailable status;
- schedule session save.

Never auto-close a clean document after disappearance.

#### `resolveConflict`

- `.cancel`: no lifecycle change; conflict notice remains.
- `.keepMine`:
  1. use cached latest stable snapshot or call `monitor.snapshotNow()`;
  2. only acknowledge a stable available/moved revision;
  3. call `keepingLocalChanges`;
  4. clear conflict notice, leave dirty, keep recovery;
  5. do not save.
- `.useExternal`:
  1. always call `snapshotNow()` immediately before replacement;
  2. only stable available/moved observations may discard local text;
  3. capture viewport and replace editor with latest snapshot, clear undo;
  4. apply `reloadedFromExternal`, remove recovery, clear notice;
  5. missing/unavailable result preserves local text and becomes unavailable.

### 7.2 Modify `WindowController.swift`

Add one `ExternalFileController` property. Construct it after the active editor text system is created, pass it into the SwiftUI shell, and call `start()` after initialization.

Dispose it in `windowWillClose`; `deinit` performs best-effort cancellation as a second guard.

Add wrappers:

```swift
func saveDocument() async
func saveDocumentAs() async
```

Each calls the model method, then immediately synchronizes monitor binding/revision from the resulting active document. Ordinary `saveDocument` refuses unresolved conflict through Workspace rules.

### 7.3 Modify `WindowCoordinator.swift`

Add:

```swift
func saveKeyDocument()
func saveKeyDocumentAs()
func controllerForDocument(
    url: URL,
    excluding controller: WindowController
) -> WindowController?
```

Generalize the existing dedupe helper; do not create a second URL-equivalence implementation. Continue using `PhysicalFileIdentity.matches`.

### 7.4 Replace all app save call sites

Repository-search and replace direct app-target calls to `WorkspaceModel.save()` / `saveAs()`:

- `WorkspaceCommands` Save and Save As;
- `WindowController.windowShouldClose`;
- deleted-document Save As flow in `WindowCoordinator+FileTree`;
- any additional app-target call discovered during implementation.

Package tests may call Workspace methods directly.

### 7.5 Explicit view injection

Pass `ExternalFileController` explicitly:

```text
WindowController
  → WorkspaceShellView
  → ContentAreaView
  → ExternalFileStatusView
```

Do not put it in `EnvironmentValues`; it is per-window service state, matching explicit injection already used for editor/highlight/parse/outline/tree services.

### 7.6 New `ExternalFileStatusView.swift`

Place below the existing document header and above the editor/preview content. It must not replace the editor or steal first responder.

Accessibility identifiers:

- `externalChangeBanner`
- `externalConflictUseDiskButton`
- `externalConflictKeepMineButton`
- `externalConflictNotNowButton`
- `externalBackingSaveAsButton`
- `externalReloadStatus`

Render all `Notice` cases exhaustively. Conflict/unavailable status is persistent. Reload/move status automatically clears after two seconds using one cancellable task.

---

## 8. Exact state tables

### 8.1 Different disk text

| Current state | Result |
|---|---|
| clean | replace text; clean; new baseline |
| dirty | preserve local; conflict; retain baseline; cache newest external |
| conflict | preserve local; conflict; replace pending external with newest |
| promptingClose | preserve local; conflict; close flow must re-evaluate |

### 8.2 Disk equals local text

For every state: clean, available, new baseline, pending conflict cleared. Remove recovery.

### 8.3 Disk equals acknowledged baseline but differs from local

| Current state | Result |
|---|---|
| clean | not normally reachable; preserve text/state metadata |
| dirty | dirty, available, no conflict |
| conflict | dirty, available, conflict cleared |
| promptingClose | keep prompting-close state |

### 8.4 File unavailable

| Current state | Result |
|---|---|
| clean | preserve text; dirty; unavailable |
| dirty | preserve text; dirty; unavailable |
| conflict | preserve text; dirty; unavailable; clear external pending |
| promptingClose | preserve text; dirty; unavailable |

### 8.5 Conflict actions

| Action | Result |
|---|---|
| Keep My Changes | acknowledge latest disk revision; dirty; no write |
| Use Disk Version | fresh stable probe; replace editor/model; clean; clear undo |
| Not Now | unchanged conflict |
| Save As | write local version to chosen new path; clean; monitor rebind |

---

## 9. Implementation commits

Do not parallelize commits 1–6. Their API order is intentional.

### Commit 1 — `FILECORE: add stable snapshots and repair save-as identity`

- add `FileSnapshot.swift`;
- modify `FileStore.swift`;
- modify `FileDocument.swift`;
- repair Save As URL/id/format/revision;
- add focused FileCore tests.

### Commit 2 — `FILECORE: add pure external-change transitions`

- add `FileDocument+ExternalChanges.swift`;
- exhaustive state-table tests;
- no Dispatch, Workspace, AppKit, or UI.

### Commit 3 — `FILECORE: add parent-directory document monitor`

- add `DocumentDirectoryWatcher.swift`;
- add `DocumentFileProbe.swift`;
- add `DocumentFileMonitor.swift`;
- fake-driven monitor tests and real filesystem integration tests;
- no app-target changes.

### Commit 4 — `EDITOR: preserve viewport across external replacement`

- add `EditorViewportSnapshot.swift`;
- modify `EditorTextSystem.swift`, `EditorTextSystem+Scroll.swift`, `EditorView.swift` only as required;
- add EditorCore tests.

### Commit 5 — `WORKSPACE: make conflict, recovery, and unavailable saves safe`

- modify `WorkspaceError.swift`, `WorkspaceModel.swift`, `TabStore.swift`, `TabStore+Close.swift`, `TabStore+Session.swift`;
- add Workspace/recovery tests.

### Commit 6 — `APP: wire one monitor per document window`

- add `ExternalFileController.swift`;
- modify WindowController/Coordinator and explicit view injection;
- route every app save call through controller wrappers;
- compile-safe status placeholder permitted.

### Commit 7 — `UI: add external-change status and conflict actions`

- add `ExternalFileStatusView.swift`;
- modify `ContentAreaView.swift`;
- conflict-specific close sheet and accessibility identifiers.

### Commit 8 — `TEST: cover end-to-end external-change paths`

- UI tests;
- real filesystem tests;
- TSan fixes and measured debounce/performance evidence;
- do not weaken earlier unit tests.

### Commit 9 — `DOCS: record EPIC-18 implementation`

Only after validation:

- convert this plan to implementation record;
- mark the high-level epic implemented;
- update README status/module map;
- change PR body from `Refs #30` to `Closes #30`.

---

## 10. Required tests

### 10.1 FileStore / revision

1. known SHA-256 vectors;
2. byte count differs correctly from character count;
3. read snapshot text/revision agree;
4. same-size different content has different digest;
5. write returns destination revision;
6. non-regular file rejected;
7. unstable read retries then fails;
8. Save As updates URL, ID, format, revision, and clean state.

### 10.2 Pure FileDocument transitions

1. clean + different snapshot → reload clean;
2. clean + same text/new metadata → clean no dirty;
3. dirty + different snapshot → conflict, local preserved;
4. conflict + newer snapshot → pending revision updates;
5. dirty + disk equals local → clean;
6. conflict + disk reverts baseline → dirty, conflict cleared;
7. Keep Mine acknowledges latest and remains dirty;
8. repeated same observation after Keep Mine does not conflict again;
9. Use Disk transition leaves clean/pending nil;
10. Cancel is bit-for-bit unchanged;
11. clean missing → dirty unavailable, text preserved;
12. conflict missing → dirty unavailable, pending cleared;
13. file reappearing with local text → clean available;
14. same-parent move updates URL/id/format;
15. dirty local text survives move;
16. prompting close + external divergence → conflict;
17. cancelling a conflict close preserves conflict.

### 10.3 Monitor tests with fakes

Provide scripted watcher/prober/sleeper fakes and a thread-safe observation recorder.

1. bind watches parent, not file;
2. bind performs initial probe;
3. rapid signals emit one latest observation;
4. rebind invalidates old generation;
5. callback after cancel ignored;
6. transient missing followed by available emits no missing;
7. confirmed missing emits once;
8. parent-vanished signal still probes;
9. update prior identity changes move classification;
10. cancel idempotent, descriptor closes once.

### 10.4 Real filesystem integration

1. in-place external write detected;
2. atomic temp + `replaceItemAt` detected;
3. app `FileStore.write` reconciles without false conflict;
4. same-parent rename detected as moved;
5. rename plus replacement at old path follows original identity;
6. deletion preserves content and surfaces unavailable;
7. permission denial classified where host permits;
8. five rapid atomic saves coalesce to final content;
9. monitor teardown emits no post-close callback.

Assert typed observations after debounce, not exact raw DispatchSource event counts.

### 10.5 Workspace / recovery

1. ordinary Save cannot overwrite unresolved conflict;
2. unavailable Save routes to Save As;
3. Save As clears old and new recovery identities;
4. Keep Mine then Save writes local content;
5. Use Disk leaves `canSave == false`;
6. successful save removes saved-file recovery;
7. external clean transition removes recovery;
8. unavailable/conflict local text is immediately recoverable;
9. restore with disk + different recovery begins dirty against disk baseline;
10. restore missing disk + recovery begins dirty/unavailable.

### 10.6 EditorCore

1. replacement preserves in-bounds selection;
2. selection clamps by UTF-16 after shrink;
3. scroll offset reapplies after frame sync;
4. external replacement clears undo;
5. conflict/keep-local leaves undo untouched;
6. programmatic replacement does not write through Binding;
7. emoji/CJK range preservation uses UTF-16.

Reuse existing TextKit/offscreen harnesses; do not create a second architecture for editor tests.

### 10.7 UI tests

**Dirty conflict:** open fixture, type local text, atomically replace fixture, assert banner, assert local text remains, exercise Not Now, then Use Disk Version, assert external text and clean title.

**Clean reload:** open clean fixture, create non-zero selection/scroll, externally append, assert text appears without modal conflict, assert selection is clamped/preserved, assert transient reload status.

**Close conflict:** create conflict, close tab, exercise each conflict close choice, assert no close occurs on failed/unstable resolution.

UI execution remains a local macOS 26 release gate while hosted CI can only build the test target.

---

## 11. Validation gates

From repository root:

```bash
cd MacDown2/Packages/MacDownKit
swift build
swift test
swift test -c release
swift test --sanitize=thread
```

```bash
cd MacDown2
xcodegen generate
xcodebuild \
  -project MacDown2.xcodeproj \
  -scheme MacDown2 \
  -destination 'platform=macOS' \
  build build-for-testing
```

```bash
swiftformat --lint MacDown2
swiftlint lint --strict MacDown2
git diff --check
```

Record a manual dogfood matrix in the PR for:

- clean in-place edit;
- clean atomic replacement;
- dirty external edit;
- own save;
- Keep Mine then Save;
- Use Disk Version;
- deletion;
- same-parent rename;
- cross-parent move;
- rapid formatter writes;
- window close while debounce/missing confirmation is pending.

Performance evidence must record build configuration and hardware:

- no periodic idle wakeups;
- one watcher per file-backed window;
- release snapshot/digest time for 1 MB and 10 MB files;
- event-to-reconciliation latency separated from intentional debounce;
- no main-actor disk read/digest work.

Do not invent a pass number before measuring.

---

## 12. Lower-tier agent boundaries

### Implementer may

- create/modify only files named in §§4–7 and their direct tests;
- add private helpers required by the exact contracts;
- split a named file only for lint/type-length limits without moving ownership;
- report a toolchain/API mismatch with the exact diagnostic before deviating.

### Implementer must not

- choose `NSFilePresenter` instead of this design;
- touch FileTree;
- add dependencies or edit package/project/CI manifests;
- add polling;
- change native tab architecture;
- add merge/diff/version-history UI;
- change preview, parser, highlighting, or E10 editing behaviour;
- save, overwrite, close, or blank from a watcher callback;
- add a controller-only conflict truth;
- use `Date()`/event-count self-save suppression;
- use `String.count` for editor ranges;
- auto-follow unproven cross-directory moves;
- silently redesign around a compile error.

### Reviewer order

1. data-loss paths;
2. conflict/unavailable Save and close behaviour;
3. generation/cancellation correctness;
4. atomic replacement and identity classification;
5. main-actor blocking-I/O separation;
6. recovery/session identity;
7. viewport/undo semantics;
8. UI accessibility/copy;
9. manifest/FileTree/scope drift.

Reviewer must trace these adversarial sequences explicitly:

- dirty edit → external write → ordinary Save before conflict action;
- Save As while an old watcher callback is queued;
- external rename → immediate write at old path;
- rename original + create replacement at old path;
- window close while missing-confirmation sleep is pending;
- conflict receives second and third external revisions;
- external file reverts to baseline;
- missing file reappears with local text;
- atomic replace changes object ID but keeps path.

### Fix agent

Fix only concrete findings. Keep each remediation narrow. Run focused tests first, then every gate in §11. Do not combine unrelated cleanup.

---

## 13. Acceptance mapping

| Issue #30 acceptance | Owner |
|---|---|
| clean reload | FileDocument reconciler + ExternalFileController + UI test |
| dirty conflict/local preserved | pure transition + inline banner + UI test |
| no false conflict on app save | returned write revision/content pre-check + integration test |
| atomic replacement | parent watcher + prober + real filesystem test |
| deletion/rename safe | identity probe + backing state + integration tests |
| rapid writes coalesced | monitor debounce/generation tests |
| selection/scroll preserved | EditorCore replacement API/tests |
| watcher lifecycle | WindowController ownership + stale-callback tests |
| narrow boundaries | no FileTree/manifest diff; app glue only above FileCore |

---

## 14. Explicit non-goals

- recursive search for files moved to another directory;
- merge editor or three-way conflict resolution;
- file version history;
- cloud-provider-specific coordination;
- guaranteed vnode semantics on every network filesystem;
- folder-browser watcher changes;
- ordinary saved-document autosave;
- E10 editing assists;
- background polling fallback;
- global multi-document filesystem daemon;
- symlink-target-specific monitoring beyond events observable at the bound lexical path.

---

## 15. Definition of done

The PR remains draft until:

- implementation matches these contracts or every deviation is documented and approved;
- package debug/release tests, TSan, app build-for-testing, format, lint, and diff checks pass;
- real atomic replacement, self-save, rename, and teardown tests pass;
- dirty conflict UI test runs on a macOS 26 host;
- manual dogfood matrix and measured performance evidence are posted;
- no new dependency, manifest, FileTree, preview/parser, or native-tab drift exists;
- review has zero unresolved blocker/high/medium data-safety findings;
- README/epic docs are updated from planned to implemented;
- only then does the PR body change from `Refs #30` to `Closes #30`.
