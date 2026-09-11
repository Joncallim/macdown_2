import AppKit
import FileCore
import Foundation

extension WindowController {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let coordinator, coordinator.controllers.contains(where: { $0 === self }) else { return true }
        // Workspace recovery cleanup owns an exact lifetime retry. Do not let
        // AppKit discard the window while that action is still the only safe
        // route to retire or remove its prior recovery state.
        guard !model.hasPendingRecoveryCleanup else { return false }
        guard let document = model.activeDocument else {
            coordinator.removeController(self)
            return true
        }
        if document.state == .clean {
            Task { @MainActor [weak self] in
                guard let self,
                      await (externalFileController.retireRecovery(
                          for: document,
                          resumeCloseOnSuccess: true
                      )).isAbsent
                else { return }
                coordinator.removeController(self)
                close()
            }
            return false
        }
        let presentedContext = CloseSheetContext(document)
        if document.state == .conflict {
            presentConflictCloseSheet(for: sender)
            return false
        }
        presentDirtyCloseSheet(for: sender, context: presentedContext)
        return false
    }

    private func presentDirtyCloseSheet(for sender: NSWindow, context: CloseSheetContext) {
        let alert = NSAlert()
        let fileName = context.fileURL?.lastPathComponent ?? "Untitled"
        // #57: a document whose backing file was deleted/moved externally is
        // still just `.dirty` here (`FileDocumentState` has no distinct case
        // for that — see `FileBackingState.unavailable`), so it used to reach
        // this exact same "Save / Cancel / Discard Changes" alert with no
        // hint that "Save" cannot write in place. Labeling the button "Save
        // As…" and explaining why up front means the destination panel that
        // follows is expected, not a second, unexplained dialog.
        let needsDestination = model.requiresDestinationToSave
        alert.messageText = "Unsaved Changes"
        alert.informativeText = needsDestination
            ? "The original file for \"\(fileName)\" is no longer available. "
            + "Save a copy to close, or discard your changes."
            : "Do you want to save changes to \"\(fileName)\"?"
        alert.addButton(withTitle: needsDestination ? "Save As…" : "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: sender) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, let coordinator,
                      let current = model.activeDocument,
                      current.state != .clean
                else { return }
                guard matchesPresentedContext(current, context) else {
                    _ = windowShouldClose(sender)
                    return
                }
                switch response {
                case .alertFirstButtonReturn:
                    // Explicit-origin, not the ambient `saveDocument()` this
                    // used ambiguously resolve its Save As panel against
                    // `NSApp.keyWindow` — during a close sheet that is
                    // usually `sender`, but never provably so. Every other
                    // window-bound save path in this app was already fixed
                    // to route this way; this alert's Save button was the
                    // one place that hadn't been (#57).
                    await saveDocumentFromExplicitOrigin()
                    if model.activeDocument?.state == .clean {
                        if let saved = model.activeDocument {
                            guard await (externalFileController.retireRecovery(
                                for: saved,
                                resumeCloseOnSuccess: true
                            )).isAbsent else { return }
                        }
                        coordinator.removeController(self)
                        close()
                    }
                case .alertThirdButtonReturn:
                    guard await (externalFileController.retireRecovery(
                        for: current,
                        resumeCloseOnSuccess: true
                    )).isAbsent else { return }
                    guard model.activeDocument?.id == current.id else { return }
                    coordinator.removeController(self)
                    close()
                default:
                    sender.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    private func presentConflictCloseSheet(for window: NSWindow) {
        guard let document = model.activeDocument else { return }
        let context = CloseSheetContext(document)
        let alert = NSAlert()
        alert.messageText = "External File Change"
        alert.informativeText = "The file changed on disk while this window has local edits. "
            + "Choose which version to close."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep My Changes and Save")
        alert.addButton(withTitle: "Use Disk Version and Close")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, let coordinator,
                      let current = model.activeDocument,
                      current.state == .conflict
                else { return }
                guard matchesPresentedContext(current, context) else {
                    _ = windowShouldClose(window)
                    return
                }
                switch response {
                case .alertFirstButtonReturn:
                    await externalFileController.resolveConflict(.keepMine)
                    // Same explicit-origin fix as the dirty-close alert
                    // above (#57): this button's save should never resolve
                    // against whatever happens to be `NSApp.keyWindow`.
                    await saveDocumentFromExplicitOrigin()
                case .alertSecondButtonReturn:
                    await externalFileController.resolveConflict(.useExternal)
                default:
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                guard model.activeDocument?.state == .clean else { return }
                if let saved = model.activeDocument {
                    guard await (externalFileController.retireRecovery(
                        for: saved,
                        resumeCloseOnSuccess: true
                    )).isAbsent else { return }
                }
                coordinator.removeController(self)
                close()
            }
        }
    }

    private func matchesPresentedContext(_ document: FileDocument, _ context: CloseSheetContext) -> Bool {
        document.id == context.documentID
            && document.fileURL?.standardizedFileURL == context.fileURL
            && document.mutationGeneration == context.mutationGeneration
            && document.text == context.text
            && document.state == context.state
            && document.lastKnownRevision == context.lastKnownRevision
            && document.pendingExternalRevision == context.pendingExternalRevision
    }

    func completeCloseAfterRecoveryRetry(
        documentID: String,
        recoveryEpoch: UUID,
        mutationGeneration: UInt
    ) {
        guard let coordinator,
              let current = model.activeDocument,
              current.id == documentID,
              current.recoveryEpoch == recoveryEpoch,
              current.mutationGeneration == mutationGeneration
        else { return }
        coordinator.removeController(self)
        close()
    }
}

private struct CloseSheetContext {
    let documentID: String
    let fileURL: URL?
    let mutationGeneration: UInt
    let text: String
    let state: FileDocumentState
    let lastKnownRevision: FileRevision?
    let pendingExternalRevision: FileRevision?

    init(_ document: FileDocument) {
        documentID = document.id
        fileURL = document.fileURL?.standardizedFileURL
        mutationGeneration = document.mutationGeneration
        text = document.text
        state = document.state
        lastKnownRevision = document.lastKnownRevision
        pendingExternalRevision = document.pendingExternalRevision
    }
}
