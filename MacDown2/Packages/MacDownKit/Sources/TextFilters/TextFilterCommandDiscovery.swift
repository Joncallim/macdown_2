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

        let commands = entries
            .filter(isExecutableRegularFile)
            .map { url -> TextFilterCommand in
                let id = url.lastPathComponent
                return TextFilterCommand(id: id, name: humanizedName(for: id), executableURL: url)
            }
        return disambiguated(commands)
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                // `id` (the real filename) is a deterministic tie-breaker:
                // two commands with the same humanized name would otherwise
                // have no stable relative order across scans (finding #11).
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
    }

    /// Rejects symlinks explicitly rather than relying on `isExecutableFile`
    /// (which follows them): the discovery contract is "executable regular
    /// files," and `.isRegularFileKey`/`isExecutableFile` alone silently
    /// admit an executable symlink, contradicting that contract
    /// (post-review finding #15).
    private static func isExecutableRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true
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

    /// Appends the real filename to the display name of any command whose
    /// humanized name collides with another's, so two distinct executables
    /// (`foo.sh` / `foo.py`) never render as visually indistinguishable
    /// menu/palette rows (post-review finding #11).
    private static func disambiguated(_ commands: [TextFilterCommand]) -> [TextFilterCommand] {
        var countsByName: [String: Int] = [:]
        for command in commands {
            countsByName[command.name, default: 0] += 1
        }
        return commands.map { command in
            guard countsByName[command.name, default: 0] > 1 else { return command }
            return TextFilterCommand(
                id: command.id,
                name: "\(command.name) (\(command.id))",
                executableURL: command.executableURL
            )
        }
    }
}
