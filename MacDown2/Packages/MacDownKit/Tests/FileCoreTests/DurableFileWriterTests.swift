@testable import FileCore
import Foundation
import Testing

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct DurableFileWriterTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func writesAndReplacesTheFileWithoutLeavingATemporary() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.json")

        try DurableFileWriter.write(Data("first".utf8), to: url)
        try DurableFileWriter.write(Data("second".utf8), to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == "second")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["ledger.json"])
    }

    /// The file's data must be flushed BEFORE the rename publishes it, and the directory AFTER, so the new name can
    /// never be durable without its contents.
    @Test func flushesTheFileBeforeTheRenameAndTheDirectoryAfter() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.json")
        let events = EventLog()

        try DurableFileWriter.write(Data("payload".utf8), to: url) { descriptor in
            var isDirectory = false
            var info = stat()
            if fstat(descriptor, &info) == 0 {
                isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
            }
            let published = FileManager.default.fileExists(atPath: url.path)
            events.append("\(isDirectory ? "directory" : "file")-sync, final name published: \(published)")
            return 0
        }

        #expect(events.values == [
            "file-sync, final name published: false",
            "directory-sync, final name published: true",
        ])
    }

    @Test func aFailedFlushLeavesTheExistingFileAndNoTemporary() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.json")
        try DurableFileWriter.write(Data("kept".utf8), to: url)

        #expect(throws: (any Error).self) {
            try DurableFileWriter.write(Data("lost".utf8), to: url) { _ in
                errno = EIO
                return -1
            }
        }

        #expect(try String(contentsOf: url, encoding: .utf8) == "kept")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["ledger.json"])
    }

    /// Round-8 review P2: a directory-flush failure used to throw AFTER the rename had published the new file, so a
    /// caller that treats a throw as "nothing changed" kept the old state while disk held the new one.
    @Test func aFailedDirectoryFlushNeverThrowsAfterThePublishAndIsReported() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.json")
        try DurableFileWriter.write(Data("old".utf8), to: url)

        let flushed = try DurableFileWriter.write(Data("new".utf8), to: url) { descriptor in
            var info = stat()
            fstat(descriptor, &info)
            if (info.st_mode & S_IFMT) == S_IFDIR {
                errno = ENOTSUP
                return -1
            }
            return 0
        }

        #expect(!flushed, "the caller can see the rename is not yet known to be durable")
        #expect(try String(contentsOf: url, encoding: .utf8) == "new", "and the new file is what is published")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["ledger.json"])
    }
}
