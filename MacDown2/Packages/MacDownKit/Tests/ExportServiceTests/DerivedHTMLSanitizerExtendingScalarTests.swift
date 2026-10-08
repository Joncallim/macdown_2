@testable import ExportService
import Foundation
import Testing

/// Review pass 7: Foundation's non-literal `replacingOccurrences` skips a `"` (or `&colon;`) followed by a
/// grapheme-extending scalar, so the quote stayed unescaped and closed the attribute — script injection into exported
/// HTML through a diagram fence — and an entity-encoded `javascript:` scheme was not recognised.
struct DerivedHTMLSanitizerExtendingScalarTests {
    @Test(arguments: ["\u{0301}", "\u{200C}", "\u{200D}", "\u{FE0F}", "\u{1885}"])
    func aQuoteFollowedByAnExtendingScalarIsStillEscaped(_ extender: String) {
        let html = "<text title='y\"\(extender) onmouseover=alert(1) z'>x</text>"

        let sanitized = DerivedHTMLSanitizer.sanitized(html)

        #expect(sanitized == "<text title=\"y&quot;\(extender) onmouseover=alert(1) z\">x</text>")
    }

    @Test(arguments: ["\u{0301}", "\u{1885}"])
    func anEntityEncodedScriptSchemeFollowedByAnExtendingScalarIsStillBlocked(_ extender: String) {
        let html = "<a href=\"javascript&colon;\(extender)=alert(1)\">x</a>"

        let sanitized = DerivedHTMLSanitizer.sanitized(html)

        #expect(sanitized.contains("href=\"#\""))
        #expect(!sanitized.contains("javascript"))
    }

    @Test func angleBracketsFollowedByExtendingScalarsAreEscapedInAttributes() {
        let sanitized = DerivedHTMLSanitizer.sanitized("<a title=\"</style>\u{0301}<b>\u{200C}\">x</a>")

        #expect(!sanitized.contains("</style>"))
        #expect(!sanitized.contains("<b>"))
    }
}
