import Foundation

/// Every way a text-filter command can fail without corrupting the
/// document (epic-14-implementation.md §9). Every case is reachable only
/// *before* any editor mutation is attempted — the caller applies the
/// command's output only after `TextFilterRunner.run` returns
/// successfully, never incrementally.
public enum TextFilterError: Error, LocalizedError, Sendable, Equatable {
    /// The process could not be started at all (missing file, not
    /// executable, or another `Process.run()` failure). `underlying` is a
    /// `String`, not `Error`, so this case stays `Sendable`/`Equatable`.
    case launchFailed(underlying: String)
    case nonZeroExit(code: Int32, stderr: String)
    case timedOut
    /// The caller's own `Task` was cancelled while the command was
    /// running. Distinct from a real thrown `CancellationError` so this
    /// type stays a single, exhaustively-testable enum; callers that want
    /// "no alert on cancellation" (epic-14-implementation.md §9) match
    /// this case explicitly rather than relying on `catch is
    /// CancellationError`.
    case cancelled
    case outputTooLarge
    case outputNotDecodable

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(underlying):
            "Couldn't run the command: \(underlying)"
        case let .nonZeroExit(code, stderr):
            stderr.isEmpty
                ? "The command exited with status \(code)."
                : "The command exited with status \(code): \(stderr)"
        case .timedOut:
            "The command took too long and was stopped."
        case .cancelled:
            "The command was cancelled."
        case .outputTooLarge:
            "The command produced more output than MacDown 2 will accept."
        case .outputNotDecodable:
            "The command's output wasn't valid text."
        }
    }
}
