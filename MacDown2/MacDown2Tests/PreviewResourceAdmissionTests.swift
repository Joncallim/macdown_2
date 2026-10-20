import Foundation
import LocalResourceAccess
@testable import MacDown2
import Testing

@Suite("Preview resource admission")
@MainActor
struct PreviewResourceAdmissionTests {
    @Test func retiredLoadKeepsRunningWorkerAndReservationUntilReadEnds() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.sandbox) }
        let entered = DispatchSemaphore(value: 0)
        let finish = DispatchSemaphore(value: 0)
        defer { finish.signal() }
        let admission = PreviewResourceAdmission { reference, directory, cancellation in
            entered.signal()
            finish.wait()
            return try ContainedResourceReader.read(
                reference, in: directory, maxBytes: PreviewResourceAdmission.resourceLimit,
                cancellation: cancellation
            )
        }
        let context = PreviewResourceLoad(grant: fixture.grant)
        let reference = try ResourceReference.parse("image.png")
        let read = Task { try await admission.read(reference, in: context) }
        let didEnter = await Task.detached { Self.waitForSignal(entered) }.value
        #expect(didEnter)

        await admission.retire(context)
        #expect(await admission.status(for: context) == .init(
            activeWorkers: 1, queued: 0,
            reserved: PreviewResourceAdmission.resourceLimit, retained: 0, delivered: 0
        ))
        finish.signal()
        await #expect(throws: PreviewResourceAdmissionError.self) { try await read.value }
        try await waitForDrain(of: context, in: admission)
        fixture.grant.revoke()
    }

    @Test func payloadReservationSurvivesRetirementUntilLastReferenceLeaves() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.sandbox) }
        let admission = PreviewResourceAdmission()
        let context = PreviewResourceLoad(grant: fixture.grant)
        var payload: PreviewResourcePayload? = try await admission.read(
            ResourceReference.parse("image.png"), in: context
        )
        #expect(payload?.snapshot.bytes == Data("image".utf8))
        #expect(await admission.status(for: context) == .init(
            activeWorkers: 0, queued: 0, reserved: 0, retained: 5, delivered: 5
        ))
        await admission.retire(context)
        #expect(await admission.status(for: context)?.retained == 5)
        payload = nil
        try await waitForDrain(of: context, in: admission)
        fixture.grant.revoke()
    }

    @Test func admittedWorkerKeepsGrantAliveAfterFolderRevocation() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.sandbox) }
        let entered = DispatchSemaphore(value: 0)
        let finish = DispatchSemaphore(value: 0)
        defer { finish.signal() }
        let admission = PreviewResourceAdmission { reference, directory, cancellation in
            entered.signal()
            finish.wait()
            return try ContainedResourceReader.read(
                reference, in: directory, maxBytes: PreviewResourceAdmission.resourceLimit,
                cancellation: cancellation
            )
        }
        let context = PreviewResourceLoad(grant: fixture.grant)
        let read = Task {
            try await admission.read(ResourceReference.parse("image.png"), in: context)
        }
        #expect(await Task.detached { Self.waitForSignal(entered) }.value)
        fixture.grant.revoke()
        finish.signal()
        let payload = try await read.value
        #expect(payload.snapshot.bytes == Data("image".utf8))
        await admission.retire(context)
    }

    private func makeFixture() async throws -> (sandbox: URL, grant: PreviewDirectoryGrantBacking) {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let document = sandbox.appendingPathComponent("story.md")
        try Data("image".utf8).write(to: sandbox.appendingPathComponent("image.png"))
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: document, folderURL: sandbox
        ))
        return try await (sandbox, PreviewDirectoryGrantBacking.acquire(
            selection: selection, currentDocumentURL: document, epoch: UUID()
        ))
    }

    private func waitForDrain(
        of context: PreviewResourceLoad, in admission: PreviewResourceAdmission
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await admission.status(for: context) != nil {
            guard ContinuousClock.now < deadline else {
                Issue.record("Retired admission retained its worker or payload ledger")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private nonisolated static func waitForSignal(_ signal: DispatchSemaphore) -> Bool {
        signal.wait(timeout: .now() + 5) == .success
    }
}
