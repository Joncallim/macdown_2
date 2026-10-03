import AppKit
@testable import EditorCore
import Testing

/// Typing a fence or a thematic break must produce exactly the characters typed: the third backtick/underscore
/// used to pair again, ending as four (and ```swift as ```swift`).
struct EditingAssistFenceTypingTests {
    private let support = EditingAssistTestSupport.self

    /// Types `typed` one character at a time through the engine, applying native insertion on passthrough.
    private func simulateTyping(_ typed: String) -> String {
        var text = ""
        var caret = 0
        for character in typed {
            let outcome = support.type(character, in: text, at: caret)
            if let result = support.applied(outcome, to: text) {
                text = result.text
                caret = result.selection.location
            } else if case let .selection(range) = outcome {
                caret = range.location
            } else {
                let nsText = text as NSString
                text = nsText.replacingCharacters(in: NSRange(location: caret, length: 0), with: String(character))
                caret += 1
            }
        }
        return text
    }

    @Test("typing three backticks or underscores does not grow a fourth")
    func tripleDelimitersDoNotEscalate() {
        #expect(simulateTyping("```") == "```")
        #expect(simulateTyping("```swift") == "```swift")
        #expect(simulateTyping("___") == "___")
    }
}
