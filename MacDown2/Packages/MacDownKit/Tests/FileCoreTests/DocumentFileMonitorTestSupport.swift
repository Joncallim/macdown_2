@testable import FileCore
import Foundation

actor ScriptedProber: DocumentFileProbing {
    private var values: [DocumentFileObservation]
    private(set) var callCount = 0
    private(set) var lastExpectedURL: URL?

    init(_ values: [DocumentFileObservation]) {
        self.values = values
    }

    func observe(
        expectedURL: URL,
        priorFileObjectID _: PhysicalFileIdentity.FileObjectID?
    ) async -> DocumentFileObservation {
        callCount += 1
        lastExpectedURL = expectedURL
        if values.isEmpty {
            return .missing(URL(fileURLWithPath: "/unexpected"))
        }
        return values.removeFirst()
    }
}

actor DeferredProber: DocumentFileProbing {
    private let initial: FileSnapshot
    private var calls = 0
    private var waiters: [CheckedContinuation<DocumentFileObservation, Never>] = []

    init(initial: FileSnapshot) {
        self.initial = initial
    }

    var waiterCount: Int {
        waiters.count
    }

    func observe(
        expectedURL _: URL,
        priorFileObjectID _: PhysicalFileIdentity.FileObjectID?
    ) async -> DocumentFileObservation {
        calls += 1
        guard calls > 1 else { return .available(initial) }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resume(_ snapshot: FileSnapshot, at index: Int) {
        resume(.available(snapshot), at: index)
    }

    func resume(_ observation: DocumentFileObservation, at index: Int) {
        guard waiters.indices.contains(index) else { return }
        waiters[index].resume(returning: observation)
    }
}

actor RecordingProber: DocumentFileProbing {
    struct Request: Sendable {
        let url: URL
        let priorFileObjectID: PhysicalFileIdentity.FileObjectID?
    }

    private(set) var lastRequest: Request?

    func observe(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?
    ) async -> DocumentFileObservation {
        lastRequest = Request(url: expectedURL, priorFileObjectID: priorFileObjectID)
        return .missing(expectedURL)
    }
}

final class MonitorWatcher: DocumentDirectoryWatching, @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [@Sendable (DocumentDirectorySignal) -> Void] = []
    private var fileCallbacks: [@Sendable (DocumentDirectorySignal) -> Void] = []
    private var storedWatchedDirectories: [URL] = []
    private var storedCancelCount = 0
    private var failuresRemaining = 0
    private var fileFailuresRemaining = 0
    private var storedFailedWatchCount = 0
    private var storedFileWatchCount = 0

    var watchedDirectories: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedWatchedDirectories
    }

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCancelCount
    }

    var failedWatchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedFailedWatchCount
    }

    var fileWatchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedFileWatchCount
    }

    func watch(
        _ directoryURL: URL,
        onSignal: @escaping @Sendable (DocumentDirectorySignal) -> Void
    ) throws -> any DocumentDirectoryWatcherHandle {
        lock.lock()
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            storedFailedWatchCount += 1
            lock.unlock()
            throw POSIXError(.ENOENT)
        }
        storedWatchedDirectories.append(directoryURL.standardizedFileURL)
        callbacks.append(onSignal)
        lock.unlock()
        return MonitorWatcherHandle { [weak self] in
            self?.recordCancellation()
        }
    }

    func watchFile(
        _: URL,
        onSignal: @escaping @Sendable (DocumentDirectorySignal) -> Void
    ) throws -> any DocumentDirectoryWatcherHandle {
        lock.lock()
        if fileFailuresRemaining > 0 {
            fileFailuresRemaining -= 1
            lock.unlock()
            throw POSIXError(.ENOENT)
        }
        storedFileWatchCount += 1
        fileCallbacks.append(onSignal)
        lock.unlock()
        // File-level handles are intentionally not included in the parent
        // watcher cancellation assertions used by the legacy monitor tests.
        return MonitorWatcherHandle(onCancel: {})
    }

    func failNextWatchAttempts(_ count: Int) {
        lock.lock()
        failuresRemaining = count
        lock.unlock()
    }

    func failNextFileWatchAttempts(_ count: Int) {
        lock.lock()
        fileFailuresRemaining = count
        lock.unlock()
    }

    func signal(_ signal: DocumentDirectorySignal, at index: Int? = nil) {
        lock.lock()
        let targets = if let index {
            callbacks.indices.contains(index) ? [callbacks[index]] : []
        } else {
            callbacks
        }
        lock.unlock()
        for callback in targets {
            callback(signal)
        }
    }

    func signalFile(_ signal: DocumentDirectorySignal, at index: Int? = nil) {
        lock.lock()
        let targets = if let index {
            fileCallbacks.indices.contains(index) ? [fileCallbacks[index]] : []
        } else {
            fileCallbacks
        }
        lock.unlock()
        for callback in targets {
            callback(signal)
        }
    }

    private func recordCancellation() {
        lock.lock()
        storedCancelCount += 1
        lock.unlock()
    }
}

private final class MonitorWatcherHandle: DocumentDirectoryWatcherHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let onCancel: @Sendable () -> Void

    init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        lock.unlock()
        onCancel()
    }
}
