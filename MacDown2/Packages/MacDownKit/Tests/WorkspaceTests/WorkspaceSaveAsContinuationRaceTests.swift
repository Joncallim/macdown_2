@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// #183 F01 / handoff regression 2: `prepareSaveAsRecoveryContinuation` awaits
/// recovery durability for the replacement and must not publish it over a
/// document that changed during that await. Driven through the real
/// `retryRecoveryCleanup` entry point with the persistence gate held open.
@MainActor
struct WorkspaceSaveAsContinuationRaceTests {
    private struct Fixture {
        let directory: URL
        let recovery: RecoveryBuffer
        let source: FileDocument
        let destination: FileDocument
        let model: WorkspaceModel
        let migration: PendingRecoveryCleanupAction
        let published: PublishCounter
    }

    private final class PublishCounter {
        var publications: [Int] = []
    }

    private func makeFixture() async -> Fixture {
        let directory = temporaryDirectory()
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let source = FileDocument(fileURL: directory.appendingPathComponent("source.md"), recoveryBuffer: recovery)
            .updatingText("draft")
        let destination = FileDocument(
            fileURL: directory.appendingPathComponent("destination.md"),
            recoveryBuffer: recovery
        ).updatingText("draft")
        #expect(await source.persistRecovery())
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        let published = PublishCounter()
        model.saveAsSessionPublisher = {
            published.publications.append(published.publications.count)
            return true
        }
        let migration = PendingRecoveryCleanupAction.migrate(source: source, destination: destination)
        model.pendingRecoveryCleanupActions.insert(migration)
        model.pendingSaveAsRecoveryContinuations[migration] = SaveAsRecoveryContinuation(
            source: source,
            replacement: destination,
            context: SaveContext(documentID: source.id, generation: 1, errorRevision: 0),
            phase: .publishDestination
        )
        return Fixture(
            directory: directory,
            recovery: recovery,
            source: source,
            destination: destination,
            model: model,
            migration: migration,
            published: published
        )
    }

    @Test func anEditDuringTheContinuationPersistenceIsNotReplacedByTheDestination() async throws {
        let fixture = await makeFixture()
        defer { cleanup(fixture.directory) }
        let model = fixture.model
        model.afterRecoveryRetryPersistence = {
            model.tabStore.updateActiveDocument { $0.updatingText("typed during the await") }
        }

        await model.retryRecoveryCleanup()

        #expect(model.activeDocument?.text == "typed during the await", "the live edit must survive")
        #expect(model.activeDocument?.id == fixture.source.id, "the destination must not replace the live document")
        #expect(model.hasPendingRecoveryCleanup, "the continuation must stay pending for a later retry")
        #expect(model.lastError != nil)
        #expect(fixture.published.publications.isEmpty, "no session snapshot of the stale replacement may be published")
        let surviving = try await fixture.recovery.load(for: fixture.source.id, epoch: fixture.source.recoveryEpoch)
        #expect(surviving != nil, "the source's recovery bytes must not be retired by a stale continuation")
    }

    @Test func aTabSwitchDuringTheContinuationPersistenceDoesNotPublishOverTheNewActiveTab() async throws {
        let fixture = await makeFixture()
        defer { cleanup(fixture.directory) }
        let model = fixture.model
        let other = FileDocument(
            fileURL: fixture.directory.appendingPathComponent("other.md"),
            recoveryBuffer: fixture.recovery
        ).updatingText("other tab")
        model.afterRecoveryRetryPersistence = {
            model.tabStore.newTab(document: other)
        }

        await model.retryRecoveryCleanup()

        #expect(model.activeDocument?.id == other.id, "the newly active tab must be left alone")
        #expect(model.activeDocument?.text == "other tab")
        #expect(fixture.published.publications.isEmpty)
        let surviving = try await fixture.recovery.load(for: fixture.source.id, epoch: fixture.source.recoveryEpoch)
        #expect(surviving != nil)
    }

    @Test func anUndisturbedContinuationStillCompletes() async {
        let fixture = await makeFixture()
        defer { cleanup(fixture.directory) }

        await fixture.model.retryRecoveryCleanup()

        #expect(!fixture.model.hasPendingRecoveryCleanup)
        #expect(fixture.model.lastError == nil)
        #expect(fixture.model.activeDocument?.fileURL == fixture.destination.fileURL?.standardizedFileURL)
        #expect(!fixture.published.publications.isEmpty)
    }

    @Test func aRecoveryLifetimeChangeDuringTheContinuationPersistenceIsNotReplaced() async throws {
        let fixture = await makeFixture()
        defer { cleanup(fixture.directory) }
        let model = fixture.model
        let epochBefore = try #require(model.activeDocument?.recoveryEpoch)
        model.afterRecoveryRetryPersistence = {
            model.tabStore.updateActiveDocument { $0.withFreshRecoveryLifetime() }
        }

        await model.retryRecoveryCleanup()

        #expect(model.activeDocument?.id == fixture.source.id, "the destination must not replace the new lifetime")
        #expect(model.activeDocument?.recoveryEpoch != epochBefore, "the fresh lifetime is retained")
        #expect(fixture.published.publications.isEmpty, "nothing is published on behalf of the retired lifetime")
        #expect(model.hasPendingRecoveryCleanup)
    }

    @Test func closingTheTabDuringTheContinuationPersistenceNeverPublishesTheDestination() async {
        let fixture = await makeFixture()
        defer { cleanup(fixture.directory) }
        let model = fixture.model
        model.afterRecoveryRetryPersistence = {
            model.tabStore.removeTab(at: 0)
        }

        await model.retryRecoveryCleanup()

        #expect(model.activeDocument?.fileURL != fixture.destination.fileURL, "the destination is not resurrected")
        #expect(fixture.published.publications.isEmpty)
    }
}
