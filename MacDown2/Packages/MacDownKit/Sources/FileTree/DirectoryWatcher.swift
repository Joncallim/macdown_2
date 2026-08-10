import Darwin
import Dispatch
import Foundation

public enum DirectoryWatchEvent: Sendable, Equatable { case contentsChanged, vanished }

public protocol DirectoryWatcherHandle: Sendable { func cancel() }

public final class DirectoryWatcher: @unchecked Sendable, DirectoryWatcherHandle {
    private let source: DispatchSourceFileSystemObject
    private let lock = NSLock()
    private var cancelled = false

    public init(url: URL, queue: DispatchQueue, onChange: @escaping @Sendable (DirectoryWatchEvent) -> Void) throws {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        let dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue
        )
        source = dispatchSource
        dispatchSource.setCancelHandler { Darwin.close(descriptor) }
        dispatchSource.setEventHandler {
            let data = dispatchSource.data
            if data.contains(.delete) || data.contains(.rename) || data.contains(.revoke) {
                onChange(.vanished)
            } else {
                onChange(.contentsChanged)
            }
        }
        dispatchSource.resume()
    }

    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return }
        cancelled = true
        source.cancel()
    }

    deinit { cancel() }
}

public protocol DirectoryWatching: Sendable {
    func watch(_ url: URL, onChange: @escaping @Sendable (DirectoryWatchEvent) -> Void) throws
        -> any DirectoryWatcherHandle
}

public struct FileSystemDirectoryWatching: DirectoryWatching {
    public init() {}
    public func watch(_ url: URL,
                      onChange: @escaping @Sendable (DirectoryWatchEvent) -> Void) throws -> any DirectoryWatcherHandle
    // swiftlint:disable:next opening_brace
    {
        try DirectoryWatcher(
            url: url,
            queue: DispatchQueue(label: "com.macdown.filetree.watcher", qos: .utility),
            onChange: onChange
        )
    }
}
