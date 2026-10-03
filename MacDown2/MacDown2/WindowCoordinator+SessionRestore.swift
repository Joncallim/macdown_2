import AppKit
import EditorCore
import FileCore
import Foundation
import Workspace

/// The per-tab half of launch-time session restore. Split out of
/// `WindowCoordinator.swift` to stay under the type-body-length lint budget
/// — `restoreSession()` itself (the entry point) stays in the main file.
/// The session file as it was when the app launched, frozen so a restore that
/// starts after the first window has triggered an autosave still sees it.
private struct LaunchSessionStore: WorkspaceSessionStoring {
    let session: WorkspaceSession

    func loadSession() -> WorkspaceSession? {
        session
    }

    func saveSession(_: WorkspaceSession) {}
}

extension WindowCoordinator {
    /// Launches that do not restore the previous session (a document opened from
    /// Finder or the command line, "Start with a new document") must still not
    /// lose what that session held UNSAVED: Quit never prompts — it relies on the
    /// session plus recovery — and the first window's autosave would otherwise
    /// overwrite the session file, orphaning the recovery records (#183 review
    /// pass 1). Only the dirty tabs come back; clean ones are not restored.
    func restoreUnsavedSessionTabs() async {
        guard let session = launchSession else { return }
        launchSession = nil
        let tempStore = TabStore(sessionStore: LaunchSessionStore(session: session), recoveryBuffer: recoveryBuffer)
        await tempStore.restoreSessionIfNeeded()
        let unsaved = Self.unsavedTabs(in: tempStore.tabs)
        guard !unsaved.isEmpty else { return }
        _ = restore(tabs: unsaved)
        updateKeyModel()
    }

    static func unsavedTabs(in tabs: [WorkspaceTab]) -> [WorkspaceTab] {
        tabs.filter { $0.document.state == .dirty || $0.document.state == .conflict }
    }

    func restore(tabs: [WorkspaceTab]) -> (WindowController?, NSWindow?) {
        var firstController: WindowController?
        var firstWindow: NSWindow?
        var previousWindow: NSWindow?

        for tab in tabs {
            let controller = makeRestoredController(tab: tab)
            controllers.append(controller)
            applyRestoredState(controller: controller, tab: tab)

            if firstController == nil {
                firstController = controller
                firstWindow = controller.window
                controller.showWindow(nil)
            } else if let previousWindow, let newWindow = controller.window {
                // After the PREVIOUS tab, not the first: AppKit inserts a tab right after
                // the receiver, so chaining everything off the first window reversed the
                // restored order (A B C D came back A D C B).
                Self.attach(newWindow, after: previousWindow)
                controller.showWindow(nil)
            }
            previousWindow = controller.window
        }

        return (firstController, firstWindow)
    }

    static func attach(_ window: NSWindow, after previous: NSWindow) {
        previous.addTabbedWindow(window, ordered: .above)
    }

    /// `items` (windows' owners, in creation order) arranged in the order their tabs
    /// appear in the tab strip. Creation order is not strip order — a new tab is appended
    /// even when inserted next to the key tab, and tabs can be dragged — so saving it
    /// directly restored tabs in a different order than the user arranged them. Separate
    /// tab groups stay in first-seen order; items without a window keep their place.
    static func inTabOrder<Item>(_ items: [Item], window: (Item) -> NSWindow?) -> [Item] {
        var result: [Item] = []
        var seenGroups: [NSWindowTabGroup] = []
        for item in items {
            guard let group = window(item)?.tabGroup else {
                result.append(item)
                continue
            }
            if seenGroups.contains(where: { $0 === group }) {
                continue
            }
            seenGroups.append(group)
            for tabWindow in group.windows {
                if let member = items.first(where: { window($0) === tabWindow }) {
                    result.append(member)
                }
            }
        }
        return result
    }

    func makeRestoredController(tab: WorkspaceTab) -> WindowController {
        let model = makeWindowModel()
        model.tabStore.newTab(id: tab.id, document: tab.document)
        return WindowController(
            model: model,
            coordinator: self,
            themeController: themeController,
            grammarRegistry: grammarRegistry,
            fileTreePreferences: fileTreePreferences
        )
    }

    func applyRestoredState(controller: WindowController, tab: WorkspaceTab) {
        let identity = tab.id.uuidString
        guard let textSystem = controller.editorStore.existingSystem(for: identity) else { return }
        if let cursorPosition = tab.cursorPosition {
            let length = tab.selectionLength ?? 0
            textSystem.selectedRange = NSRange(location: cursorPosition, length: length)
        }
        if let scrollOffset = tab.scrollOffset {
            textSystem.scrollOffset = CGFloat(scrollOffset)
        }
        if let previewLayout = tab.previewLayout {
            controller.model.tabStore.setPreviewLayout(previewLayout, for: tab.id)
        }
        if let previewMode = tab.previewMode {
            controller.model.tabStore.setPreviewMode(previewMode, for: tab.id)
        }
        if tab.syntaxFormat.id != tab.document.format.id {
            controller.model.tabStore.setSyntaxMode(tab.syntaxFormat.id, for: tab.id)
        }
        if let bookmark = tab.folderRootBookmark {
            var stale = false
            if let root = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                let lexical = tab.folderRootAlias.flatMap {
                    PhysicalFileIdentity.matches($0, root) ? $0 : nil
                } ?? root
                controller.model.setFolderRoot(lexical)
                Task { await controller.setFileTreeRoot(lexical, accessURL: root) }
                if stale {
                    // The next debounced session save rewrites the optional
                    // bookmark without changing the session schema.
                    scheduleSaveSession()
                }
            }
        }
    }

    func activate(controller: WindowController?, activeID: UUID?) {
        let activeController: WindowController? = {
            guard let activeID else { return nil }
            return controllers.first { $0.model.tabStore.activeTabID == activeID }
        }()
        guard let windowToActivate = (activeController ?? controller)?.window else { return }
        // Set the tab group's selection explicitly. Under native tabbing,
        // makeKeyAndOrderFront alone is not enough: the last-shown window
        // remains the tab group's selectedWindow and re-emerges as key on the
        // next run loop, overwriting the restored active tab.
        windowToActivate.tabGroup?.selectedWindow = windowToActivate
        windowToActivate.makeKeyAndOrderFront(nil)
    }
}
