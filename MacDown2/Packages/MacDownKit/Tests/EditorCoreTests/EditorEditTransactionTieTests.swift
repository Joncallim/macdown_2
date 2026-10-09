import AppKit
@testable import EditorCore
import Foundation
import Testing

@MainActor
@Suite("EditorEditTransaction same-offset ties")
struct EditorEditTransactionTieTests {
    private let support = EditingAssistIntegrationSupport.self

    /// Review pass 6: sorting by location alone left a zero-length insert and a replacement at the same offset in
    /// input order — one order corrupted the text, the other tripped the overlap assertion.
    @Test(arguments: [false, true])
    func aInsertAndAReplacementAtTheSameOffsetApplyInOneDeterministicOrder(reversedInput: Bool) {
        let system = support.makeSystem(text: "0123456789abcdef")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        var replacements = [
            TextReplacement(range: NSRange(location: 5, length: 0), replacementText: "AAAA"),
            TextReplacement(range: NSRange(location: 5, length: 3), replacementText: "B"),
        ]
        if reversedInput {
            replacements.reverse()
        }

        system.apply(EditorEditTransaction(replacements: replacements))

        #expect(system.text == "01234AAAAB89abcdef")
    }
}
