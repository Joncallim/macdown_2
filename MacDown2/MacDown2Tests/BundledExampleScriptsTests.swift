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

        let installedCount = BundledExampleScripts.install(into: directory)

        #expect(installedCount == BundledExampleScripts.all.count)
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

        _ = BundledExampleScripts.install(into: directory)

        #expect(try String(contentsOf: url, encoding: .utf8) == "user's own edit")
    }

    @Test func createsTheDirectoryWhenMissing() throws {
        let parent = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("Commands")

        let installedCount = BundledExampleScripts.install(into: directory)

        #expect(installedCount == BundledExampleScripts.all.count)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }
}
