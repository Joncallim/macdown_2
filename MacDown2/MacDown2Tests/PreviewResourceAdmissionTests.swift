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
        let admission = PreviewResourceAdmission(readOperation: { reference, directory, cancellation in
            entered.signal()
            finish.wait()
            return try ContainedResourceReader.read(
                reference, in: directory, maxBytes: PreviewResourceAdmission.resourceLimit,
                cancellation: cancellation
            )
        })
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
        let admission = PreviewResourceAdmission(readOperation: { reference, directory, cancellation in
            entered.signal()
            finish.wait()
            return try ContainedResourceReader.read(
                reference, in: directory, maxBytes: PreviewResourceAdmission.resourceLimit,
                cancellation: cancellation
            )
        })
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

    @Test func retainedPayloadsAcrossOldLoadsConsumeTheGlobalInputCap() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.sandbox) }
        try Data(repeating: 65, count: PreviewResourceAdmission.resourceLimit)
            .write(to: fixture.sandbox.appendingPathComponent("image.png"))
        let admission = PreviewResourceAdmission(inputLimit: 2 * PreviewResourceAdmission.resourceLimit)
        let contexts = (0 ..< 3).map { _ in PreviewResourceLoad(grant: fixture.grant) }
        let reference = try ResourceReference.parse("image.png")
        var first: PreviewResourcePayload? = try await admission.read(reference, in: contexts[0])
        let second = try await admission.read(reference, in: contexts[1])
        #expect(await admission.globalStatus() == .init(
            reserved: 0, retained: 2 * PreviewResourceAdmission.resourceLimit
        ))
        await #expect(throws: PreviewResourceAdmissionError.limitExceeded) {
            try await admission.read(reference, in: contexts[2])
        }
        first = nil
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await admission.globalStatus().retained != PreviewResourceAdmission.resourceLimit {
            guard ContinuousClock.now < deadline else {
                Issue.record("Released payload did not return global capacity")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        let third = try await admission.read(reference, in: contexts[2])
        #expect(third.snapshot.bytes.count == PreviewResourceAdmission.resourceLimit)
        #expect(second.snapshot.bytes.count == PreviewResourceAdmission.resourceLimit)
        #expect(first == nil)
        for context in contexts {
            await admission.retire(context)
        }
        fixture.grant.revoke()
    }

    @Test func cancelledSuccessfulReadKeepsItsInputChargeThroughSettlement() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.sandbox) }
        try Data(repeating: 65, count: PreviewResourceAdmission.resourceLimit)
            .write(to: fixture.sandbox.appendingPathComponent("image.png"))
        let entered = DispatchSemaphore(value: 0)
        let releaseRead = DispatchSemaphore(value: 0)
        let enteredSettlement = DispatchSemaphore(value: 0)
        let releaseSettlement = DispatchSemaphore(value: 0)
        defer {
            releaseRead.signal()
            releaseSettlement.signal()
        }
        let admission = PreviewResourceAdmission(
            settlementGate: {
                enteredSettlement.signal()
                _ = await Task.detached { Self.waitForSignal(releaseSettlement) }.value
            },
            readOperation: { reference, directory, _ in
                entered.signal()
                releaseRead.wait()
                return try ContainedResourceReader.read(
                    reference, in: directory, maxBytes: PreviewResourceAdmission.resourceLimit,
                    cancellation: ResourceCancellation()
                )
            }
        )
        let context = PreviewResourceLoad(grant: fixture.grant)
        let read = Task {
            try await admission.read(ResourceReference.parse("image.png"), in: context)
        }
        #expect(await Task.detached { Self.waitForSignal(entered) }.value)
        read.cancel()
        releaseRead.signal()
        #expect(await Task.detached { Self.waitForSignal(enteredSettlement) }.value)
        #expect(await admission.globalStatus() == .init(
            reserved: PreviewResourceAdmission.resourceLimit, retained: 0
        ))
        releaseSettlement.signal()
        await #expect(throws: PreviewResourceAdmissionError.self) { try await read.value }
        await admission.retire(context)
        try await waitForDrain(of: context, in: admission)
        fixture.grant.revoke()
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
