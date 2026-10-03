import Foundation
import Preview
import Testing

struct HTMLPreviewContentTypeTests {
    @Test func everyResponseCarriesAContentTypeAlongsideTheCSP() {
        let headers = HTMLPreviewResponseHeaders.headers(for: .v1, contentType: HTMLPreviewContentType.mainDocument)

        #expect(headers["Content-Type"] == "text/html; charset=utf-8")
        #expect(headers[HTMLPreviewResponseHeaders.contentSecurityPolicy] == HTMLPreviewPolicy.v1.contentSecurityPolicy)
    }

    @Test func subresourceTypesComeFromTheFileExtension() {
        #expect(HTMLPreviewContentType.forFileExtension("png") == "image/png")
        #expect(HTMLPreviewContentType.forFileExtension(".SVG") == "image/svg+xml")
        #expect(HTMLPreviewContentType.forFileExtension("css") == "text/css")
        #expect(HTMLPreviewContentType.forFileExtension("html") == "text/html")
        #expect(HTMLPreviewContentType.isHTML("htm"))
        #expect(!HTMLPreviewContentType.isHTML("png"))
    }

    @Test func anUnknownOrMissingExtensionFallsBackToOctetStream() {
        #expect(HTMLPreviewContentType.forFileExtension("") == "application/octet-stream")
        #expect(HTMLPreviewContentType.forFileExtension("zzzunknown") == "application/octet-stream")
    }
}
