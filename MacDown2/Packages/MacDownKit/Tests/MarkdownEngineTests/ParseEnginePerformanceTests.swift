import Foundation
@testable import MarkdownEngine
import Testing

/// Ceilings are debug-build DOCUMENTATION ceilings (E05 convention), calibrated
/// on the GitHub `macos-26` runner where the parallel test run saturates the
/// cooperative pool (measured 2026-07-23: 1 MB → 2.34 s, 10 MB → 21.0 s under
/// full contention). Release-build budgets are measured locally and recorded on
/// the epic PR. Raise with headroom only if CI hardware changes; a genuine
/// regression should still trip these.
struct ParseEnginePerformanceTests {
    private let engine = ParseEngine()

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000.0 + Double(components.attoseconds) / 1e15
    }

    @Test("1 MB re-parse within debug documentation ceiling")
    func parse1MB() async {
        let text = Fixtures.markdown(targetByteCount: 1_000_000)

        let duration = await ContinuousClock().measure {
            _ = try? await engine.parse(text, revision: 1)
        }

        let elapsed = milliseconds(duration)
        #expect(duration < .seconds(8), "1 MB parse took \(elapsed) ms")
    }

    @Test("10 MB re-parse establishes baseline")
    func parse10MB() async {
        let text = Fixtures.markdown(targetByteCount: 10_000_000)

        let duration = await ContinuousClock().measure {
            _ = try? await engine.parse(text, revision: 1)
        }

        let elapsed = milliseconds(duration)
        #expect(duration < .seconds(60), "10 MB parse took \(elapsed) ms")
    }

    @Test("Pathological blockquote nesting parses without regression")
    func parsePathological() async {
        let text = Fixtures.nestedBlockquotes(depth: 250) + "\n" + Fixtures.emphasisBomb(length: 2500)

        let duration = await ContinuousClock().measure {
            _ = try? await engine.parse(text, revision: 1)
        }

        let elapsed = milliseconds(duration)
        #expect(duration < .seconds(5), "Pathological parse took \(elapsed) ms")
    }
}
