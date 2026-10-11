import Darwin
import Foundation

/// Read access to a filter's stdout/stderr pipes through descriptors this object OWNS (duplicates of the pipes' read
/// ends). Readability callbacks use it instead of `FileHandle.availableData`, which raises an uncatchable Objective-C
/// exception ("Bad file descriptor") if the handle was closed while a callback was already queued, taking down the
/// whole process. Reads and `retire()` share a lock, so after `retire()` returns no read is in flight and every later
/// call reports `.retired` without touching any descriptor.
final class PipeReadDescriptors: @unchecked Sendable {
    enum Stream { case stdout, stderr }

    enum Result {
        /// One read's data; empty means end-of-file.
        case chunk(Data)
        /// Nothing available right now (would block).
        case idle
        case retired
        /// A read error other than EINTR/EAGAIN: never to be mistaken for end-of-file.
        case failed
    }

    private let lock = NSLock()
    private var retiredFlag = false
    private var stdoutDescriptor: Int32
    private var stderrDescriptor: Int32

    init(stdout: FileHandle, stderr: FileHandle) {
        stdoutDescriptor = Self.duplicateNonBlocking(stdout)
        stderrDescriptor = Self.duplicateNonBlocking(stderr)
    }

    deinit { retire() }

    func read(_ stream: Stream) -> Result {
        lock.lock()
        defer { lock.unlock() }
        let descriptor = stream == .stdout ? stdoutDescriptor : stderrDescriptor
        guard !retiredFlag, descriptor >= 0 else { return .retired }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count >= 0 {
                return .chunk(Data(buffer[0 ..< count]))
            }
            switch errno {
            case EINTR: continue
            case EAGAIN: return .idle
            default: return .failed
            }
        }
    }

    func retire() {
        lock.lock()
        defer { lock.unlock() }
        guard !retiredFlag else { return }
        retiredFlag = true
        for descriptor in [stdoutDescriptor, stderrDescriptor] where descriptor >= 0 {
            Darwin.close(descriptor)
        }
        stdoutDescriptor = -1
        stderrDescriptor = -1
    }

    private static func duplicateNonBlocking(_ handle: FileHandle) -> Int32 {
        let descriptor = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        if descriptor >= 0 {
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        }
        return descriptor
    }
}
