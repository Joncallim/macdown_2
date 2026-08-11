@testable import FileCore
import Foundation
import Testing

@Suite("FileStore conditional publication")
struct FileStoreConditionalPublicationTests {
    @Test func displacedReadFailureRollsBackAndKeepsTheBaseline() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store = FileStore(
            conditionalPublicationHooks: ConditionalPublicationTestHooks(
                beforeDisplacedRead: { _ in throw POSIXError(.EIO) }
            )
        )
        let dirty = try FileDocument(fileURL: fixture.url, fileStore: store)
            .load()
            .edited(text: "ours")

        #expect(throws: FileStoreError.self) {
            _ = try dirty.save()
        }
        #expect(try FileStore().read(from: fixture.url).content == "baseline")
    }

    @Test func rollbackFailurePreservesTheDisplacedExternalVersionForRecovery() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store = FileStore(
            afterBaselineVerification: { url in
                try Data("external winner".utf8).write(to: url, options: .atomic)
            },
            conditionalPublicationHooks: ConditionalPublicationTestHooks(
                beforeRollbackSwap: { _, _ in throw POSIXError(.EIO) }
            )
        )
        let dirty = try FileDocument(fileURL: fixture.url, fileStore: store)
            .load()
            .edited(text: "ours")

        do {
            _ = try dirty.save()
            Issue.record("Expected recovery-required error after the injected rollback failure")
        } catch let .conditionalPublicationRecoveryRequired(recoveryURL) {
            #expect(try String(contentsOf: recoveryURL, encoding: .utf8) == "external winner")
            #expect(FileManager.default.fileExists(atPath: recoveryURL.path))
        } catch {
            Issue.record("Expected conditionalPublicationRecoveryRequired, got \(error)")
        }

        #expect(try FileStore().read(from: fixture.url).content == "ours")
    }

    @Test func sameByteReplacementWithANewObjectIdentityIsRolledBack() throws {
        let fixture = try FixtureFile(text: "same bytes")
        let baseline = try FileStore().readSnapshot(from: fixture.url).revision
        let store = FileStore(afterBaselineVerification: { url in
            try Data("same bytes".utf8).write(to: url, options: .atomic)
        })
        let dirty = try FileDocument(fileURL: fixture.url, fileStore: store)
            .load()
            .edited(text: "ours")

        #expect(throws: FileStoreError.self) {
            _ = try dirty.save()
        }
        let external = try FileStore().readSnapshot(from: fixture.url)
        #expect(external.text == "same bytes")
        #expect(external.revision.fileObjectID != baseline.fileObjectID)
    }

    @Test func directWriterBeforeRollbackSwapIsPreservedForRecovery() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store = FileStore(
            afterBaselineVerification: { url in
                try Data("first external".utf8).write(to: url, options: .atomic)
            },
            conditionalPublicationHooks: ConditionalPublicationTestHooks(
                beforeRollbackSwap: { _, destination in
                    try Data("newer external".utf8).write(to: destination, options: .atomic)
                }
            )
        )
        let dirty = try FileDocument(fileURL: fixture.url, fileStore: store)
            .load()
            .edited(text: "ours")

        do {
            _ = try dirty.save()
            Issue.record("Expected recovery-required error after a competing rollback write")
        } catch let .conditionalPublicationRecoveryRequired(recoveryURL) {
            #expect(try String(contentsOf: recoveryURL, encoding: .utf8) == "newer external")
        } catch {
            Issue.record("Expected conditionalPublicationRecoveryRequired, got \(error)")
        }

        #expect(try FileStore().read(from: fixture.url).content == "first external")
    }
}
