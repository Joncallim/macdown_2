import Foundation
import MarkdownEngine

/// Multi-line display math inside a block quote reaches the scanner with the quote's own `>` markers on every
/// continuation line (`> $$\n> x^2\n> $$`), so the LaTeX handed to the renderer (and used as `alt` text) was
/// `\n> x^2\n> ` and typeset as "> x² >". The markers belong to the container, not the equation.
public enum MathContainerPrefix {
    /// Whether the line holding `spanStart` has a block-quote marker before the span.
    public static func isInsideQuote(spanStart: Int, character: (Int) -> UInt16) -> Bool {
        var index = spanStart - 1
        while index >= 0 {
            let unit = character(index)
            if unit == 0x0A || unit == 0x0D {
                return false
            }
            if unit == 0x3E { // `>`
                return true
            }
            index -= 1
        }
        return false
    }

    /// `latex` with each continuation line's leading indentation and `>` markers removed (one optional space after
    /// each marker, as CommonMark does). The first line starts right after the opening delimiter, so it is kept.
    public static func strippingQuoteMarkers(from latex: String) -> String {
        let lines = latex.markdownLines()
        guard lines.count > 1 else { return latex }
        let stripped = lines.enumerated().map { offset, line -> String in
            guard offset > 0 else { return line }
            var rest = Substring(line)
            while true {
                let trimmed = rest.drop { $0 == " " || $0 == "\t" }
                guard trimmed.first == ">" else { return String(trimmed) }
                let afterMarker = trimmed.dropFirst()
                rest = afterMarker.first == " " ? afterMarker.dropFirst() : afterMarker
            }
        }
        return stripped.joined(separator: "\n")
    }
}
