import FileCore
import Foundation

public extension TabStore {
    // MARK: - Close intents

    /// Begins closing a single tab. Clean tabs close immediately; dirty tabs
    /// enter the pending-close prompt state.
    func requestClose(_ id: UUID) {
        guard let index = tabIndex(of: id) else { return }
        guard !tabs[index].isPinned else { return }

        let tab = tabs[index]
        let (updated, closeImmediately) = tab.document.requestClose()

        if closeImmediately != nil {
            removeTab(at: index)
            persist()
        } else {
            tabs[index].document = updated
            pendingCloseTabID = id
            persist()
        }
    }

    func requestCloseActiveTab() {
        guard let activeTabID else { return }
        requestClose(activeTabID)
    }

    /// Closes all tabs except `id`. Clean tabs close immediately; dirty tabs are
    /// enqueued and prompted one-by-one. Pinned tabs are never closed.
    func requestCloseOthers(of id: UUID) {
        let idsToClose = tabs
            .filter { $0.id != id && !$0.isPinned }
            .map(\.id)
        enqueueBatchCloses(idsToClose)
    }

    /// Closes every tab to the right of `id`. Pinned tabs are skipped.
    func requestCloseToTheRight(of id: UUID) {
        guard let index = tabIndex(of: id) else { return }
        let idsToClose = tabs
            .enumerated()
            .filter { $0.offset > index && !$0.element.isPinned }
            .map(\.element.id)
        enqueueBatchCloses(idsToClose)
    }

    /// Resolves the current dirty-close prompt. For `.save`, the caller must
    /// supply a closure that attempts to save the active document and returns
    /// `true` only when the save actually succeeded.
    func resolveClose(
        _ resolution: CloseResolution,
        saveActiveDocument: () async -> Bool = { false }
    ) async {
        guard let pendingCloseTabID else { return }
        guard let index = tabIndex(of: pendingCloseTabID) else {
            self.pendingCloseTabID = nil
            closeQueue.removeAll()
            return
        }

        switch resolution {
        case .save:
            let saved = await saveActiveDocument()
            if saved {
                removeTab(at: index)
            } else {
                tabs[index].document = tabs[index].document.resolveClose(.cancel)
                closeQueue.removeAll()
                self.pendingCloseTabID = nil
                persist()
                return
            }
        case .discard:
            removeTab(at: index)
        case .cancel:
            tabs[index].document = tabs[index].document.resolveClose(.cancel)
            closeQueue.removeAll()
            self.pendingCloseTabID = nil
            persist()
            return
        }

        advanceCloseQueue()
        persist()
    }

    // MARK: - Internal helpers

    private func enqueueBatchCloses(_ ids: [UUID]) {
        var dirtyIDs: [UUID] = []
        for id in ids {
            guard let index = tabIndex(of: id) else { continue }
            let tab = tabs[index]
            let (updated, closeImmediately) = tab.document.requestClose()
            if closeImmediately != nil {
                removeTab(at: index)
            } else {
                tabs[index].document = updated
                dirtyIDs.append(id)
            }
        }

        if let first = dirtyIDs.first {
            closeQueue = Array(dirtyIDs.dropFirst())
            pendingCloseTabID = first
        } else {
            closeQueue.removeAll()
            pendingCloseTabID = nil
        }

        persist()
    }

    private func advanceCloseQueue() {
        guard let nextID = closeQueue.first else {
            pendingCloseTabID = nil
            return
        }
        closeQueue.removeFirst()
        pendingCloseTabID = nextID
        guard let index = tabIndex(of: nextID) else {
            pendingCloseTabID = nil
            closeQueue.removeAll()
            return
        }
        tabs[index].document = tabs[index].document.requestClose().document
    }
}
