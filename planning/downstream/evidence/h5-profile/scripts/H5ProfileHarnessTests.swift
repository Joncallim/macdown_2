import Foundation
@testable import Highlighting
import Testing

/// SCRATCH-ONLY profiling harness (H5 profile, dep-trial). Not for commit to
/// any shipping branch. Opens a document with Neon unbounded (fallback
/// disabled, sizePolicy nil), waits until quiet, writes `<H5PROF_DIR>/ready`
/// with the pid, waits `H5PROF_LEAD_MS` for an external `sample` to attach,
/// then runs the workload and writes `<H5PROF_DIR>/done`.
///
///   H5PROF=1 H5PROF_MODE=edit|paste H5PROF_KB=256 H5PROF_FIXTURE=inlineDense
///   H5PROF_EDITS=20 H5PROF_GAP_MS=400 H5PROF_DIR=...
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["H5PROF"] == "1"))
struct H5ProfileHarnessTests {
    static let env = ProcessInfo.processInfo.environment
    static func int(_ key: String, _ fallback: Int) -> Int { env[key].flatMap(Int.init) ?? fallback }

    @Test func profileWorkload() async throws {
        let dir = URL(fileURLWithPath: Self.env["H5PROF_DIR"] ?? NSTemporaryDirectory())
        let mode = Self.env["H5PROF_MODE"] ?? "edit"
        let kb = Self.int("H5PROF_KB", 256)
        let fixture = HighlightBudgetFixture(rawValue: Self.env["H5PROF_FIXTURE"] ?? "inlineDense") ?? .inlineDense
        let edits = Self.int("H5PROF_EDITS", 20)
        let gap = Self.int("H5PROF_GAP_MS", 400)
        let lead = Self.int("H5PROF_LEAD_MS", 3000)
        let clock = ContinuousClock()

        let editor: HighlightedEditor
        var pasteText = ""
        if mode == "paste" {
            let cutoff = HighlightingSizePolicy.markdown.reduceAboveUTF16Units
            let full = fixture.markdown(utf8Bytes: cutoff * 3)
            let end = (full as NSString).rangeOfComposedCharacterSequence(at: cutoff - 200).location
            editor = HighlightedEditor(text: (full as NSString).substring(to: end), sizePolicy: { _ in nil })
            pasteText = fixture.markdown(utf8Bytes: kb * 1024)
        } else {
            editor = HighlightedEditor(text: fixture.markdown(utf8Bytes: kb * 1024), sizePolicy: { _ in nil })
        }
        let quiet = Duration.milliseconds(max(1500, (editor.textView.string as NSString).length / 1024 * 10))
        let openStart = clock.now
        let ok = await editor.waitUntilQuiet(quietPeriod: quiet, timeout: .seconds(600))
        print("H5PROF open quiet=\(ok) took=\(clock.now - openStart) units=\((editor.textView.string as NSString).length) mode=\(editor.highlighter.state.mode) inlineNearEnd=\(editor.hasInlineStylingNearEnd())")

        try "\(getpid())\n".write(to: dir.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .milliseconds(lead))
        let t0 = clock.now
        if mode == "paste" {
            let s = clock.now
            editor.textView.insertText(pasteText, replacementRange: NSRange(location: 100, length: 0))
            print("H5PROF paste call=\(clock.now - s)")
            // let the deferred main-actor work run; poll the run loop
            let baseline = editor.highlighter.styledTokenCount
            _ = await editor.waitUntilQuiet(quietPeriod: .seconds(3), timeout: .seconds(600), requireActivityAfter: baseline)
            print("H5PROF paste settled after=\(clock.now - s)")
        } else {
            let location = HighlightBudgetFixture.editLocations(in: editor.textView.string)[1].location
            var calls: [Double] = []
            var turns: [Double] = []
            for index in 0 ..< edits {
                let s = clock.now
                editor.typeOrDelete(at: location, insert: index.isMultiple(of: 2))
                let c = clock.now - s
                // time until the main actor is next free (includes deferred work queued by the edit)
                await Task.yield()
                let t = clock.now - s
                calls.append(Double(c.components.attoseconds) / 1e15 + Double(c.components.seconds) * 1e3)
                turns.append(Double(t.components.attoseconds) / 1e15 + Double(t.components.seconds) * 1e3)
                try? await Task.sleep(for: .milliseconds(gap))
            }
            print("H5PROF edit call ms: \(calls.map { Int($0) })")
            print("H5PROF edit call+yield ms: \(turns.map { Int($0) })")
        }
        print("H5PROF workload took=\(clock.now - t0)")
        if Self.env["H5PROF_DUMP"] != nil {
            _ = await editor.waitUntilQuiet(quietPeriod: .seconds(2), timeout: .seconds(600))
            let runs = editor.renderedRuns()
            var h: UInt64 = 1469598103934665603
            for b in runs.map(\.description).joined(separator: "|").utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
            print("H5PROF rendered runs=\(runs.count) hash=\(String(h, radix: 16))")
        }
        try "done\n".write(to: dir.appendingPathComponent("done"), atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .milliseconds(500))
    }
}
