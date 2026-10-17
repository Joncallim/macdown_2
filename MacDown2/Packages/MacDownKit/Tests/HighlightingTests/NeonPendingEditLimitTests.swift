import AppKit
import Foundation
@testable import Highlighting
import Testing

/// DEP-TRIAL ONLY (stage C1 task 2, `planning/downstream/evidence/h5-neon-invalidation/`).
///
/// A change of 2,048 units or more makes Neon parse in the background. A second
/// change made before that parse completes is clamped against, and given a
/// content snapshot limited by, `RangeProcessor.processedUpperBound`, which
/// does not yet include the pending change's delta. The parse then reads past
/// the snapshot limit (Debug: `assertionFailure("location is greater than end")`
/// in SwiftTreeSitter `String+Data.swift`; Release: the read returns nil and the
/// parser treats it as the end of the document), or the second change is
/// dropped when it lies beyond the stale bound. ``EditWideningStorageDelegate``
/// makes every keystroke such a change, so two keystrokes in one turn are enough.
///
/// The tests assert on the document tail only: widened edits also hit the
/// separate missing-sublayer-resolution divergence in the middle of the
/// document (`h5-neon-divergence`), which is reported as `units` but not asserted.
///
/// Opt-in: `MACDOWN_NEON_PENDING_TRIAL=1`. Each test aborts the Debug test
/// process on stock Neon, so run them one at a time there.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_NEON_PENDING_TRIAL"] == "1"))
struct NeonPendingEditLimitTests {
    /// The 48 KB fixture with a tail whose highlighting depends on its last characters.
    static let text = StallFixtures.markdown(utf8Bytes: 48 * 1024) + "end **bold**"
    static var middle: Int { text.utf16.count / 2 }

    private func divergence(after edits: (NSTextView) -> Void) async throws -> (units: Int, tailUnits: Int, detail: String) {
        let editor = HighlightedEditor(text: Self.text, widensEdits: true)
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(1)))
        edits(editor.textView)
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(2)))
        let fresh = HighlightedEditor(text: editor.textView.string)
        try #require(await fresh.waitUntilQuiet(quietPeriod: .seconds(1)))
        let length = (editor.textView.string as NSString).length
        func map(_ e: HighlightedEditor) -> [String] {
            var s = [String](repeating: "", count: length)
            for run in e.renderedRuns() where run.range.location < length {
                for i in run.range.location ..< min(NSMaxRange(run.range), length) { s[i] = run.signature }
            }
            return s
        }
        let a = map(editor), b = map(fresh)
        let differing = a.indices.filter { a[$0] != b[$0] }
        var detail = differing.first.map { "first=\($0) edited='\(a[$0])' fresh='\(b[$0])'" } ?? ""
        if let last = differing.last, last >= length - 12 {
            detail += " lastDiff=\(last) edited='\(a[last])' fresh='\(b[last])'"
        }
        // The tail ("end **bold**", the last 12 units) is far from every edit, so
        // only a parse that stopped short of the document end can change it.
        let tail = differing.filter { $0 >= length - 12 }.count
        print("H5-PENDING units=\(differing.count) tailUnits=\(tail) \(detail) length=\(length)")
        return (differing.count, tail, detail)
    }

    /// The minimal Debug abort: one background keystroke, then a second before its parse completes.
    @Test func insertThenDeleteInOneTurn() async throws {
        let result = try await divergence { view in
            view.insertText("x", replacementRange: NSRange(location: Self.middle, length: 0))
            view.insertText("", replacementRange: NSRange(location: Self.middle, length: 1))
        }
        #expect(result.tailUnits == 0)
    }

    /// Two background inserts: the second snapshot stops one unit short, so the
    /// parse drops the document's last character ("**bold*").
    @Test func twoInsertsInOneTurnKeepTheDocumentTail() async throws {
        let result = try await divergence { view in
            view.insertText("x", replacementRange: NSRange(location: Self.middle, length: 0))
            view.insertText("y", replacementRange: NSRange(location: Self.middle + 1, length: 0))
        }
        #expect(result.tailUnits == 0)
    }

    /// A background insert, then deleting the last character: the deletion lies
    /// beyond the stale processed bound, so Neon drops it and the tree keeps it.
    @Test func deletingTheLastCharacterAfterABackgroundEdit() async throws {
        let result = try await divergence { view in
            view.insertText("x", replacementRange: NSRange(location: Self.middle, length: 0))
            let length = (view.string as NSString).length
            view.insertText("", replacementRange: NSRange(location: length - 1, length: 1))
        }
        #expect(result.tailUnits == 0)
    }

    /// Control for the previous test: the same deletion with no pending change. Not asserted,
    /// because it shows a separate single-edit residual at the tail (see the evidence README).
    @Test func controlDeletingTheLastCharacterAlone() async throws {
        let result = try await divergence { view in
            let length = (view.string as NSString).length
            view.insertText("", replacementRange: NSRange(location: length - 1, length: 1))
        }
        print("H5-PENDING-CONTROL tailUnits=\(result.tailUnits)")
    }
}
