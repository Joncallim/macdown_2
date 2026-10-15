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

@MainActor
@Suite("WindowCoordinator folder-search cancellation")
struct WindowCoordinatorFolderSearchCancellationTests {
    private final class Gate: @unchecked Sendable {
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

    private func makeCoordinator() -> WindowCoordinator {
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

    @Test func falseBeforeSerializedAdmissionDoesNotOpenOrCreateAController() async throws {
        let coordinator = makeCoordinator()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        await coordinator.openDocument(at: url, shouldContinue: { false })

        #expect(coordinator.controllers.isEmpty)
    }

    @Test func falseAfterFileLoadDoesNotPublishAWindow() async throws {
        let coordinator = makeCoordinator()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        var checks = 0
        var reachedFileLoad = false
        coordinator.afterFolderSearchFileLoad = { reachedFileLoad = true }

        await coordinator.openDocument(at: url, shouldContinue: {
            checks += 1
            return checks <= 2
        })

        #expect(reachedFileLoad)
        #expect(checks == 3)
        #expect(coordinator.controllers.isEmpty)
    }

    @Test func falseAfterRootRebuildDoesNotPublishAWindow() async throws {
        let coordinator = makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("rooted.md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        var reachedRootRebuild = false
        coordinator.afterFolderSearchRootRebuild = { reachedRootRebuild = true }
        var checks = 0

        await coordinator.openDocument(at: url, folderRoot: root, folderAccessURL: root, shouldContinue: {
            checks += 1
            return checks <= 3
        })

        #expect(reachedRootRebuild)
        #expect(checks == 4)
        #expect(coordinator.controllers.isEmpty)
    }

    @Test func nilContinuationKeepsOrdinaryOpenBehavior() async throws {
        let coordinator = makeCoordinator()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer {
            coordinator.controllers.last?.close()
            try? FileManager.default.removeItem(at: url)
        }

        await coordinator.openDocument(at: url)

        #expect(coordinator.controllers.count == 1)
        #expect(coordinator.controllers.first?.model.activeDocument?.fileURL?.standardizedFileURL
            == url.standardizedFileURL)
    }

    @Test func ordinaryOpenCanRefocusAHiddenLiveWindow() async throws {
        let coordinator = makeCoordinator()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer {
            coordinator.controllers.last?.close()
            try? FileManager.default.removeItem(at: url)
        }

        await coordinator.openDocument(at: url)
        let controller = try #require(coordinator.controllers.first)
        controller.window?.orderOut(nil)
        #expect(controller.window?.isVisible == false)

        await coordinator.openDocument(at: url)

        #expect(coordinator.controllers.count == 1)
        #expect(controller.window?.isVisible == true)
    }

    @Test func cancelledFolderSearchDoesNotPublishAfterRootRebuild() async throws {
        let coordinator = makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("result.md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let gate = Gate()
        coordinator.afterFolderSearchRootRebuild = {
            await gate.wait()
        }
        let task = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "result.md",
                root: root,
                folderAccessURL: root,
                range: NSRange(location: 0, length: 6)
            )
        }

        // The real folder-open path can spend several seconds rebuilding its
        // root before reaching this deliberate suspension point. The gate's
        // buffered entry stream is retained by `gate`, so waiting here cannot
        // lose the signal even when the callback fires before iteration starts.
        let entered = await Gate.waitForEntry(gate.entered, timeout: .seconds(10))
        task.cancel()
        gate.release()
        await task.value

        #expect(entered)
        #expect(coordinator.controllers.isEmpty)
    }

