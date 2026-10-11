@testable import EditorCore
import Foundation
import Testing

/// Cross-feature review (2026-10-11), F3: #396 made the shared line helpers treat a lone CR as a line terminator, which
/// changes every caller, but only the Tab/Shift-Tab/heading paths were pinned. These tests pin the other callers on
/// bare-CR and mixed-EOL text so any later change to those semantics is deliberate.
struct EditingAssistBareCRCallerTests {
    private let support = EditingAssistTestSupport.self

    private func returnKey(_ text: String, at location: Int) -> String? {
        let outcome = support.outcome(for: .insertNewline, in: text, selection: NSRange(location: location, length: 0))
        return support.applied(outcome, to: text)?.text
    }

    @Test func returnOnABareCRListItemContinuesTheListWithTheDocumentsOwnTerminator() {
        let text = "x\r- item"
        #expect(returnKey(text, at: text.utf16.count) == "x\r- item\r- ")
    }

    @Test func returnOnAnEmptyBareCRListItemTerminatesTheListWithoutIntroducingLF() {
        let text = "- a\r- "
        let result = returnKey(text, at: text.utf16.count)
        #expect(result?.contains("\n") == false, "no second line-ending convention may appear")
    }

    @Test func returnInAMixedEOLDocumentUsesTheTerminatorOfTheLineItBreaks() {
        let text = "- a\r\n- b\r- c"
        #expect(returnKey(text, at: text.utf16.count)?.hasSuffix("\r- c\r- ") == true)
    }

    @Test func smartHomeOnALaterBareCRLineWorksOnThatLineNotTheDocumentStart() {
        let text = "first\r    indented"
        let firstNonBlank = "first\r    ".utf16.count
        let lineStart = "first\r".utf16.count

        let first = support.outcome(
            for: .smartHome,
            in: text,
            selection: NSRange(location: text.utf16.count, length: 0)
        )
        #expect(first == .selection(NSRange(location: firstNonBlank, length: 0)))

        let second = support.outcome(for: .smartHome, in: text, selection: NSRange(location: firstNonBlank, length: 0))
        #expect(second == .selection(NSRange(location: lineStart, length: 0)))
    }

    @Test func aBareCRFenceIsClassifiedAsFencedCode() {
        let text = "prose\r```swift\rlet x = 1\r```\rmore" as NSString
        let inside = text.range(of: "let x").location
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: inside) == .fencedCode(languageID: "swift"))
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: 0) == .prose)
    }

    @Test func bareCRFrontMatterIsDetected() {
        let text = "---\rtitle: x\r---\rbody" as NSString
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: 6) == .frontMatter)
        #expect(FencedRegionClassifier.classify(text: text, atUTF16Offset: text.length - 1) == .prose)
    }

    @Test func lfAndCRLFBehaviourIsUnchanged() {
        #expect(returnKey("x\n- item", at: 8) == "x\n- item\n- ")
        #expect(returnKey("x\r\n- item", at: 9) == "x\r\n- item\r\n- ")
        let fenced = "p\r\n```swift\r\nlet x\r\n```\r\nq" as NSString
        #expect(FencedRegionClassifier.classify(text: fenced, atUTF16Offset: fenced.range(of: "let").location)
            == .fencedCode(languageID: "swift"))
    }
}
