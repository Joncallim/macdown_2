import Foundation

/// One discovered, executable script under the user's Commands folder
/// (epic-14-implementation.md §6.5). A plain value, not a live handle: the
/// script may be edited, moved, or deleted at any time between discovery
/// and invocation — `TextFilterRunner` handles that as an ordinary launch
/// failure, not a precondition this type enforces.
public struct TextFilterCommand: Sendable, Equatable, Identifiable {
    /// The script's filename, unique within one Commands folder listing.
    public let id: String
    /// A humanized display name derived from the filename.
    public let name: String
    public let executableURL: URL

    public init(id: String, name: String, executableURL: URL) {
        self.id = id
        self.name = name
        self.executableURL = executableURL
    }
}
