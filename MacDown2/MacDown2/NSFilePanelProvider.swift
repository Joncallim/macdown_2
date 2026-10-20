import AppKit
import FileCore
import Foundation
import Workspace

/// Evidence of an explicit folder-panel choice for one document. This value is not a resource grant:
/// the caller must still acquire a retained directory backing and reject a stale document/window epoch.
struct PreviewResourceFolderSelection {
    let requestedDocumentURL: URL
    let selectedFolderURL: URL

    fileprivate init(requestedDocumentURL: URL, selectedFolderURL: URL) {
        self.requestedDocumentURL = requestedDocumentURL
        self.selectedFolderURL = selectedFolderURL
    }
}

/// AppKit implementation of `FilePanelProviding` for the MacDown 2 app target.
///
/// For this single-window app, panels are presented as sheets on the current key
/// window. If no key window is available, the panel falls back to a modal dialog.
@MainActor
final class NSFilePanelProvider: FilePanelProviding {
    private weak var window: NSWindow?

    init(window: NSWindow? = nil) {
        self.window = window
    }

    func chooseFile() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = FileFormatRegistry.defaultFormats.map(\.utType)

        return await present(panel)
    }

    func chooseFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Folder"

        return await present(panel)
    }

    /// Obtains a folder from a dedicated document-relative panel. The result only records user selection;
    /// no preview resource is admitted until the #121 grant owner pins and verifies the chosen directory.
    func choosePreviewResourceFolder(near documentURL: URL) async -> PreviewResourceFolderSelection? {
        // A document-specific permission prompt cannot migrate to a different key window while awaiting the panel.
        guard documentURL.isFileURL, let window else { return nil }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = documentURL.deletingLastPathComponent()

        let selectedFolderURL = await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { result in
                continuation.resume(returning: result == .OK ? panel.urls.first : nil)
            }
        }
        guard let selectedFolderURL else { return nil }
        return PreviewResourceFolderSelection(
            requestedDocumentURL: documentURL,
            selectedFolderURL: selectedFolderURL
        )
    }

    func chooseSaveLocation(defaultName: String, format: FileFormat) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true

        return await present(panel)
    }

    private func present(_ panel: NSOpenPanel) async -> URL? {
        await withCheckedContinuation { continuation in
            if let targetWindow = window ?? NSApp.keyWindow {
                panel.beginSheetModal(for: targetWindow) { result in
                    continuation.resume(returning: result == .OK ? panel.urls.first : nil)
                }
            } else {
                let result = panel.runModal()
                continuation.resume(returning: result == .OK ? panel.urls.first : nil)
            }
        }
    }

    private func present(_ panel: NSSavePanel) async -> URL? {
        await withCheckedContinuation { continuation in
            if let targetWindow = window ?? NSApp.keyWindow {
                panel.beginSheetModal(for: targetWindow) { result in
                    continuation.resume(returning: result == .OK ? panel.url : nil)
                }
            } else {
                let result = panel.runModal()
                continuation.resume(returning: result == .OK ? panel.url : nil)
            }
        }
    }
}
