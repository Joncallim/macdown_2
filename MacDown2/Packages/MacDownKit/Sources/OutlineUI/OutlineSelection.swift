import MarkdownEngine

public enum OutlineSelection {
    /// The last heading starting at or before `line` (D5). Binary search over
    /// the document-ordered list. `nil` when `line` precedes every heading, or
    /// when `headings` is empty.
    ///
    /// Callers pass a line derived from the *current* parse's `SourceMap`;
    /// the controller owns that translation so a stale map can never leak in.
    public static func currentItemID(forLine line: Int, in headings: [HeadingItem]) -> Int? {
        guard !headings.isEmpty, headings[0].lineRange.lowerBound <= line else { return nil }

        var low = 0
        var high = headings.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if headings[mid].lineRange.lowerBound <= line {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
