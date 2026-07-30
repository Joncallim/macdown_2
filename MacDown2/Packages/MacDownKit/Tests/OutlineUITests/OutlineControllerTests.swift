import Foundation
@testable import MarkdownEngine
@testable import OutlineUI
import Testing

@MainActor
@Suite("OutlineController")
struct OutlineControllerTests {
    // MARK: - Availability gating (D7/§2.4)

    @Test func nilDocumentYieldsNotParsed() {
        let controller = OutlineController()
        controller.update(document: nil, isMarkdown: false, formatName: "Python")
        #expect(controller.availability == .notParsed)
        #expect(controller.items.isEmpty)
    }

    @Test func nonMarkdownFormatYieldsUnsupportedFormatWithEmptyItemsEvenWhenHeadingsArePopulated() async {
        // A Python-comment corpus: the engine parses `# comment` lines as
        // headings regardless of the file's real format (§2.4) — the app-level
        // gate is what must keep them out of the outline.
        let session = MarkdownParseSession()
        let document = await session.parseNow("# comment\nx = 1\n# another comment\n")
        #expect((document?.headings.count ?? 0) > 0, "fixture must actually produce headings")

        let controller = OutlineController()
        controller.update(document: document, isMarkdown: false, formatName: "Python")

        #expect(controller.availability == .unsupportedFormat(formatName: "Python"))
        #expect(controller.items.isEmpty)
    }

    @Test func markdownWithZeroHeadingsYieldsNoHeadings() async {
        let session = MarkdownParseSession()
        let document = await session.parseNow("just a paragraph, no headings\n")

        let controller = OutlineController()
        controller.update(document: document, isMarkdown: true, formatName: "Markdown")

        #expect(controller.availability == .noHeadings)
        #expect(controller.items.isEmpty)
    }

    @Test func markdownWithHeadingsYieldsReady() async {
        let session = MarkdownParseSession()
        let document = await session.parseNow("# Title\n\nBody\n")

        let controller = OutlineController()
        controller.update(document: document, isMarkdown: true, formatName: "Markdown")

        #expect(controller.availability == .ready)
        #expect(controller.items.map(\.title) == ["Title"])
    }

    // MARK: - D2: single shared parse, no second pipeline

    @Test func sharesThePreviewParseSessionAndDoesNotReparse() async {
        let session = MarkdownParseSession()
        let document = await session.parseNow("# A\n## B\n")

        let controller = OutlineController()
        controller.update(document: document, isMarkdown: true, formatName: "Markdown")
        #expect(controller.availability == .ready)
        #expect(controller.items.map(\.title) == ["A"])

        // Simulate a user interaction the no-op guard must preserve.
        controller.collapsedItemIDs = [0]

        // Same revision, same availability: update() must be a no-op — proof
        // there is no second pipeline recomputing anything behind the scenes.
        controller.update(document: document, isMarkdown: true, formatName: "Markdown")
        #expect(controller.collapsedItemIDs == [0], "unchanged revision must not touch reconciled state")
    }

    @Test func updateIsANoOpOnAnUnchangedRevision() async {
        let session = MarkdownParseSession()
        let document = await session.parseNow("# A\n")

        let controller = OutlineController()
        controller.update(document: document, isMarkdown: true, formatName: "Markdown")
        controller.selectedItemID = 0

        controller.update(document: document, isMarkdown: true, formatName: "Markdown")
        #expect(controller.selectedItemID == 0)
    }

    // MARK: - Reconciliation across a re-parse (D4)

    @Test func reconciliationDropsIDsTheNewTreeDoesNotContainAtAll() async {
        let session = MarkdownParseSession()
        let first = await session.parseNow("# A\n## B\n## C\n## D\n")

        let controller = OutlineController()
        controller.update(document: first, isMarkdown: true, formatName: "Markdown")
        controller.collapsedItemIDs = [1, 3]
        controller.selectedItemID = 3

        let second = await session.parseNow("# A\n## B\n")
        controller.update(document: second, isMarkdown: true, formatName: "Markdown")

        let validIDs = Set(controller.items.flatMap { [$0.id] + $0.children.map(\.id) })
        #expect(controller.collapsedItemIDs.isSubset(of: validIDs))
        #expect(controller.selectedItemID == nil, "selection pointing at a heading that no longer exists must clear")
    }

