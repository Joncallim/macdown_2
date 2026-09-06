import Foundation

/// Runs a discovered `TextFilterCommand` against one piece of text
/// (epic-14-implementation.md §6.5). Not actor-isolated — safe to call
/// from any isolation domain, including a plain background `Task` (§8) —
/// so awaiting it never risks blocking the main actor.
public struct TextFilterRunner: Sendable {
    public struct Limits: Sendable, Equatable {
        public let timeout: Duration
        public let maxOutputBytes: Int

        public init(timeout: Duration, maxOutputBytes: Int) {
            self.timeout = timeout
            self.maxOutputBytes = maxOutputBytes
        }

        /// 10s: generous for an interactive, user-initiated action; 4 MB:
        /// comfortably covers realistic documents while still bounding a
        /// runaway or malicious script (epic-14-implementation.md §11).
        public static let standard = Limits(timeout: .seconds(10), maxOutputBytes: 4 << 20)
    }

    private let limits: Limits

    public init(limits: Limits = .standard) {
        self.limits = limits
    }

    /// Launches `command` with structured arguments only — `input` travels
    /// solely via stdin, never as a shell-interpolated argument (§10) —
    /// waits (bounded by `limits.timeout`), and returns decoded stdout on
    /// a zero exit. Any other outcome throws `TextFilterError`; nothing is
    /// left for the caller to undo, because nothing has been applied yet
    /// (§4, §9). `documentURL` is the active document's saved location
    /// (`nil` for an untitled document) — used only to pick the process's
    /// working directory and to populate `MACDOWN_DOCUMENT_PATH` (§10).
    public func run(_ command: TextFilterCommand, input: String, documentURL: URL? = nil) async throws -> String {
        let context = TextFilterLaunchContext(
            documentURL: documentURL,
            selectionLength: (input as NSString).length
        )
        let session = TextFilterProcessSession(maxOutputBytes: limits.maxOutputBytes)
        return try await session.run(command: command, input: input, context: context, timeout: limits.timeout)
    }
}
