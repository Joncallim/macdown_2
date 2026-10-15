import Highlighting
import SwiftUI

/// Why a document's syntax highlighting is reduced (register row H5), for the
/// non-modal note in the status bar.
struct ReducedHighlightingNote: Equatable {
    /// Full highlighting returns automatically at or below this length.
    let restoreAtOrBelowUTF16Units: Int

    /// `nil` unless `state` is reduced.
    init?(_ state: HighlightingState?) {
        guard let state, state.isReduced,
              let policy = HighlightingSizePolicy.default(for: state.requestedLanguageID)
        else { return nil }
        restoreAtOrBelowUTF16Units = policy.restoreAtOrBelowUTF16Units
    }

    var explanation: String {
        let restore = restoreAtOrBelowUTF16Units.formatted()
        return String(
            localized: """
            Syntax highlighting is off for this large document to keep typing responsive. \
            The text, editing and search are unaffected. Highlighting returns automatically \
            once the document is at or below \(restore) UTF-16 units (roughly that many characters of ordinary text).
            """
        )
    }
}

/// A concise, non-modal indicator; the full explanation is its help text.
struct ReducedHighlightingNoteView: View {
    let note: ReducedHighlightingNote

    var body: some View {
        Label(String(localized: "Highlighting reduced"), systemImage: "speedometer")
            .labelStyle(.titleAndIcon)
            .fixedSize()
            .help(note.explanation)
            .accessibilityIdentifier("highlightingReducedNote")
            .accessibilityHint(note.explanation)
    }
}
