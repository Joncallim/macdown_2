import Foundation
@testable import Preview
import Testing
@testable import Textual

@Suite("Inline math after a preview edit")
@MainActor
struct InlineMathDemoRegressionTests {
    private let equationLine = "The area of a circle is $A = \\pi r^2$, and"

    @Test func exactEquationParsesAsOneMathAttachment() throws {
        let parsed = try PreviewMarkupParser(syntaxExtensions: [.math]).attributedString(for: equationLine)
        let attachments = parsed.runs.compactMap(\.textual.attachment)

        #expect(attachments.count == 1)
        #expect(attachments.first?.description == "$A = \\pi r^2$")
        #expect(String(parsed.characters) == "The area of a circle is \u{FFFC}, and")
    }

    @Test func mathEditsInvalidateInnerTextWithoutRemountingOrdinaryProse() {
        let prose = "The area of a circle is "
        #expect(BlockView.inlineMathContentID(blockSource: prose, renderedSource: prose) == "")
        let larger = "The area is larger"
        #expect(BlockView.inlineMathContentID(blockSource: larger, renderedSource: larger) == "")

        let before = BlockView.inlineMathContentID(blockSource: equationLine, renderedSource: equationLine)
        let edited = equationLine.replacingOccurrences(of: "r^2", with: "r^3")
        let after = BlockView.inlineMathContentID(blockSource: edited, renderedSource: edited)
        #expect(before != after)
        #expect(BlockView.inlineMathContentID(blockSource: equationLine, renderedSource: equationLine) == before)

        // Rendering can transform the source without changing its block ID.
        // The inner identity must follow the actual parsed input in that case.
        #expect(BlockView.inlineMathContentID(blockSource: equationLine, renderedSource: edited) == edited)
    }
}
