import AppKit
import Foundation
@testable import Highlighting
import Testing

/// DEP-TRIAL SCRATCH COPY of NeonReplacementEditTests: every `withKnownIssue`
/// is a plain `#expect`, and each comparison prints a divergence summary
/// (`H5-STRICT`) so a failure says where and how much the incremental
/// highlighting differs from a fresh highlighter. `RenderedRun` compares the
/// rendering attributes (foreground colour + font traits), so any mismatch is
/// a visible highlight difference.
@MainActor
@Suite(.serialized)
struct NeonReplacementEditStrictTests {
    private static let text = StallFixtures.markdown(utf8Bytes: 48 * 1024)

    private func runs(afterEditing editor: HighlightedEditor) async throws
        -> (edited: [RenderedRun], fresh: [RenderedRun]) {
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(3)))
        let fresh = HighlightedEditor(text: editor.textView.string)
        try #require(await fresh.waitUntilQuiet(quietPeriod: .seconds(2)))
        let edited = editor.renderedRuns(), freshRuns = fresh.renderedRuns()
        if edited != freshRuns {
            // Diagnostic only (no assertion): re-query every range from the edited editor's
            // existing parse state. Equal afterwards = the trees were right and only Neon's
            // invalidation was stale; still different = the parse state itself differs.
            editor.highlighter.invalidateAll()
            _ = await editor.waitUntilQuiet(quietPeriod: .seconds(3))
            print("H5-STRICT-DIAG afterInvalidateAll equalToFresh=\(editor.renderedRuns() == freshRuns)")
        }
        return (edited, freshRuns)
    }

    /// Per-UTF-16-unit comparison of the two run lists.
    private func report(_ name: String, _ edited: [RenderedRun], _ fresh: [RenderedRun], text: String) {
        let length = (text as NSString).length
        func map(_ runs: [RenderedRun]) -> [String] {
            var signatures = [String](repeating: "", count: length)
            for run in runs {
                let upper = min(NSMaxRange(run.range), length)
                guard run.range.location < upper else { continue }
                for index in run.range.location ..< upper { signatures[index] = run.signature }
            }
            return signatures
        }
        let a = map(edited), b = map(fresh)
        var differing = 0
        var first = -1, last = -1
        for index in 0 ..< length where a[index] != b[index] {
            differing += 1
            if first < 0 { first = index }
            last = index
        }
        var line = "H5-STRICT test=\(name) equal=\(edited == fresh) runs edited=\(edited.count) fresh=\(fresh.count)"
        line += " differingUnits=\(differing)"
        if first >= 0 {
            let string = text as NSString
            let lo = max(0, first - 20), hi = min(length, first + 40)
            let excerpt = string.substring(with: NSRange(location: lo, length: hi - lo))
                .replacingOccurrences(of: "\n", with: "\\n")
            line += " span=\(first)..<\(last + 1) firstDiff edited='\(a[first])' fresh='\(b[first])' near='\(excerpt)'"
        }
        print(line)
    }

    private func editor() async throws -> HighlightedEditor {
        let editor = HighlightedEditor(text: Self.text)
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(2)))
        return editor
    }

    private func typeRapidly(in editor: HighlightedEditor) {
        let middle = Self.text.utf16.count / 2
        for index in 0 ..< 11 {
            editor.typeOrDelete(at: middle, insert: index.isMultiple(of: 2))
        }
    }

    @Test func rapidTypingMatchesAFreshHighlighter() async throws {
        let editor = try await editor()
        typeRapidly(in: editor)
        let (edited, fresh) = try await runs(afterEditing: editor)
        report("rapidTyping", edited, fresh, text: editor.textView.string)
        #expect(!fresh.isEmpty)
        #expect(edited == fresh)
    }

    @Test func deletingABlockMatchesAFreshHighlighter() async throws {
        let editor = try await editor()
        editor.textView.insertText("", replacementRange: NSRange(location: 1000, length: 1500))
        let (edited, fresh) = try await runs(afterEditing: editor)
        report("deletingABlock", edited, fresh, text: editor.textView.string)
        #expect(!fresh.isEmpty)
        #expect(edited == fresh)
    }

    @Test func typingThenDeletingABlockInOneTurnMatchesAFreshHighlighter() async throws {
        let editor = try await editor()
        typeRapidly(in: editor)
        editor.textView.insertText("", replacementRange: NSRange(location: 1000, length: 1500))
        let (edited, fresh) = try await runs(afterEditing: editor)
        report("typingThenDeletingOneTurn", edited, fresh, text: editor.textView.string)
        #expect(edited == fresh)
    }

    @Test func replacingASelectionContainingInlineRangesMatchesAFreshHighlighter() async throws {
        let editor = try await editor()
        let range = NSRange(location: Self.text.utf16.count / 2, length: 600)
        let replacement = (Self.text as NSString).substring(with: range) + "y"
        editor.textView.insertText(replacement, replacementRange: range)
        let (edited, fresh) = try await runs(afterEditing: editor)
        report("replacingSelection", edited, fresh, text: editor.textView.string)
        #expect(edited == fresh)
    }

    /// B1's known limitation: a replacement that removes inline markup
    /// entirely (the injection vanishes), so its old included range is stale.
    @Test func replacingInlineMarkupWithPlainTextMatchesAFreshHighlighter() async throws {
        let editor = try await editor()
        let range = NSRange(location: Self.text.utf16.count / 2, length: 600)
        let old = (Self.text as NSString).substring(with: range)
        let plain = String(old.map { "*_`[]()".contains($0) ? " " : $0 })
        editor.textView.insertText(plain, replacementRange: range)
        let (edited, fresh) = try await runs(afterEditing: editor)
        report("replacingWithPlainText", edited, fresh, text: editor.textView.string)
        #expect(edited == fresh)
    }

    /// Debug aborts the host on stock (see NeonReplacementEditTests); opt in with MACDOWN_STRICT_WIDENED_DEBUG=1.
    @Test(.enabled(if: !isStrictDebugBuild || ProcessInfo.processInfo.environment["MACDOWN_STRICT_WIDENED_DEBUG"] == "1"))
    func widenedBackgroundTypingMatchesAFreshHighlighter() async throws {
        let editor = HighlightedEditor(text: Self.text, widensEdits: true)
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(2)))
        typeRapidly(in: editor)
        let (edited, fresh) = try await runs(afterEditing: editor)
        report("widenedBackgroundTyping", edited, fresh, text: editor.textView.string)
        #expect(edited == fresh)
    }
}

private let isStrictDebugBuild: Bool = {
    #if DEBUG
        true
    #else
        false
    #endif
}()
