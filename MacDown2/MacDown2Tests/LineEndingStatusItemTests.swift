import FileCore
@testable import MacDown2
import Testing

@Suite("LineEndingStatusItemView (Slice 8c)")
struct LineEndingStatusItemTests {
    private func label(for text: String) -> String {
        LineEndingStatusItemView(profile: LineEndingProfile(detecting: text), onConvert: { _ in }).label
    }

    @Test func labelNamesTheDocumentsActualLineEndings() {
        #expect(label(for: "a\nb") == "LF")
        #expect(label(for: "a\r\nb") == "CRLF")
        #expect(label(for: "a\rb") == "CR")
    }

    @Test func mixedAndTerminatorFreeDocumentsAreNotLabelledAsAnyOneConvention() {
        #expect(label(for: "a\nb\r\nc") == "Mixed Line Endings")
        #expect(label(for: "single line") == "No Line Endings")
        #expect(label(for: "") == "No Line Endings")
    }

    @Test func choicesMapToTheirLineEndings() {
        #expect(LineEndingChoice.allCases.map(\.ending) == [.lineFeed, .crlf, .carriageReturn])
        #expect(LineEndingChoice.allCases.map(\.shortName) == ["LF", "CRLF", "CR"])
    }
}
