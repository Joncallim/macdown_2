import Foundation
@testable import JSONSupport
@testable import OutlineUI
import Testing

/// EPIC-11 §3.4/Gate 3 — format-neutral outline integration: the JSON channel
/// populates from analysis results, publishes diagnostics for invalid
/// documents, clears on format transitions, and preserves collapse/selection
/// state across rebuilds with path-based IDs.
@MainActor
@Suite("JSONOutlineChannel")
struct JSONOutlineChannelTests {
    @Test func validResultPopulatesItemsAndAvailability() {
        let controller = OutlineController()
        let result = JSONAnalyzer.analyze(#"{"a":{"b":1},"c":2}"#)
        controller.updateJSON(result: result, formatID: "json")

        #expect(controller.jsonAvailability == .ready)
        #expect(controller.jsonItems.first?.id == "$")
        #expect(controller.jsonItems.first?.children.map(\.id) == ["$.a", "$.c"])
        #expect(controller.jsonDiagnostic == nil)
    }

    @Test func invalidResultPublishesDiagnosticAndNoItems() {
        let controller = OutlineController()
        let result = JSONAnalyzer.analyze(#"{"a":1,"a":2}"#)
        controller.updateJSON(result: result, formatID: "json")

        #expect(controller.jsonAvailability == .invalidJSON)
        #expect(controller.jsonItems.isEmpty)
        #expect(controller.jsonDiagnostic?.message.contains("Duplicate object key") == true)
    }

    @Test func nilResultClearsChannel() {
        let controller = OutlineController()
        controller.updateJSON(result: JSONAnalyzer.analyze(#"{"a":1}"#), formatID: "json")
        #expect(controller.jsonAvailability == .ready)

        // Format transition (Save As to Markdown) or not-yet-analyzed state.
        controller.updateJSON(result: nil, formatID: "json")
        #expect(controller.jsonAvailability == .notParsed)
        #expect(controller.jsonItems.isEmpty)

        // A non-JSON format never populates the channel.
        controller.updateJSON(result: JSONAnalyzer.analyze(#"{"a":1}"#), formatID: "markdown")
        #expect(controller.jsonAvailability == .notParsed)
        #expect(controller.jsonItems.isEmpty)
    }

    @Test func sameTextRebuildIsANoOp() {
        let controller = OutlineController()
        let result = JSONAnalyzer.analyze(#"{"a":1}"#)
        controller.updateJSON(result: result, formatID: "json")
        let countAfterFirst = controller.jsonRebuildCount

        controller.updateJSON(result: result, formatID: "json")
        #expect(controller.jsonRebuildCount == countAfterFirst)

        // A new text rebuilds.
        controller.updateJSON(result: JSONAnalyzer.analyze(#"{"a":2}"#), formatID: "json")
        #expect(controller.jsonRebuildCount == countAfterFirst + 1)
    }

    @Test func collapseAndSelectionSurviveRebuildsByPathID() {
        let controller = OutlineController()
        controller.updateJSON(result: JSONAnalyzer.analyze(#"{"a":{"b":1},"c":2}"#), formatID: "json")
        controller.jsonCollapsedItemIDs = ["$.a"]
        controller.jsonSelectedItemID = "$.c"

        // The same structure reformatted keeps identical path IDs.
        let formatted = JSONAnalyzer.analyze("{\n  \"a\": {\n    \"b\": 1\n  },\n  \"c\": 2\n}")
        controller.updateJSON(result: formatted, formatID: "json")

        #expect(controller.jsonCollapsedItemIDs == ["$.a"])
        #expect(controller.jsonSelectedItemID == "$.c")
    }

    @Test func currentItemFollowsReferenceOffset() {
        let controller = OutlineController()
        controller.updateJSON(result: JSONAnalyzer.analyze(#"{"a":{"b":1},"c":2}"#), formatID: "json")

        // Offset inside the root object.
        controller.jsonReferenceOffsetDidChange(0)
        #expect(controller.jsonCurrentItemID == "$")

        // Offset inside "b"'s value '1' (units 10..<11).
        controller.jsonReferenceOffsetDidChange(10)
        #expect(controller.jsonCurrentItemID == "$.a.b")

        // Offset inside "c"'s value '2' (unit 17).
        controller.jsonReferenceOffsetDidChange(17)
        #expect(controller.jsonCurrentItemID == "$.c")

        // Outside the document has no item.
        controller.jsonReferenceOffsetDidChange(200)
        #expect(controller.jsonCurrentItemID == nil)
    }

    @Test func activatePublishesSourceRangeForJump() {
        let controller = OutlineController()
        controller.updateJSON(result: JSONAnalyzer.analyze(#"{"a":{"b":1}}"#), formatID: "json")

        controller.activateJSON("$.a.b")
        #expect(controller.pendingJSONJumpSourceRange == 10 ..< 11)
        #expect(controller.jsonSelectedItemID == "$.a.b")

        // Unknown IDs are ignored.
        controller.pendingJSONJumpSourceRange = nil
        controller.activateJSON("$.nope")
        #expect(controller.pendingJSONJumpSourceRange == nil)
    }

    @Test func requestFocusSelectsCurrentOrFirstRow() {
        let controller = OutlineController()
        controller.updateJSON(result: JSONAnalyzer.analyze(#"{"a":1,"b":2}"#), formatID: "json")
        controller.jsonReferenceOffsetDidChange(11) // inside "b"'s value '2' (unit 11)

        controller.requestJSONFocus()
        #expect(controller.jsonSelectedItemID == "$.b")
        #expect(controller.jsonFocusRequestID == 1)

        // With no reference offset, the first visible row is selected.
        let empty = OutlineController()
        empty.updateJSON(result: JSONAnalyzer.analyze(#"{"a":1}"#), formatID: "json")
        empty.requestJSONFocus()
        #expect(empty.jsonSelectedItemID == "$")
    }

    @Test func markdownChannelIsUnaffectedByJSONChannel() {
        let controller = OutlineController()
        // JSON activity must not disturb Markdown state (and vice versa).
        controller.updateJSON(result: JSONAnalyzer.analyze(#"{"a":1}"#), formatID: "json")
        controller.update(document: nil, isMarkdown: true, formatName: "Markdown")
        #expect(controller.availability == .notParsed)
        #expect(controller.jsonAvailability == .ready)
        #expect(controller.items.isEmpty)
        #expect(controller.jsonItems.count == 1)
    }

    @Test func visibleRowsHonorJSONCollapseState() {
        let controller = OutlineController()
        controller.updateJSON(result: JSONAnalyzer.analyze(#"{"a":{"b":1},"c":2}"#), formatID: "json")
        controller.jsonCollapsedItemIDs = ["$.a"]
        let rows = JSONOutlineBuilder.visibleRows(controller.jsonItems, collapsed: controller.jsonCollapsedItemIDs)
        #expect(rows.map(\.item.id) == ["$", "$.a", "$.c"])
    }
}
