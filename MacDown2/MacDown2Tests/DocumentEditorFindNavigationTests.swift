import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
import JSONSupport
@testable import MacDown2
import MarkdownEngine
import OutlineUI
import Preview
import SwiftUI
import Testing
import Themes
import Workspace

/// Regression coverage for the mounted editor's final async-find publication
/// guard. The coordinator-only test proves the revision changes; this test
/// calls the production `applyFindHighlights` method against a real mounted
/// `EditorView` and proves the guard protects the live selection.
@MainActor
@Suite("Document editor find navigation")
struct DocumentEditorFindNavigationTests {
    @Test func staleFindCompletionCannotMoveNewerFolderSearchSelection() async throws {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let model = coordinator.makeWindowModel()
        let text = "old result\nnew result"
        model.tabStore.newTab(document: FileDocument(text: text))
        let tab = try #require(model.tabStore.activeTab)
        let identity = tab.id.uuidString
        let editorStore = EditorTextSystemStore()
        let findStore = EditorFindModelStore()
        let parseStore = MarkdownParseStore(debounce: .zero)
        let jsonStore = JSONAnalysisStore(debounce: .zero)
        let split = DocumentEditorSplitView(
            model: model,
            document: tab.document,
            tab: tab,
            identity: identity,
            text: .constant(text),
            editorStore: editorStore,
            findStore: findStore,
            highlightStore: SyntaxHighlightStore(registry: GrammarRegistry()),
            parseStore: parseStore,
            jsonAnalysisStore: jsonStore,
            themeController: ThemeController(),
            scrollController: ScrollSyncController(),
            outlineController: OutlineController()
        )
        let hosting = NSHostingView(rootView: AnyView(
            EditorView(
                text: .constant(text),
                identity: identity,
                configuration: .default,
                store: editorStore
            )
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        defer { window.contentView = nil; window.close() }

        let staleModel = EditorFindModel(query: "old")
        staleModel.isActive = true
        #expect(await staleModel.updateMatches(in: text))
        let staleToken = coordinator.folderSearchNavigationDidChange()

        let currentModel = EditorFindModel(query: "new")
        currentModel.isActive = true
        #expect(await currentModel.updateMatches(in: text))
        let currentToken = coordinator.folderSearchNavigationDidChange()

        let system = try #require(editorStore.existingSystem(for: identity))
        #expect(system.textView.window === window)
        #expect(!system.isDetachedFromEditorView)
        split.applyFindHighlights(
            currentModel,
            navigationToken: currentToken,
            navigationCoordinator: coordinator
        )
        let selectedByCurrent = system.selectedRange
        #expect(selectedByCurrent == NSRange(location: 11, length: 3))
        #expect(system.textView.window === window)
        #expect(!system.isDetachedFromEditorView)
        split.applyFindHighlights(
            staleModel,
            navigationToken: staleToken,
            navigationCoordinator: coordinator
        )
        #expect(system.selectedRange == selectedByCurrent)
    }
}
