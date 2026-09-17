@testable import DiagramsD2
import Foundation
import MarkdownEngine
import Testing

@Suite("D2FenceScanner")
struct D2FenceScannerTests {
    private static func document(_ text: String) async throws -> MarkdownDocument {
        try await ParseEngine().parse(text, revision: 0)
    }

    @Test func scanFindsATopLevelD2Fence() async throws {
        let text = "# Title\n\n```d2\na -> b\n```\n"
        let fences = try await D2FenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
        #expect(fences[0].source == "a -> b")
    }

    @Test func scanIgnoresNonD2Fences() async throws {
        let text = "```swift\nlet x = 1\n```\n"
        let fences = try await D2FenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.isEmpty)
    }

    @Test func scanMatchesTheLanguageTagCaseInsensitively() async throws {
        let text = "```D2\na -> b\n```\n"
        let fences = try await D2FenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
    }

    @Test func scanFindsAFenceNestedInsideAListItem() async throws {
        let text = "- item one\n  ```d2\n  a -> b\n  ```\n- item two\n"
        let fences = try await D2FenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
        #expect(fences[0].source.contains("a -> b"))
    }

    @Test func scanFindsAFenceNestedInsideABlockQuote() async throws {
        let text = "> quoted\n> ```d2\n> a -> b\n> ```\n"
        let fences = try await D2FenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
    }

    @Test func scanSourceRangeSpansTheEntireFenceIncludingDelimiters() async throws {
        let text = "```d2\na -> b\n```"
        let fences = try await D2FenceScanner.scan(Self.document(text), sourceText: text)
        let fence = try #require(fences.first)
        let nsRange = NSRange(location: fence.sourceRange.lowerBound, length: fence.sourceRange.count)
        let slice = (text as NSString).substring(with: nsRange)
        #expect(slice == text)
    }
}
