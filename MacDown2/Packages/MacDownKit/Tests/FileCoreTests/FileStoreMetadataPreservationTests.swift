import Darwin
@testable import FileCore
import Foundation
import Testing

/// Issue #174 — a save must not silently change what the destination file is:
/// its permission bits and extended attributes (Finder tags, quarantine).
@Suite("FileStore metadata preservation (#174)")
struct FileStoreMetadataPreservationTests {
    private static let xattrName = "com.macdown2.test"

    private func mode(of url: URL) throws -> mode_t {
        var info = stat()
        guard stat(url.path, &info) == 0 else { throw POSIXError(.EIO) }
        return info.st_mode & 0o7777
    }

    private func setXattr(_ url: URL, _ value: String) throws {
        let bytes = Array(value.utf8)
        guard setxattr(url.path, Self.xattrName, bytes, bytes.count, 0, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func xattr(_ url: URL) -> String? {
        let size = getxattr(url.path, Self.xattrName, nil, 0, 0, 0)
        guard size >= 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(url.path, Self.xattrName, &buffer, size, 0, 0) == size else { return nil }
        return String(bytes: buffer, encoding: .utf8)
    }

    @Test(arguments: [mode_t(0o700), mode_t(0o600), mode_t(0o644), mode_t(0o755)])
    func aConditionalSavePreservesPermissionBits(_ bits: mode_t) throws {
        let fixture = try FixtureFile(text: "one")
        #expect(chmod(fixture.url.path, bits) == 0)
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "two")

        _ = try document.save()

        #expect(try FileStore().read(from: fixture.url).content == "two")
        #expect(try mode(of: fixture.url) == bits)
    }

    @Test func aConditionalSavePreservesExtendedAttributes() throws {
        let fixture = try FixtureFile(text: "one")
        try setXattr(fixture.url, "tag")
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "two")

        _ = try document.save()

        #expect(xattr(fixture.url) == "tag")
    }

    @Test func anUnconditionalOverwritePreservesPermissionBitsAndExtendedAttributes() throws {
        let fixture = try FixtureFile(text: "one")
        #expect(chmod(fixture.url.path, 0o700) == 0)
        try setXattr(fixture.url, "tag")

        _ = try FileStore().write("two", to: fixture.url)

        #expect(try FileStore().read(from: fixture.url).content == "two")
        #expect(try mode(of: fixture.url) == 0o700)
        #expect(xattr(fixture.url) == "tag")
    }

    @Test func aNewFileStillGetsOrdinaryDefaultPermissions() throws {
        let fixture = try FixtureFile()

        _ = try FileStore().write("fresh", to: fixture.url)

        #expect(try mode(of: fixture.url) & 0o600 == 0o600)
    }

    @Test func aReadOnlyDestinationKeepsItsModeThroughAConditionalSave() throws {
        let fixture = try FixtureFile(text: "one")
        let document = try FileDocument(fileURL: fixture.url).load().edited(text: "two")
        #expect(chmod(fixture.url.path, 0o444) == 0)

        _ = try document.save()

        #expect(try FileStore().read(from: fixture.url).content == "two")
        #expect(try mode(of: fixture.url) == 0o444)
    }
}
