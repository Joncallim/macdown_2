import AppKit
import Foundation

extension WindowCoordinator {
    var keyFolderRoot: URL? {
        controllers.first(where: { $0.window == NSApp.keyWindow })?.fileTreeModel.root
    }

    var keyFolderSelection: URL? {
        controllers.first(where: { $0.window == NSApp.keyWindow })?.fileTreeModel.selectedURL
    }

    func renameKeyFolderSelection() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              let selected = controller.fileTreeModel.selectedURL else { return }
        controller.fileTreeModel.renamingURL = selected
    }

    func duplicateKeyFolderSelection() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              let selected = controller.fileTreeModel.selectedURL else { return }
        let context = controller.fileTreeModel.beginOperation()
        Task { @MainActor in
            do {
                _ = try await controller.fileTreeModel.duplicate(selected, context: context)
            } catch where controller.fileTreeModel.isCurrent(context) {
                controller.fileTreeModel.recordOperationError(error)
            } catch {}
        }
    }

    func trashKeyFolderSelection() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              let selected = controller.fileTreeModel.selectedURL,
              let window = controller.window else { return }
        let alert = NSAlert()
        alert.messageText = "Move \"\(selected.lastPathComponent)\" to Trash?"
        alert.informativeText = "You can recover it from the Trash in Finder."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self, weak controller] response in
            guard response == .alertFirstButtonReturn, let self, let controller else { return }
            let context = controller.fileTreeModel.beginOperation()
            Task { @MainActor in
                do {
                    let result = try await controller.fileTreeModel.moveToTrash(selected, context: context)
                    self.documentFileWasDeleted(at: result.url)
                } catch where controller.fileTreeModel.isCurrent(context) {
                    controller.fileTreeModel.recordOperationError(error)
                } catch {}
            }
        }
    }

    func createInKeyFolder(isDirectory: Bool) {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              let root = controller.fileTreeModel.root else { return }
        let context = controller.fileTreeModel.beginOperation()
        Task { @MainActor in
            do {
                let result = try await (isDirectory
                    ? controller.fileTreeModel.createFolder(in: root, context: context)
                    : controller.fileTreeModel.createFile(in: root, context: context))
                guard result.isCurrent else { return }
                let created = result.url
                controller.fileTreeModel.selectedURL = created
                controller.fileTreeModel.renamingURL = created
                if !isDirectory {
                    controller.fileTreeModel.pendingOpenURL = created
                    await openDocument(
                        at: created,
                        folderRoot: root,
                        folderAccessURL: controller.fileTreeModel.rootAccessURL,
                        folderSelectionURL: created,
                        folderRenameURL: created
                    )
                    if controller.fileTreeModel.isCurrent(context), controller.fileTreeModel.root == root {
                        controller.fileTreeModel.pendingOpenURL = nil
                    }
                }
            } catch {
                if controller.fileTreeModel.isCurrent(context) {
                    controller.fileTreeModel.recordOperationError(error)
                }
            }
        }
    }

    func chooseFolder() {
        Task { @MainActor in
            guard let url = await panelProvider.chooseFolder() else { return }
            openFolder(url)
        }
    }

    /// Opens a root in the key window only; roots are intentionally per-window.
    func openFolder(_ url: URL, accessURL: URL? = nil) {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }) else { return }
        controller.model.setFolderRoot(url)
        recentFolderRoots.record(url)
        Task { await controller.fileTreeModel.setRoot(url, accessURL: accessURL) }
        scheduleSaveSession()
    }

    func openRecentFolder(_ url: URL) {
        guard let resolution = recentFolderRoots.resolve(url) else { return }
        openFolder(resolution.lexicalURL, accessURL: resolution.accessURL)
    }

    func revealActiveFile() {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }),
              let url = controller.model.activeDocument?.fileURL else { return }
        controller.model.sidebarVisible = true
        controller.model.setSectionExpanded(.folder, true)
        Task {
            guard await !controller.fileTreeModel.reveal(url) else { return }
            presentRevealOutsideRootAlert(for: url, controller: controller)
        }
    }

    private func presentRevealOutsideRootAlert(for url: URL, controller: WindowController) {
        guard let window = controller.window else { return }
        let alert = NSAlert()
        alert.messageText = "File Is Outside the Open Folder"
        alert.informativeText = "Open its parent folder to reveal it in the sidebar?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Parent Folder")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self, weak controller] response in
            guard response == .alertFirstButtonReturn, let self, let controller else { return }
            Task { @MainActor in
                let root = url.deletingLastPathComponent()
                controller.model.setFolderRoot(root)
                self.recentFolderRoots.record(root)
                await controller.fileTreeModel.setRoot(root)
                _ = await controller.fileTreeModel.reveal(url)
                self.scheduleSaveSession()
            }
        }
    }

    func documentWasRenamed(from old: URL, to new: URL) {
        for controller in controllers {
            controller.model.tabStore.documentWasRenamed(from: old, to: new)
            controller.model.remapFolderRoot(from: old, to: new)
            controller.fileTreeModel.itemWasRenamed(from: old, to: new)
        }
        recentFolderRoots.remap(from: old, to: new)
        scheduleSaveSession()
    }

    func documentFileWasDeleted(at url: URL) {
        for controller in controllers {
            switch controller.model.tabStore.documentFileWasDeleted(at: url) {
            case .closedCleanTab:
                removeController(controller)
                controller.close()
            case let .needsPrompt(id):
                presentDeletedDocumentAlert(on: controller, tabID: id)
            case .notOpen:
                break
            }
        }
        scheduleSaveSession()
    }

    private func presentDeletedDocumentAlert(on controller: WindowController, tabID: UUID) {
        guard let window = controller.window else { return }
        let alert = NSAlert()
        alert.messageText = "File Moved to Trash"
        alert.informativeText = "This document has unsaved changes."
        alert.addButton(withTitle: "Save As…")
        alert.addButton(withTitle: "Close Without Saving")
        alert.addButton(withTitle: "Keep Open")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { [weak self, weak controller] response in
            Task { @MainActor in
                guard let self, let controller else { return }
                if response == .alertFirstButtonReturn {
                    controller.model.tabStore.activate(tabID)
                    await controller.model.saveAs()
                } else if response == .alertSecondButtonReturn {
                    self.removeController(controller)
                    controller.close()
                }
            }
        }
    }
}
