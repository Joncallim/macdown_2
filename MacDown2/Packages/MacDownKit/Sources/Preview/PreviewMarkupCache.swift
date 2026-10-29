import Foundation
import Textual

/// Keeps unchanged blocks' parsed text across resource generations. Parsed URL attributes, rather than source
/// spelling, decide which Textual subtrees must be replaced to retire their asynchronous attachment state.
@MainActor
final class PreviewMarkupCache {
    private let parse: (String, URL?) throws -> AttributedString
    private var cached: CachedPreviewMarkup?

    init(parse: @escaping (String, URL?) throws -> AttributedString = { source, baseURL in
        try PreviewMarkupParser(baseURL: baseURL, syntaxExtensions: [.math]).attributedString(for: source)
    }) {
        self.parse = parse
    }

    func parser(for source: String, baseURL: URL?) -> CachedPreviewMarkup {
        if let cached, cached.source == source, cached.baseURL == baseURL {
            return cached
        }
        let result = Result { try parse(source, baseURL) }
        let parser = CachedPreviewMarkup(source: source, baseURL: baseURL, result: result)
        cached = parser
        return parser
    }
}

struct PreviewTextRenderingIdentity: Hashable {
    let baseURL: URL?
    let mathContentID: String
    let resourceLoadID: UUID?
}

@MainActor
struct CachedPreviewMarkup: MarkupParser {
    let source: String
    let baseURL: URL?
    let result: Result<AttributedString, any Error>

    let hasResourceReferences: Bool

    init(source: String, baseURL: URL?, result: Result<AttributedString, any Error>) {
        self.source = source
        self.baseURL = baseURL
        self.result = result
        if case let .success(attributed) = result {
            hasResourceReferences = attributed.runs.contains { $0.imageURL != nil || $0.textual.emojiURL != nil }
        } else {
            // A failed classification must not retain potentially resource-bearing Textual state.
            hasResourceReferences = true
        }
    }

    func renderingIdentity(mathContentID: String, resourceLoadID: UUID?) -> PreviewTextRenderingIdentity {
        PreviewTextRenderingIdentity(
            baseURL: baseURL, mathContentID: mathContentID,
            resourceLoadID: hasResourceReferences ? resourceLoadID : nil
        )
    }

    func attributedString(for input: String) throws -> AttributedString {
        // Preserve the established attachment parser path; cache only ordinary text output.
        guard input == source, !hasResourceReferences else {
            return try PreviewMarkupParser(baseURL: baseURL, syntaxExtensions: [.math]).attributedString(for: input)
        }
        return try result.get()
    }
}
