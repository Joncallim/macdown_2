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
    let navigationRevision: UInt
    let range: NSRange
    let controllerID: ObjectIdentifier
    let originControllerID: ObjectIdentifier?
    let originGeneration: UInt?
    let originLexicalRoot: URL?
    let originAccessRoot: URL?
    let originResult: FolderSearchModel.PresentedResult?

    init(
        generation: UInt,
        navigationRevision: UInt,
        range: NSRange,
        controllerID: ObjectIdentifier,
        originControllerID: ObjectIdentifier? = nil,
        originGeneration: UInt? = nil,
        originLexicalRoot: URL? = nil,
        originAccessRoot: URL? = nil,
        originResult: FolderSearchModel.PresentedResult? = nil
    ) {
        self.generation = generation
        self.navigationRevision = navigationRevision
        self.range = range
        self.controllerID = controllerID
        self.originControllerID = originControllerID
        self.originGeneration = originGeneration
        self.originLexicalRoot = originLexicalRoot
        self.originAccessRoot = originAccessRoot
        self.originResult = originResult
    }
}

/// Identity of the window and folder that produced a clicked search row.
/// Capture this in the button action, before its asynchronous open is queued.
@MainActor
struct FolderSearchOrigin {
    let controller: WindowController
    let generation: UInt
    let lexicalRoot: URL
    let accessRoot: URL
    /// Present for a clicked sidebar row. Direct, non-row callers can still
    /// use the existing root-only origin checks.
    let presentedResult: FolderSearchModel.PresentedResult?

    init(
        controller: WindowController,
        generation: UInt,
        lexicalRoot: URL,
        accessRoot: URL,
        presentedResult: FolderSearchModel.PresentedResult? = nil
    ) {
        self.controller = controller
        self.generation = generation
        self.lexicalRoot = lexicalRoot
        self.accessRoot = accessRoot
        self.presentedResult = presentedResult
    }

    var isCurrent: Bool {
        !controller.isClosed
            && controller.workspaceRootRequestGeneration == generation
            && controller.folderSearchModel.root == accessRoot
            && (controller.folderSearchModel.lexicalRoot ?? accessRoot) == lexicalRoot
            && controller.fileTreeModel.root == lexicalRoot
            && controller.fileTreeModel.rootAccessURL == accessRoot
            && (presentedResult.map { controller.folderSearchModel.isCurrentResult($0) } ?? true)
    }

    func matches(lexicalRoot: URL, accessRoot: URL?) -> Bool {
        isCurrent && self.lexicalRoot == lexicalRoot && self.accessRoot == accessRoot
    }
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
        range: NSRange,
        origin: FolderSearchOrigin? = nil
    ) async {
        guard origin?.matches(lexicalRoot: root, accessRoot: folderAccessURL) ?? true else { return }
        let url = root.appendingPathComponent(relativePath)
        let navigationRevision = folderSearchNavigationDidChange()
        let requestGeneration = folderSearchRequestGate.begin()
        let requestToken = FolderSearchRequestToken()
        await withTaskCancellationHandler {
            await openDocument(
                at: url,
                folderRoot: root,
                folderAccessURL: folderAccessURL,
                folderSelectionURL: url,
                shouldContinue: { [self] in
                    folderSearchRequestIsCurrent(
                        requestGeneration, navigationRevision: navigationRevision,
                        token: requestToken, origin: origin
                    )
                }
            )
        } onCancel: {
            requestToken.cancel()
        }
        guard folderSearchRequestIsCurrent(
            requestGeneration, navigationRevision: navigationRevision,
            token: requestToken, origin: origin
        )
        else {
            return
        }
        guard let controller = controllerForDocument(url: url),
              let tabID = controller.model.tabStore.tabID(forFileURL: url)
        else { return }

        if !attemptFolderSearchReveal(
            tabID: tabID,
            generation: requestGeneration,
            range: range,
            controller: controller
        ) {
            pendingFolderSearchReveals[tabID] = PendingFolderSearchReveal(
                generation: requestGeneration,
                navigationRevision: navigationRevision,
                range: range,
                controllerID: ObjectIdentifier(controller),
                originControllerID: origin.map { ObjectIdentifier($0.controller) },
                originGeneration: origin?.generation,
                originLexicalRoot: origin?.lexicalRoot,
                originAccessRoot: origin?.accessRoot,
                originResult: origin?.presentedResult
            )
        }
    }

    /// Called after an editor pane mounts and whenever its layout changes.
    /// Delayed background-tab attachment therefore keeps the request alive
    /// without a fixed retry count or timeout.
    func folderSearchEditorLayoutChanged(tabID: String) {
        afterFolderSearchEditorLayoutChange?()
        guard let tabUUID = UUID(uuidString: tabID),
              let pending = pendingFolderSearchReveals[tabUUID],
              folderSearchRequestGate.owns(pending.generation),
              folderSearchNavigationRevision == pending.navigationRevision,
              pendingFolderSearchOriginIsCurrent(pending),
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

    private func folderSearchOriginIsCurrent(_ origin: FolderSearchOrigin?) -> Bool {
        origin?.isCurrent ?? true
    }

    private func folderSearchRequestIsCurrent(
        _ generation: UInt,
        navigationRevision: UInt,
        token: FolderSearchRequestToken,
        origin: FolderSearchOrigin?
    ) -> Bool {
        folderSearchRequestGate.owns(generation)
            && folderSearchNavigationRevision == navigationRevision
            && !token.isCancelled
            && !Task.isCancelled
            && folderSearchOriginIsCurrent(origin)
    }

    private func pendingFolderSearchOriginIsCurrent(_ pending: PendingFolderSearchReveal) -> Bool {
        guard let originID = pending.originControllerID else { return true }
        return controllers.contains { controller in
            ObjectIdentifier(controller) == originID
                && !controller.isClosed
                && controller.workspaceRootRequestGeneration == pending.originGeneration
                && controller.fileTreeModel.root == pending.originLexicalRoot
                && controller.fileTreeModel.rootAccessURL == pending.originAccessRoot
                && (pending.originResult.map { result in
                    controller.folderSearchModel.isCurrentResult(result)
                } ?? true)
        }
    }

    /// Invalidates a deferred folder-search reveal when a newer user-driven
    /// navigation command targets an editor. The revision is captured before
    /// the asynchronous open begins, so navigation during file loading also
    /// wins over the eventual reveal.
    @discardableResult
    func folderSearchNavigationDidChange() -> UInt {
        folderSearchNavigationRevision &+= 1
        pendingFolderSearchReveals.removeAll()
        return folderSearchNavigationRevision
    }

    func folderSearchNavigationIsCurrent(_ revision: UInt) -> Bool {
        folderSearchNavigationRevision == revision
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
