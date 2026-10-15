import Foundation
@testable import Highlighting
import Testing

/// Opt-in Release benchmark for register row H5's size-based fallback: the
/// actual editor path (EditorTextSystem + NeonSyntaxHighlighter, inline
/// injections resolved) per workload, size and edit location. Reports the
/// main-thread stall per edit (p50/p95/max) and the time until highlights
/// settle separately, for opening a document and for edits at the start,
/// middle and end. Run serially, on an otherwise idle Mac:
///
///     MACDOWN_HIGHLIGHT_BUDGET_BENCH=1 MACDOWN_HIGHLIGHT_BUDGET_KB=32,64,96,128,256 \
///         swift test -c release -Xswiftc -enable-testing --no-parallel \
///         --filter HighlightBudgetBenchmarkTests
///
/// `MACDOWN_HIGHLIGHT_BUDGET_FIXTURES` narrows the workloads (comma list of
/// `HighlightBudgetFixture` raw values).
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_HIGHLIGHT_BUDGET_BENCH"] == "1"))
struct HighlightBudgetBenchmarkTests {
    nonisolated static let sizes: [Int] = (ProcessInfo.processInfo
        .environment["MACDOWN_HIGHLIGHT_BUDGET_KB"] ?? "32,64,96,128,256")
        .split(separator: ",")
        .compactMap { Int($0).map { $0 * 1024 } }

    nonisolated static let fixtures: [HighlightBudgetFixture] = {
        guard let names = ProcessInfo.processInfo.environment["MACDOWN_HIGHLIGHT_BUDGET_FIXTURES"] else {
            return HighlightBudgetFixture.allCases
        }
        return names.split(separator: ",").compactMap { HighlightBudgetFixture(rawValue: String($0)) }
    }()

    /// Fewer edits where each one is known to take seconds (keeps a run
    /// bounded). Always even: inserts and deletes alternate, so the document
    /// ends where it started.
    private static func editCount(utf8Bytes: Int) -> Int {
        switch utf8Bytes {
        case ...(128 * 1024): 16
        case ...(256 * 1024): 8
        default: 4
        }
    }

    @Test(arguments: fixtures)
    func editorPath(fixture: HighlightBudgetFixture) async {
        for size in Self.sizes {
            let text = fixture.markdown(utf8Bytes: size)
            let units = (text as NSString).length
            let label = "fixture=\(fixture) KB=\(size / 1024) utf8=\(text.utf8.count) utf16=\(units) mode=full"
            let quiet = Duration.milliseconds(max(1500, units / 1024 * 10))
            let (editor, open) = await HighlightedEditor.measureOpen(
                { HighlightedEditor(text: text) },
                quiet: quiet,
                expectsHighlighting: true
            )
            print("H5-BUDGET \(label) phase=open \(open)")
            #expect(editor.hasInlineStylingNearEnd(), "inline injection must be resolved: \(label)")
            for (name, location) in HighlightBudgetFixture.editLocations(in: text) {
                let result = await editor.measureEdits(Self.editCount(utf8Bytes: size), at: location, quiet: quiet)
                print("H5-BUDGET \(label) phase=edit pos=\(name) \(result)")
                print("H5-BUDGET-RAW \(label) pos=\(name) stall=\(result.stall.values.map { Int($0) })")
            }
            #expect(editor.textView.string == text)
        }
    }
}

extension HighlightedEditor {
    /// True if Neon has applied an inline (emphasis / strong / code) style in
    /// the last tenth of the document, i.e. the inline injection was resolved
    /// for the whole document, not only near the start.
    func hasInlineStylingNearEnd() -> Bool {
        let threshold = (textView.string as NSString).length * 9 / 10
        return renderedRuns().contains { run in
            run.range.location >= threshold && (run.signature.contains(",fi") || run.signature.contains(",fb"))
        }
    }
}
