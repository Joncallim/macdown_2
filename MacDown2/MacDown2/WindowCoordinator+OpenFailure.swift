import AppKit
import FileCore
import Foundation

/// A human-readable description of a failed file open. `FileStoreError`
/// itself carries no `LocalizedError` conformance — it is a typed-throw
/// value from `FileCore`, not user-facing prose — so this maps it here, at
/// the one App-target boundary that needs to show it to someone. Shared by
/// `WindowCoordinator`'s failed-open alert and `ContentAreaView`'s empty
/// state, so the two surfaces can't drift apart.
enum FileOpenFailurePresentation {
    static func message(for error: FileStoreError) -> String {
        switch error {
        case .fileMissing: "The file could not be found."
        case .permissionDenied: "MacDown does not have permission to read this file."
        case .notRegularFile: "This is not a regular file."
        case .invalidURL: "This is not a valid file location."
        case .fileChangedDuringRead: "The file changed while it was being read. Try again."
        case .encodingDetectionFailed: "The file's text encoding could not be determined."
        case let .decodingFailed(diagnostics):
            diagnostics.first?.message ?? "The file's contents could not be decoded."
        default: "The file could not be read."
        }
    }
}

/// The failed-open alert for `openDocument(at:)`. Split out of
/// `WindowCoordinator.swift` to stay under the file-length lint budget.
///
/// `openDocument(at:)` can fail before any window/controller exists for the
/// document — there is nothing else in the app that would ever tell the user
/// a Finder double-click, a Dock drop, or a launch-argument file silently
/// failed to open, so this presents the real reason rather than the app
/// doing nothing.
extension WindowCoordinator {
    func presentOpenFailure(_ error: FileStoreError, url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't Open \"\(url.lastPathComponent)\""
        alert.informativeText = FileOpenFailurePresentation.message(for: error)
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }
}
