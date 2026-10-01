@testable import FileCore
import Foundation
import Testing

/// #183 F22 — Save As publishes against the destination baseline captured at
/// authorization, so a file another process created or changed in between is
/// never silently overwritten.
@Suite("FileStore Save As destination baseline (#183 F22)")
struct FileStoreSaveAsBaselineTests {
    private func leftovers(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".tmp-") }
    }

    @Test func baselineDescribesAbsentFilesAndRegularFiles() throws {
        let fixture = try FixtureFile(text: "x")
        let store = FileStore()

        #expect(try store.destinationBaseline(at: fixture.directory.appendingPathComponent("nope.md")) == .absent)
        guard case .revision = try store.destinationBaseline(at: fixture.url) else {
            Issue.record("expected a revision baseline")
            return
        }
    }

    @Test func anAbsentBaselineWritesANewFile() throws {
        let fixture = try FixtureFile()
        _ = try FileStore().write("fresh", to: fixture.url, destinationBaseline: .absent)

        #expect(try FileStore().read(from: fixture.url).content == "fresh")
        #expect(try leftovers(in: fixture.directory).isEmpty)
    }

    @Test func anAbsentBaselineRefusesADestinationThatNowExists() throws {
        let fixture = try FixtureFile(text: "someone else's file")

        #expect(throws: FileStoreError.self) {
            _ = try FileStore().write("ours", to: fixture.url, destinationBaseline: .absent)
        }
        #expect(try FileStore().read(from: fixture.url).content == "someone else's file")
        #expect(try leftovers(in: fixture.directory).isEmpty)
    }

    @Test func anAbsentBaselineLosesARaceToAFileCreatedJustBeforePublication() throws {
        let fixture = try FixtureFile()
        let store = FileStore(afterBaselineVerification: { url in
            try Data("external winner".utf8).write(to: url)
        })

        do {
            _ = try store.write("ours", to: fixture.url, destinationBaseline: .absent)
            Issue.record("expected the exclusive publication to fail")
        } catch FileStoreError.fileChangedDuringRead {
            // expected
        }

        #expect(try FileStore().read(from: fixture.url).content == "external winner")
        #expect(try leftovers(in: fixture.directory).isEmpty)
    }

    @Test func aRevisionBaselineOverwritesAnUnchangedDestination() throws {
        let fixture = try FixtureFile(text: "one")
        let baseline = try FileStore().destinationBaseline(at: fixture.url)

        _ = try FileStore().write("two", to: fixture.url, destinationBaseline: baseline)

        #expect(try FileStore().read(from: fixture.url).content == "two")
    }

    @Test func aRevisionBaselineRefusesADestinationModifiedAfterAuthorization() throws {
        let fixture = try FixtureFile(text: "one")
        let baseline = try FileStore().destinationBaseline(at: fixture.url)
        try Data("changed behind our back".utf8).write(to: fixture.url)

        #expect(throws: FileStoreError.self) {
            _ = try FileStore().write("ours", to: fixture.url, destinationBaseline: baseline)
        }
        #expect(try FileStore().read(from: fixture.url).content == "changed behind our back")
    }

    @Test func aDirectoryDestinationIsRefusedAtBaselineCapture() throws {
        let fixture = try FixtureFile()

        #expect(throws: FileStoreError.self) {
            _ = try FileStore().destinationBaseline(at: fixture.directory)
        }
    }
}
