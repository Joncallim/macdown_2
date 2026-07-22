@testable import Highlighting
import Testing

struct CaptureFallbackTests {
    @Test func rootReturnsNil() {
        #expect(HighlightCaptureName.fallback("keyword") == nil)
    }

    @Test func trimsOneSegment() {
        #expect(HighlightCaptureName.fallback("keyword.control") == "keyword")
    }

    @Test func trimsNestedSegment() {
        #expect(HighlightCaptureName.fallback("keyword.control.return") == "keyword.control")
    }

    @Test func canonicalSetContainsRoots() {
        #expect(HighlightCaptureName.canonical.contains("keyword"))
        #expect(HighlightCaptureName.canonical.contains("markup.heading"))
        #expect(HighlightCaptureName.canonical.contains("embedded"))
    }
}
