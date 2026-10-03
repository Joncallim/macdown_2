import DiagramWebKitPool
import Foundation
import Testing

/// `WKWebView.callAsyncJavaScript` ignores cancellation, so the old task-group timeout kept the
/// caller (and its pool slot) waiting for as long as a stuck script ran — 37 s for a 1 s timeout.
struct DiagramTimeoutRaceTests {
    private struct Timeout: Error, Equatable {}
    private struct Boom: Error, Equatable {}

    /// Finishes after `seconds` no matter what: cancellation does not wake it.
    private static func uncancellableWait(seconds: Double) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
    }

    @Test func aHungOperationDoesNotHoldTheCallerPastTheTimeout() async {
        let start = ContinuousClock.now

        await #expect(throws: Timeout.self) {
            try await DiagramTimeoutRace.run(timeout: .milliseconds(100), timeoutError: Timeout()) {
                await Self.uncancellableWait(seconds: 5)
            }
        }

        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func aFastOperationReturnsItsValue() async throws {
        let value = try await DiagramTimeoutRace.run(timeout: .seconds(5), timeoutError: Timeout()) { 42 }

        #expect(value == 42)
    }

    @Test func anOperationErrorPropagatesUnchanged() async {
        await #expect(throws: Boom.self) {
            try await DiagramTimeoutRace.run(timeout: .seconds(5), timeoutError: Timeout()) {
                throw Boom()
            }
        }
    }

    @Test func cancellingTheCallerReturnsPromptlyEvenIfTheOperationIgnoresCancellation() async {
        let start = ContinuousClock.now
        let task = Task {
            try await DiagramTimeoutRace.run(timeout: .seconds(30), timeoutError: Timeout()) {
                await Self.uncancellableWait(seconds: 5)
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let result = await task.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(ContinuousClock.now - start < .seconds(2))
    }
}
