import EditorCore
import Observation

/// Pure query/selection logic for the Insert Snippet picker (EPIC-22 §6.18,
/// Slice 9e), kept free of AppKit/SwiftUI so it is directly testable —
/// mirrors `QuickOpenModel`/`CommandPaletteModel`'s same separation. The
/// candidate list is fixed at panel-open time (already merged and scoped to
/// the origin document's syntax format); only the name filter is live.
@MainActor
@Observable
final class SnippetPickerModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            results = SnippetCatalog.filter(snippets, query: query)
            selectedIndex = 0
        }
    }

    private(set) var results: [Snippet]
    private(set) var selectedIndex = 0
    let snippets: [Snippet]
    /// Why the user's snippet file contributed nothing or less than expected.
    let notice: String?

    init(snippets: [Snippet], notice: String? = nil) {
        self.snippets = snippets
        self.notice = notice
        results = snippets
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let count = results.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    func select(at index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
    }

    var selectedSnippet: Snippet? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }
}
