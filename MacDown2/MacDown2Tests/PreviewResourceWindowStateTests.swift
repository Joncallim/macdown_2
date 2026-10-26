import FileCore
import Foundation
@testable import MacDown2
import Testing

@Suite("Preview window resource ownership")
@MainActor
struct PreviewResourceWindowStateTests {
    @Test func absentGrantDeniesBothResourceConsumers() {
        let document = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/story.md"))
        let owner = PreviewResourceWindowState()
        #expect(owner.beginLoad(for: document, consumer: .markdown) == nil)
        #expect(owner.beginLoad(for: document, consumer: .html) == nil)
        owner.close()
    }

    @Test func closingWindowRevokesBothConsumersAndItsBacking() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"))
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let owner = PreviewResourceWindowState()
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: origin) { document }
        let markdown = try #require(owner.beginLoad(for: document, consumer: .markdown))
        let html = try #require(owner.beginLoad(for: document, consumer: .html))
        #expect(markdown.id != html.id)

        owner.close()
        #expect(markdown.isRevoked)
        #expect(html.isRevoked)
        #expect(markdown.acquireUse() == nil)
        #expect(html.acquireUse() == nil)
        #expect(owner.beginLoad(for: document, consumer: .markdown) == nil)
    }

    @Test func switchedDocumentRejectsAnAwaitingFolderSelection() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"))
        let other = FileDocument(fileURL: folder.appendingPathComponent("other.md"))
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let owner = PreviewResourceWindowState()
        let origin = try #require(owner.beginSelection(for: document))
        var reads = 0
        await #expect(throws: PreviewResourceAdmissionError.revoked) {
            try await owner.install(selection, from: origin) {
                reads += 1
                return reads == 1 ? document : other
            }
        }
        #expect(owner.beginLoad(for: document, consumer: .markdown) == nil)
    }

    @Test func observedAwayAndBackCannotReusePendingSelection() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"))
        let other = FileDocument(fileURL: folder.appendingPathComponent("other.md"))
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let owner = PreviewResourceWindowState()
        let origin = try #require(owner.beginSelection(for: document))
        owner.reconcile(with: other)
        owner.reconcile(with: document)
        await #expect(throws: PreviewResourceAdmissionError.revoked) {
            try await owner.install(selection, from: origin) { document }
        }
    }

    @Test func delayedOldMarkdownTaskCannotRetireTheNewGeneration() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.md"))
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let owner = PreviewResourceWindowState()
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: origin) { document }
        let tabID = UUID()
        var liveDocument = document
        owner.setCurrentPreviewDocument { (tabID, liveDocument) }
        let oldRevision = owner.revision
        let old = try #require(owner.beginPreviewLoad(
            for: document, tabID: tabID,
            sourceGeneration: document.mutationGeneration, grantRevision: oldRevision,
            consumer: .markdown
        ))
        liveDocument = document.markClean()
        let current = try #require(owner.beginPreviewLoad(
            for: liveDocument, tabID: tabID,
            sourceGeneration: liveDocument.mutationGeneration, grantRevision: owner.revision,
            consumer: .markdown
        ))
        #expect(old.isRevoked)
        #expect(owner.beginPreviewLoad(
            for: document, tabID: tabID,
            sourceGeneration: document.mutationGeneration, grantRevision: oldRevision,
            consumer: .markdown
        ) == nil)
        #expect(!current.isRevoked)
        owner.retire(.markdown, matching: old)
        #expect(!current.isRevoked)
        owner.close()
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
