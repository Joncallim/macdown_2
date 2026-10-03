@testable import EditorCore
import Foundation
import Testing

/// #183 audit finding 9: Move Line Up/Down on documents that mix `\n`, `\r`
/// and `\r\n` must only permute lines; it may never create or destroy a
/// terminator by letting a moved `\r` land next to an unrelated `\n`.
@Suite("EditorLineTransforms — Move Line with mixed line endings")
struct EditorMoveLinesMixedEndingsTests {
    /// Lines (content + terminator) of `text`, split the CommonMark way.
    static func units(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            current.unicodeScalars.append(scalar)
            if scalar == "\n" {
                result.append(current); current = ""
            } else if scalar == "\r" {
                if index + 1 < scalars.count, scalars[index + 1] == "\n" {
                    current.unicodeScalars.append("\n")
                    index += 1
                }
                result.append(current); current = ""
            }
            index += 1
        }
        result.append(current)
        return result
    }

    /// Every document of 2...4 lines built from empty/non-empty lines joined by
    /// any of the three terminators.
    static func mixedEndingDocuments() -> [String] {
        let atoms = ["a", "", "b"]
        let terminators = ["\n", "\r", "\r\n"]
        var documents: [String] = []
        for count in 2 ... 4 {
            var combos: [[(String, String)]] = [[]]
            for _ in 0 ..< count - 1 {
                combos = combos.flatMap { prefix in
                    atoms.flatMap { atom in terminators.map { prefix + [(atom, $0)] } }
                }
            }
            for combo in combos {
                for last in atoms {
                    documents.append(combo.map { $0.0 + $0.1 }.joined() + last)
                }
            }
        }
        return documents
    }

    private static func contents(of units: [String]) -> [String] {
        units.map { String($0.filter { !$0.isNewline }) }.sorted()
    }

    @Test("every applied move only permutes lines: same line count, same line contents")
    func exhaustiveMixedEndingMoves() {
        var failures: [String] = []
        for document in Self.mixedEndingDocuments() {
            let text = document as NSString
            let lineIndex = EditorLineIndex(text: text)
            let before = Self.units(of: document)
            for line in 1 ... lineIndex.lineCount {
                let start = lineIndex.lineStartOffsets[line - 1]
                let selection = EditorSelectionSet(single: NSRange(location: start, length: 0))
                for moveUp in [true, false] {
                    let transaction = moveUp
                        ? EditorLineTransforms.moveLinesUpTransaction(
                            text: text, lineIndex: lineIndex, selection: selection
                        )
                        : EditorLineTransforms.moveLinesDownTransaction(
                            text: text, lineIndex: lineIndex, selection: selection
                        )
                    guard let applied = LineTransformTestSupport.applied(transaction, to: document) else { continue }
                    let after = Self.units(of: applied.text)
                    if after.count != before.count || Self.contents(of: after) != Self.contents(of: before) {
                        failures.append("\(document.debugDescription) line \(line) up=\(moveUp)")
                    }
                }
            }
        }
        if !failures.isEmpty {
            Issue.record("\(failures.count) bad moves, e.g. \(failures.prefix(3))")
        }
    }

    @Test("a move that would fuse a CR and an unrelated LF into one CRLF is declined")
    func fusingMoveIsDeclined() {
        let text = "a\ra\n" as NSString // lines "a" (CR), "a" (LF), "" -- moving line 2 down would give "a\r\na"
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 2, length: 0))
        #expect(EditorLineTransforms
            .moveLinesDownTransaction(text: text, lineIndex: lineIndex, selection: selection) == nil)
    }

    @Test("a mixed-ending move that fuses nothing still applies and keeps every terminator")
    func nonFusingMixedMoveStillApplies() {
        let text = "a\rb\nc" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: 2, length: 0))
        let transaction = EditorLineTransforms.moveLinesDownTransaction(
            text: text,
            lineIndex: lineIndex,
            selection: selection
        )
        #expect(LineTransformTestSupport.applied(transaction, to: text as String)?.text == "a\rc\nb")
    }
}
