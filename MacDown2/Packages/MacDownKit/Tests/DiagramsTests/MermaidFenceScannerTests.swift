@testable import Diagrams
import Foundation
import MarkdownEngine
import Testing

@Suite("MermaidFenceScanner")
struct MermaidFenceScannerTests {
    private static func document(_ text: String) async throws -> MarkdownDocument {
        try await ParseEngine().parse(text, revision: 0)
    }

    @Test func scanFindsATopLevelMermaidFence() async throws {
        let text = "# Title\n\n```mermaid\ngraph TD; A-->B;\n```\n"
        let fences = try await MermaidFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
        #expect(fences[0].source == "graph TD; A-->B;")
    }

    @Test func scanIgnoresNonMermaidFences() async throws {
        let text = "```swift\nlet x = 1\n```\n"
        let fences = try await MermaidFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.isEmpty)
    }

    @Test func scanMatchesTheLanguageTagCaseInsensitively() async throws {
        let text = "```Mermaid\ngraph TD; A-->B;\n```\n"
        let fences = try await MermaidFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
    }

    @Test func scanFindsAFenceNestedInsideAListItem() async throws {
        let text = "- item one\n  ```mermaid\n  graph TD; A-->B;\n  ```\n- item two\n"
        let fences = try await MermaidFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
        #expect(fences[0].source.contains("graph TD"))
    }

    @Test func scanFindsAFenceNestedInsideABlockQuote() async throws {
        let text = "> quoted\n> ```mermaid\n> graph TD; A-->B;\n> ```\n"
        let fences = try await MermaidFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
    }

    @Test func scanFindsMultipleFencesAndIsolatesEachOne() async throws {
        let text = "```mermaid\ngraph TD; A-->B;\n```\n\nProse.\n\n```mermaid\nsequenceDiagram\n  A->>B: hi\n```\n"
        let fences = try await MermaidFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 2)
        #expect(fences[0].source == "graph TD; A-->B;")
        #expect(fences[1].source == "sequenceDiagram\n  A->>B: hi")
    }

    @Test func scanSourceRangeSpansTheEntireFenceIncludingDelimiters() async throws {
        let text = "```mermaid\ngraph TD; A-->B;\n```"
        let fences = try await MermaidFenceScanner.scan(Self.document(text), sourceText: text)
        let fence = try #require(fences.first)
        let nsRange = NSRange(location: fence.sourceRange.lowerBound, length: fence.sourceRange.count)
        let slice = (text as NSString).substring(with: nsRange)
        #expect(slice == text)
    }

    @Test func scanReturnsEmptySourceForAnEmptyFence() async throws {
        let text = "```mermaid\n```\n"
        let fences = try await MermaidFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
        #expect(fences[0].source.isEmpty)
    }

    // MARK: - #183 F07: CRLF / CR fences are found, not silently skipped

    @Test func aCRLFFenceFollowedByMoreTextIsFound() async throws {
        let text = "```mermaid\r\ngraph TD; A-->B;\r\n```\r\nafter"
        let fences = try await MermaidFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
        #expect(fences.first?.source == "graph TD; A-->B;")
    }

    @Test func aBareCRFenceIsFound() async throws {
        let text = "```mermaid\rgraph TD; A-->B;\r```\rafter"
        let fences = try await MermaidFenceScanner.scan(Self.document(text), sourceText: text)
        #expect(fences.count == 1)
        #expect(fences.first?.source == "graph TD; A-->B;")
    }
}
