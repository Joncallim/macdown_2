import AppKit
import EditorCore
import Foundation
import Workspace

/// The per-tab half of launch-time session restore. Split out of
/// `WindowCoordinator.swift` to stay under the type-body-length lint budget
/// — `restoreSession()` itself (the entry point) stays in the main file.
extension WindowCoordinator {
    func restore(tabs: [WorkspaceTab]) -> (WindowController?, NSWindow?) {
        var firstController: WindowController?
        var firstWindow: NSWindow?

        for tab in tabs {
            let controller = makeRestoredController(tab: tab)
            controllers.append(controller)
            applyRestoredState(controller: controller, tab: tab)

            if firstController == nil {
                firstController = controller
                firstWindow = controller.window
                controller.showWindow(nil)
            } else if let firstWindow, let newWindow = controller.window {
                firstWindow.addTabbedWindow(newWindow, ordered: .above)
                controller.showWindow(nil)
            }
        }

        return (firstController, firstWindow)
    }

    func makeRestoredController(tab: WorkspaceTab) -> WindowController {
        let model = makeWindowModel()
        model.tabStore.newTab(id: tab.id, document: tab.document)
        return WindowController(
            model: model,
            coordinator: self,
            themeController: themeController,
            grammarRegistry: grammarRegistry
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