    @Test func newerNavigationDuringFileLoadDoesNotPublishFolderSearchResult() async throws {
        let coordinator = makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "needle".write(to: root.appendingPathComponent("result.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        var reachedFileLoad = false
        coordinator.afterFolderSearchFileLoad = {
            reachedFileLoad = true
            coordinator.folderSearchNavigationDidChange()
        }

        await coordinator.openFolderSearchResult(
            relativePath: "result.md",
            root: root,
            folderAccessURL: root,
            range: NSRange(location: 0, length: 6)
        )

        #expect(reachedFileLoad)
        #expect(coordinator.controllers.isEmpty)
        #expect(coordinator.pendingFolderSearchReveals.isEmpty)
    }

    @Test func olderFindCompletionTokenCannotInvalidateNewerFolderSearch() async throws {
        let coordinator = makeCoordinator()
        let olderFindToken = coordinator.folderSearchNavigationDidChange()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "prefix needle suffix".write(
            to: root.appendingPathComponent("result.md"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: root)
        }
        var folderSearchStarted = false
        coordinator.afterFolderSearchFileLoad = {
            folderSearchStarted = true
            #expect(!coordinator.folderSearchNavigationIsCurrent(olderFindToken))
        }
        defer { coordinator.afterFolderSearchFileLoad = nil }

        await coordinator.openFolderSearchResult(
            relativePath: "result.md",
            root: root,
            folderAccessURL: root,
            range: NSRange(location: 7, length: 6)
        )

        #expect(!coordinator.folderSearchNavigationIsCurrent(olderFindToken))
        #expect(folderSearchStarted)
        let controller = try #require(coordinator.controllers.first)
        let activeTabID = try #require(controller.model.tabStore.activeTab?.id.uuidString)
        let system = try #require(controller.editorStore.existingSystem(for: activeTabID))
        #expect(system.selectedRange == NSRange(location: 7, length: 6))
    }

    @Test func newerNavigationSurvivesActualPreviewOnlyToEditorMount() async throws {
        let coordinator = makeCoordinator()
        let preferences = FileTreePreferences()
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: "line one\nline two\nline three"))
        let tabID = try #require(model.tabStore.activeTab?.id)
        model.tabStore.setPreviewLayout(.previewOnly, for: tabID)
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        controller.window?.makeKeyAndOrderFront(nil)
        defer {
            coordinator.removeController(controller)
            controller.close()
        }

        let findModel = controller.findStore.model(for: tabID.uuidString)
        findModel.query = "line"
        let previewSystem = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        findModel.isActive = true
        findModel.pendingRevealNavigationToken = coordinator.folderSearchNavigationDidChange()
        #expect(findModel.pendingRevealNavigationToken != nil)

        let generation = coordinator.folderSearchRequestGate.begin()
        coordinator.pendingFolderSearchReveals[tabID] = PendingFolderSearchReveal(
            generation: generation,
            navigationRevision: coordinator.folderSearchNavigationRevision,
            range: NSRange(location: 2, length: 0),
            controllerID: ObjectIdentifier(controller)
        )
        let mounted = AsyncStream<Void>.makeStream()
        coordinator.afterFolderSearchEditorLayoutChange = {
            mounted.continuation.yield(())
        }
        defer {
            coordinator.afterFolderSearchEditorLayoutChange = nil
        }
        let panel = GoToLinePanel(coordinator: coordinator, originController: controller)
        panel.jump(to: "2")
        #expect(coordinator.pendingFolderSearchReveals[tabID] == nil)

        model.tabStore.setPreviewLayout(.split(fraction: 0.5), for: tabID)
        #expect(await Gate.waitForEntry(mounted.stream))

        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        #expect(system === previewSystem)
        #expect(!system.isDetachedFromEditorView)
        #expect(system.selectedRange == NSRange(location: 9, length: 0))
        #expect(coordinator.pendingFolderSearchReveals[tabID] == nil)
        #expect(findModel.pendingRevealNavigationToken == nil)
    }

    @Test func newerFolderSearchSupersedesOlderResult() async throws {
        let coordinator = makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "one".write(to: root.appendingPathComponent("one.md"), atomically: true, encoding: .utf8)
        try "two".write(to: root.appendingPathComponent("two.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let olderGate = Gate()
        let newerGate = Gate()
        var calls = 0
        coordinator.afterFolderSearchFileLoad = {
            calls += 1
            if calls == 1 {
                await olderGate.wait()
            } else {
                await newerGate.wait()
            }
        }
        let older = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "one.md", root: root, folderAccessURL: root,
                range: NSRange(location: 0, length: 3)
            )
        }
        #expect(await Gate.waitForEntry(olderGate.entered))
        let newer = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "two.md", root: root, folderAccessURL: root,
                range: NSRange(location: 0, length: 3)
            )
        }
        #expect(await Gate.waitForEntry(newerGate.entered))
        newerGate.release()
        olderGate.release()
        await older.value
        await newer.value

