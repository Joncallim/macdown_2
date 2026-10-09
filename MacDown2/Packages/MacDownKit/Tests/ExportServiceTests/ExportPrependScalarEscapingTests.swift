@testable import ExportService
import Foundation
import Testing

/// Review pass 8: Swift merges a Unicode Prepend scalar (U+0600–0605, U+06DD, U+070F, U+08E2, …) with the NEXT scalar
/// into one `Character`, so per-`Character` escaping and `contains("<")` guards skipped a `<`, `>` or `"` that follows
/// one. Title text reached `<title>` / the synthesised `<h1>` of a self-contained export unescaped.
struct ExportPrependScalarEscapingTests {
    @Test(arguments: ["\u{0600}", "\u{06DD}", "\u{070F}", "\u{08E2}", "\u{0301}"])
    func theTitleEscapingHandlesDelimitersNextToPrependAndExtendingScalars(_ scalar: String) {
        let escaped = HTMLEscaping.escape("a \(scalar)<img src=x onerror=alert(1) \(scalar)> \(scalar)\"q\(scalar)'")

        #expect(!escaped.contains("<"))
        #expect(!escaped.unicodeScalars.contains("<"))
        #expect(!escaped.unicodeScalars.contains(">"))
        #expect(!escaped.unicodeScalars.contains("\""))
        #expect(!escaped.unicodeScalars.contains("'"))
    }

    @Test func theSanitizerEarlyReturnDoesNotTrustACharacterLevelContains() {
        let sanitized = DerivedHTMLSanitizer.sanitized("\u{0600}<script>alert(1)</script>")

        #expect(!sanitized.contains("script"))
    }

    @Test func aLeakedSentinelPrecededByAPrependScalarIsDetected() {
        let leaked = DerivedContentComposer.leakedSentinelIndices(in: "x \u{0600}E12INLINE3Z y", suffix: "")

        #expect(leaked == [3])
    }
}
