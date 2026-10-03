import Foundation

/// Runs synchronous, deeply recursive work on a thread with a large stack and
/// waits for it. Only the pages actually touched are committed.
enum OnLargeStack {
    static let stackSize = 1 << 30

    private final class Box<T>: @unchecked Sendable {
        var result: Result<T, Error>?
    }

    static func run<T>(_ work: @escaping () throws -> T) throws -> T {
        let box = Box<T>()
        let finished = DispatchSemaphore(value: 0)
        nonisolated(unsafe) let task = work
        let thread = Thread {
            box.result = Result { try task() }
            finished.signal()
        }
        thread.stackSize = stackSize
        thread.qualityOfService = .userInitiated
        thread.name = "ExportService.render"
        thread.start()
        finished.wait()
        guard let result = box.result else { throw CMarkError.renderFailed }
        return try result.get()
    }
}