        #expect(coordinator.controllers.count == 1)
        #expect(coordinator.controllers.first?.model.activeDocument?.fileURL?.lastPathComponent == "two.md")
    }

    @Test func queuedFolderSearchCancellationDoesNotDisturbAnAdmittedOrdinaryOpen() async throws {
        let coordinator = makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("one.md")
        try "one".write(to: url, atomically: true, encoding: .utf8)
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: root)
        }

        let blockerGate = Gate()
        var fileLoadCalls = 0
        coordinator.afterFolderSearchFileLoad = {
            fileLoadCalls += 1
            if fileLoadCalls == 1 {
                await blockerGate.wait()
            }
        }

        let ordinaryOpen = Task {
            await coordinator.openDocument(at: url, folderRoot: root, folderAccessURL: root, shouldContinue: { true })
        }
        #expect(await Gate.waitForEntry(blockerGate.entered))

        var rootRebuildCalls = 0
        let queuedAdmission = AsyncStream<Void>.makeStream()
        coordinator.documentOpens.onEnqueue = {
            queuedAdmission.continuation.yield(())
        }
        coordinator.afterFolderSearchRootRebuild = {
            rootRebuildCalls += 1
        }
        let queuedSearch = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "one.md", root: root, folderAccessURL: root,
                range: NSRange(location: 0, length: 3)
            )
        }

        #expect(await Gate.waitForEntry(queuedAdmission.stream))
        // The ordinary open owns this file's serial key. The admitted request is
        // queued behind it, and cancellation must prevent any later navigation.
        queuedSearch.cancel()
        blockerGate.release()
        await ordinaryOpen.value
        await queuedSearch.value

        #expect(coordinator.controllers.count == 1)
        #expect(coordinator.controllers.first?.model.activeDocument?.fileURL?.lastPathComponent == "one.md")
        #expect(rootRebuildCalls == 1)
    }

    @Test func closingExistingWindowDuringRootAwaitCannotRefocusIt() async throws {
        let coordinator = makeCoordinator()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: root)
        }

        await coordinator.openDocument(at: url)
        let controller = try #require(coordinator.controllers.first)
        let gate = Gate()
        controller.beforeRootRebuild = { await gate.wait() }

        let task = Task {
            await coordinator.openDocument(
                at: url,
                folderRoot: root,
                folderAccessURL: root,
                shouldContinue: { true }
            )
        }
        #expect(await Gate.waitForEntry(gate.entered))
        coordinator.removeController(controller)
        controller.close()
        gate.release()
        await task.value

        #expect(!coordinator.controllers.contains { $0 === controller })
        #expect(controller.isClosed)
    }

    @Test func pendingFolderSearchRevealDrainsIntoTheMountedEditorSelection() async throws {
        let coordinator = makeCoordinator()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: url)
        }

        await coordinator.openDocument(at: url)
        let controller = try #require(coordinator.controllers.first)
        let tabID = try #require(controller.model.tabStore.tabID(forFileURL: url))
        let generation = coordinator.folderSearchRequestGate.begin()
        coordinator.pendingFolderSearchReveals[tabID] = PendingFolderSearchReveal(
            generation: generation,
            navigationRevision: coordinator.folderSearchNavigationRevision,
            range: NSRange(location: 2, length: 0),
            controllerID: ObjectIdentifier(controller)
        )
        controller.window?.makeKeyAndOrderFront(nil)

        coordinator.folderSearchEditorLayoutChanged(tabID: tabID.uuidString)

        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        #expect(system.selectedRange == NSRange(location: 2, length: 0))
        #expect(coordinator.pendingFolderSearchReveals[tabID] == nil)
    }

    @Test func selectAllMatchesInvalidatesSuspendedExistingWindowFolderSearch() async throws {
        let coordinator = makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("result.md")
        let text = "cat one cat"
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: root)
        }

        await coordinator.openDocument(at: url)
        let controller = try #require(coordinator.controllers.first)
        let tab = try #require(controller.model.tabStore.activeTab)
        let identity = tab.id.uuidString
        let system = try #require(controller.editorStore.existingSystem(for: identity))
        controller.window?.makeKeyAndOrderFront(nil)
        #expect(system.textView.window === controller.window)

        let findModel = controller.findStore.model(for: identity)
        findModel.query = "cat"
        findModel.isActive = true
        #expect(await findModel.updateMatches(in: text, preferringLocationNear: 0))
        let selection = try #require(findModel.selectionSetForAllMatches)
        #expect(selection.isMultiple)

        let split = DocumentEditorSplitView(
            model: controller.model,
            document: tab.document,
            tab: tab,
            identity: identity,
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

        let gate = Gate()
        controller.beforeRootRebuild = { await gate.wait() }
        defer { controller.beforeRootRebuild = nil }
        let folderOpen = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "result.md",
                root: root,
                folderAccessURL: root,
                range: NSRange(location: 0, length: 3)
            )
        }
        #expect(await Gate.waitForEntry(gate.entered))

        // Exercise the production Select All Matches application path while
        // the older folder-search open is suspended in its root rebuild.
        split.applySelectAllMatches(selection, navigationCoordinator: coordinator)
        split.closeFindBar(findModel)
        #expect(system.selectionSet == selection)

        gate.release()
        await folderOpen.value

        #expect(system.selectionSet == selection)
        #expect(system.selectionSet.isMultiple)
    }
}
