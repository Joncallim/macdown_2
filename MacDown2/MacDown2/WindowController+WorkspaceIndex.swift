import Foundation

/// Keeps `workspaceFileIndex` in sync with `fileTreeModel.root` (EPIC-22
/// §6.15, Slice 6a). Split out of `WindowController.swift` for the same
/// reason `WindowController+Close.swift`/`WindowController+TextFilterTasks.swift`
/// are: a distinct, self-contained ownership concern kept in one place.
extension WindowController {
    /// Lets Replace in Folder (Slice 7c) ask the coordinator whether any
    /// window holds unsaved edits for a file it is about to rewrite.
    func installFolderSearchHooks() {
        folderSearchModel.hasUnsavedOpenDocument = { [weak coordinator] url in
            coordinator?.hasUnsavedOpenDocument(at: url) ?? false
        }
        fileTreeModel.onDidMutate = { [weak self] in
            Task { await self?.refreshWorkspaceIndex() }
        }
    }

    /// Re-walks the open folder so Quick Open and Folder Search follow changes
    /// made by this app's own file operations and by other programs (#183
    /// F18). A newer call supersedes an in-flight walk
    /// (`WorkspaceFileIndex.rebuild`), the old snapshot stays queryable until
    /// the new one lands, and no folder (or a closed one) is a no-op.
    ///
    /// `minInterval` lets a frequent trigger (a native tab becoming key) skip a
    /// walk that just finished; file operations always walk.
    func refreshWorkspaceIndex(minInterval: TimeInterval = 0) async {
        guard let root = fileTreeModel.rootAccessURL else { return }
        if minInterval > 0, let last = lastWorkspaceIndexRefresh, Date().timeIntervalSince(last) < minInterval {
            return
        }
        lastWorkspaceIndexRefresh = Date()
        await workspaceFileIndex.rebuild(root: root)
    }

    /// Sets `fileTreeModel`'s root and rebuilds `workspaceFileIndex` to
    /// match it in one step. Deliberately not named `setFolderRoot` —
    /// `WorkspaceModel.setFolderRoot(_:)` is a different, pre-existing
    /// method most call sites already call right next to this one, and
    /// this method needs its own distinct name so the two are never
    /// mistaken for each other. Every call site that changes
    /// `fileTreeModel.root` must go through this method, never
    /// `fileTreeModel.setRoot(_:accessURL:)` directly, so the index can
    /// never silently drift out of sync with the root it is supposed to be
    /// indexing.
    ///
    /// Indexes `fileTreeModel.rootAccessURL` — the real, security-scoped
    /// access URL `setRoot` always establishes once `root` is non-nil — not
    /// the lexical `root` itself, matching `FileTreeModel`'s own
    /// access-scope convention (§2.1) rather than inventing a second one.
    /// A `nil` root (closing the folder) clears the index instead of
    /// rebuilding it, so a stale snapshot from a previously-open folder can
    /// never leak into a later Quick Open query in this same window.
    func setFileTreeRoot(_ url: URL?, accessURL: URL? = nil) async {
        // Before the first suspension: results shown against the old root must
        // never be actionable against the new one (#183 F19).
        coordinator?.closeQuickOpenIfOrigin(self)
        await fileTreeModel.setRoot(url, accessURL: accessURL)
        // Closes Quick Open (Slice 6b) if it's open against this window —
        // an independent hostile review of that slice found the panel's
        // own results/selection could otherwise resolve against a folder
        // root that no longer matches what `fileTreeModel`/
        // `workspaceFileIndex` now point to: `removeController`'s own
        // force-close guard only fires when the WINDOW closes, never when
        // an already-open window's root changes underneath it (Open
        // Folder…/Open Recent Folder/session restore all route through
        // this exact method without ever closing the window), so a stale
        // Quick Open result could resolve `path.relativePath` against the
        // NEW root and silently open the wrong file (or fail silently).
        coordinator?.closeQuickOpenIfOrigin(self)
        guard let indexRoot = fileTreeModel.rootAccessURL else {
            await workspaceFileIndex.clear()
            folderSearchModel.setRoot(nil)
            return
        }
        await workspaceFileIndex.rebuild(root: indexRoot)
        // After the rebuild, not before: a folder search re-run by
        // `setRoot(_:)` reads `workspaceFileIndex` through the closure
        // captured at `FolderSearchModel.init` time, so it must see the
        // freshly-rebuilt snapshot for the new root, not the old (or
        // `.empty`) one.
        folderSearchModel.setRoot(indexRoot, lexicalRoot: fileTreeModel.root)
    }
}
