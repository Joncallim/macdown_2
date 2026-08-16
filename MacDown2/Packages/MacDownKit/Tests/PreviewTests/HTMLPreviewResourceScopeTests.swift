import Foundation
@testable import Preview
import Testing

@Suite("HTMLPreviewResourceScope")
struct HTMLPreviewResourceScopeTests {
    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HTMLPreviewResourceScope-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func approvesFileInsideRoot() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("img.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)

        let approved = HTMLPreviewResourceScope.approvedFileURL(for: file, relativeTo: root)
        #expect(approved == file.resolvingSymlinksInPath().standardizedFileURL)
    }

    @Test func approvesNestedFileInsideRoot() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("assets/font.woff2", isDirectory: false)
        try FileManager.default.createDirectory(
            at: nested.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x00, 0x01]).write(to: nested)

        let approved = HTMLPreviewResourceScope.approvedFileURL(for: nested, relativeTo: root)
        #expect(approved != nil)
    }

    @Test func rejectsTraversalOutsideRoot() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let secret = root.deletingLastPathComponent().appendingPathComponent("secret-\(UUID().uuidString).txt")
        try Data("secret".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }

        let escaping = root.appendingPathComponent("..").appendingPathComponent(secret.lastPathComponent)
        let approved = HTMLPreviewResourceScope.approvedFileURL(for: escaping, relativeTo: root)
        #expect(approved == nil)
    }

    @Test func rejectsSymlinkEscapingRoot() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        let link = root.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let approved = HTMLPreviewResourceScope.approvedFileURL(for: link, relativeTo: root)
        #expect(approved == nil)
    }

    @Test func rejectsDirectoryAsResource() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let approved = HTMLPreviewResourceScope.approvedFileURL(for: root, relativeTo: root)
        #expect(approved == nil)
    }

    @Test func rejectsMissingFile() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing.png")
        let approved = HTMLPreviewResourceScope.approvedFileURL(for: missing, relativeTo: root)
        #expect(approved == nil)
    }

    @Test func rejectsNonFileURL() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = try #require(URL(string: "https://example.com/img.png"))
        #expect(HTMLPreviewResourceScope.approvedFileURL(for: remote, relativeTo: root) == nil)
    }

    @Test func untitledDocumentHasNoApprovedResources() {
        let file = URL(fileURLWithPath: "/tmp/anything-\(UUID().uuidString).png")
        // No root: nothing is approved, even a well-formed file URL.
        #expect(HTMLPreviewResourceScope.approvedFileURL(for: file, relativeTo: nil) == nil)
    }
}
