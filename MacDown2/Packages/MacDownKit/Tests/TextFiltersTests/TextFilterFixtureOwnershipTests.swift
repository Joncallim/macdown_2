import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter fixture ownership")
struct TextFilterFixtureOwnershipTests {
    @Test func pidReadinessRequiresCompleteUniquePositiveRecords() throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pids")
        try "worker=123\nworker=123\npartial=\nnot a record\nnegative=-4\noverflow=999999999999999999999999\nworker=456 trailing\n"
            .write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
        #expect(TextFilterFixtures.completePIDs(in: url) == [123])

        try "worker=123".write(to: url, atomically: true, encoding: .utf8)
        #expect(TextFilterFixtures.completePIDs(in: url).isEmpty)

        try "123\nworker=45".write(to: url, atomically: true, encoding: .utf8)
        #expect(TextFilterFixtures.completePIDs(in: url) == [123])
        try "123\nworker=456\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(TextFilterFixtures.completePIDs(in: url) == [123, 456])
    }

    @Test func asyncDirectoryOwnerCleansUpAfterOperationJoins() async throws {
        var observed: URL?
        try await TextFilterFixtures.withTemporaryDirectory { directory in
            observed = directory
            let marker = directory.appendingPathComponent("marker")
            try "done".write(to: marker, atomically: true, encoding: .utf8)
            try await Task.sleep(for: .milliseconds(1))
            #expect(FileManager.default.fileExists(atPath: marker.path))
        }
        #expect(observed.map { !FileManager.default.fileExists(atPath: $0.path) } == true)
    }
}
