import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 3c — Select Next/All Occurrence (§6.9).
@MainActor
@Suite("EditorTextSystem occurrence selection (Slice 3c)")
struct EditorOccurrenceSelectionTests {
    private let support = EditingAssistIntegrationSupport.self

    // MARK: - selectNextOccurrence: first press (bare caret)

    @Test func selectNextOccurrenceFromABareCaretSelectsTheWordAtTheCaret() {
        let system = support.makeSystem(text: "one cat two")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 5, length: 0) // inside "cat"

        let handled = system.selectNextOccurrence()

        #expect(handled)
        #expect(system.selectionSet.ranges == [NSRange(location: 4, length: 3)])
    }

    @Test func selectNextOccurrenceTouchingEitherEdgeOfAWordStillSelectsIt() {
        let system = support.makeSystem(text: "one cat two")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 4, length: 0) // just before "cat"

        #expect(system.selectNextOccurrence())
        #expect(system.selectionSet.ranges == [NSRange(location: 4, length: 3)])

        system.selectedRange = NSRange(location: 7, length: 0) // just after "cat"
        #expect(system.selectNextOccurrence())
        #expect(system.selectionSet.ranges == [NSRange(location: 4, length: 3)])
    }

    @Test func firstPressDoesNotAlsoJumpToASecondOccurrence() {
        // The literal J1 walkthrough's own three-press count for three
        // occurrences: the first press only selects the word, it does not
        // also add a second occurrence in the same call.
        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 0)

        #expect(system.selectNextOccurrence())

        #expect(!system.selectionSet.isMultiple)
    }

    @Test func aCaretTouchingNoWordDeclines() {
        let system = support.makeSystem(text: "one   two")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 4, length: 0) // middle of the whitespace run

        #expect(!system.selectNextOccurrence())
        #expect(!system.selectionSet.isMultiple)
    }

    // MARK: - selectNextOccurrence: subsequent presses (existing selection)

    @Test func selectNextOccurrenceAfterAWordSelectionAddsTheNextOccurrence() {
        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 3) // first "cat"

        #expect(system.selectNextOccurrence())

        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 3),
            NSRange(location: 4, length: 3),
        ])
        #expect(system.selectionSet.primaryRange == NSRange(location: 4, length: 3))
    }

    @Test func threePressesSelectAllThreeOccurrences() {
        // The exact J1 walkthrough: press once to select the word, press
        // twice more to reach all three occurrences.
        let system = support.makeSystem(text: "cat cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 0)

        system.selectNextOccurrence() // 1: selects the first "cat"
        system.selectNextOccurrence() // 2: adds the second
        system.selectNextOccurrence() // 3: adds the third

        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 3),
            NSRange(location: 4, length: 3),
            NSRange(location: 8, length: 3),
        ])
    }

    @Test func selectNextOccurrenceWrapsAroundToTheDocumentStart() {
        let system = support.makeSystem(text: "cat one cat two cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        // Start from the LAST occurrence -- there is nothing after it, so
        // the next occurrence must wrap around to the first one.
        system.selectedRange = NSRange(location: 16, length: 3)

        #expect(system.selectNextOccurrence())

        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 3),
            NSRange(location: 16, length: 3),
        ])
        #expect(system.selectionSet.primaryRange == NSRange(location: 0, length: 3))
    }

    @Test func repeatedPressesOnceEveryOccurrenceIsSelectedAreANoOp() {
        let system = support.makeSystem(text: "cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 0)
        system.selectNextOccurrence() // selects first "cat"
        system.selectNextOccurrence() // adds second "cat"
        #expect(system.selectionSet.count == 2)

        let handled = system.selectNextOccurrence()

        #expect(!handled)
        #expect(system.selectionSet.count == 2, "a declined call must not mutate the existing selection")
    }

    @Test func selectNextOccurrenceMatchesAsASubstringInsideALongerWord() {
        // Matches Sublime/VS Code's own Cmd-D convention: the search step is
        // a plain substring match, not restricted to whole-word boundaries,
        // even though the FIRST press (from a bare caret) selects a whole
        // word.
        let system = support.makeSystem(text: "cat category")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 3) // "cat"

        #expect(system.selectNextOccurrence())

        #expect(
            system.selectionSet.ranges.contains(NSRange(location: 4, length: 3)),
            "must match \"cat\" inside \"category\""
        )
    }

    @Test func selectNextOccurrenceIsCaseSensitive() {
        let system = support.makeSystem(text: "cat Cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 3) // lowercase "cat"

        #expect(system.selectNextOccurrence())

        // Must skip "Cat" (offset 4) and land on the second lowercase "cat"
        // (offset 8), not the differently-cased one in between.
        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 3),
        ])
    }

    // MARK: - selectAllOccurrences

    @Test func selectAllOccurrencesFromABareCaretSelectsEveryOccurrenceInOneCall() {
        let system = support.makeSystem(text: "cat one cat two cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 0) // inside the first "cat"

        let handled = system.selectAllOccurrences()

        #expect(handled)
        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 3),
            NSRange(location: 16, length: 3),
        ])
    }

    @Test func selectAllOccurrencesPrimaryTracksTheStartingPosition() {
        let system = support.makeSystem(text: "cat one cat two cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 8, length: 3) // the MIDDLE "cat"

        #expect(system.selectAllOccurrences())

        #expect(system.selectionSet.primaryRange == NSRange(location: 8, length: 3))
    }

    @Test func selectAllOccurrencesDeclinesWhenTheCaretTouchesNoWord() {
        let system = support.makeSystem(text: "one   two")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 4, length: 0)

        #expect(!system.selectAllOccurrences())
        #expect(!system.selectionSet.isMultiple)
    }

    @Test func selectAllOccurrencesReplacesAnyPriorUnrelatedSelectionEntirely() {
        let system = support.makeSystem(text: "cat one cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.toggleSecondaryCaret(at: 5) // an unrelated caret, inside "one"
        #expect(system.selectionSet.isMultiple)
        system.selectedRange = NSRange(location: 0, length: 3) // primary stays "cat"

        #expect(system.selectAllOccurrences())

        #expect(system.selectionSet.ranges == [
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 3),
        ])
    }

    // MARK: - IME / programmatic-update safety

    @Test func markedTextSessionBypassesOccurrenceSelectionEntirely() {
        let system = support.makeSystem(text: "cat cat")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 3)
        system.textView.setMarkedText(
            "\u{3042}",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(system.textView.hasMarkedText())

        #expect(!system.selectNextOccurrence())
        #expect(!system.selectAllOccurrences())
    }
}
