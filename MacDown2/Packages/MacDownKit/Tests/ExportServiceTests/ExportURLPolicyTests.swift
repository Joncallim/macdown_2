@testable import ExportService
import Testing

struct ExportURLPolicyTests {
    @Test func rejectsJavaScriptScheme() {
        #expect(!ExportURLPolicy.isSafe("javascript:alert(1)"))
        #expect(!ExportURLPolicy.isSafe("JAVASCRIPT:alert(1)"))
    }

    @Test func rejectsVBScriptScheme() {
        #expect(!ExportURLPolicy.isSafe("vbscript:msgbox(1)"))
    }

    @Test func rejectsDataScheme() {
        #expect(!ExportURLPolicy.isSafe("data:text/html,<script>alert(1)</script>"))
        #expect(!ExportURLPolicy.isSafe("data:image/png;base64,AAAA"))
    }

    @Test func rejectsFileScheme() {
        #expect(!ExportURLPolicy.isSafe("file:///etc/passwd"))
    }

    @Test func allowsRelativeReferences() {
        #expect(ExportURLPolicy.isSafe("images/foo.png"))
        #expect(ExportURLPolicy.isSafe("./foo.png"))
        #expect(ExportURLPolicy.isSafe("../foo.png"))
    }

    @Test func allowsFragments() {
        #expect(ExportURLPolicy.isSafe("#section"))
    }

    @Test func allowsPlainHTTPAndHTTPS() {
        #expect(ExportURLPolicy.isSafe("https://example.com/x"))
        #expect(ExportURLPolicy.isSafe("http://example.com/x"))
    }

    @Test func allowsOtherSchemes() {
        #expect(ExportURLPolicy.isSafe("mailto:a@b.c"))
    }

    @Test func extractsLowercasedScheme() {
        #expect(ExportURLPolicy.scheme(of: "HTTPS://x") == "https")
        #expect(ExportURLPolicy.scheme(of: "images/foo.png") == nil)
        #expect(ExportURLPolicy.scheme(of: "#frag") == nil)
    }
}
