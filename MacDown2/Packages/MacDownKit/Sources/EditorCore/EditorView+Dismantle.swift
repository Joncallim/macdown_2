import AppKit
import SwiftUI

public extension EditorView {
    /// `static` is what makes this the `NSViewRepresentable` protocol witness
    /// (an instance method of the same name is never called by SwiftUI —
    /// #183 F09). The text system outlives a mount, so a newer mount may
    /// already own the shared text view when an older one is torn down; only
    /// detach what this mount still owns.
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.removeObserver(coordinator, name: .NSUndoManagerDidUndoChange, object: nil)
        NotificationCenter.default.removeObserver(coordinator, name: .NSUndoManagerDidRedoChange, object: nil)
        coordinator.gutterView = nil
        guard let system = coordinator.system else { return }
        if system.textView.delegate === coordinator {
            system.textView.delegate = nil
        }
        if system.scrollView === scrollView {
            system.scrollView = nil
        }
    }
}
