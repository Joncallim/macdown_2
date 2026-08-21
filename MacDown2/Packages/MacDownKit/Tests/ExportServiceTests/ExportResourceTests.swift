@testable import ExportService
import Foundation
import Testing

/// Slice 2: typed deterministic resources and the frozen manifest.
struct ExportResourceTests {
    @Test func identityIsContentAddressed() {
        let bytes = Data("hello".utf8)
        let identity = ExportResourceIdentity(bytes: bytes, mimeType: "text/plain")
        #expect(identity.sha256.count == 64)
        #expect(identity.sha256 == ExportResourceIdentity.sha256Hex(of: bytes))
        #expect(identity.fileName == "\(identity.sha256).txt")
    }

    @Test func identicalBytesShareIdentity() {
        let first = ExportResourceIdentity(bytes: Data("x".utf8), mimeType: "text/plain")
        let second = ExportResourceIdentity(bytes: Data("x".utf8), mimeType: "text/plain")
        #expect(first == second)
    }

    @Test func differentBytesDiffer() {
        let first = ExportResourceIdentity(bytes: Data("x".utf8), mimeType: "text/plain")
        let second = ExportResourceIdentity(bytes: Data("y".utf8), mimeType: "text/plain")
        #expect(first != second)
    }

    @Test func mimeTypeUsesSystemMapping() {
        #expect(ExportMIMEType.mimeType(forFileExtension: "png") == "image/png")
        #expect(ExportMIMEType.mimeType(forFileExtension: "css") == "text/css")
        #expect(ExportMIMEType.mimeType(forFileExtension: "js") == "text/javascript")
    }

    @Test func mimeTypeFallsBackToOctetStream() {
        #expect(ExportMIMEType.mimeType(forFileExtension: "no-such-extension-xyz") == "application/octet-stream")
    }

    @Test func canonicalExtensionFallsBackToBin() {
        let identity = ExportResourceIdentity(bytes: Data("x".utf8), mimeType: "application/x-unknown-thing")
        #expect(identity.canonicalExtension == "bin")
        #expect(identity.fileName.hasSuffix(".bin"))
    }
}
