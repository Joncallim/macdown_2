@testable import DiagramsGraphviz
import Foundation
import MarkdownEngine
import Testing

@Suite("GraphvizFenceScanner")
struct GraphvizFenceScannerTests {
    private static func document(_ text: String) async throws -> MarkdownDocument {
        try await ParseEngine().parse(text, revision: 0)
    }

    @Test func scanFindsATopLevelDotFence() async throws {
        let text = "# Title\n\n```dot\ndigraph { a -> b; }\n```\n"
        let fences = try await GraphvizFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
        #expect(fences[0].source == "digraph { a -> b; }")
    }

    @Test func scanAcceptsTheGraphvizAliasToo() async throws {
        let text = "```graphviz\ndigraph { a -> b; }\n```\n"
        let fences = try await GraphvizFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
    }

    @Test func scanIgnoresNonGraphvizFences() async throws {
        let text = "```swift\nlet x = 1\n```\n"
        let fences = try await GraphvizFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.isEmpty)
    }

    @Test func scanMatchesTheLanguageTagCaseInsensitively() async throws {
        let text = "```DOT\ndigraph { a -> b; }\n```\n"
        let fences = try await GraphvizFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
    }

    @Test func scanFindsAFenceNestedInsideAListItem() async throws {
        let text = "- item one\n  ```dot\n  digraph { a -> b; }\n  ```\n- item two\n"
        let fences = try await GraphvizFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
        #expect(fences[0].source.contains("a -> b"))
    }

    @Test func scanFindsAFenceNestedInsideABlockQuote() async throws {
        let text = "> quoted\n> ```dot\n> digraph { a -> b; }\n> ```\n"
        let fences = try await GraphvizFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
    }

    @Test func scanSourceRangeSpansTheEntireFenceIncludingDelimiters() async throws {
        let text = "```dot\ndigraph { a -> b; }\n```"
        let fences = try await GraphvizFenceScanner.scan(Self.document(text), sourceText: text)
        let fence = try #require(fences.first)
        let nsRange = NSRange(location: fence.sourceRange.lowerBound, length: fence.sourceRange.count)
        let slice = (text as NSString).substring(with: nsRange)
        #expect(slice == text)
    }
}
