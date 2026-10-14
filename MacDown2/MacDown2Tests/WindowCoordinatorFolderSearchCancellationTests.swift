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
    private final class Barrier: @unchecked Sendable {
        private let lock = NSLock()
        private var released = false
        private var waiter: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if released {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiter = continuation
                    lock.unlock()
                }
            }
        }

        func release() {
            lock.lock()
            released = true
            let waiter = waiter
            self.waiter = nil
            lock.unlock()
            waiter?.resume()
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

        var reachedRootRebuild = false
        var release: CheckedContinuation<Void, Never>?
        coordinator.afterFolderSearchRootRebuild = {
            reachedRootRebuild = true
            await withCheckedContinuation { continuation in
                release = continuation
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

        for _ in 0..<2_000 where !reachedRootRebuild {
            await Task.yield()
        }
        task.cancel()
        release?.resume()
        await task.value

        #expect(reachedRootRebuild)
        #expect(coordinator.controllers.isEmpty)
    }

    @Test func newerFolderSearchSupersedesOlderResult() async throws {
        let coordinator = makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "one".write(to: root.appendingPathComponent("one.md"), atomically: true, encoding: .utf8)
        try "two".write(to: root.appendingPathComponent("two.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let olderBarrier = Barrier()
        coordinator.afterFolderSearchFileLoad = { await olderBarrier.wait() }
        let older = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "one.md", root: root, folderAccessURL: root,
                range: NSRange(location: 0, length: 3)
            )
        }
        await Task.yield()
        let newer = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "two.md", root: root, folderAccessURL: root,
                range: NSRange(location: 0, length: 3)
            )
        }
        olderBarrier.release()
        await older.value
        await newer.value

        #expect(coordinator.controllers.count == 1)
        #expect(coordinator.controllers.first?.model.activeDocument?.fileURL?.lastPathComponent == "two.md")
    }

    @Test func queuedOlderFolderSearchCannotPublishAfterNewerRequest() async throws {
        let coordinator = makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "one".write(to: root.appendingPathComponent("one.md"), atomically: true, encoding: .utf8)
        try "two".write(to: root.appendingPathComponent("two.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let barrier = Barrier()
        coordinator.afterFolderSearchFileLoad = { await barrier.wait() }
        let first = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "one.md", root: root, folderAccessURL: root,
                range: NSRange(location: 0, length: 3)
            )
        }
        let second = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "two.md", root: root, folderAccessURL: root,
                range: NSRange(location: 0, length: 3)
            )
        }
        await Task.yield()
        barrier.release()
        await first.value
        await second.value

        #expect(coordinator.controllers.count == 1)
        #expect(coordinator.controllers.first?.model.activeDocument?.fileURL?.lastPathComponent == "two.md")
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
        let barrier = Barrier()
        controller.beforeRootRebuild = { await barrier.wait() }

        let task = Task {
            await coordinator.openDocument(
                at: url,
                folderRoot: root,
                folderAccessURL: root,
                shouldContinue: { true }
            )
        }
        await Task.yield()
        coordinator.removeController(controller)
        controller.close()
        barrier.release()
        await task.value

        #expect(!coordinator.controllers.contains { $0 === controller })
        #expect(controller.isClosed)
    }
}
