import FileCore
import Foundation
import Testing
@testable import Workspace

/// Review pass 1: a dirty tab restored after a relaunch adopted the file's
/// CURRENT bytes as its baseline, so a change made while the app was quit (a
/// `git pull`, a sync) was silently overwritten by the first Save.
@MainActor
struct RestoredDirtyTabExternalChangeTests {
    private func restore(modifyFileAfterQuit modification: ((URL) throws -> Void)?) async throws -> FileDocument {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let url = directory.appendingPathComponent("notes.md")
        try "disk v1".write(to: url, atomically: true, encoding: .utf8)

        let loaded = try await FileDocument.create(fileURL: url, recoveryBuffer: recovery).load()
        let dirty = loaded.updatingText("my unsaved edit")
        #expect(await dirty.persistRecovery())
        let record = TabRecord(
            id: UUID(),
            fileURL: url,
            documentRecoveryEpoch: dirty.recoveryEpoch,
            baseSHA256: dirty.lastKnownRevision?.sha256
        )

        try modification?(url) // while the app is "quit"

        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let tab = try #require(await store.restoreTab(from: record))
        return tab.document
    }

    @Test func aFileChangedWhileTheAppWasQuitComesBackAsAConflictWithTheUnsavedTextIntact() async throws {
        let document = try await restore { try "disk v2 (pulled)".write(to: $0, atomically: true, encoding: .utf8) }

        #expect(document.state == .conflict)
        #expect(document.text == "my unsaved edit")
        #expect(document.pendingExternalRevision != nil)
    }

    @Test func anUnchangedFileStillRestoresAsPlainDirty() async throws {
        let document = try await restore(modifyFileAfterQuit: nil)

        #expect(document.state == .dirty)
        #expect(document.text == "my unsaved edit")
    }

    @Test func aSessionWithoutABaselineKeepsTheOldBehaviour() async throws {
        let document = try await {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
            let url = directory.appendingPathComponent("a.md")
            try "v1".write(to: url, atomically: true, encoding: .utf8)
            let dirty = try await FileDocument.create(fileURL: url, recoveryBuffer: recovery).load()
                .updatingText("edit")
            #expect(await dirty.persistRecovery())
            try "v2".write(to: url, atomically: true, encoding: .utf8)
            let record = TabRecord(id: UUID(), fileURL: url, documentRecoveryEpoch: dirty.recoveryEpoch)
            let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
            return try #require(await store.restoreTab(from: record)).document
        }()

        #expect(document.state == .dirty)
    }
}
