import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter fixture ownership")
struct TextFilterFixtureOwnershipTests {
    @Test func pidReadinessAcceptsOnlyCompletePositiveRecords() throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pids")
        try "worker=123\nworker=123\npartial=\nnot-a-record\nnegative=-4\nworker=456 trailing\n789\n".write(
            to: url, atomically: true, encoding: .utf8
        )

        #expect(TextFilterFixtures.completePIDs(in: url) == [123, 789])

        try "worker=123 trailing".write(to: url, atomically: true, encoding: .utf8)
        #expect(TextFilterFixtures.completePIDs(in: url).isEmpty)
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