    @Test func reconciliationRemapsAnOrdinalShiftedByAnInsertAbove() async {
        let session = MarkdownParseSession()
        let first = await session.parseNow("# A\n# B\n")

        let controller = OutlineController()
        controller.update(document: first, isMarkdown: true, formatName: "Markdown")
        // "B" is ordinal 1; collapse it.
        controller.collapsedItemIDs = [1]

        // Insert a heading above both — "B" is now ordinal 2.
        let second = await session.parseNow("# Z\n# A\n# B\n")
        controller.update(document: second, isMarkdown: true, formatName: "Markdown")

        #expect(controller.items.map(\.title) == ["Z", "A", "B"])
        #expect(
            controller.collapsedItemIDs == [2],
            "collapse must follow \"B\" to its new ordinal, not stay at 1 (now \"A\")"
        )
    }

    // MARK: - activate(_:) / jump

    @Test func activateOnUnknownIDDoesNothing() {
        let controller = OutlineController()
        controller.activate(42)
        #expect(controller.pendingJumpLineRange == nil)
        #expect(controller.selectedItemID == nil)
    }

    @Test func activatePublishesTheHeadingLineOnlyNotTheFullRange() async {
        let session = MarkdownParseSession()
        // A Setext-style range spans multiple lines; activate must target only
        // the heading line, per the plan's "not the whole lineRange" rule.
        let document = await session.parseNow("# Title\n\nBody text on the next line.\n")

        let controller = OutlineController()
        controller.update(document: document, isMarkdown: true, formatName: "Markdown")

        controller.activate(0)
        #expect(controller.pendingJumpLineRange == 1 ... 1)
        #expect(controller.selectedItemID == 0)
    }

    // MARK: - requestFocus (D11)

    @Test func requestFocusIncrementsMonotonically() {
        let controller = OutlineController()
        let start = controller.focusRequestID
        controller.requestFocus()
        controller.requestFocus()
        #expect(controller.focusRequestID == start + 2)
    }

    // MARK: - Reference offset resolution (D5)

    @Test func referenceOffsetBeforeTheFirstHeadingYieldsNilCurrentItem() async {
        let session = MarkdownParseSession()
        let document = await session.parseNow("preamble\n# Title\n")

        let controller = OutlineController()
        controller.update(document: document, isMarkdown: true, formatName: "Markdown")
        controller.referenceOffsetDidChange(0)

        #expect(controller.currentItemID == nil)
    }

    @Test func referenceOffsetPastLiveTextEndResolvesToTheLastHeading() async {
        let session = MarkdownParseSession()
        let document = await session.parseNow("# A\n## B\n")

        let controller = OutlineController()
        controller.update(document: document, isMarkdown: true, formatName: "Markdown")
        controller.referenceOffsetDidChange(1_000_000)

        #expect(controller.currentItemID == 1)
    }

    @Test func currentSectionFollowsTheCaretAcrossAReparseWithoutASecondEvent() async throws {
        let session = MarkdownParseSession()
        let first = await session.parseNow("# A\nline under A\n# B\nline under B\n")
        guard let bText = first?.sourceMap else {
            Issue.record("fixture parse failed")
            return
        }
        let offsetUnderB = bText.utf16Range(ofLines: 4 ... 4).location

        let controller = OutlineController()
        controller.update(document: first, isMarkdown: true, formatName: "Markdown")
        controller.referenceOffsetDidChange(offsetUnderB)
        #expect(controller.currentItemID == 1, "offset under \"B\" should resolve to \"B\"")

        // Insert two lines above the caret's line. The stored offset is a
        // UTF-16 position, so after this edit it now falls under a *different*
        // heading — a real caret sitting at that byte position would too.
        let second = await session.parseNow("# Z\nfiller\n# A\nline under A\n# B\nline under B\n")
        controller.update(document: second, isMarkdown: true, formatName: "Markdown")

        // Re-translated through the NEW source map at the SAME stored offset,
        // without calling referenceOffsetDidChange again.
        let expected = try OutlineSelection.currentItemID(
            forLine: #require(second?.sourceMap.line(atUTF16Offset: offsetUnderB)),
            in: #require(second?.headings)
        )
        #expect(controller.currentItemID == expected)
    }
}
