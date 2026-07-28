import Foundation
import Textual

/// A ``MarkupParser`` seam that wraps Textual's Markdown parser.
///
/// This type exists so the rest of the preview layer depends on a local
/// abstraction rather than Textual's parser initializers directly.
public struct PreviewMarkupParser: MarkupParser {
    public let baseURL: URL?
    public let syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension]

    public init(
        baseURL: URL? = nil,
        syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
    ) {
        self.baseURL = baseURL
        self.syntaxExtensions = syntaxExtensions
    }

    public func attributedString(for input: String) throws -> AttributedString {
        try AttributedStringMarkdownParser(
            baseURL: baseURL,
            syntaxExtensions: syntaxExtensions
        )
        .attributedString(for: input)
    }
}
