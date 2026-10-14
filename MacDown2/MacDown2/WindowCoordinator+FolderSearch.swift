import AppKit
import FileCore
import TextSearch

final class FolderSearchRequestToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

struct FolderSearchRequestGate {
    private var generation: UInt = 0

    mutating func begin() -> UInt {
        generation &+= 1
        return generation
    }

    func owns(_ requestedGeneration: UInt) -> Bool {
        generation == requestedGeneration
    }
}

struct PendingFolderSearchReveal {
    let generation: UInt
    let range: NSRange
    let controllerID: ObjectIdentifier
}

/// Opens a folder-search result and reveals the matched range (EPIC-22
/// §6.16, Slice 7b) — reuses the existing document-open path
/// (`openDocument(at:folderRoot:...)`, the same one Quick Open and the
/// file tree already route through) rather than inventing a third opening
/// mechanism, per §6.15's own precedent.
extension WindowCoordinator {
    /// `range` is the first match's own UTF-16 range in `relativePath`'s
    /// text, as read at search time. If the file is already open and has
    /// been edited since, the live buffer may no longer agree with that
    /// range — `revealSelection` clamps against the live text length
    /// (`EditorTextSystem`'s own existing behavior, shared with Go to
    /// Line), so a now-stale range degrades to "select somewhere near the
    /// end" rather than crashing or silently doing nothing; a precise
    /// re-search-on-open is Slice 7c/polish scope, not required for a
    /// correct (if occasionally imprecise) result here.
    func openFolderSearchResult(
        relativePath: String,
        root: URL,
        folderAccessURL: URL?,
        range: NSRange
    ) async {
        let url = root.appendingPathComponent(relativePath)
        let requestGeneration = folderSearchRequestGate.begin()
        let requestToken = FolderSearchRequestToken()
        pendingFolderSearchReveals.removeAll()
        await withTaskCancellationHandler {
            await openDocument(
                at: url,
                folderRoot: root,
                folderAccessURL: folderAccessURL,
                folderSelectionURL: url,
                shouldContinue: { [self] in
                    folderSearchRequestGate.owns(requestGeneration)
                        && !requestToken.isCancelled
                        && !Task.isCancelled
                }
            )
        } onCancel: {
            requestToken.cancel()
        }
        guard folderSearchRequestGate.owns(requestGeneration), !requestToken.isCancelled, !Task.isCancelled else {
            return
        }
        guard let controller = controllerForDocument(url: url),
              let tabID = controller.model.tabStore.tabID(forFileURL: url)
        else { return }

        guard !requestToken.isCancelled, !Task.isCancelled else { return }
        if !attemptFolderSearchReveal(
            tabID: tabID,
            generation: requestGeneration,
            range: range,
            controller: controller
        ) {
            pendingFolderSearchReveals[tabID] = PendingFolderSearchReveal(
                generation: requestGeneration,
                range: range,
                controllerID: ObjectIdentifier(controller)
            )
        }
    }

    /// Called after an editor pane mounts and whenever its layout changes.
    /// Delayed background-tab attachment therefore keeps the request alive
    /// without a fixed retry count or timeout.
    func folderSearchEditorLayoutChanged(tabID: String) {
        guard let tabUUID = UUID(uuidString: tabID),
              let pending = pendingFolderSearchReveals[tabUUID],
              folderSearchRequestGate.owns(pending.generation),
              let controller = controllers.first(where: {
                  ObjectIdentifier($0) == pending.controllerID
                      && $0.model.tabStore.activeTabID == tabUUID
              })
        else { return }
        pendingFolderSearchReveals.removeValue(forKey: tabUUID)
        if attemptFolderSearchReveal(
            tabID: tabUUID,
            generation: pending.generation,
            range: pending.range,
            controller: controller
        ) {
            return
        }
        pendingFolderSearchReveals[tabUUID] = pending
    }

    private func attemptFolderSearchReveal(
        tabID: UUID,
        generation: UInt,
        range: NSRange,
        controller: WindowController
    ) -> Bool {
        guard folderSearchRequestGate.owns(generation),
              controller.window?.isVisible == true,
              controller.model.tabStore.activeTabID == tabID,
              let textSystem = controller.editorStore.existingSystem(for: tabID.uuidString),
              textSystem.textView.window != nil,
              !textSystem.textView.bounds.isEmpty,
              folderSearchRequestGate.owns(generation)
        else { return false }
        textSystem.revealSelection(utf16Range: range, flash: true, animated: true)
        return true
    }

    /// Whether any window has `url` open with edits not yet on disk (dirty,
    /// mid-close-prompt, or in an unresolved external-change conflict).
    /// Replace in Folder must never rewrite such a file underneath its
    /// in-memory buffer.
    func hasUnsavedOpenDocument(at url: URL) -> Bool {
        controllers.contains { controller in
            controller.model.tabStore.tabs.contains { tab in
                tab.document.state != .clean
                    && (tab.document.fileURL.map { PhysicalFileIdentity.matches($0, url) } ?? false)
            }
        }
    }
}
