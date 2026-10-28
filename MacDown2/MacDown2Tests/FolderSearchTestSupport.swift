import AppKit
import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Preview
import SwiftUI
import Testing
import Themes
import Workspace

/// Suspends a coordinator test hook until the test releases it, and reports
/// when the hook was entered. Shared by the folder-search suites.
final class FolderSearchGate: @unchecked Sendable {
    let entered: AsyncStream<Void>
    private let enteredContinuation: AsyncStream<Void>.Continuation
    private let releaseStream: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init() {
        (entered, enteredContinuation) = AsyncStream<Void>.makeStream()
        (releaseStream, releaseContinuation) = AsyncStream<Void>.makeStream()
    }

    func wait() async {
        enteredContinuation.yield(())
        var iterator = releaseStream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        releaseContinuation.yield(())
        releaseContinuation.finish()
        enteredContinuation.finish()
    }

    static func waitForEntry(
        _ stream: AsyncStream<Void>,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}

@MainActor
enum FolderSearchTestSupport {
    static func makeCoordinator() -> WindowCoordinator {
        let preferences = FileTreePreferences()
        return WindowCoordinator(
            recoveryBuffer: RecoveryBuffer(recoveryDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)),
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
    }

    /// A split view over `controller`'s own stores, as the window builds it
    /// for `tab`.
    static func makeSplit(
        controller: WindowController,
        tab: WorkspaceTab,
        text: String
    ) -> DocumentEditorSplitView {
        DocumentEditorSplitView(
            model: controller.model,
            document: tab.document,
            tab: tab,
            identity: tab.id.uuidString,
            text: .constant(text),
            editorStore: controller.editorStore,
            findStore: controller.findStore,
            highlightStore: controller.highlightStore,
            parseStore: controller.parseStore,
            jsonAnalysisStore: controller.jsonAnalysisStore,
            themeController: controller.themeController,
            scrollController: ScrollSyncController(),
            outlineController: controller.outlineController
        )
    }
}
