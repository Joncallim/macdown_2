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

/// #183 F05 — a same-tab Save As that moves a document into a format with a
/// parser (unchanged text) must start that format's initial analysis.
@MainActor
@Suite("Format change starts analysis (#183 F05)")
struct FormatChangeAnalysisMountTests {
    private struct Harness {
        let hosting: NSHostingView<AnyView>
        let window: NSWindow
        let parseStore: MarkdownParseStore
        let jsonStore: JSONAnalysisStore
        let identity: String
        let model: WorkspaceModel
        let tab: WorkspaceTab
        let text: String
    }

    private func makeView(
        _ harness: Harness,
        format: FileFormat,
        coordinator: WindowCoordinator
    ) -> AnyView {
        let document = FileDocument(
            fileURL: URL(fileURLWithPath: "/tmp/format-change.\(format.extensions[0])"),
            text: harness.text
        )
        let stores = (
            EditorTextSystemStore(),
            EditorFindModelStore(),
            SyntaxHighlightStore(registry: GrammarRegistry())
        )
        return AnyView(
            DocumentEditorSplitView(
                model: harness.model,
                document: document,
                tab: harness.tab,
                identity: harness.identity,
                text: .constant(harness.text),
                editorStore: stores.0,
                findStore: stores.1,
                highlightStore: stores.2,
                parseStore: harness.parseStore,
                jsonAnalysisStore: harness.jsonStore,
                themeController: ThemeController(),
                scrollController: ScrollSyncController(),
                outlineController: OutlineController()
            )
            .environment(\.windowCoordinator, coordinator)
        )
    }

    private func pump(until condition: () -> Bool, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func movingUnchangedTextIntoJSONStartsJSONAnalysis() async throws {
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
        let text = #"{"a": 1}"#
        model.tabStore.newTab(document: FileDocument(text: text))
        let tab = try #require(model.tabStore.activeTab)
        let formats = FileFormatRegistry.defaultFormats
        let plain = try #require(formats.first { $0.id == "plaintext" })
        let json = try #require(formats.first { $0.id == "json" })
        let harness = Harness(
            hosting: NSHostingView(rootView: AnyView(EmptyView())),
            window: NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            ),
            parseStore: MarkdownParseStore(debounce: .milliseconds(1)),
            jsonStore: JSONAnalysisStore(debounce: .milliseconds(1)),
            identity: tab.id.uuidString,
            model: model,
            tab: tab,
            text: text
        )
        harness.window.contentView = harness.hosting
        harness.window.makeKeyAndOrderFront(nil)
        defer { harness.window.orderOut(nil) }

        harness.hosting.rootView = makeView(harness, format: plain, coordinator: coordinator)
        harness.hosting.layoutSubtreeIfNeeded()
        await pump(until: { false }, timeout: 0.5)
        #expect(harness.jsonStore.existingSession(for: harness.identity)?.result == nil)

        harness.hosting.rootView = makeView(harness, format: json, coordinator: coordinator)
        harness.hosting.layoutSubtreeIfNeeded()
        await pump(until: { harness.jsonStore.existingSession(for: harness.identity)?.result != nil })

        #expect(harness.jsonStore.existingSession(for: harness.identity)?.result?.isValid == true)
    }
}
