import AppKit
import FileCore
import Foundation
import LocalResourceAccess
@testable import MacDown2
import MarkdownEngine
import Preview
import SwiftUI
import Testing
import Themes

/// The temporary fixture is selected through the test-only receipt; no native panel or persistent grant is used.
@Suite("Secured Markdown mounted attachment", .serialized)
@MainActor
struct SecuredMarkdownMountedTests {
    @Test func anUnchangedImageReferenceLoadsAgainUnderANewDocumentGeneration() async throws {
        let (folder, imageBytes) = try makeFolderWithImage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = "![fixture](image.png)"
        let parsed = try await ParseEngine().parse(source, revision: 1)
        var document = FileDocument(fileURL: folder.appendingPathComponent("story.md"), text: source)
        let owner = PreviewResourceWindowState()
        let tabID = UUID()
        owner.setCurrentPreviewDocument { (tabID, document) }
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL, folderURL: folder
        ))
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: origin) { document }
        let recorder = LoadIDRecorder()
        let initialInput = await PreviewResourceAdmission.shared.globalStatus().retained
        let hosting = NSHostingView(rootView: mountedView(
            document: document, parsed: parsed, tabID: tabID, owner: owner, recorder: recorder
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer {
            owner.close()
            window.orderOut(nil)
        }
        hosting.layoutSubtreeIfNeeded()
        let first = try await waitForLoad(
            after: nil,
            recorder: recorder,
            minimumRetained: initialInput + imageBytes.count
        )

        document = document.updatingText(source).markClean()
        hosting.rootView = mountedView(
            document: document, parsed: parsed, tabID: tabID, owner: owner, recorder: recorder
        )
        hosting.layoutSubtreeIfNeeded()
        let second = try await waitForLoad(
            after: first, recorder: recorder, minimumRetained: initialInput + imageBytes.count
        )
        #expect(second != first)
        owner.invalidateForIdentityChange()
        #expect(owner.beginPreviewLoad(
            for: document, tabID: tabID, sourceGeneration: document.mutationGeneration,
            grantRevision: owner.revision, consumer: .markdown
        ) == nil)
    }

    private func mountedView(
        document: FileCore.FileDocument, parsed: MarkdownDocument, tabID: UUID,
        owner: PreviewResourceWindowState,
        recorder: LoadIDRecorder
    ) -> some View {
        SecuredMarkdownResourceHost(
            tabID: tabID, document: document, sourceGeneration: document.mutationGeneration
        ) { loader, loadID in
            TextualMarkdownPreview(
                document: parsed, text: document.text,
                theme: PreviewTheme(theme: BundledThemes.light),
                resourceImageLoader: loader, resourceLoadID: loadID
            )
            .onAppear { recorder.record(loadID) }
        }
        .environment(\.previewResourceWindowState, owner)
    }

    private func waitForLoad(
        after prior: UUID?, recorder: LoadIDRecorder, minimumRetained: Int
    ) async throws -> UUID {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let current = recorder.lastID, current != prior,
               await PreviewResourceAdmission.shared.globalStatus().retained >= minimumRetained {
                return current
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Mounted Textual did not admit the expected document-bound image")
        throw PreviewResourceAdmissionError.limitExceeded
    }

    private func smallPNG() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func makeFolderWithImage() throws -> (URL, Data) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let bytes = try smallPNG()
            try bytes.write(to: folder.appendingPathComponent("image.png"))
            return (folder, bytes)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}

@MainActor
private final class LoadIDRecorder {
    private(set) var lastID: UUID?

    func record(_ id: UUID?) {
        if let id {
            lastID = id
        }
    }
}
