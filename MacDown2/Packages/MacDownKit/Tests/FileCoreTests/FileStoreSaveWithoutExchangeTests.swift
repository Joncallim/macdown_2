@testable import FileCore
import Foundation
import Testing

/// Review pass 1: Save onto an existing file always failed on volumes whose
/// `renameatx_np(RENAME_SWAP)` returns ENOTSUP (exFAT/FAT32 sticks and cards,
/// many network shares) — the conditional publication had no fallback.
@Suite("FileStore save without RENAME_SWAP")
struct FileStoreSaveWithoutExchangeTests {
    private let noExchange = ConditionalPublicationTestHooks(simulateSwapUnsupported: true)

    @Test func saveSucceedsWhenTheVolumeCannotExchange() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store = FileStore(conditionalPublicationHooks: noExchange)
        let dirty = try FileDocument(fileURL: fixture.url, fileStore: store).load().edited(text: "ours")

        let saved = try dirty.save()

        #expect(try FileStore().read(from: fixture.url).content == "ours")
        #expect(saved.state == .clean)
    }

    @Test func aStaleBaselineIsStillRefusedWithoutExchange() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store = FileStore(conditionalPublicationHooks: noExchange)
        let dirty = try FileDocument(fileURL: fixture.url, fileStore: store).load().edited(text: "ours")
        try Data("external change".utf8).write(to: fixture.url, options: .atomic)

        #expect(throws: FileStoreError.self) {
            _ = try dirty.save()
        }
        #expect(try FileStore().read(from: fixture.url).content == "external change")
    }

    @Test func permissionsAreStillCarriedWithoutExchange() throws {
        let fixture = try FixtureFile(text: "baseline")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.url.path)
        let store = FileStore(conditionalPublicationHooks: noExchange)
        let dirty = try FileDocument(fileURL: fixture.url, fileStore: store).load().edited(text: "ours")

        _ = try dirty.save()

        let mode = try #require(FileManager.default
            .attributesOfItem(atPath: fixture.url.path)[.posixPermissions] as? Int)
        #expect(mode & 0o777 == 0o600)
    }
}
