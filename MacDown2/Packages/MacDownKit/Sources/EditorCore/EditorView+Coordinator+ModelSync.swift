import AppKit
import SwiftUI

/// Tracks the last text both sides agreed on, so a model replacement that arrives while an IME composition is open
/// (when `updateNSView` deliberately skips the push) is not reverted by the composition's commit.
struct EditorModelSyncState {
    var lastSyncedText: String?
    var divergedDuringComposition = false
}

extension EditorView.Coordinator {
    func noteSynced(_ text: String) {
        sync.lastSyncedText = text
    }

    /// `updateNSView` skipped the model push because marked text is open. If the model no longer matches the last
    /// agreed text, it was replaced from outside (not typed through this view).
    func noteSkippedPush(model: String) {
        guard let synced = sync.lastSyncedText, !model.isExactlyEqual(to: synced) else { return }
        sync.divergedDuringComposition = true
    }

    /// Called when the view reports a text change. When the model was replaced during the composition that just ended,
    /// the view's text (old text plus the composed characters) is stale: adopt the model instead of publishing it.
    /// Returns `true` when the model was adopted and the view's text must not be published.
    @MainActor func adoptReplacedModelIfNeeded(into system: EditorTextSystem) -> Bool {
        guard sync.divergedDuringComposition else { return false }
        sync.divergedDuringComposition = false
        guard let model = textBinding?.wrappedValue, !model.isExactlyEqual(to: system.text) else { return false }
        isApplyingModelText = true
        system.setText(model)
        isApplyingModelText = false
        sync.lastSyncedText = model
        system.textView.sizeToFit()
        return true
    }
}
