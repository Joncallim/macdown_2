import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

@MainActor
@Suite("WindowCoordinator folder-search cancellation")
struct WindowCoordinatorFolderSearchCancellationTests {
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        var reachedRootRebuild = false
        coordinator.afterFolderSearchRootRebuild = { reachedRootRebuild = true }
        var checks = 0

        await coordinator.openDocument(at: url, shouldContinue: {
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

        var reachedRootRebuild = false
        var reachedSignal: AsyncStream<Void>.Continuation?
        var release: CheckedContinuation<Void, Never>?
        let reached = AsyncStream<Void> { continuation in reachedSignal = continuation }
        coordinator.afterFolderSearchRootRebuild = {
            reachedRootRebuild = true
            await withCheckedContinuation { continuation in
                release = continuation
                reachedSignal?.yield()
            }
        }
        let task = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "result.md",
                root: root,
                folderAccessURL: root,
                range: NSRange(location: 0, length: 6)
            )
        }

        var iterator = reached.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        release?.resume()
        await task.value

        #expect(reachedRootRebuild)
        #expect(coordinator.controllers.isEmpty)
    }
}
