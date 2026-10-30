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
    @Test func aGrantedImageCopiesAsPNGAndLoadsAgainUnderANewDocumentGeneration() async throws {
        let (folder, imageBytes) = try makeFolderWithImage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = "MOUNTED_LEFT_519 ![fixture](image.png) MOUNTED_RIGHT_519"
        let parsed = try await ParseEngine().parse(source, revision: 1)
        var document = FileDocument(fileURL: folder.appendingPathComponent("story.md"), text: source)
        let owner = PreviewResourceWindowState()
        let tabID = UUID()
        owner.setCurrentPreviewDocument { (tabID, document) }
        try await installGrant(owner: owner, document: document, folder: folder)
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
        let pasteboard = try makePasteboardSession()
        defer {
            if NSPasteboard.general.changeCount == pasteboard.lastChangeCount {
                restorePasteboard(pasteboard.original)
            }
        }
        try await assertGrantedImageCopies(from: hosting, phase: "initial generation", pasteboard: pasteboard)

        document = document.updatingText(source).markClean()
        hosting.rootView = mountedView(
            document: document, parsed: parsed, tabID: tabID, owner: owner, recorder: recorder
        )
        hosting.layoutSubtreeIfNeeded()
        let second = try await waitForLoad(
            after: first, recorder: recorder, minimumRetained: initialInput + imageBytes.count
        )
        #expect(second != first)
        try await assertGrantedImageCopies(from: hosting, phase: "replacement generation", pasteboard: pasteboard)
        let revocation = RevocationContext(owner: owner, document: document, tabID: tabID,
                                           recorder: recorder, priorID: second)
        try await assertRevocationStopsCopy(from: hosting, context: revocation, pasteboard: pasteboard)
    }

    private func installGrant(
        owner: PreviewResourceWindowState,
        document: FileCore.FileDocument,
        folder: URL
    ) async throws {
        let documentURL = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: documentURL,
            folderURL: folder
        ))
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: origin) { document }
    }

    private func makePasteboardSession() throws -> PasteboardSession {
        let count = NSPasteboard.general.changeCount
        let original = snapshotPasteboard()
        try #require(NSPasteboard.general.changeCount == count,
                     "The pasteboard changed during snapshot; leave it untouched")
        return PasteboardSession(original: original, changeCount: count)
    }

    private func mountedView(
        document: FileCore.FileDocument, parsed: MarkdownDocument, tabID: UUID,
        owner: PreviewResourceWindowState,
        recorder: LoadIDRecorder
    ) -> some View {
        SecuredMarkdownResourceHost(
            tabID: tabID, document: document, sourceGeneration: document.mutationGeneration
        ) { loader, loadID in
            let renderingRevision = owner.revision
            return TextualMarkdownPreview(
                document: parsed, text: document.text,
                theme: PreviewTheme(theme: BundledThemes.light),
                resourceImageLoader: loader, resourceLoadID: loadID
            )
            .onAppear { recorder.record(loadID, revision: renderingRevision) }
            .onChange(of: loadID) { _, current in recorder.record(current, revision: renderingRevision) }
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

    private func copiedHTML(
        from view: NSView, pasteboard: PasteboardSession, deadline: ContinuousClock.Instant, phase: String
    ) async throws -> String {
        while ContinuousClock.now < deadline {
            for interaction in textInteractions(in: view) {
                let board = NSPasteboard.general
                guard board.changeCount == pasteboard.lastChangeCount else {
                    Issue.record("The general pasteboard changed outside this test; preserving the newer contents")
                    throw PreviewResourceAdmissionError.limitExceeded
                }
                _ = interaction.perform(NSSelectorFromString("selectAll:"), with: nil)
                _ = interaction.perform(NSSelectorFromString("copy:"), with: nil)
                let current = board.changeCount
                if current != pasteboard.lastChangeCount {
                    pasteboard.lastChangeCount = current
                    if let html = board.string(forType: .html),
                       html.contains("MOUNTED_LEFT_519"), html.contains("MOUNTED_RIGHT_519") {
                        return html
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The sentinel-bearing Textual block did not produce fresh native HTML in \(phase)")
        throw PreviewResourceAdmissionError.limitExceeded
    }

    private func assertGrantedImageCopies(
        from view: NSView, phase: String, pasteboard: PasteboardSession
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var lastHTML = ""
        while ContinuousClock.now < deadline {
            lastHTML = try await copiedHTML(from: view, pasteboard: pasteboard, deadline: deadline, phase: phase)
            if lastHTML.contains("data:image/png;base64,") {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Mounted Textual never copied its admitted image in \(phase); final HTML: \(lastHTML)")
    }

    private func assertRevocationStopsCopy(
        from view: NSView, context: RevocationContext, pasteboard: PasteboardSession
    ) async throws {
        let owner = context.owner
        let document = context.document
        let tabID = context.tabID
        let recorder = context.recorder
        let priorID = context.priorID
        let revision = owner.revision
        owner.invalidateForIdentityChange()
        #expect(owner.revision != revision)
        #expect(owner.beginPreviewLoad(
            for: document, tabID: tabID, sourceGeneration: document.mutationGeneration,
            grantRevision: owner.revision, consumer: .markdown
        ) == nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let revokedRevision = owner.revision
        while ContinuousClock.now < deadline,
              recorder.lastID == priorID || recorder.lastRevision != revokedRevision {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(recorder.lastID != nil && recorder.lastID != priorID && recorder.lastRevision == revokedRevision,
                     "Mounted host must acknowledge the revoked resource identity")
        var sawRevokedBlock = false
        while ContinuousClock.now < deadline {
            let html = try await copiedHTML(from: view, pasteboard: pasteboard, deadline: deadline, phase: "revocation")
            if !html.contains("data:image/png;base64,") {
                sawRevokedBlock = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(sawRevokedBlock, "The sentinel-bearing block must reflect revocation")
        try await Task.sleep(for: .milliseconds(250))
        let later = try await copiedHTML(from: view, pasteboard: pasteboard,
                                         deadline: .now.advanced(by: .seconds(5)), phase: "post-revocation dwell")
        #expect(!later.contains("data:image/png;base64,"), "The revoked image must not reappear")
    }

    private func textInteractions(in view: NSView) -> [NSView] {
        var found = NSStringFromClass(type(of: view)).hasSuffix(".NSTextInteractionView") ? [view] : []
        for child in view.subviews {
            found.append(contentsOf: textInteractions(in: child))
        }
        return found
    }

    private func snapshotPasteboard() -> [NSPasteboardItem] {
        NSPasteboard.general.pasteboardItems?.map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
    }

    private func restorePasteboard(_ items: [NSPasteboardItem]) {
        NSPasteboard.general.clearContents()
        if !items.isEmpty {
            _ = NSPasteboard.general.writeObjects(items)
        }
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
    private(set) var lastRevision: UUID?

    func record(_ id: UUID?, revision: UUID) {
        if let id {
            lastID = id
            lastRevision = revision
        }
    }
}

@MainActor
private final class PasteboardSession {
    let original: [NSPasteboardItem]
    var lastChangeCount: Int

    init(original: [NSPasteboardItem], changeCount: Int) {
        self.original = original
        lastChangeCount = changeCount
    }
}

@MainActor
private struct RevocationContext {
    let owner: PreviewResourceWindowState
    let document: FileCore.FileDocument
    let tabID: UUID
    let recorder: LoadIDRecorder
    let priorID: UUID
}
