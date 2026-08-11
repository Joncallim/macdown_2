import Darwin
import Dispatch
import Foundation

enum DocumentDirectorySignal: Sendable, Equatable {
    case changed
    case parentVanished
}

protocol DocumentDirectoryWatcherHandle: Sendable {
    func cancel()
}

protocol DocumentDirectoryWatching: Sendable {
    func watch(
        _ directoryURL: URL,
        onSignal: @escaping @Sendable (DocumentDirectorySignal) -> Void
    ) throws -> any DocumentDirectoryWatcherHandle
}

struct LiveDocumentDirectoryWatcher: DocumentDirectoryWatching, Sendable {
    func watch(
        _ directoryURL: URL,
        onSignal: @escaping @Sendable (DocumentDirectorySignal) -> Void
    ) throws -> any DocumentDirectoryWatcherHandle {
        try DocumentDirectoryWatcherHandleImpl(directoryURL: directoryURL, onSignal: onSignal)
    }
}

private final class DocumentDirectoryWatcherHandleImpl: DocumentDirectoryWatcherHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var cancelled = false

    init(
        directoryURL: URL,
        onSignal: @escaping @Sendable (DocumentDirectorySignal) -> Void
    ) throws {
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            throw POSIXError(code)
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .revoke, .attrib, .extend, .link],
            queue: DispatchQueue(label: "com.macdown.filecore.document-watcher", qos: .utility)
        )
        self.source = source
        source.setEventHandler { [weak self, weak source] in
            guard let source else { return }
            let events = source.data
            let vanished = events.contains(.delete) || events.contains(.rename) || events.contains(.revoke)
            onSignal(vanished ? .parentVanished : .changed)
            _ = self
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        let source = source
        self.source = nil
        lock.unlock()
        source?.cancel()
    }

    deinit {
        cancel()
    }
}
