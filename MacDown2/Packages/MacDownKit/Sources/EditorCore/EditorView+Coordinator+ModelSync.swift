import AppKit
import SwiftUI

/// The last text both sides agreed on, so a model replacement that has not been pushed into the view yet (a render
/// is pending, or an IME composition is open and `updateNSView` skips the push) is never reverted when the view
/// publishes its own, now stale, text.
struct EditorModelSyncState {
    var lastSyncedText: String?
}

extension EditorView.Coordinator {
    @MainActor func noteSynced(_ text: String) {
        sync.lastSyncedText = text
        system?.lastExternalReplacementText = nil
    }

    /// Called before the view publishes its text (a text change, an undo/redo). When the model changed since the last
    /// agreed text, and it is not simply the text an external replacement just wrote into the view, the view's text
    /// (the old text plus whatever was typed or composed since) is stale: adopt the model instead of publishing.
    /// Returns `true` when the model was adopted and the view's text must not be published.
    @MainActor func adoptReplacedModelIfNeeded(into system: EditorTextSystem) -> Bool {
        guard let model = textBinding?.wrappedValue, let synced = sync.lastSyncedText,
              !model.isExactlyEqual(to: synced),
              !(system.lastExternalReplacementText.map { model.isExactlyEqual(to: $0) } ?? false),
              !model.isExactlyEqual(to: system.text) else { return false }
        isApplyingModelText = true
        system.setText(model)
        isApplyingModelText = false
        sync.lastSyncedText = model
        system.textView.sizeToFit()
        return true
    }
}
