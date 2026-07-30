@testable import MarkdownEngine
@testable import OutlineUI
import Testing

@Suite("OutlineSelection.currentItemID")
struct OutlineSelectionTests {
    private let headings = [
        Fixtures.heading(level: 1, title: "One", line: 1),
        Fixtures.heading(level: 2, title: "Two", line: 5),
        Fixtures.heading(level: 3, title: "Three", line: 10),
    ]

    @Test func emptyHeadingsReturnsNil() {
        #expect(OutlineSelection.currentItemID(forLine: 3, in: []) == nil)
    }

    @Test func lineBeforeFirstHeadingReturnsNil() {
        #expect(OutlineSelection
            .currentItemID(forLine: 1, in: [Fixtures.heading(level: 1, title: "H", line: 5)]) == nil)
    }

    @Test func exactHeadingLineReturnsThatHeading() {
        #expect(OutlineSelection.currentItemID(forLine: 5, in: headings) == 1)
    }

    @Test func lineInsideASectionReturnsThatSection() {
        #expect(OutlineSelection.currentItemID(forLine: 7, in: headings) == 1)
    }

    @Test func lineInsideANestedSectionReturnsTheNestedHeadingNotItsParent() {
        #expect(OutlineSelection.currentItemID(forLine: 12, in: headings) == 2)
    }

    @Test func lastLineReturnsLastHeading() {
        #expect(OutlineSelection.currentItemID(forLine: 1000, in: headings) == 2)
    }

    @Test func monotonicityOverAscendingLines() {
        var previous = -1
        for line in 0 ... 20 {
            guard let id = OutlineSelection.currentItemID(forLine: line, in: headings) else { continue }
            #expect(id >= previous, "id regressed at line \(line)")
            previous = id
        }
    }
}
