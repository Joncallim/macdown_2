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
    private let hasURLReferences: Bool

    init(source: String, baseURL: URL?, result: Result<AttributedString, any Error>) {
        self.source = source
        self.baseURL = baseURL
        self.result = result
        if case let .success(attributed) = result {
            hasResourceReferences = attributed.runs.contains { $0.imageURL != nil || $0.textual.emojiURL != nil }
            hasURLReferences = hasResourceReferences || attributed.runs.contains { $0.link != nil }
        } else {
            // A failed classification must not retain potentially resource-bearing Textual state.
            hasResourceReferences = true
            hasURLReferences = true
        }
    }

    /// Textual observes only its input string, not changes to its parser. A link-only block can rebind in place
    /// when that input changes; the private adapter key never becomes rendered text or authored resource input.
    var renderingInput: String {
        guard hasURLReferences, !hasResourceReferences else { return source }
        let location = baseURL?.absoluteString ?? ""
        return "\u{0}\(location.utf8.count):\(location)\(source)"
    }

    func renderingIdentity(mathContentID: String, resourceLoadID: UUID?) -> PreviewTextRenderingIdentity {
        PreviewTextRenderingIdentity(
            // Resources still replace asynchronous attachment state; ordinary links reparse in place.
            baseURL: hasResourceReferences ? baseURL : nil, mathContentID: mathContentID,
            resourceLoadID: hasResourceReferences ? resourceLoadID : nil
        )
    }

    func attributedString(for input: String) throws -> AttributedString {
        // Preserve the established attachment parser path; cache only ordinary text output.
        guard input == source || input == renderingInput, !hasResourceReferences else {
            return try PreviewMarkupParser(baseURL: baseURL, syntaxExtensions: [.math]).attributedString(for: input)
        }
        return try result.get()
    }
}
