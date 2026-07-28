import Foundation

/// Extracts CommonMark link reference definitions from the whole document
/// source, so they can be replayed into each independently-parsed preview
/// block.
///
/// A link reference definition (`[label]: destination "title"`) is resolved
/// during parsing and is normally visible to every reference anywhere in the
/// same document. Because each ``PreviewBlock`` is handed to Textual as its
/// own standalone parse, a definition living in one block is invisible to a
/// `[text][label]` reference living in another — the reference renders as
/// literal text instead of a link. Prepending every definition's original
/// line to a block's source before it reaches Textual gives that block's
/// parse the same reference map a whole-document parse would have had.
/// Reference definitions produce no visible output on their own, so this is
/// safe to do unconditionally.
///
/// Known limitations, accepted as proportionate to the common case:
/// - Only single-line definitions are recognized. CommonMark also allows the
///   destination/title to continue onto a following line; that form is rare
///   in practice and is left to degrade to the pre-existing behavior
///   (unresolved reference rendered as literal text).
/// - Extraction is text-only and not fence-aware, so a line that looks like a
///   definition inside a fenced code block would be misidentified. This
///   mirrors the same trade-off already accepted for reference-definition
///   detection versus a full CommonMark parse.
public enum PreviewLinkDefinitions {
    /// Up to three leading spaces (CommonMark's allowance for a definition to
    /// be indented like other block content), `[label]:`, at least one space
    /// or tab, then a non-empty destination.
    ///
    /// `Regex` isn't `Sendable`, but a compiled pattern is logically immutable
    /// after initialization, so sharing this read-only value across threads
    /// is safe despite the compiler's inability to verify it statically.
    private nonisolated(unsafe) static let pattern = #/^ {0,3}\[[^\]\n]+\]:[ \t]+\S.*$/#

    /// Reference definition lines found anywhere in `text`, in document
    /// order, with original formatting preserved.
    public static func extract(from text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line in
                line.wholeMatch(of: pattern) != nil ? String(line) : nil
            }
    }
}
