import Foundation
@testable import MacDown2
import Testing

@Suite("BundledExampleScripts")
struct BundledExampleScriptsTests {
    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func installsEveryScriptExecutable() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = BundledExampleScripts.install(into: directory)

        #expect(result.installedCount == BundledExampleScripts.all.count)
        #expect(!result.hadFailure)
        for script in BundledExampleScripts.all {
            let path = directory.appendingPathComponent(script.filename).path
            #expect(FileManager.default.isExecutableFile(atPath: path))
        }
    }

    @Test func doesNotOverwriteAnExistingFileWithTheSameName() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let first = BundledExampleScripts.all.first else {
            Issue.record("expected at least one bundled example script")
            return
        }
        let url = directory.appendingPathComponent(first.filename)
        try "user's own edit".write(to: url, atomically: true, encoding: .utf8)

        let result = BundledExampleScripts.install(into: directory)

        #expect(try String(contentsOf: url, encoding: .utf8) == "user's own edit")
        #expect(!result.hadFailure)
    }

    @Test func createsTheDirectoryWhenMissing() throws {
        let parent = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("Commands")

        let result = BundledExampleScripts.install(into: directory)

        #expect(result.installedCount == BundledExampleScripts.all.count)
        #expect(!result.hadFailure)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    /// Codex review finding (PR #56): a directory-creation failure used to
    /// be swallowed by `try?` and reported identically to "nothing new to
    /// add".
    @Test func reportsFailureWhenTheDirectoryCannotBeCreated() throws {
        let parent = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let blockingFile = parent.appendingPathComponent("blocking-file")
        try Data().write(to: blockingFile)
        // A path under a plain file can never become a directory.
        let directory = blockingFile.appendingPathComponent("Commands")

        let result = BundledExampleScripts.install(into: directory)

        #expect(result.installedCount == 0)
        #expect(result.hadFailure)
    }

    /// Codex review finding (PR #56): a write/`fchmod` failure used to
    /// return the same "0 installed" result as every script already
    /// existing, hiding the failure from the user.
    @Test func reportsFailureWhenAScriptCannotBeWritten() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)

        let result = BundledExampleScripts.install(into: directory)

        #expect(result.installedCount == 0)
        #expect(result.hadFailure)
    }
}
