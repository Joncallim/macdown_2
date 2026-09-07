import AppKit
import EditorCore
import Foundation
import TextFilters
import Workspace

/// Orchestrates running one discovered text-filter command against a
/// document's active editor (epic-14-implementation.md §7.2, §17 Slice 6).
///
/// A value type with no stored state of its own, mirroring
/// `ExportCoordinator`'s shape: the window coordinator hands one out per
/// menu/palette evaluation, and nothing must survive between them. The
/// running command's own lifetime is owned by the originating
/// `WindowController` (`registerTextFilterTask`/`clearTextFilterTask`), not
/// by this struct or by an unstructured `Task` the caller forgets to keep a
/// handle to (post-review finding #5).
@MainActor
struct TextFilterCoordinator {
    private let coordinator: WindowCoordinator
    /// Presents one failure alert. A real `NSAlert` sheet by default;
    /// overridable so tests can deterministically assert *whether* a
    /// failure would have been presented (and to whom) without driving
    /// real UI (post-review finding #7's own suggestion — "introduce a
    /// small alert-presenter/test seam rather than making the UI behavior
    /// untestable").
    private let alertPresenter: (Error, String, NSWindow) async -> Void

    init(
        coordinator: WindowCoordinator,
        alertPresenter: @escaping (Error, String, NSWindow) async -> Void = TextFilterCoordinator.presentAlert
    ) {
        self.coordinator = coordinator
        self.alertPresenter = alertPresenter
    }

    /// `true` when the key window has an active document with a live
    /// editor text system. Text filters operate on plain selected/whole
    /// text (§5) — no format restriction, unlike the Markdown- and
    /// JSON-specific formatting commands.
    var canRunTextFilters: Bool {
        keyEditingTarget != nil
    }

    /// Runs `command` against the key window's active editor — the entry
    /// point used by the Commands menu, where "key window" is exactly the
    /// window the user is looking at.
    func run(_ command: TextFilterCommand) async {
        guard let target = keyEditingTarget else { return }
        await run(command, against: target)
    }

    /// Runs `command` against an explicit `target` rather than resolving
    /// one from `NSApp.keyWindow`.
    ///
    /// This is the seam the command palette uses: the palette itself
    /// becomes the key window while it is open, so a filter it invokes
    /// must target the document window the palette was opened *from*,
    /// captured before presentation — not whatever window happens to be
    /// key by the time this async command completes (post-review
    /// finding #7). It also lets tests drive the full mutation/undo/
    /// staleness path against a real `EditorTextSystem` without depending
    /// on real window-server key-window state (finding #12).
    ///
    /// Applies the output as exactly one undoable edit on success; shows
    /// an alert naming the command on failure, except cancellation, which
    /// is a deliberate withdrawal, not an error (§9). A completion that
    /// arrives after the originating document changed (a live edit,
    /// external reload, tab close, ...) is discarded without mutating
    /// anything — mirroring `WindowCoordinator.performJSONFormatting`'s
    /// same stale-completion policy (post-review finding #1).
    func run(_ command: TextFilterCommand, against target: TextFilterEditingTarget) async {
        let selection = target.textSystem.textView.selectedRange()
        let liveText = target.textSystem.textView.string as NSString
        let scope: ReplacementScope = selection.length == 0 ? .wholeDocument : .selection(selection)
        let input = scope.isWholeDocument ? (liveText as String) : liveText.substring(with: selection)

        let baseline = TextFilterBaseline(
            tabID: target.tabID,
            documentGeneration: target.documentGeneration,
            editorContentRevision: target.textSystem.contentRevision,
            scope: scope
        )
        let controller = target.controller
        let documentURL = target.documentURL

        let task = Task { @MainActor in
            do {
                let output = try await TextFilterRunner().run(command, input: input, documentURL: documentURL)
                applyIfStillCurrent(output, baseline: baseline, controller: controller, commandName: command.name)
            } catch TextFilterError.cancelled {
                // The user withdrew the action (e.g. closed the window mid-run);
                // there is nothing to report (§9).
            } catch {
                // A genuine failure (launch/nonzero-exit/timeout/...) can
                // race a supersession or window close: the task backing
                // this run may already be cancelled, or its originating
                // window may already be gone, by the time the error
                // reaches here. Either way withdrawal wins — surfacing an
                // alert for a run the user (or a newer run) already
                // withdrew would contradict the same "cancellation is
                // silent" policy this catches TextFilterError.cancelled
                // for, and falling back to a global `runModal()` alert
                // when the origin is gone would turn a window-owned
                // operation into an app-wide interruption
                // (second-adversarial-pass finding #7).
                guard !Task.isCancelled, let window = controller.window else { return }
                await alertPresenter(error, command.name, window)
            }
        }
        let token = controller.registerTextFilterTask(task, forTab: target.tabID)
        await task.value
        controller.clearTextFilterTask(forTab: target.tabID, token: token)
    }

