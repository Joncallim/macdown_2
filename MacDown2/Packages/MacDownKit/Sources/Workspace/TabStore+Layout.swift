import FileCore
import Foundation

public extension TabStore {
    // MARK: - Arrangement & navigation

    func activate(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        persist()
    }

    /// Sets the preview layout for the tab identified by `id`. The layout is
    /// clamped before storage so session restore cannot produce an invisible
    /// pane.
    func setPreviewLayout(_ layout: PreviewLayoutMode, for id: UUID) {
        guard let index = tabIndex(of: id) else { return }
        tabs[index].previewLayout = layout.clamped()
        persist()
    }

    /// Sets the preview pane's display mode for the tab identified by `id`.
    /// `nil` restores the format's default mode. Persisted with the session;
    /// format transitions that invalidate the mode are handled by the view.
    func setPreviewMode(_ mode: PreviewMode?, for id: UUID) {
        guard let index = tabIndex(of: id) else { return }
        tabs[index].previewMode = mode
        persist()
    }

    func selectNextTab() {
        guard let activeTabID, tabs.count > 1 else { return }
        guard let index = tabIndex(of: activeTabID) else { return }
        let nextIndex = (index + 1) % tabs.count
        activate(tabs[nextIndex].id)
    }

    func selectPreviousTab() {
        guard let activeTabID, tabs.count > 1 else { return }
        guard let index = tabIndex(of: activeTabID) else { return }
        let previousIndex = (index - 1 + tabs.count) % tabs.count
        activate(tabs[previousIndex].id)
    }

    /// Selects a tab by visible index. Index 8 (⌘9) always means the last tab.
    func selectTab(at index: Int) {
        guard !tabs.isEmpty else { return }
        let targetIndex = (index == 8) ? tabs.count - 1 : min(index, tabs.count - 1)
        guard targetIndex >= 0 else { return }
        activate(tabs[targetIndex].id)
    }

    func togglePin(_ id: UUID) {
        guard let index = tabIndex(of: id) else { return }
        let wasPinned = tabs[index].isPinned
        let tab = tabs.remove(at: index)
        let pinnedCount = tabs.filter(\.isPinned).count

        if wasPinned {
            tabs.insert(WorkspaceTab(
                id: tab.id,
                document: tab.document,
                isPinned: false,
                cursorPosition: tab.cursorPosition,
                selectionLength: tab.selectionLength,
                scrollOffset: tab.scrollOffset,
                previewLayout: tab.previewLayout,
                previewMode: tab.previewMode,
                folderRootBookmark: tab.folderRootBookmark,
                folderRootAlias: tab.folderRootAlias
            ), at: pinnedCount)
        } else {
            tabs.insert(WorkspaceTab(
                id: tab.id,
                document: tab.document,
                isPinned: true,
                cursorPosition: tab.cursorPosition,
                selectionLength: tab.selectionLength,
                scrollOffset: tab.scrollOffset,
                previewLayout: tab.previewLayout,
                previewMode: tab.previewMode,
                folderRootBookmark: tab.folderRootBookmark,
                folderRootAlias: tab.folderRootAlias
            ), at: pinnedCount)
        }

        persist()
    }

    /// Moves a tab from one visible index to another, clamping the destination
    /// so pinned tabs never leave the pinned region and unpinned tabs never
    /// enter it.
    func moveTab(from source: Int, to destination: Int) {
        guard source >= 0, source < tabs.count else { return }
        let sourceTab = tabs[source]
        let pinnedCount = tabs.filter(\.isPinned).count

        let clampedDestination: Int = if sourceTab.isPinned {
            min(max(destination, 0), pinnedCount - 1)
        } else {
            min(max(destination, pinnedCount), tabs.count - 1)
        }

        guard clampedDestination != source else { return }
        let tab = tabs.remove(at: source)
        // `clampedDestination` is a visible index: removal only shifts
        // entries after `source`, never the destination's meaning.
        tabs.insert(tab, at: clampedDestination)
        persist()
    }
}
