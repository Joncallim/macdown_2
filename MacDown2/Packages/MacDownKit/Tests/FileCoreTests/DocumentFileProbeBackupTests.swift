@testable import FileCore
import Foundation
import Testing

/// Review pass 1: `perl -pi.bak`, Emacs' backup-by-rename, or `mv foo.md foo.md.bak`
/// followed by recreating `foo.md` made the probe report the document as MOVED to the
/// backup — retitling the window and sending the next Save into the `.bak`.
struct DocumentFileProbeBackupTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func aBackupMadeByRenamingAndRecreatingTheFileIsNotAMove() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("foo.md")
        try "old".write(to: url, atomically: true, encoding: .utf8)
        let prior = try FileStore().readSnapshot(from: url).revision.fileObjectID

        let backup = directory.appendingPathComponent("foo.md.bak")
        try FileManager.default.moveItem(at: url, to: backup)
        try "new".write(to: url, atomically: true, encoding: .utf8)

        let observation = await DocumentFileProbe().observe(expectedURL: url, priorFileObjectID: prior)

        guard case let .available(snapshot) = observation else {
            Issue.record("expected the recreated file to be the document, got \(observation)")
            return
        }
        #expect(snapshot.text == "new")
        #expect(snapshot.revision.url.lastPathComponent == "foo.md")
    }

    @Test func aFileThatReallyMovedAwayIsStillFollowed() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("foo.md")
        try "text".write(to: url, atomically: true, encoding: .utf8)
        let prior = try FileStore().readSnapshot(from: url).revision.fileObjectID
        let moved = directory.appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: url, to: moved)

        let observation = await DocumentFileProbe().observe(expectedURL: url, priorFileObjectID: prior)

        #expect(try observation == .moved(FileStore().readSnapshot(from: moved)))
    }
}
