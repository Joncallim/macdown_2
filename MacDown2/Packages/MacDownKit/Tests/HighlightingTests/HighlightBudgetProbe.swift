import AppKit
import Foundation
@testable import Highlighting

/// Results of one measured phase (opening a document, or a burst of edits).
struct BudgetPhaseResult: CustomStringConvertible {
    /// Longest main-thread stall attributed to each edit (one value for open).
    let stall: StallStats
    /// Wall-clock duration of each synchronous call (construction or edit).
    let call: StallStats
    /// From the last call until highlighting last changed (0 if it never did).
    let settleMilliseconds: Double

    var description: String {
        String(
            format: "stall p50 %.1f p95 %.1f max %.1f | call p50 %.1f max %.1f | settle %.0f ms (n=%d)",
            stall.median, stall.p95, stall.max, call.median, call.max, settleMilliseconds, stall.values.count
        )
    }
}

/// Watches `styledTokenCount` so the time highlighting settles can be reported
/// separately from the input stall. Polls on the main actor, so a reading can
/// lag by one main-thread stall; that only ever lengthens the settle time.
@MainActor
enum HighlightActivity {
    /// Waits until `count()` has not changed for `quiet` (or `timeout` passes)
    /// and returns the uptime (ns) of the last change, or `since` if none.
    static func lastChange(
        of count: () -> Int,
        since start: UInt64,
        quiet: Duration,
        timeout: Duration,
        requireActivity: Bool
    ) async -> UInt64 {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var last = count()
        var lastChange = start
        var changedAt = clock.now
        var sawActivity = false
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            let current = count()
            if current != last {
                last = current
                lastChange = DispatchTime.now().uptimeNanoseconds
                changedAt = clock.now
                sawActivity = true
                continue
            }
            if clock.now - changedAt >= quiet, sawActivity || !requireActivity {
                break
            }
        }
        return lastChange
    }
}

extension HighlightedEditor {
    /// Opens `text` under a stall monitor and reports the construction call,
    /// the longest main-thread stall until highlighting settled, and the
    /// settle time.
    static func measureOpen(
        _ make: () -> HighlightedEditor,
        quiet: Duration,
        expectsHighlighting: Bool
    ) async -> (HighlightedEditor, BudgetPhaseResult) {
        let monitor = MainThreadStallMonitor()
        monitor.start()
        try? await Task.sleep(for: .milliseconds(100))
        let start = DispatchTime.now().uptimeNanoseconds
        let editor = make()
        let call = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        let last = await HighlightActivity.lastChange(
            of: { editor.highlighter.styledTokenCount },
            since: start,
            quiet: quiet,
            timeout: .seconds(900),
            requireActivity: expectsHighlighting
        )
        // Let the monitor observe the stall that ended with the last change.
        try? await Task.sleep(for: .milliseconds(50))
        let end = DispatchTime.now().uptimeNanoseconds
        monitor.stop()
        let stall = monitor.maxStall(endingIn: start, end)
        return (editor, BudgetPhaseResult(
            stall: StallStats(values: [max(stall, call)]),
            call: StallStats(values: [call]),
            settleMilliseconds: Double(last - start) / 1e6
        ))
    }

    /// `edits` alternating one-character inserts/deletes at `location`,
    /// `cadence` apart, under a stall monitor; then waits for highlighting to
    /// settle and reports it separately.
    func measureEdits(
        _ edits: Int,
        at location: Int,
        cadence: Duration = .milliseconds(50),
        quiet: Duration
    ) async -> BudgetPhaseResult {
        await measureCalls(edits, cadence: cadence, quiet: quiet) { index in
            typeOrDelete(at: location, insert: index.isMultiple(of: 2))
        }
    }

    /// Runs `perform(index)` `count` times under a stall monitor.
    func measureCalls(
        _ count: Int,
        cadence: Duration = .milliseconds(50),
        quiet: Duration,
        perform: (Int) -> Void
    ) async -> BudgetPhaseResult {
        let monitor = MainThreadStallMonitor()
        monitor.start()
        try? await Task.sleep(for: .milliseconds(100))
        var starts: [UInt64] = []
        var calls: [Double] = []
        for index in 0 ..< count {
            let start = DispatchTime.now().uptimeNanoseconds
            starts.append(start)
            perform(index)
            calls.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            // After the last call, go straight to watching for highlighting
            // activity so its settle time is not hidden by the cadence wait.
            if index + 1 < count {
                try? await Task.sleep(for: cadence)
            }
        }
        let lastCall = starts.last ?? DispatchTime.now().uptimeNanoseconds
        let last = await HighlightActivity.lastChange(
            of: { highlighter.styledTokenCount },
            since: lastCall,
            quiet: quiet,
            timeout: .seconds(900),
            requireActivity: false
        )
        try? await Task.sleep(for: .milliseconds(50))
        let end = DispatchTime.now().uptimeNanoseconds
        monitor.stop()
        var stalls: [Double] = []
        for (index, start) in starts.enumerated() {
            let windowEnd = index + 1 < starts.count ? starts[index + 1] : end
            stalls.append(max(monitor.maxStall(endingIn: start, windowEnd), calls[index]))
        }
        return BudgetPhaseResult(
            stall: StallStats(values: stalls),
            call: StallStats(values: calls),
            settleMilliseconds: last > lastCall ? Double(last - lastCall) / 1e6 : 0
        )
    }
}
