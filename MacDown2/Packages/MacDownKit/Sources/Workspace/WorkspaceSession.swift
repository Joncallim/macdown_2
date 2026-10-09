import FileCore
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

    private enum CodingKeys: String, CodingKey {
        case version, tabs, activeTabID
    }

    /// A tab record that cannot be decoded (a field this build does not know, e.g. after a downgrade) costs
    /// that one tab, not the whole session: failing the entire decode meant no restore and an autosave that
    /// overwrote the file, orphaning every other tab's dirty recovery.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        tabs = try container.decode([LossyTabRecord].self, forKey: .tabs).compactMap(\.record)
        activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
    }

    private struct LossyTabRecord: Decodable {
        let record: TabRecord?

        init(from decoder: Decoder) throws {
            record = try? TabRecord(from: decoder)
        }
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
    /// Exact recovery lifetime. Optional for sessions written before E18.
    public var documentRecoveryEpoch: UUID?
    public var isPinned: Bool

    /// The UTF-16 offset of the start of the editor selection. When
    /// `selectionLength` is zero this is the insertion point (caret).
    public var cursorPosition: Int?

    /// The number of UTF-16 code units selected. Together with `cursorPosition`
    /// this reconstructs the full `NSRange` on restore.
    public var selectionLength: Int?

    public var scrollOffset: Double?
    public var previewLayout: PreviewLayoutMode?
    /// The preview pane's display mode, or `nil` for the format's default.
    /// Optional so sessions written before EPIC-11 still decode.
    public var previewMode: PreviewMode?
    /// The tab's explicit Syntax Mode. Optional so sessions written before
    /// Slice 9d still decode.
    public var syntaxOverride: SyntaxModeOverride?
    /// Decoding metadata needed to interpret the restored text. Optional so
    /// sessions written before EPIC-11 still decode; absent metadata uses the
    /// documented default (UTF-8, no BOM). Raw bytes are never persisted.
    public var encoding: FileEncodingMetadata?
    /// SHA-256 of the file content this tab was last known to match on disk.
    /// A restored DIRTY tab whose file no longer hashes to this was changed
    /// outside the app while it was quit, and must come back as a conflict
    /// rather than silently adopting the new file as its baseline. Optional so
    /// older sessions still decode.
    public var baseSHA256: String?
    /// Optional so sessions written before the folder browser still decode.
    public var folderRootBookmark: Data?
    /// Lexical spelling paired with the physical security-scoped bookmark.
    public var folderRootAlias: URL?

    public init(
        id: UUID,
        fileURL: URL? = nil,
        untitledDocumentID: String? = nil,
        documentRecoveryEpoch: UUID? = nil,
        isPinned: Bool = false,
        cursorPosition: Int? = nil,
        selectionLength: Int? = nil,
        scrollOffset: Double? = nil,
        previewLayout: PreviewLayoutMode? = nil,
        previewMode: PreviewMode? = nil,
        syntaxOverride: SyntaxModeOverride? = nil,
        encoding: FileEncodingMetadata? = nil,
        baseSHA256: String? = nil,
        folderRootBookmark: Data? = nil,
        folderRootAlias: URL? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.untitledDocumentID = untitledDocumentID
        self.documentRecoveryEpoch = documentRecoveryEpoch
        self.isPinned = isPinned
        self.cursorPosition = cursorPosition
        self.selectionLength = selectionLength
        self.scrollOffset = scrollOffset
        self.previewLayout = previewLayout
        self.previewMode = previewMode
        self.syntaxOverride = syntaxOverride
        self.encoding = encoding
        self.baseSHA256 = baseSHA256
        self.folderRootBookmark = folderRootBookmark
        self.folderRootAlias = folderRootAlias
    }
}

/// Abstraction over session persistence so `TabStore` can be tested with an
/// in-memory store and the real app can use a JSON file.
@MainActor
public protocol WorkspaceSessionStoring: Sendable {
    func loadSession() -> WorkspaceSession?
    func saveSession(_ session: WorkspaceSession)
}

public extension WorkspaceSessionStoring {
    /// A lifecycle boundary, unlike best-effort autosave. The caller can only
    /// retire a recovery redirect after the exact replacement session is
    /// readable from the canonical store.
    @discardableResult
    func saveSessionVerified(_ session: WorkspaceSession) -> Bool {
        saveSession(session)
        return loadSession() == session
    }
}

/// JSON file-backed session store.
///
/// Writes atomically and never throws: failures are swallowed because session
/// restore is best-effort.
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
        guard let session = try? JSONDecoder().decode(WorkspaceSession.self, from: data),
              session.version == WorkspaceSession.currentVersion
        else {
            preserveUnreadableSession()
            return nil
        }
        // A tab that decoded leniently away is gone from the next autosave, with its recovery pointer: keep the
        // file it came from.
        if let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let rawTabs = raw["tabs"] as? [Any], rawTabs.count > session.tabs.count {
            preserveUnreadableSession()
        }
        return session
    }

    /// The next autosave replaces `session.json`; keep a copy of one that could not be read (a newer build's
    /// format, corruption) so it is not the only evidence lost when that happens.
    private func preserveUnreadableSession() {
        let backup = fileURL.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: fileURL, to: backup)
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
