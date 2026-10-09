import Foundation
@testable import JSONSupport
import Testing

/// #183 F04 — a superseded or cancelled analysis must never publish, even when
/// its caller's own task was not the one cancelled.
@MainActor
@Suite("JSONAnalysisSession supersession (#183 F04)")
struct JSONAnalysisSessionSupersessionTests {
    /// Holds the analyzer for one specific text until released.
    private final class Gate: @unchecked Sendable {
        private let held: String
        private let entered = DispatchSemaphore(value: 0)
        private let release = DispatchSemaphore(value: 0)

        init(holding text: String) {
            held = text
        }

        func analyze(_ text: String) -> JSONAnalysisResult {
            if text == held {
                entered.signal()
                release.wait()
            }
            return JSONAnalyzer.analyze(text)
        }

        func waitUntilEntered() async {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    self.entered.wait()
                    continuation.resume()
                }
            }
        }

        func open() {
            release.signal()
        }
    }

    private func session(_ gate: Gate) -> JSONAnalysisSession {
        JSONAnalysisSession(debounce: .milliseconds(1)) { gate.analyze($0) }
    }

    @Test func aCancelledImmediateAnalysisDoesNotPublishWhenItFinishesLater() async {
        let gate = Gate(holding: #"{"old":1}"#)
        let session = session(gate)
        let running = Task { await session.analyzeNow(#"{"old":1}"#) }
        await gate.waitUntilEntered()

        session.cancelPending()
        gate.open()
        _ = await running.value

        #expect(session.result == nil)
        #expect(session.completedAnalysisCount == 0)
    }

    @Test func anOlderImmediateAnalysisNeverOverwritesANewerPublishedResult() async {
        let gate = Gate(holding: #"{"old":1}"#)
        let session = session(gate)
        let older = Task { await session.analyzeNow(#"{"old":1}"#) }
        await gate.waitUntilEntered()

        _ = await session.analyzeNow(#"{"new":2}"#)
        gate.open()
        let returned = await older.value

        #expect(returned.text == #"{"old":1}"#)
        #expect(session.result?.text == #"{"new":2}"#)
    }

    @Test func anAlreadyCancelledCallerStillReturnsAResultWithoutPublishing() async {
        let session = JSONAnalysisSession(debounce: .milliseconds(1))
        let task = Task { () -> JSONAnalysisResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return await session.analyzeNow(#"{"a":1}"#)
        }

        let result = await task.value

        #expect(result.isValid)
        #expect(session.result == nil)
    }
}
