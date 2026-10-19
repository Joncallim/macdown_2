import AppKit
import Foundation
@testable import MacDown2
@testable import TextSearch
import Workspace

@MainActor
struct ControllerFixture {
    let controller: WindowController
    let coordinator: WindowCoordinator
    let defaults: UserDefaults
    let suiteName: String
    let stateDirectory: URL

    func waitForIndexedPath(_ path: String) async -> Bool {
        for _ in 0 ..< 200 {
            let paths = await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath))
            if paths.contains(path) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func retire() {
        coordinator.removeController(controller)
        controller.close()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: stateDirectory)
    }
}

final class IndexWalkProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var walkCount = 0
    private var completedWalkCount = 0
    private var heldRoot: URL?
    private var unreadableRoot: URL?
    private let unreadableWalkNumber: Int?
    private let gate: IndexWalkGate?
    private let gatesByWalk: [Int: IndexWalkGate]
    private var hasHeldWalk = false
    private var changedPermissions = false
    private let holdEveryWalk: Bool

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return walkCount
    }

    var completedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completedWalkCount
    }

    var permissionChangeSucceeded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return changedPermissions
    }

    init(
        heldRoot: URL? = nil,
        unreadableRoot: URL? = nil,
        unreadableWalkNumber: Int? = nil,
        gate: IndexWalkGate? = nil,
        gatesByWalk: [Int: IndexWalkGate] = [:],
        holdEveryWalk: Bool = false
    ) {
        self.heldRoot = heldRoot?.standardizedFileURL
        self.unreadableRoot = unreadableRoot?.standardizedFileURL
        self.unreadableWalkNumber = unreadableWalkNumber
        self.gate = gate
        self.gatesByWalk = gatesByWalk
        self.holdEveryWalk = holdEveryWalk
    }

    func makeIndex() -> WorkspaceFileIndex {
        WorkspaceFileIndex { [self] root, excluded in
            let shouldHold: Bool
            let shouldChangePermissions: Bool
            let selectedGate: IndexWalkGate?
            lock.lock()
            walkCount += 1
            let walkNumber = walkCount
            selectedGate = gatesByWalk[walkNumber] ?? gate
            shouldHold = root.standardizedFileURL == heldRoot
                && (gatesByWalk[walkNumber] != nil || holdEveryWalk || !hasHeldWalk)
            if shouldHold, !holdEveryWalk {
                hasHeldWalk = true
            }
            shouldChangePermissions = root.standardizedFileURL == unreadableRoot
                && !changedPermissions
                && (unreadableWalkNumber == nil || unreadableWalkNumber == walkNumber)
            if shouldChangePermissions {
                changedPermissions = true
            }
            lock.unlock()
            if shouldHold {
                selectedGate?.blockUntilReleased()
            }
            if shouldChangePermissions {
                do {
                    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
                } catch {
                    lock.lock()
                    changedPermissions = false
                    lock.unlock()
                }
            }
            let result = DirectoryWalker().walk(root: root, excludedDirectoryNames: excluded)
            lock.lock()
            completedWalkCount += 1
            lock.unlock()
            return result
        }
    }
}

final class IndexWalkGate: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)

    func blockUntilReleased() {
        started.signal()
        releaseSignal.wait()
    }

    func waitUntilBlocked(timeout: DispatchTime = .now() + 5) -> Bool {
        started.wait(timeout: timeout) == .success
    }

    func release() {
        releaseSignal.signal()
    }
}
