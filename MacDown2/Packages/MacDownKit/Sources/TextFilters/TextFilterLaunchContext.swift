import Foundation

/// The explicit, bounded working directory and environment a text-filter
/// process launches with (epic-14-implementation.md §10) — never the app's
/// own bundle directory, never the app process's own inherited environment.
/// A pure value type so this policy is directly unit-testable without
/// launching a real process.
struct TextFilterLaunchContext: Equatable {
    let workingDirectoryURL: URL
    let environment: [String: String]

    /// - Parameters:
    ///   - documentURL: the active document's saved location, `nil` for an
    ///     untitled document.
    ///   - selectionLength: UTF-16 length of the input handed to the
    ///     command (the selection, or the whole document when nothing is
    ///     selected).
    ///   - homeDirectoryURL: injectable for tests; production always uses
    ///     `FileManager.default.homeDirectoryForCurrentUser`.
    ///   - temporaryDirectoryURL: injectable for tests; production always
    ///     uses `FileManager.default.temporaryDirectory`.
    init(
        documentURL: URL?,
        selectionLength: Int,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectoryURL: URL = FileManager.default.temporaryDirectory
    ) {
        workingDirectoryURL = documentURL?.deletingLastPathComponent() ?? homeDirectoryURL

        // A fixed, minimal PATH — never the app process's own inherited
        // PATH, which could carry unrelated, unaudited entries into a
        // script the user did not ask to run with them (§10). Includes
        // both Apple-Silicon (`/opt/homebrew`) and Intel (`/usr/local`)
        // Homebrew prefixes so a `#!/usr/bin/env`-style filter invoking a
        // normally-installed tool (`node`, `jq`, `pandoc`, ...) resolves on
        // either architecture — omitting shell-profile/custom PATH entries
        // remains intentional, not an oversight (post-review finding #10).
        var env: [String: String] = [
            "PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin",
            "HOME": homeDirectoryURL.path,
            "TMPDIR": temporaryDirectoryURL.path,
            "MACDOWN_SELECTION_LENGTH": String(selectionLength),
        ]
        if let documentURL {
            env["MACDOWN_DOCUMENT_PATH"] = documentURL.path
        }
        environment = env
    }
}
