import FileCore
import Foundation
@testable import MacDown2
import Testing

@Suite("Preview window resource ownership")
@MainActor
struct PreviewResourceWindowStateTests {
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

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
