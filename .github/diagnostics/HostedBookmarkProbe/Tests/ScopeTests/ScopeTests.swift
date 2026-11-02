import Foundation
import Testing

struct ScopeTests {
    @Test func scopedBookmarkUsesTheActualRunnerIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("host-scope-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.md")
        try Data("private scoped fixture".utf8).write(to: file)
        var record: [String: Any] = ["process": ProcessInfo.processInfo.processName,
            "executable": Bundle.main.executableURL?.path ?? "nil", "bundle": Bundle.main.bundleURL.path,
            "identifier": Bundle.main.bundleIdentifier ?? "nil"]
        do {
            let bytes = try file.bookmarkData(options: .withSecurityScope)
            var stale = false
            _ = try URL(resolvingBookmarkData: bytes, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            record["success"] = true
        } catch {
            record["success"] = false
            record["error"] = (error as NSError).description
            Issue.record("Scoped private fixture failed: \(error)")
        }
        let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("HOST_SCOPE_RESULT " + String(decoding: bytes, as: UTF8.self))
    }
}
