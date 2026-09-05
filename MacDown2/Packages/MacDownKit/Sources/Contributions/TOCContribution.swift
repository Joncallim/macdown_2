import Foundation
import MarkdownEngine

/// Replaces every line consisting only of `[TOC]` (surrounding whitespace
/// trimmed) with a nested Markdown list built from `document.headings`.
///
/// The list is plain text, not clickable links: no part of today's export
/// pipeline generates a stable `id` for a heading, and Preview hands every
/// link — anchor or not — to `NSWorkspace.shared.open` rather than
/// scrolling to it, so a link would not go anywhere useful in either
/// destination (epic-14-implementation.md §18, residual risk 2).
///
/// Zero headings still replaces the marker, with a short placeholder — the
/// literal text `[TOC]` never remains visible once a marker is found.
public struct TOCContribution: Contributing {
    public let id = "toc"

    public init() {}

    public func run(
        document: MarkdownDocument,
        sourceText: String,
        sourceGeneration: UInt
    ) async throws -> [ContributionResult] {
        let markers = Self.findMarkers(in: sourceText, document: document)
        guard !markers.isEmpty else { return [] }

        let list = Self.markdownList(for: document.headings)
        return markers.map { range in
            ContributionResult(
                contributionID: id,
                content: ContributionContent(sourceRange: range, placement: .block, representation: .markdown(list)),
                sourceGeneration: sourceGeneration
            )
        }
    }

    /// Every line whose trimmed content is exactly `[TOC]` AND that is
    /// semantically a top-level CommonMark paragraph, as the UTF-16 range of
    /// the whole physical line (trailing `\r` included, on a CRLF-terminated
    /// line) — never a zero-width point, since `[TOC]` itself is non-empty,
    /// satisfying `DerivedContentComposer`'s existing non-empty-range
    /// requirement by construction.
    ///
    /// A line lexically matching `[TOC]` inside fenced/indented code, a
    /// list item, a block quote, a heading, front matter, or an HTML block
    /// is literal text, not this contribution's syntax — checked against
    /// `document.blocks` (top-level parse blocks only) rather than a text
    /// scan, so Preview and Export can never disagree about which markers
    /// are "real" (epic-14-implementation.md architecture pass 3/10).
    static func findMarkers(in text: String, document: MarkdownDocument) -> [Range<Int>] {
        let sourceMap = document.sourceMap
        let nsText = text as NSString
        var ranges: [Range<Int>] = []
        for line in 1 ... sourceMap.lineCount {
            let nsRange = sourceMap.utf16Range(ofLines: line ... line)
            let lineText = nsText.substring(with: nsRange)
            guard lineText.trimmingCharacters(in: .whitespacesAndNewlines) == "[TOC]" else { continue }
            guard isTopLevelParagraphLine(line, in: document.blocks) else { continue }
            ranges.append(nsRange.location ..< (nsRange.location + nsRange.length))
        }
        return ranges
    }

    /// `true` only when exactly one TOP-LEVEL block (no recursion into
    /// `children`) contains `line` and that block's kind is `.paragraph`.
    /// Deliberately not `document.block(atLine:)`: that helper recurses into
    /// children and would accept a paragraph nested inside a list item or
    /// block quote, both still literal/unsupported placement contexts for
    /// this first-party contribution.
    private static func isTopLevelParagraphLine(_ line: Int, in topLevelBlocks: [MarkdownBlock]) -> Bool {
        let containing = topLevelBlocks.filter { $0.lineRange.contains(line) }
        guard containing.count == 1, case .paragraph = containing[0].kind else { return false }
        return true
    }

    /// Nests by heading level using 2-space Markdown list indentation (the
    /// minimum CommonMark requires to nest under a single-character `-`
    /// marker). A heading whose level skips ahead of its immediate
    /// predecessor (H1 directly followed by H3) is indented one level under
    /// the nearest shallower heading already seen, not clamped or rejected
    /// — a document's own heading structure is never "invalid" to this
    /// contribution.
    static func markdownList(for headings: [HeadingItem]) -> String {
        guard !headings.isEmpty else { return "*(No headings found.)*" }

        var lines: [String] = []
        var openLevels: [Int] = []
        for heading in headings {
            while let top = openLevels.last, top >= heading.level {
                openLevels.removeLast()
            }
            let indent = String(repeating: "  ", count: openLevels.count)
            openLevels.append(heading.level)
            lines.append("\(indent)- \(escaped(heading.title))")
        }
        return lines.joined(separator: "\n")
    }

    /// Backslash-escapes CommonMark's ASCII punctuation set. `title` is
    /// already plain text (markup stripped by swift-markdown) but can still
    /// contain characters — `[`, `*`, `#`, and similar — that would be
    /// re-interpreted as syntax once re-embedded in this newly generated
    /// list; backslash-escaping is valid anywhere in CommonMark and has no
    /// effect beyond presenting the literal character, so escaping every
    /// occurrence is always safe.
    private static func escaped(_ title: String) -> String {
        var result = ""
        result.reserveCapacity(title.count)
        for character in title {
            if escapableCharacters.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    private static let escapableCharacters = Set("\\`*_{}[]()#+-.!<>|~")
}
