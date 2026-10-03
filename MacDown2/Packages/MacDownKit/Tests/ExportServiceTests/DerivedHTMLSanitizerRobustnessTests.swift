@testable import ExportService
import Foundation
import Testing

/// The sanitizer's first version ran regexes over the whole fragment: it rewrote text and attribute values
/// that merely looked like attributes (corrupting math `alt` text), rejoined a blocked tag after deleting an
/// inner one, and was quadratic on unclosed elements.
struct DerivedHTMLSanitizerRobustnessTests {
    @Test func textThatLooksLikeAnAttributeIsLeftAlone() {
        let math = #"<img src="data:image/png;base64,AAAA" alt="x \text{ one = 2} then on=1 /on=2" width="10">"#
        #expect(DerivedHTMLSanitizer.sanitized(math).contains(#"alt="x \text{ one = 2} then on=1 /on=2""#))

        let text = "<p>Handling onclick=foo events, set src=javascript:x</p>"
        #expect(DerivedHTMLSanitizer.sanitized(text) == text)
    }

    @Test func aBlockedTagCannotBeReassembledFromItsParts() {
        for hostile in [
            "<scr<iframe>ipt>alert(1)</scr<iframe>ipt>",
            "<<script>script>alert(1)<</script>/script>",
            "<ifr<object>ame src=x>",
        ] {
            let once = DerivedHTMLSanitizer.sanitized(hostile)
            #expect(!once.lowercased().contains("<script"))
            #expect(!once.lowercased().contains("<iframe"))
            #expect(DerivedHTMLSanitizer.sanitized(once) == once, "not idempotent for \(hostile)")
        }
    }

    @Test func anUnterminatedQuotedUrlFailsClosed() {
        let out = DerivedHTMLSanitizer.sanitized(#"<svg><a href="javascript:alert(1)//>click</a></svg>"#)

        #expect(!out.contains("javascript"))
    }

    @Test func smilAnimationOfAnHrefIsRemoved() {
        let out = DerivedHTMLSanitizer.sanitized(
            ##"<a href="#x"><set attributeName="href" to="javascript:alert(1)"/><text>t</text></a>"##
        )

        #expect(!out.contains("javascript"))
        #expect(out.contains("<text>t</text>"))
    }

    @Test func plainLessThanInTextIsKeptAsAnEscapedLessThan() {
        #expect(DerivedHTMLSanitizer.sanitized("<p>a < b and c > d</p>") == "<p>a &lt; b and c > d</p>")
    }

    @Test func hostileInputIsLinear() {
        let start = ContinuousClock.now

        _ = DerivedHTMLSanitizer.sanitized(String(repeating: "<script ", count: 20000))
        _ = DerivedHTMLSanitizer.sanitized(String(repeating: "<a href=\"", count: 20000))
        _ = DerivedHTMLSanitizer.sanitized(String(repeating: "<", count: 100_000))

        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
