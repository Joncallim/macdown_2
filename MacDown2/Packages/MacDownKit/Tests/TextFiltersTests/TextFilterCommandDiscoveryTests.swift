import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilterCommandDiscovery")
struct TextFilterCommandDiscoveryTests {
    @Test func createsTheCommandsDirectoryWhenMissing() throws {
        let parent = try TextFilterFixtures.makeTemporaryDirectory()
        let directory = parent.appendingPathComponent("Commands")
        defer { try? FileManager.default.removeItem(at: parent) }

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let commands = TextFilterCommandDiscovery.discoverCommands(in: directory)

        #expect(commands.isEmpty)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func discoversOnlyExecutableRegularFiles() throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try TextFilterFixtures.makeExecutableScript(TextFilterFixtures.echoStdin, named: "script.sh", in: directory)
        try TextFilterFixtures.makeNonExecutableFile(named: "notes.txt", in: directory)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("subfolder", isDirectory: true),
            withIntermediateDirectories: true
        )

        let commands = TextFilterCommandDiscovery.discoverCommands(in: directory)

        #expect(commands.count == 1)
        #expect(commands.first?.id == "script.sh")
    }

    @Test func doesNotRecurseIntoSubdirectories() throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try TextFilterFixtures.makeExecutableScript(TextFilterFixtures.echoStdin, named: "hidden.sh", in: nested)

        #expect(TextFilterCommandDiscovery.discoverCommands(in: directory).isEmpty)
    }

    @Test func humanizesFilenamesForDisplay() throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try TextFilterFixtures.makeExecutableScript(
            TextFilterFixtures.echoStdin, named: "uppercase_selection.sh", in: directory
        )

        let commands = TextFilterCommandDiscovery.discoverCommands(in: directory)
        #expect(commands.first?.name == "Uppercase Selection")
    }

    @Test func sortsResultsByDisplayName() throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try TextFilterFixtures.makeExecutableScript(TextFilterFixtures.echoStdin, named: "zebra.sh", in: directory)
        try TextFilterFixtures.makeExecutableScript(TextFilterFixtures.echoStdin, named: "apple.sh", in: directory)

        let commands = TextFilterCommandDiscovery.discoverCommands(in: directory)
        #expect(commands.map(\.name) == ["Apple", "Zebra"])
    }

    @Test func humanizedNameHandlesHyphensAndMixedSeparators() {
        #expect(TextFilterCommandDiscovery.humanizedName(for: "my-cool_script.sh") == "My Cool Script")
        #expect(TextFilterCommandDiscovery.humanizedName(for: "plain.sh") == "Plain")
    }
}
