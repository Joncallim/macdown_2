import Foundation

/// Races an operation against a timer and returns as soon as either finishes.
///
/// A structured task group cannot do this: it always awaits every child before returning,
/// and `WKWebView.callAsyncJavaScript` ignores cancellation, so a render stuck in script kept
/// the caller (and its pool slot) waiting for as long as the script ran. Here the losing
/// operation is left running unobserved and the caller gets its answer immediately.
public enum DiagramTimeoutRace {
    public static func run<T: Sendable>(
        timeout: Duration,
        timeoutError: any Error,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = Gate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                let work = Task {
                    do {
                        try await gate.resolve(.success(operation()))
                    } catch {
                        gate.resolve(.failure(error))
                    }
                }
                let timer = Task {
                    try? await Task.sleep(for: timeout)
                    gate.resolve(.failure(timeoutError))
                }
                gate.onResolved {
                    timer.cancel()
                    work.cancel()
                }
            }
        } onCancel: {
            gate.resolve(.failure(CancellationError()))
        }
    }

    /// Resolves exactly once, whichever of the result, the timer or cancellation comes first —
    /// including cancellation arriving before the continuation is installed.
    private final class Gate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, any Error>?
        private var outcome: Result<T, any Error>?
        private var finished = false
        private var cleanup: (@Sendable () -> Void)?

        func install(_ continuation: CheckedContinuation<T, any Error>) {
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(with: outcome)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func onResolved(_ cleanup: @escaping @Sendable () -> Void) {
            lock.lock()
            if finished {
                lock.unlock()
                cleanup()
                return
            }
            self.cleanup = cleanup
            lock.unlock()
        }

        func resolve(_ result: Result<T, any Error>) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            outcome = result
            let continuation = continuation
            self.continuation = nil
            let cleanup = cleanup
            lock.unlock()
            continuation?.resume(with: result)
            cleanup?()
        }
    }
}
