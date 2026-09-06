import MarkdownEngine

/// Shared fixture builders for `ContributionsTests`. A hand-built
/// `MarkdownDocument` whose `sourceMap` does not actually match the text a
/// test passes alongside it is a worse test than no test — `findMarkers`
/// and `markdownList` are tested directly (§ below) precisely to avoid
/// needing one; this helper covers the few tests that need a real,
/// self-consistent document without a full `ParseEngine` parse.
enum MarkdownDocumentFixtures {
    /// A document with no headings and no blocks, whose `sourceMap`
    /// correctly matches `sourceText` (unlike a fixed empty `SourceMap`
    /// paired with unrelated text, which would silently test nothing).
    static func document(sourceText: String, headings: [HeadingItem] = []) -> MarkdownDocument {
        MarkdownDocument(
            body: sourceText,
            bodyLineOffset: 0,
            blocks: [],
            headings: headings,
            frontMatter: nil,
            sourceMap: SourceMap(text: sourceText),
            revision: 0,
            options: .default
        )
    }
}
