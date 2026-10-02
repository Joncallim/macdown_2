import AppKit
import FileCore
import Foundation
import Workspace

extension WindowCoordinator {
    /// The active document's encoding in the key window, for menu checkmarks.
    var keyDocumentEncoding: FileEncodingMetadata? {
        keyModel?.activeDocument?.encoding
    }

    /// Reopen and Save with Encoding both operate on the document's own file,
    /// so they need a usable backing file and no unresolved conflict.
    var keyDocumentSupportsEncodingChange: Bool {
        keyModel?.activeDocument?.hasEncodableBackingFile == true
    }

    func reopenKeyDocument(withEncoding encoding: String.Encoding) {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }) else { return }
        Task { await controller.reopenDocument(withEncoding: encoding) }
    }

    func saveKeyDocument(withEncoding encoding: FileEncodingMetadata) {
        guard let controller = controllers.first(where: { $0.window == NSApp.keyWindow }) else { return }
        Task { await controller.saveDocument(withEncoding: encoding) }
    }

    /// The status-bar encoding actions act on the window that owns the bar —
    /// not whichever window happens to be key when the action runs (#183 R01).
    func reopenDocument(in model: WorkspaceModel, withEncoding encoding: String.Encoding) {
        guard let controller = controllers.first(where: { $0.model === model }) else { return }
        Task { await controller.reopenDocument(withEncoding: encoding) }
    }

    func saveDocument(in model: WorkspaceModel, withEncoding encoding: FileEncodingMetadata) {
        guard let controller = controllers.first(where: { $0.model === model }) else { return }
        Task { await controller.saveDocument(withEncoding: encoding) }
    }
}

extension FileDocument {
    var hasEncodableBackingFile: Bool {
        guard fileURL != nil, state != .conflict else { return false }
        if case .unavailable = backingState {
            return false
        }
        return true
    }
}
