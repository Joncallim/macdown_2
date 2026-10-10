import Darwin
import Foundation

/// A file descriptor with exactly-once close and in-use counting. `close()` while a read is mid-call only marks the
/// descriptor closed: the real `close(2)` runs when the last user finishes, so a cancelled or disposed owner can never
/// close a descriptor number that another thread's read still holds (or that the kernel has meanwhile reused).
final class OwnedDescriptor: @unchecked Sendable {
    private let descriptor: Int32
    private let lock = NSLock()
    private var users = 0
    private var closeRequested = false
    private var didClose = false

    init(_ descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit { requestClose() }

    /// Runs `body` with the raw descriptor, or returns `nil` if the owner has already been closed.
    func withDescriptor<T, E: Error>(_ body: (Int32) throws(E) -> T) throws(E) -> T? {
        lock.lock()
        guard !closeRequested else {
            lock.unlock()
            return nil
        }
        users += 1
        lock.unlock()
        defer { finishUse() }
        return try body(descriptor)
    }

    func requestClose() {
        lock.lock()
        closeRequested = true
        let shouldClose = users == 0 && !didClose
        if shouldClose {
            didClose = true
        }
        lock.unlock()
        if shouldClose {
            Darwin.close(descriptor)
        }
    }

    private func finishUse() {
        lock.lock()
        users -= 1
        let shouldClose = users == 0 && closeRequested && !didClose
        if shouldClose {
            didClose = true
        }
        lock.unlock()
        if shouldClose {
            Darwin.close(descriptor)
        }
    }
}
