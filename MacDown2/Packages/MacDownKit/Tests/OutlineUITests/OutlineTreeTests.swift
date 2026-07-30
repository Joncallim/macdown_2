@testable import MarkdownEngine
@testable import OutlineUI
import Testing

@Suite("OutlineTree.build")
struct OutlineTreeBuildTests {
    @Test func emptyInputProducesEmptyOutput() {
        #expect(OutlineTree.build(from: []).isEmpty)
    }

    @Test func simpleNestingProducesOneRoot() {
        let items = OutlineTree.build(from: Fixtures.simpleNesting)
        #expect(items.map(\.id) == [0])
        #expect(items[0].children.map(\.id) == [1])
        #expect(items[0].children[0].children.map(\.id) == [2])
    }

    @Test func skippedLevelAttachesToShallowerAncestorWithoutSynthesizing() {
        // H1 → H3: H3 nests under H1, level stays 3 (D3).
        let items = OutlineTree.build(from: Fixtures.skippedLevel)
        #expect(items.count == 1)
        #expect(items[0].id == 0)
        #expect(items[0].children.count == 1)
        #expect(items[0].children[0].id == 1)
        #expect(items[0].children[0].level == 3)
    }

    @Test func headingShallowerThanEverythingBeforeStartsANewRoot() {
        // Opens at H3, later H1 → two roots, document order preserved.
        let items = OutlineTree.build(from: Fixtures.opensDeepThenShallow)
        #expect(items.map(\.id) == [0, 1])
        #expect(items[0].level == 3)
        #expect(items[1].level == 1)
        let allLeaves = items.allSatisfy(\.children.isEmpty)
        #expect(allLeaves)
    }

    @Test func siblingAtSameLevelClosesThePreviousSubtree() {
        let headings = [
            Fixtures.heading(level: 1, title: "A", line: 1),
            Fixtures.heading(level: 2, title: "A.1", line: 2),
            Fixtures.heading(level: 3, title: "A.1.a", line: 3),
            Fixtures.heading(level: 2, title: "A.2", line: 4),
        ]
        let items = OutlineTree.build(from: headings)
        #expect(items.count == 1)
        #expect(items[0].children.map(\.id) == [1, 3])
        #expect(items[0].children[0].children.map(\.id) == [2])
        #expect(items[0].children[1].children.isEmpty)
    }

    @Test func duplicateTitlesKeepDistinctOrdinalIdentity() {
        let headings = [
            Fixtures.heading(level: 1, title: "Overview", line: 1),
            Fixtures.heading(level: 1, title: "Overview", line: 2),
        ]
        let items = OutlineTree.build(from: headings)
        #expect(items.map(\.id) == [0, 1])
        #expect(items.map(\.title) == ["Overview", "Overview"])
    }

    @Test func emptyTitleHeadingStillProducesAnItem() {
        let items = OutlineTree.build(from: [Fixtures.heading(level: 2, title: "", line: 1)])
        #expect(items.count == 1)
        #expect(items[0].title.isEmpty)
    }

    @Test func fiveThousandHeadingCorpusBuildsWithoutTimingOut() {
        let headings = (0 ..< 5000).map { index in
            Fixtures.heading(level: (index % 6) + 1, title: "H\(index)", line: index + 1)
        }
        let items = OutlineTree.build(from: headings)
        #expect(OutlineTree.allIDs(items).count == 5000)
    }
}

@Suite("OutlineTree.visibleItems / allIDs")
struct OutlineTreeTraversalTests {
    @Test func visibleItemsIsDepthFirstDocumentOrderWhenNothingCollapsed() {
        let items = OutlineTree.build(from: Fixtures.simpleNesting)
        let visible = OutlineTree.visibleItems(items, collapsed: [])
        #expect(visible.map(\.id) == [0, 1, 2])
    }

    @Test func collapsingAParentHidesExactlyItsDescendants() {
        let headings = [
            Fixtures.heading(level: 1, title: "A", line: 1),
            Fixtures.heading(level: 2, title: "A.1", line: 2),
            Fixtures.heading(level: 1, title: "B", line: 3),
        ]
        let items = OutlineTree.build(from: headings)
        let visible = OutlineTree.visibleItems(items, collapsed: [0])
        #expect(visible.map(\.id) == [0, 2])
    }

    @Test func collapsingALeafChangesNothing() {
        let items = OutlineTree.build(from: Fixtures.simpleNesting)
        let visible = OutlineTree.visibleItems(items, collapsed: [2])
        #expect(visible.map(\.id) == [0, 1, 2])
    }

    @Test func nestedCollapseHidesOnlyTheCollapsedSubtree() {
        let headings = [
            Fixtures.heading(level: 1, title: "A", line: 1),
            Fixtures.heading(level: 2, title: "A.1", line: 2),
            Fixtures.heading(level: 3, title: "A.1.a", line: 3),
            Fixtures.heading(level: 2, title: "A.2", line: 4),
        ]
        let items = OutlineTree.build(from: headings)
        let visible = OutlineTree.visibleItems(items, collapsed: [1])
        #expect(visible.map(\.id) == [0, 1, 3])
    }

    @Test func allIDsCollectsEveryNodeRegardlessOfDepth() {
        let items = OutlineTree.build(from: Fixtures.simpleNesting)
        #expect(OutlineTree.allIDs(items) == [0, 1, 2])
    }

    @Test func itemLookupFindsNestedNodes() {
        let items = OutlineTree.build(from: Fixtures.simpleNesting)
        #expect(OutlineTree.item(withID: 2, in: items)?.title == "Three")
        #expect(OutlineTree.item(withID: 99, in: items) == nil)
    }
}
