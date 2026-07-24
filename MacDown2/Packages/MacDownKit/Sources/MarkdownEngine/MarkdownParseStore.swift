import Foundation

/// identity (tab UUID string) → session. Mirrors EditorTextSystemStore.
@MainActor
public final class MarkdownParseStore {
    private let engine: any ParseExecuting
    private var sessions: [String: MarkdownParseSession] = [:]

    public init(engine: any ParseExecuting = ParseEngine()) {
        self.engine = engine
    }

    public func session(for identity: String) -> MarkdownParseSession {
        if let session = sessions[identity] {
            return session
        }
        let session = MarkdownParseSession(engine: engine)
        sessions[identity] = session
        return session
    }

    public func existingSession(for identity: String) -> MarkdownParseSession? {
        sessions[identity]
    }

    public func evict(_ identity: String) {
        sessions.removeValue(forKey: identity)
    }

    public func evictAll() {
        sessions.removeAll()
    }
}
