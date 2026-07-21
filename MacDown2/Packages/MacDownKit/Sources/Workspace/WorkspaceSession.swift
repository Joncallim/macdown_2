import Foundation

/// Persistent representation of an open tab session.
///
/// The schema is versioned so future epics can add fields without migration.
/// Unknown versions are treated as empty sessions during restore.
public struct WorkspaceSession: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var tabs: [TabRecord]
    public var activeTabID: UUID?

    public init(version: Int = currentVersion, tabs: [TabRecord] = [], activeTabID: UUID? = nil) {
        self.version = version
        self.tabs = tabs
        self.activeTabID = activeTabID
    }

    /// An empty session using the current schema version.
    public static var empty: WorkspaceSession {
        WorkspaceSession()
    }
}

/// One persisted tab.
public struct TabRecord: Codable, Sendable, Equatable {
    public var id: UUID
    public var fileURL: URL?
    public var untitledDocumentID: String?
    public var isPinned: Bool
    public var cursorPosition: Int?
    public var scrollOffset: Double?

    public init(
        id: UUID,
        fileURL: URL? = nil,
        untitledDocumentID: String? = nil,
        isPinned: Bool = false,
        cursorPosition: Int? = nil,
        scrollOffset: Double? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.untitledDocumentID = untitledDocumentID
        self.isPinned = isPinned
        self.cursorPosition = cursorPosition
        self.scrollOffset = scrollOffset
    }
}

/// Abstraction over session persistence so `TabStore` can be tested with an
/// in-memory store and the real app can use a JSON file.
@MainActor
public protocol WorkspaceSessionStoring: Sendable {
    func loadSession() -> WorkspaceSession?
    func saveSession(_ session: WorkspaceSession)
}

/// JSON file-backed session store.
///
/// Writes atomically (temp file + rename) and never throws: failures are
/// swallowed because session restore is best-effort.
@MainActor
public struct WorkspaceSessionStore: WorkspaceSessionStoring {
    public static let defaultFileName = "session.json"

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            let directory = appSupport.appendingPathComponent("MacDown 2", isDirectory: true)
            self.fileURL = directory.appendingPathComponent(Self.defaultFileName)
        }
    }

    public func loadSession() -> WorkspaceSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let session = try? JSONDecoder().decode(WorkspaceSession.self, from: data) else { return nil }
        guard session.version == WorkspaceSession.currentVersion else { return nil }
        return session
    }

    public func saveSession(_ session: WorkspaceSession) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        guard let data = try? JSONEncoder().encode(session) else { return }

        // `.atomic` writes to a temp file and renames it over `fileURL`,
        // atomically replacing any existing session. A manual temp+`moveItem`
        // would fail once the destination exists, silently freezing the file
        // at its first-written value.
        try? data.write(to: fileURL, options: .atomic)
    }
}
