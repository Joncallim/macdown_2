import Foundation

/// The example scripts "Add Example Scripts" installs into the user's
/// Commands folder (epic-14-implementation.md §17 Slice 6). Embedded as
/// string literals rather than bundled resource files — a script is a
/// handful of lines, and this sidesteps giving a plain-text/no-extension
/// resource a bundle build rule for no real benefit.
enum BundledExampleScripts {
    struct Script {
        let filename: String
        let contents: String
    }

    static let all: [Script] = [
        Script(
            filename: "uppercase_selection.sh",
            contents: """
            #!/bin/sh
            # MacDown 2 example text-filter command.
            # Uppercases stdin (the selection, or the whole document when
            # nothing is selected) and writes the result to stdout.
            cat | tr '[:lower:]' '[:upper:]'
            """
        ),
        Script(
            filename: "sort_lines.sh",
            contents: """
            #!/bin/sh
            # MacDown 2 example text-filter command.
            # Sorts stdin's lines alphabetically.
            cat | sort
            """
        ),
    ]

    /// Writes every script in `all` into `directory`, executable, skipping
    /// any filename that already exists there — installing examples must
    /// never silently overwrite a user's own edited copy.
    @discardableResult
    static func install(into directory: URL) -> Int {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var installedCount = 0
        for script in all {
            let url = directory.appendingPathComponent(script.filename)
            guard !fileManager.fileExists(atPath: url.path) else { continue }
            guard (try? script.contents.write(to: url, atomically: true, encoding: .utf8)) != nil else { continue }
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            installedCount += 1
        }
        return installedCount
    }
}
