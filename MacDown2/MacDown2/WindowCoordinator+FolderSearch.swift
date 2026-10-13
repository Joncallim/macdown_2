import AppKit
import FileCore
import TextSearch

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
        await openDocument(
            at: url,
            folderRoot: root,
            folderAccessURL: folderAccessURL,
            folderSelectionURL: url,
            shouldContinue: { [self] in folderSearchRequestGate.owns(requestGeneration) }
        )
        guard folderSearchRequestGate.owns(requestGeneration), !Task.isCancelled else { return }
        guard let controller = controllerForDocument(url: url),
              let tabID = controller.model.tabStore.tabID(forFileURL: url)
        else { return }

        // A background tab can need several run-loop turns to attach its
        // editor view after `openDocument` selects it. Wait only while this
        // request is still authoritative and the view has a usable window
        // and frame; never reveal into a detached or zero-sized view.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            guard folderSearchRequestGate.owns(requestGeneration),
                  !Task.isCancelled,
                  controller.window?.isVisible == true,
                  controller.model.tabStore.activeTabID == tabID
            else { return }
            if let textSystem = controller.editorStore.existingSystem(for: tabID.uuidString),
               textSystem.textView.window != nil,
               !textSystem.textView.bounds.isEmpty {
                guard folderSearchRequestGate.owns(requestGeneration),
                      !Task.isCancelled else { return }
                textSystem.revealSelection(utf16Range: range, flash: true, animated: true)
                return
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
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
