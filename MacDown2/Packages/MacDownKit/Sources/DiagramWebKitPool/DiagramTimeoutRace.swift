import Foundation

/// Races an operation against a timer and returns as soon as either finishes.
///
/// A structured task group cannot do this: it always awaits every child before returning,
/// and `WKWebView.callAsyncJavaScript` ignores cancellation. A timed-out caller can return
/// while the losing operation retires. Pool requests opt into waiting for their worker on
/// explicit caller cancellation so page teardown finishes before that caller returns.
public enum DiagramTimeoutRace {
    private enum ResolutionSource {
        case operation
        case timer
        case cancellation
    }

    public static func run<T: Sendable>(
        timeout: Duration,
        timeoutError: any Error,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await race(timeout: timeout, timeoutError: timeoutError, waitForOperationOnCancellation: false) { _ in
            try await operation()
        }
    }

    /// Bounds admission and page construction. Once the page is acquired,
    /// the caller signals the milestone and its existing evaluation timer
    /// owns the next phase. Cancellation still waits for page cleanup.
    static func runWaitingForCancellationCleanupUntilMilestone<T: Sendable>(
        timeout: Duration,
        timeoutError: any Error,
        operation: @escaping @Sendable (@Sendable () -> Void) async throws -> T
    ) async throws -> T {
        try await race(timeout: timeout, timeoutError: timeoutError, waitForOperationOnCancellation: true,
                       operation: operation)
    }

    private static func race<T: Sendable>(
        timeout: Duration,
        timeoutError: any Error,
        waitForOperationOnCancellation: Bool,
        operation: @escaping @Sendable (@Sendable () -> Void) async throws -> T
    ) async throws -> T {
        let gate = Gate<T>(waitForOperationOnCancellation: waitForOperationOnCancellation)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                let work = Task {
                    do {
                        try await gate.resolveOperation(.success(operation { gate.disarmTimeout() }))
                    } catch {
                        gate.resolveOperation(.failure(error))
                    }
                }
                let timer = Task {
                    try? await Task.sleep(for: timeout)
                    gate.resolveTimeout(timeoutError)
                }
                gate.onResolved {
                    timer.cancel()
                    work.cancel()
                }
            }
        } onCancel: {
            gate.cancel()
        }
    }

    /// Resolves exactly once, whichever of the result, the timer or cancellation comes first —
    /// including cancellation arriving before the continuation is installed.
    private final class Gate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private let waitForOperationOnCancellation: Bool
        private var continuation: CheckedContinuation<T, any Error>?
        private var outcome: Result<T, any Error>?
        private var finished = false
        private var cancellationRequested = false
        private var timerStopped = false
        private var cleanup: (@Sendable () -> Void)?

        init(waitForOperationOnCancellation: Bool) {
            self.waitForOperationOnCancellation = waitForOperationOnCancellation
        }

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
            if finished || cancellationRequested {
                lock.unlock()
                cleanup()
                return
            }
            self.cleanup = cleanup
            lock.unlock()
        }

        func cancel() {
            guard waitForOperationOnCancellation else {
                resolve(.failure(CancellationError()), from: .cancellation)
                return
            }
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            cancellationRequested = true
            let cleanup = cleanup
            self.cleanup = nil
            lock.unlock()
            cleanup?()
        }

        func disarmTimeout() {
            lock.lock()
            timerStopped = true
            lock.unlock()
        }

        func resolveTimeout(_ error: any Error) {
            resolve(.failure(error), from: .timer)
        }

        func resolveOperation(_ result: Result<T, any Error>) {
            resolve(result, from: .operation)
        }

        private func resolve(_ result: Result<T, any Error>, from source: ResolutionSource) {
            lock.lock()
            guard !finished, !(source == .timer && (cancellationRequested || timerStopped)) else {
                lock.unlock()
                return
            }
            let result: Result<T, any Error> = source == .operation && cancellationRequested
                ? .failure(CancellationError()) : result
            finished = true
            outcome = result
            let continuation = continuation
            self.continuation = nil
            let cleanup = cleanup
            self.cleanup = nil
            lock.unlock()
            continuation?.resume(with: result)
            cleanup?()
        }
    }
}
