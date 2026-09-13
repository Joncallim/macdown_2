import Foundation

/// Scans raw source text for math spans, using literally the same matching
/// rule as `Textual`'s sealed `.math` `SyntaxExtension`
/// (`PatternTokenizer.Pattern.mathBlock`/`.mathInline`, verified against the
/// checked-out `textual@0.5.0` source — epic-19-implementation.md §2.1, §6.1)
/// so Preview's pre-processing and Export's `MathContribution` can never
/// disagree with each other, or with what Textual itself will actually
/// render, about where an equation starts and ends.
///
/// `Textual`'s own `PatternTokenizer` cannot be reused directly — its types
/// are not `public` (epic-19-implementation.md §2.1) — so this is an
/// independent implementation of the identical rule: a left-to-right scan
/// that, at each position, tries the display pattern first and the inline
/// pattern second, each as a PREFIX match (not a search) at that exact
/// position; a position where neither matches advances by one character as
/// literal text. This ordering is what stops a `$$...$$` block from being
/// seen as two adjacent, incorrectly-matched inline spans.
///
/// The two regex literals below are copied verbatim from
/// `Textual/Internal/MarkdownParser/PatternTokenizer.swift`'s
/// `.mathBlock`/`.mathInline` patterns. If a future `textual` upgrade
/// changes them, `MathSpanScannerTests`'s fixture corpus is what catches the
/// drift — do not let this comment substitute for re-checking the dependency
/// source at that time.
public enum MathSpanScanner {
    /// **Deliberate, documented divergence from Textual's own tokenizer**
    /// (adversarial-review finding, post-merge, `chatgpt-codex-connector`):
    /// for input like `Price: \$5 and $x=1$ today.`, Textual's real
    /// tokenizer (and this scanner, before this fix) reaches the escaped
    /// `\$` one character at a time — the backslash matches neither
    /// pattern, so it is skipped as plain text, and the scan resumes
    /// exactly AT the following `$` with no memory that it was just
    /// escaped, so `mathInline` matches "$5 and $" as a phantom equation,
    /// consuming the real `$x=1$` equation's opening delimiter and leaving
    /// `x=1$` behind as broken literal text.
    ///
    /// This scanner now skips an escaped `\$` as a two-character unit when
    /// no pattern matches at the current position, so the `$` immediately
    /// after `\` is never revisited as a fresh opening delimiter. Textual's
    /// own sealed tokenizer has no equivalent fix and cannot be patched
    /// from here, so Export (which uses this scanner directly) now handles
    /// this input correctly while Preview (whose actual glyph rendering
    /// depends on Textual's own real tokenizer, not merely on what this
    /// scanner privately concludes) still inherits Textual's original
    /// behavior — a residual, Preview-only limitation recorded in
    /// epic-19-implementation.md §18, accepted because Export can be fully
    /// correct on its own and Preview cannot be fixed without fragile,
    /// speculative rewriting of prose this epic does not otherwise touch.
    public static func scan(_ text: String) -> [MathSpan] {
        var spans: [MathSpan] = []
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            let remainder = text[currentIndex...]

            if let match = try? displayPattern.prefixMatch(in: remainder) {
                spans.append(span(for: match, style: .display, in: text))
                currentIndex = match.range.upperBound
                continue
            }
            if let match = try? inlinePattern.prefixMatch(in: remainder) {
                spans.append(span(for: match, style: .inline, in: text))
                currentIndex = match.range.upperBound
                continue
            }
            if isEscapedDollar(at: currentIndex, in: text) {
                currentIndex = text.index(currentIndex, offsetBy: 2)
                continue
            }
            currentIndex = text.index(after: currentIndex)
        }

        return spans
    }

    private static func isEscapedDollar(at index: String.Index, in text: String) -> Bool {
        guard text[index] == "\\" else { return false }
        let next = text.index(after: index)
        return next < text.endIndex && text[next] == "$"
    }

    private static func span(
        for match: Regex<(Substring, Substring)>.Match,
        style: MathSpan.Style,
        in text: String
    ) -> MathSpan {
        let lower = match.range.lowerBound.utf16Offset(in: text)
        let upper = match.range.upperBound.utf16Offset(in: text)
        return MathSpan(range: lower ..< upper, style: style, latex: String(match.output.1))
    }

    /// `Regex` is not `Sendable` (it is, in practice, an immutable compiled
    /// value safe to share for concurrent reads — there is no mutation after
    /// construction); `nonisolated(unsafe)` avoids recompiling either literal
    /// on every `scan(_:)` call, which the sub-millisecond-per-block budget
    /// in epic-19-implementation.md §11 assumes.
    /// Verbatim copy of Textual's `PatternTokenizer.Pattern.mathBlock`.
    private nonisolated(unsafe) static let displayPattern = /(?s)\$\$(.+?)\$\$/
    /// Verbatim copy of Textual's `PatternTokenizer.Pattern.mathInline`.
    private nonisolated(unsafe) static let inlinePattern = /\$(?!\$)((?:\\\$|[^$\n])+)\$/
}
