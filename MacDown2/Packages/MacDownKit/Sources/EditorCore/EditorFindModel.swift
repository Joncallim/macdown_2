import Foundation
import Observation
import TextSearch

// MARK: - Current-document Find state (EPIC-22 §6.14, Slice 5a)

/// Pure find/navigate state for the current-document Find bar. Kept free of
/// any AppKit/SwiftUI/`NSTextView` knowledge so it is directly testable
/// without presenting UI, matching `CommandPaletteModel`'s own established
/// convention for a live, `@Observable` SwiftUI-bound model.
///
/// `TextSearchEngine.matches` itself is pure and stateless — it recomputes
/// the full match list from scratch on every call. This type owns the state
/// a Find bar needs ON TOP of that: the current query/`SearchOptions`, the
/// last-computed match list, which match is "current" for Find Next/
/// Previous, and the wrap-around navigation those two actions apply (§6.14:
/// `SearchOptions.wraps` is real but was, until this slice, consumed
/// nowhere — this is that first consumer).
///
/// This type never mutates live text and never scrolls or selects anything
/// itself — callers read `currentMatch` and act on it via
/// `EditorTextSystem`'s own existing `revealSelection(utf16Range:flash:animated:)`.
/// It also never recomputes `matches` on its own: `query`/`options` changes
/// do NOT auto-trigger a search, because this model has no access to the
/// live document text (that lives in whatever `EditorTextSystem` the Find
/// bar is attached to) — callers must explicitly call `updateMatches(in:)`
/// whenever the query, options, or underlying document text changes.
@MainActor
@Observable
public final class EditorFindModel {
    public var query: String
    public var options: SearchOptions
    /// Whether the Find bar is currently docked/visible for this tab. Owned
    /// here (not by the SwiftUI view) so it survives a tab switch and back
    /// via `EditorFindModelStore`'s own per-identity caching, exactly like
    /// `query`/`options`/`matches` already do.
    public var isActive = false

    public private(set) var matches: [SearchMatch] = []
    public private(set) var currentIndex: Int?
    /// Set when the last `updateMatches(in:)` call failed to compile a regex
    /// query — surfaced by the Find bar as a visible diagnostic, per
    /// `SearchQueryError`'s own doc comment ("never silently fall back to a
    /// zero-result state").
    public private(set) var error: SearchQueryError?

    public init(query: String = "", options: SearchOptions = SearchOptions()) {
        self.query = query
        self.options = options
    }

    public var currentMatch: SearchMatch? {
        guard let currentIndex, matches.indices.contains(currentIndex) else { return nil }
        return matches[currentIndex]
    }

    public var matchCount: Int {
        matches.count
    }

    /// Recomputes `matches` against `text` for the current `query`/`options`,
    /// then resolves `currentIndex` to the first match starting AT OR AFTER
    /// `anchor` (typically the live caret position when the bar was opened,
    /// or the previously-current match's own start when re-searching after
    /// an option toggle) — wrapping to the first match overall if `anchor`
    /// is past every match, or `nil` if `anchor` itself is `nil`
    /// (defaulting to the very first match) or there are no matches at all.
    /// A failed regex compile clears `matches`/`currentIndex` and populates
    /// `error` instead of leaving stale results on screen.
    public func updateMatches(in text: String, preferringLocationNear anchor: Int? = nil) {
        do {
            matches = try TextSearchEngine.matches(in: text, query: query, options: options)
            error = nil
        } catch {
            matches = []
            self.error = error
        }
        currentIndex = Self.nearestIndex(in: matches, to: anchor)
    }

    /// Moves to the next match, wrapping to the first if `options.wraps` and
    /// already at the last — or staying put (a no-op) at the boundary if
    /// wrap is disabled. Starting from no current match (a fresh search)
    /// goes to the first match. Returns the new `currentMatch`.
    @discardableResult
    public func findNext() -> SearchMatch? {
        advance(by: 1)
    }

    /// The reverse of `findNext()`: starting from no current match goes to
    /// the LAST match (not the first), matching every real editor's own
    /// "Find Previous with nothing selected yet" convention.
    @discardableResult
    public func findPrevious() -> SearchMatch? {
        advance(by: -1)
    }

    @discardableResult
    private func advance(by delta: Int) -> SearchMatch? {
        guard !matches.isEmpty else {
            currentIndex = nil
            return nil
        }
        guard let index = currentIndex else {
            currentIndex = delta > 0 ? 0 : matches.count - 1
            return currentMatch
        }
        let next = index + delta
        guard next < 0 || next >= matches.count else {
            currentIndex = next
            return currentMatch
        }
        guard options.wraps else {
            return currentMatch
        }
        currentIndex = next < 0 ? matches.count - 1 : 0
        return currentMatch
    }

    private static func nearestIndex(in matches: [SearchMatch], to anchor: Int?) -> Int? {
        guard !matches.isEmpty else { return nil }
        guard let anchor else { return 0 }
        return matches.firstIndex { $0.range.location >= anchor } ?? 0
    }
}
