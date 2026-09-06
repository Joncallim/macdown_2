import Foundation

/// Scans the user's Commands folder for runnable text filters
/// (epic-14-implementation.md §6.5, §17 Slice 5). Stateless by design —
/// `discoverCommands()` re-scans the filesystem every call rather than
/// caching, so an edit made between two menu/palette openings is always
/// picked up (§7.2).
public enum TextFilterCommandDiscovery {
    /// `~/Library/Application Support/MacDown 2/Commands`, matching
    /// `RecoveryBuffer`/`WorkspaceSession`'s existing Application Support
    /// convention (§2.1). Falls back to the home directory if Application
    /// Support is unavailable for any reason (sandboxed/misconfigured
    /// environment) rather than crashing on a force-unwrap.
    public static var commandsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("MacDown 2", isDirectory: true)
            .appendingPathComponent("Commands", isDirectory: true)
    }

    /// Every executable regular file directly inside `commandsDirectory`
    /// (no recursion into subfolders), sorted by display name. Creates the
    /// directory, empty, if it does not exist yet — a first launch after
    /// this feature ships is not an error state (§9).
    public static func discoverCommands(in directory: URL = commandsDirectory) -> [TextFilterCommand] {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter(isExecutableRegularFile)
            .map { url in
                let id = url.lastPathComponent
                return TextFilterCommand(id: id, name: humanizedName(for: id), executableURL: url)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func isExecutableRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// Strips the extension and turns `_`/`-` separators into spaced,
    /// capitalized words: `uppercase_selection.sh` -> "Uppercase Selection".
    static func humanizedName(for filename: String) -> String {
        let base = (filename as NSString).deletingPathExtension
        let normalized = base.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        let words = normalized.split(separator: " ").filter { !$0.isEmpty }
        guard !words.isEmpty else { return base }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
