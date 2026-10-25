@testable import DiagramWebKitPool
import Foundation
import Testing

@MainActor
struct DiagramPoolAdmissionBudgetTests {
    private struct EvaluationWatchdogExceeded: Error {}

    private func makePage() async throws -> (DiagramHarnessPage, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "<!doctype html><html><body>harness</body></html>".write(
            to: directory.appendingPathComponent("harness.html"), atomically: true, encoding: .utf8
        )
        let bundle = try #require(Bundle(url: directory))
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        return (page, directory)
    }

    @Test func coldPageAdmissionHasItsOwnBoundWithoutExtendingEvaluation() async throws {
        let (page, directory) = try await makePage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(
            poolSize: 1,
            timeout: .milliseconds(100),
            admissionTimeout: .seconds(1)
        ) {
            try await Task.sleep(for: .milliseconds(250))
            return page
        }

        let value = try await pool.withPage { _ in 42 }
        #expect(value == 42)
        await pool.shutdown()
        #expect(page.isTerminated)
    }

    @Test func readyPageDisarmsAdmissionWhileExecutionContinues() async throws {
        let (page, directory) = try await makePage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(
            poolSize: 1,
            timeout: .seconds(2),
            admissionTimeout: .milliseconds(200)
        ) { page }

        let value = try await pool.withPage { _ in
            try await Task.sleep(for: .milliseconds(500))
            return 42
        }
        #expect(value == 42)
        await pool.shutdown()
        #expect(page.isTerminated)
    }

    @Test func evaluationDeadlineStillWinsAfterReadyPageAdmission() async throws {
        let (page, directory) = try await makePage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(
            poolSize: 1,
            timeout: .milliseconds(100),
            admissionTimeout: .seconds(1)
        ) { page }

        await #expect(throws: DiagramPoolError.timedOut) {
            _ = try await DiagramTimeoutRace.run(
                timeout: .milliseconds(750),
                timeoutError: EvaluationWatchdogExceeded()
            ) {
                try await pool.withPage { _ in
                    try await Task.sleep(for: .seconds(2))
                    return 43
                }
            }
        }
        await pool.shutdown()
        #expect(page.isTerminated)
    }
}
