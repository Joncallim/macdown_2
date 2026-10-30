import AppKit
import FileCore
import Foundation
@testable import MacDown2
import MarkdownEngine
import Preview
import SwiftUI
import Testing
import Themes

@Suite("Secured Markdown scroll retention", .serialized)
@MainActor
struct SecuredMarkdownScrollRetentionTests {
    enum Transition: Sendable {
        case edit, saveAs, saveAsWithLinks
    }

    @Test(arguments: [Transition.edit, .saveAs, .saveAsWithLinks])
    func aDocumentTransitionDoesNotCollapseUnchangedParagraphsAboveTheViewport(_ transition: Transition) async throws {
        var document = makeDocument(includeLinks: transition == .saveAsWithLinks)
        let source = document.text
        let parsed = try await ParseEngine().parse(source, revision: 1)
        let owner = PreviewResourceWindowState()
        let tabID = UUID()
        owner.setCurrentPreviewDocument { (tabID, document) }
        let controller = ScrollSyncController()
        let loads = ScrollLoadRecorder()
        let hosting = NSHostingView(rootView: preview(
            document, parsed: parsed, ownership: (tabID, owner), controller: controller, loads: loads
        ))
        let window = makeWindow(containing: hosting)
        defer {
            owner.close()
            window.orderOut(nil)
        }
        try await waitUntil {
            hosting.layoutSubtreeIfNeeded()
            return loads.lastID != nil && controller.blockHeights.count >= 120
                && (findScrollView(hosting)?.documentView?.frame.height ?? 0) > 6000
        }
        let scroll = try #require(findScrollView(hosting))
        let content = try #require(scroll.documentView)
        let requested = (content.frame.height - scroll.contentView.bounds.height) * 0.7
        scroll.contentView.scroll(to: CGPoint(x: 0, y: requested))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await waitUntil { scroll.contentView.bounds.minY > 2000 }
        try await Task.sleep(for: .milliseconds(200))
        let before = scroll.contentView.bounds.minY
        let priorLoad = try #require(loads.lastID)
        controller.targetSourceLine = nil

        document = changedDocument(document, for: transition)
        let edited = try await ParseEngine().parse(document.text, revision: 2)
        hosting.rootView = preview(
            document, parsed: edited, ownership: (tabID, owner), controller: controller, loads: loads
        )
        let minimumOffset = try await minimumOffsetDuringUpdate(in: hosting, scroll: scroll, initial: before)
        let currentLoad = try #require(loads.lastID)
        #expect(currentLoad != priorLoad, "A changed document must still receive a new resource lifetime")
        #expect(
            minimumOffset >= before - 1,
            "Unchanged text collapsed and clamped the preview from \(before) to \(minimumOffset)"
        )
        #expect(scroll.contentView.bounds.minY >= before - 1)
        #expect(controller.targetSourceLine != 1, "A geometry collapse must not masquerade as a user scroll to the top")
    }

    private func changedDocument(_ document: FileCore.FileDocument, for transition: Transition) -> FileCore
        .FileDocument {
        switch transition {
        case .edit: document.updatingText(document.text + " edited")
        case .saveAs,
             .saveAsWithLinks: document.renamed(to: URL(fileURLWithPath: "/tmp/secured-scroll-destination/story.md"))
        }
    }

    private func preview(
        _ document: FileCore.FileDocument, parsed: MarkdownDocument,
        ownership: (tabID: UUID, owner: PreviewResourceWindowState),
        controller: ScrollSyncController, loads: ScrollLoadRecorder
    ) -> some View {
        SecuredMarkdownResourceHost(
            tabID: ownership.tabID, document: document, sourceGeneration: document.mutationGeneration
        ) { loader, loadID in
            TextualMarkdownPreview(
                document: parsed, text: document.text,
                theme: PreviewTheme(theme: BundledThemes.light),
                linkResolver: PreviewLinkResolver(baseURL: document.fileURL), controller: controller,
                resourceImageLoader: loader, resourceLoadID: loadID
            )
            .onAppear { loads.lastID = loadID }
            .onChange(of: loadID) { _, current in loads.lastID = current }
        }
        .environment(\.previewResourceWindowState, ownership.owner)
    }

    private func minimumOffsetDuringUpdate(in view: NSView, scroll: NSScrollView,
                                           initial: CGFloat) async throws -> CGFloat {
        var minimumOffset = initial
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline {
            view.layoutSubtreeIfNeeded()
            minimumOffset = min(minimumOffset, scroll.contentView.bounds.minY)
            try await Task.sleep(for: .milliseconds(10))
        }
        return minimumOffset
    }

    private func makeDocument(includeLinks: Bool) -> FileCore.FileDocument {
        let source = (1 ... 120).map {
            "Paragraph \($0): ordinary preview text that remains unchanged while another paragraph is edited."
                + (includeLinks ? " [related](related.md)" : "")
        }.joined(separator: "\n\n")
        return FileDocument(fileURL: URL(fileURLWithPath: "/tmp/secured-scroll-fixture/story.md"), text: source)
    }

    private func makeWindow(containing view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Mounted preview did not reach the required scrollable state")
        throw CancellationError()
    }

    private func findScrollView(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView {
            return scroll
        }
        for child in view.subviews {
            if let found = findScrollView(child) {
                return found
            }
        }
        return nil
    }
}

@MainActor
private final class ScrollLoadRecorder {
    var lastID: UUID?
}
