import Foundation

/// One line-number label the gutter should draw, at a given vertical
/// position in the text view's own coordinate space.
public struct GutterLineLabel: Sendable, Equatable {
    public let lineNumber: Int
    public let minY: CGFloat

    public init(lineNumber: Int, minY: CGFloat) {
        self.lineNumber = lineNumber
        self.minY = minY
    }
}

/// Pure line-number gutter layout — computes WHICH visible fragments get a
/// label and WHAT number they show, with no AppKit dependency, so this is
/// directly unit-testable without a real text view or window.
///
/// The one non-trivial rule: a logical line that wraps across multiple
/// `NSTextLayoutFragment`s must show its number only once, on its FIRST
/// fragment — every mainstream code editor's gutter convention. A
/// continuation fragment's starting UTF-16 offset is never itself a
/// recorded line-start offset in `EditorLineIndex`, which is exactly the
/// check used to tell the two apart.
public enum EditorGutterLayout {
    /// `fragments` is the ordered, already viewport-bounded list of
    /// `(utf16Offset, minY)` pairs for every `NSTextLayoutFragment`
    /// currently materialized in the visible rect — the caller (AppKit
    /// glue) is responsible for that bounding; this function performs no
    /// viewport logic of its own and is safe to call with any input size.
    public static func labels(
        for fragments: [(utf16Offset: Int, minY: CGFloat)],
        lineIndex: EditorLineIndex
    ) -> [GutterLineLabel] {
        fragments.compactMap { fragment in
            let lineNumber = lineIndex.line(atUTF16Offset: fragment.utf16Offset)
            guard lineNumber >= 1, lineNumber <= lineIndex.lineCount else { return nil }
            let lineStart = lineIndex.lineStartOffsets[lineNumber - 1]
            guard fragment.utf16Offset == lineStart else { return nil }
            return GutterLineLabel(lineNumber: lineNumber, minY: fragment.minY)
        }
    }
}
