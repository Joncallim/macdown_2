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

/// Folder-search opens that are cancelled, superseded or told to stop by
/// `shouldContinue` must never publish a window.
@MainActor
@Suite("WindowCoordinator folder-search cancellation")
struct FolderSearchCancellationTests {
    @Test func falseBeforeSerializedAdmissionDoesNotOpenOrCreateAController() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        await coordinator.openDocument(at: url, shouldContinue: { false })

        #expect(coordinator.controllers.isEmpty)
    }

    @Test func falseAfterFileLoadDoesNotPublishAWindow() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
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
        let coordinator = FolderSearchTestSupport.makeCoordinator()
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
        let coordinator = FolderSearchTestSupport.makeCoordinator()
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
        let coordinator = FolderSearchTestSupport.makeCoordinator()
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
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("result.md")
        try "needle".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let gate = FolderSearchGate()
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
        let entered = await FolderSearchGate.waitForEntry(gate.entered, timeout: .seconds(10))
        task.cancel()
        gate.release()
        await task.value

        #expect(entered)
        #expect(coordinator.controllers.isEmpty)
    }

    @Test func newerFolderSearchSupersedesOlderResult() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "one".write(to: root.appendingPathComponent("one.md"), atomically: true, encoding: .utf8)
        try "two".write(to: root.appendingPathComponent("two.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let olderGate = FolderSearchGate()
        let newerGate = FolderSearchGate()
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
        #expect(await FolderSearchGate.waitForEntry(olderGate.entered))
        let newer = Task {
            await coordinator.openFolderSearchResult(
                relativePath: "two.md", root: root, folderAccessURL: root,
                range: NSRange(location: 0, length: 3)
            )
        }
        #expect(await FolderSearchGate.waitForEntry(newerGate.entered))
        newerGate.release()
        olderGate.release()
        await older.value
        await newer.value

        #expect(coordinator.controllers.count == 1)
        #expect(coordinator.controllers.first?.model.activeDocument?.fileURL?.lastPathComponent == "two.md")
    }

    @Test func queuedFolderSearchCancellationDoesNotDisturbAnAdmittedOrdinaryOpen() async throws {
        let coordinator = FolderSearchTestSupport.makeCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("one.md")
        try "one".write(to: url, atomically: true, encoding: .utf8)
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: root)
        }

        let blockerGate = FolderSearchGate()
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
        #expect(await FolderSearchGate.waitForEntry(blockerGate.entered))

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

        #expect(await FolderSearchGate.waitForEntry(queuedAdmission.stream))
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
        let coordinator = FolderSearchTestSupport.makeCoordinator()
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
        let gate = FolderSearchGate()
        controller.beforeRootRebuild = { await gate.wait() }

        let task = Task {
            await coordinator.openDocument(
                at: url,
                folderRoot: root,
                folderAccessURL: root,
                shouldContinue: { true }
            )
        }
        #expect(await FolderSearchGate.waitForEntry(gate.entered))
        coordinator.removeController(controller)
        controller.close()
        gate.release()
        await task.value

        #expect(!coordinator.controllers.contains { $0 === controller })
        #expect(controller.isClosed)
    }
}