    // MARK: - Applying a successful result

    /// Rejects the result unless `controller`'s tab `baseline.tabID` still
    /// exists, its document generation and its editor's content revision
    /// exactly match the command-time baseline. Any mismatch means an
    /// incompatible change happened while the command ran (or the tab/
    /// window is gone) — the live text is left untouched rather than
    /// having a stale range/snapshot spliced or overwritten into it
    /// (post-review finding #1).
    private func applyIfStillCurrent(
        _ output: String,
        baseline: TextFilterBaseline,
        controller: WindowController,
        commandName: String
    ) {
        guard !Task.isCancelled,
              let tab = controller.model.tabStore.tabs.first(where: { $0.id == baseline.tabID }),
              let textSystem = controller.editorStore.existingSystem(for: baseline.tabID.uuidString),
              tab.document.mutationGeneration == baseline.documentGeneration,
              textSystem.contentRevision == baseline.editorContentRevision
        else {
            return
        }

        let liveLength = (textSystem.textView.string as NSString).length
        let targetRange: NSRange = if case let .selection(range) = baseline.scope {
            range
        } else {
            NSRange(location: 0, length: liveLength)
        }
        textSystem.applyExternalReplacement(output, in: targetRange, undoActionName: commandName)
    }

    // MARK: - Failure presentation

    /// Presents the failure sheeted on the originating document's own
    /// window — never whatever window happens to be key when the alert is
    /// about to show (post-review finding #5/#7) — and never as a global
    /// `runModal()` fallback: a live `window` is a precondition the one
    /// caller above already checked, not something this method falls back
    /// around (finding #7).
    private static func presentAlert(_ error: Error, commandName: String, on window: NSWindow) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\"\(commandName)\" Failed"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            alert.beginSheetModal(for: window) { _ in continuation.resume() }
        }
    }

    // MARK: - Target resolution

    /// Everything a filter run needs to know about the document it targets,
    /// captured once at invocation time. Not `private` — the command
    /// palette builds one via `editingTarget(for:)` from an explicit
    /// origin controller, and app-target tests build one directly against
    /// a real `WindowController`/`EditorTextSystem` (finding #12).
    struct TextFilterEditingTarget {
        let controller: WindowController
        let tabID: UUID
        let textSystem: EditorTextSystem
        let documentURL: URL?
        let documentGeneration: UInt
    }

    /// Whether a run targets the current selection or the whole document —
    /// folded together with the selection range itself so the baseline and
    /// the later replacement carry one value instead of two correlated ones.
    private enum ReplacementScope {
        case selection(NSRange)
        case wholeDocument

        var isWholeDocument: Bool {
            if case .wholeDocument = self {
                true
            } else {
                false
            }
        }
    }

    private struct TextFilterBaseline {
        let tabID: UUID
        let documentGeneration: UInt
        let editorContentRevision: UInt64
        let scope: ReplacementScope
    }

    private var keyEditingTarget: TextFilterEditingTarget? {
        guard let controller = coordinator.controllers.first(where: { $0.window == NSApp.keyWindow }) else {
            return nil
        }
        return Self.editingTarget(for: controller)
    }

    /// Builds an editing target for `controller`'s active tab, if it has a
    /// live editor — independent of `NSApp.keyWindow`, so the command
    /// palette can resolve the window it was opened from rather than
    /// whatever window is key once its async command completes
    /// (post-review finding #7).
    func editingTarget(for controller: WindowController) -> TextFilterEditingTarget? {
        Self.editingTarget(for: controller)
    }

    private static func editingTarget(for controller: WindowController) -> TextFilterEditingTarget? {
        guard let activeTab = controller.model.tabStore.activeTab,
              let textSystem = controller.editorStore.existingSystem(for: activeTab.id.uuidString)
        else {
            return nil
        }
        return TextFilterEditingTarget(
            controller: controller,
            tabID: activeTab.id,
            textSystem: textSystem,
            documentURL: activeTab.document.fileURL,
            documentGeneration: activeTab.document.mutationGeneration
        )
    }
}
