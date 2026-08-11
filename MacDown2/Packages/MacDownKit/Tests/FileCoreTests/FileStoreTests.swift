@testable import FileCore
import Foundation
import Testing

@Test func fileStoreRoundTrip() throws {
    let store = FileStore()
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("test.md")
    let content = "Hello, MacDown 2!\nÜnicode: üöä"

    try store.write(content, to: url)
    let (read, encoding) = try store.read(from: url)

    #expect(read == content)
    #expect(encoding == .utf8)
}

@Test func fileStoreAtomicWriteReplacesContent() throws {
    let store = FileStore()
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("test.md")
    try store.write("first", to: url)
    try store.write("second", to: url)

    let (read, _) = try store.read(from: url)
    #expect(read == "second")
}

@Test func fileStoreReadFailsForNonexistentFile() {
    let store = FileStore()
    let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-nonexistent.md")
    #expect(throws: FileStoreError.self) {
        try store.read(from: url)
    }
}

@Test func fileStoreReadFailsForNonFileURL() throws {
    let store = FileStore()
    let url = try #require(URL(string: "https://example.com/file.md"))
    #expect(throws: FileStoreError.self) {
        try store.read(from: url)
    }
}

@Test func conditionalWriteAcceptsAFreshRevisionAfterAnAtomicReplacement() throws {
    let store = FileStore()
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("document.md")

    _ = try store.write("first", to: url)
    _ = try store.write("external replacement", to: url)
    let baseline = try store.readSnapshot(from: url).revision
    _ = try store.write("local replacement", to: url, expectedRevision: baseline)

    #expect(try store.read(from: url).content == "local replacement")
}

@Test func publicationLockRegistryEvictsIdleEntries() throws {
    let registry = FilePublicationLocks()
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for index in 0 ..< 32 {
        let url = directory.appendingPathComponent("\(index).md")
        registry.withLock(for: url) {}
    }

    #expect(registry.isEmpty)
}
