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

    @Test func rejectsSchemesHiddenBehindLeadingWhitespace() {
        // URL parsers strip leading whitespace before reading the scheme, so a
        // policy that does not would class this as a harmless relative path.
        #expect(!ExportURLPolicy.isSafe(" javascript:alert(1)"))
        #expect(!ExportURLPolicy.isSafe("\u{0B}vbscript:msgbox(1)"))
    }

    @Test func ignoresTabsAndNewlinesInsideTheScheme() {
        // Tab, line feed and carriage return are removed from anywhere in a URL
        // before it is parsed.
        #expect(!ExportURLPolicy.isSafe("java\tscript:alert(1)"))
        #expect(!ExportURLPolicy.isSafe("java\nscript:alert(1)"))
    }

    @Test func rejectsSchemeNamesThatAreNotSchemes() {
        // A colon later in a relative path is not a scheme delimiter.
        #expect(ExportURLPolicy.scheme(of: "images/my:file.png") == nil)
        #expect(ExportURLPolicy.scheme(of: "1nvalid:x") == nil)
        #expect(ExportURLPolicy.scheme(of: ":x") == nil)
        #expect(ExportURLPolicy.isSafe("images/my:file.png"))
    }

    @Test func acceptsTheFullSchemeGrammar() {
        #expect(ExportURLPolicy.scheme(of: "x-custom.app+v2:payload") == "x-custom.app+v2")
    }
}
