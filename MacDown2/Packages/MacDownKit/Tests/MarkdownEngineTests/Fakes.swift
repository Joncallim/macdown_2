import Foundation
@testable import MarkdownEngine

/// A configurable engine spy for debounce and options tests.
actor ParseSpy: ParseExecuting {
    struct Call: Sendable {
        let text: String
        let options: MarkdownParseOptions
        let revision: Int
    }

    private(set) var calls: [Call] = []
    private var results: [Int: Result<MarkdownDocument, any Error>] = [:]
    private var delay: Duration?

    init(delay: Duration? = nil) {
        self.delay = delay
    }

    func parse(_ text: String, options: MarkdownParseOptions, revision: Int) async throws -> MarkdownDocument {
        calls.append(Call(text: text, options: options, revision: revision))

        if let delay {
            try await Task.sleep(for: delay)
        }

        if let result = results[revision] {
            return try result.get()
        }

        return MarkdownDocument(
            body: text,
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: text),
            revision: revision,
            options: options
        )
    }

    func stub(_ revision: Int, with result: Result<MarkdownDocument, any Error>) {
        results[revision] = result
    }

    func stub(_ revision: Int, throwing error: any Error) {
        results[revision] = .failure(error)
    }
}
