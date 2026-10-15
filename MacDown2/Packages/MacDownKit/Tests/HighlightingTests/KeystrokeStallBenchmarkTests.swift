import Foundation
@testable import Highlighting
import Testing

/// Opt-in benchmark for register row H5: the main-thread stall of a keystroke
/// in large Markdown documents with Neon as shipped, and with the
/// ``EditWideningStorageDelegate`` experiment (background reparse; not shipped).
/// Run in Release, serially; pick sizes with `MACDOWN_KEYSTROKE_BENCH_KB`
/// (a 1 MB run takes ~1 h, mostly the shipped path's ~6 s keystrokes):
///
///     MACDOWN_KEYSTROKE_BENCH=1 MACDOWN_KEYSTROKE_BENCH_KB=64,256 \
///         swift test -c release -Xswiftc -enable-testing --no-parallel \
///         --filter KeystrokeStallBenchmarkTests
///
/// Each run: open, wait until Neon has gone quiet (the inline sublayer of a
/// 1 MB document takes ~10 s to resolve), then 50 keystrokes 50 ms apart
/// (alternating insert/delete in the middle, below Neon's 1,048,576-unit
/// synchronous cut-off) under a ``MainThreadStallMonitor``.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MACDOWN_KEYSTROKE_BENCH"] == "1"))
struct KeystrokeStallBenchmarkTests {
    nonisolated static let sizes: [Int] = (ProcessInfo.processInfo
        .environment["MACDOWN_KEYSTROKE_BENCH_KB"] ?? "64,256")
        .split(separator: ",")
        .compactMap { Int($0).map { $0 * 1024 } }

    @Test(arguments: sizes)
    func keystrokeStall(utf8Bytes: Int) async {
        let text = StallFixtures.markdown(utf8Bytes: utf8Bytes)
        let location = min((text as NSString).length / 2, 512 * 1024)
        let quiet = Duration.seconds(max(3, 15 * utf8Bytes / (1024 * 1024)))
        for (name, widens) in [("neon", false), ("widened-experiment", true)] {
            let editor = HighlightedEditor(text: text, widensEdits: widens)
            #expect(await editor.waitUntilQuiet(quietPeriod: quiet, timeout: .seconds(900)))
            let result = await editor.measureTyping(edits: 50, at: location, settle: quiet)
            print("H5-BENCH size=\(utf8Bytes / 1024)KB mode=\(name) \(result)")
            print("H5-BENCH per-edit stall ms: \(result.stall.values.map { Int($0) })")
        }
    }
}
