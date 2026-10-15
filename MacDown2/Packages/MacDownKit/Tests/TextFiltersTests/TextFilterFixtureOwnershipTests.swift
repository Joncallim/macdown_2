import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter fixture ownership")
struct TextFilterFixtureOwnershipTests {
    private enum FixtureFailure: Error {
        case expected
    }

    private actor LifecycleProbe {
        private(set) var directory: URL?
        private(set) var taskWasCancelled = false
        private(set) var directoryWasPresentWhenTaskCancelled = false

        func record(directory: URL) {
            self.directory = directory
        }

        func recordTaskCancellation(directory: URL) {
            taskWasCancelled = true
            directoryWasPresentWhenTaskCancelled = FileManager.default.fileExists(atPath: directory.path)
        }
    }

    @Test func pidReadinessRequiresCompleteUniquePositiveRecords() throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pids")
        try """
        worker=123
        worker=123
        partial=
        not a record
        negative=-4
        overflow=999999999999999999999999
        worker=456 trailing
        """
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

    @Test func ownedDirectoryJoinsTrackedTaskBeforeNormalCleanup() async throws {
        var observed: URL?
        try await TextFilterFixtures.withOwnedTemporaryDirectory { directory, owner in
            observed = directory
            let marker = directory.appendingPathComponent("marker")
            let task = await owner.start {
                try await Task.sleep(for: .milliseconds(1))
                try "done".write(to: marker, atomically: true, encoding: .utf8)
            }

            try await task.value
            #expect(FileManager.default.fileExists(atPath: marker.path))
        }

        #expect(observed.map { !FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test func ownedDirectoryCancelsAndJoinsTrackedTaskAfterAnEarlyError() async throws {
        let probe = LifecycleProbe()
        var observed: URL?

        await #expect(throws: FixtureFailure.expected) {
            try await TextFilterFixtures.withOwnedTemporaryDirectory { directory, owner in
                observed = directory
                _ = await owner.start {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        await probe.recordTaskCancellation(directory: directory)
                        throw error
                    }
                }
                throw FixtureFailure.expected
            }
        }

        #expect(await probe.taskWasCancelled)
        #expect(await probe.directoryWasPresentWhenTaskCancelled)
        #expect(observed.map { !FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test func ownedDirectoryCancelsAndJoinsTrackedTaskWhenScopeIsCancelled() async throws {
        let probe = LifecycleProbe()
        let scope = Task {
            try await TextFilterFixtures.withOwnedTemporaryDirectory { directory, owner in
                await probe.record(directory: directory)
                _ = await owner.start {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        await probe.recordTaskCancellation(directory: directory)
                        throw error
                    }
                }
                try await Task.sleep(for: .seconds(30))
            }
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await probe.directory == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        scope.cancel()
        _ = await scope.result

        #expect(await probe.taskWasCancelled)
        #expect(await probe.directoryWasPresentWhenTaskCancelled)
        if let directory = await probe.directory {
            #expect(!FileManager.default.fileExists(atPath: directory.path))
        } else {
            Issue.record("the owned fixture scope never started")
        }
    }
}
