import Foundation
@testable import Highlighting
import Testing

/// Opt-in Release benchmark of the shipped size fallback (register row H5),
/// with the shipped Markdown policy: opening and editing documents above the
/// cut-off (reduced mode), typing across the cut-off, and pasting a large
/// document into a highlighted one. Stall (p50/p95/max) and settle time are
/// reported separately; "settle" in reduced mode is the time until the
/// highlighter-owned presentation was cleared. Run on an idle Mac:
///
///     MACDOWN_HIGHLIGHT_FALLBACK_BENCH=1 swift test -c release -Xswiftc -enable-testing \
///         --no-parallel --filter HighlightFallbackBenchmarkTests
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_HIGHLIGHT_FALLBACK_BENCH"] == "1"))
struct HighlightFallbackBenchmarkTests {
    private static let shipped: (String?) -> HighlightingSizePolicy? = HighlightingSizePolicy.default(for:)
    private static let cutoff = HighlightingSizePolicy.markdown.reduceAboveUTF16Units

    @Test(arguments: [HighlightBudgetFixture.ordinary, .inlineDense, .longLines, .unicode, .fences])
    func reducedModeOpenAndEdit(fixture: HighlightBudgetFixture) async {
        for kilobytes in [12, 32, 64, 128, 256, 1024, 4096] {
            let text = fixture.markdown(utf8Bytes: kilobytes * 1024)
            let units = (text as NSString).length
            let label = "fixture=\(fixture) KB=\(kilobytes) utf8=\(text.utf8.count) utf16=\(units) mode=shipped"
            let (editor, open) = await HighlightedEditor.measureOpen(
                { HighlightedEditor(text: text, sizePolicy: Self.shipped) },
                quiet: .milliseconds(500),
                expectsHighlighting: false
            )
            #expect(editor.highlighter.state.isReduced == (units > Self.cutoff), "\(label)")
            print("H5-FALLBACK \(label) state=\(editor.highlighter.state.mode) phase=open \(open)")
            for (name, location) in HighlightBudgetFixture.editLocations(in: text) {
                let result = await editor.measureEdits(16, at: location, quiet: .milliseconds(500))
                print("H5-FALLBACK \(label) phase=edit pos=\(name) \(result)")
            }
            #expect(editor.textView.string == text)
            #expect(editor.highlighter.styledTokenCount == 0 || units <= Self.cutoff)
        }
    }

    /// Typing across the cut-off one character at a time, in the middle.
    @Test(arguments: [HighlightBudgetFixture.ordinary, .inlineDense, .unicode])
    func typingAcrossTheCutoff(fixture: HighlightBudgetFixture) async throws {
        let editor = try await highlightedJustBelowCutoff(fixture, margin: 5)
        let location = HighlightBudgetFixture.editLocations(in: editor.textView.string)[1].location
        let clears = editor.highlighter.presentationClearCount
        let result = await editor.measureCalls(12, quiet: .milliseconds(800)) { _ in
            editor.textView.insertText("x", replacementRange: NSRange(location: location, length: 0))
        }
        #expect(editor.highlighter.state.isReduced)
        #expect(editor.highlighter.presentationClearCount == clears + 1)
        print("H5-FALLBACK fixture=\(fixture) phase=type-across-cutoff \(result)")
        print("H5-FALLBACK-RAW fixture=\(fixture) type-across stall=\(result.stall.values.map { Int($0) })")
    }

    /// Pasting a large document into a highlighted one just below the cut-off:
    /// the paste call, its stall, the time until reduced mode settled, and
    /// typing straight afterwards.
    @Test(arguments: [256, 1024, 4096])
    func pasteAcrossTheCutoff(kilobytes: Int) async throws {
        let editor = try await highlightedJustBelowCutoff(.inlineDense, margin: 200)
        let paste = HighlightBudgetFixture.inlineDense.markdown(utf8Bytes: kilobytes * 1024)
        let expected = (editor.textView.string as NSString).replacingCharacters(
            in: NSRange(location: 100, length: 0), with: paste
        )
        let clears = editor.highlighter.presentationClearCount
        let styled = editor.highlighter.styledTokenCount
        let start = DispatchTime.now().uptimeNanoseconds
        let pasteResult = await editor.measureCalls(1, quiet: .milliseconds(800)) { _ in
            editor.textView.insertText(paste, replacementRange: NSRange(location: 100, length: 0))
        }
        let clearedAfter = Double(editor.highlighter.lastPresentationClearUptime - start) / 1e6
        #expect(editor.highlighter.state.isReduced)
        #expect(editor.highlighter.presentationClearCount == clears + 1)
        #expect(editor.highlighter.styledTokenCount == styled, "no late styling after the paste")
        #expect(editor.textView.string == expected)
        print(String(
            format: "H5-FALLBACK paste=%dKB phase=paste %@ | reduced settled (presentation cleared) %.1f ms",
            kilobytes, pasteResult.description, clearedAfter
        ))
        let location = HighlightBudgetFixture.editLocations(in: expected)[1].location
        let typing = await editor.measureEdits(16, at: location, quiet: .milliseconds(500))
        print("H5-FALLBACK paste=\(kilobytes)KB phase=type-after-paste \(typing)")
        #expect(editor.highlighter.styledTokenCount == styled)
    }

    /// Full-mode comparison: the same paste with the fallback disabled
    /// (Neon unbounded, as before H5). Settle = until Neon goes quiet.
    @Test(arguments: [256, 1024])
    func pasteWithoutTheFallback(kilobytes: Int) async throws {
        let editor = try await highlightedJustBelowCutoff(.inlineDense, margin: 200, policy: { _ in nil })
        let paste = HighlightBudgetFixture.inlineDense.markdown(utf8Bytes: kilobytes * 1024)
        let pasteResult = await editor.measureCalls(1, quiet: .seconds(3)) { _ in
            editor.textView.insertText(paste, replacementRange: NSRange(location: 100, length: 0))
        }
        #expect(editor.highlighter.state.mode == .full)
        print("H5-FALLBACK paste=\(kilobytes)KB mode=full phase=paste \(pasteResult)")
        let location = HighlightBudgetFixture.editLocations(in: editor.textView.string)[1].location
        let typing = await editor.measureEdits(4, at: location, quiet: .seconds(3))
        print("H5-FALLBACK paste=\(kilobytes)KB mode=full phase=type-after-paste \(typing)")
    }

    private func highlightedJustBelowCutoff(
        _ fixture: HighlightBudgetFixture,
        margin: Int,
        policy: @escaping (String?) -> HighlightingSizePolicy? = shipped
    ) async throws -> HighlightedEditor {
        let full = fixture.markdown(utf8Bytes: Self.cutoff * 3)
        let end = (full as NSString).rangeOfComposedCharacterSequence(at: Self.cutoff - margin).location
        let text = (full as NSString).substring(to: end)
        let editor = HighlightedEditor(text: text, sizePolicy: policy)
        try #require(editor.highlighter.state.mode == .full)
        try #require(await editor.waitUntilQuiet(quietPeriod: .seconds(1)))
        return editor
    }
}
