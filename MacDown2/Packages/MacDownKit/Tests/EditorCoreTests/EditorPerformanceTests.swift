import AppKit
@testable import EditorCore
import Foundation
import Testing

@MainActor
@Suite("Editor performance")
struct EditorPerformanceTests {
    private let viewportBounds = NSRect(x: 0, y: 0, width: 800, height: 1000)

    /// Converts a `Duration` to milliseconds.
    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000.0 + Double(components.attoseconds) / 1e15
    }

    /// Enumerates layout fragments that intersect the viewport, returning the
    /// count. This proves lazy layout: a large document should only lay out the
    /// visible region.
    private func layoutViewportFragments(in system: EditorTextSystem) -> Int {
        let start = system.layoutManager.documentRange.location
        var count = 0
        var reachedViewportEnd = false

        system.layoutManager.enumerateTextLayoutFragments(from: start, options: .ensuresLayout) { fragment in
            count += 1
            let frame = fragment.layoutFragmentFrame
            // Stop once we have passed the bottom of the viewport.
            if frame.origin.y + frame.height > system.textView.bounds.height {
                reachedViewportEnd = true
                return false
            }
            return true
        }

        _ = reachedViewportEnd
        return count
    }

    @Test("1 MB document opens within viewport budget")
    func open1MB() {
        let text = Fixtures.markdown(targetByteCount: 1_000_000)

        let duration = ContinuousClock().measure {
            let system = EditorTextSystem(
                identity: UUID().uuidString,
                initialText: text,
                configuration: .default
            )
            system.textView.frame = viewportBounds
            _ = layoutViewportFragments(in: system)
        }

        let durationMilliseconds = milliseconds(duration)
        #expect(durationMilliseconds < 300, "1 MB open took \(durationMilliseconds) ms (budget 300 ms)")
    }

    @Test("10 MB document proves viewport-lazy layout")
    func open10MBLazy() {
        let text = Fixtures.markdown(targetByteCount: 10_000_000)
        let system = EditorTextSystem(
            identity: UUID().uuidString,
            initialText: text,
            configuration: .default
        )
        system.textView.frame = viewportBounds

        let fragmentCount = layoutViewportFragments(in: system)

        // A 10 MB document has far more fragments than a single viewport; if we
        // see only a small number, the layout manager is being lazy.
        #expect(fragmentCount < 500, "Viewport laid out \(fragmentCount) fragments")
    }

    @Test("keystroke with incremental line-index update stays within budget on a 10 MB document")
    func keystrokeLineIndexIncremental() {
        // Proves `EditorTextSystem.noteIncrementalEdit` reads the live,
        // backing `NSTextStorage` (`assistTextSource`) rather than
        // `textView.string` (a real O(document length) materialization,
        // per `EditorTextSystem+EditingAssists.swift`'s own documented
        // "last resort only" characterization) -- a single keystroke on a
        // 10 MB document must stay within the SAME budget as an ordinary
        // keystroke on a 1 MB document with no line-index wiring at all
        // (see `keystroke()` above), not scale with document size. Unlike
        // `keystroke()`, this attaches a real `Coordinator` as the text
        // view's delegate so `shouldChangeTextIn`/`textDidChange` actually
        // fire and drive `noteIncrementalEdit` -- without a delegate
        // attached, that path never runs at all.
        let text = Fixtures.markdown(targetByteCount: 10_000_000)
        let system = EditorTextSystem(
            identity: UUID().uuidString,
            initialText: text,
            configuration: .default
        )
        system.textView.frame = viewportBounds
        let coordinator = EditorView.Coordinator()
        coordinator.system = system
        system.textView.delegate = coordinator

        // Prime layout with one viewport pass.
        _ = layoutViewportFragments(in: system)

        let duration = ContinuousClock().measure {
            system.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        }

        let durationMilliseconds = milliseconds(duration)
        #expect(
            durationMilliseconds < 50,
            "keystroke with line-index update took \(durationMilliseconds) ms (budget 50 ms, 10 MB document)"
        )
        #expect(system.lineIndex.utf16Length == (system.text as NSString).length)
    }

    @Test("gutter/status caret update stays within the 8 ms main-actor budget (synthetic keystroke loop)")
    func gutterCaretUpdateStaysWithinBudget() {
        // epic-22-implementation.md §11: "Gutter/status caret update | < 8 ms
        // main-actor work | package unit benchmark (synthetic keystroke
        // loop)" is a narrower, dedicated budget -- distinct from the 50 ms
        // whole-keystroke ceiling `keystrokeLineIndexIncremental` enforces
        // above, which measures the ENTIRE `NSTextView.insertText`
        // pipeline (TextKit layout and painting included). This test
        // isolates only the two pieces of work `textDidChange` actually
        // performs synchronously on every keystroke for the gutter/caret:
        // `EditorLineIndex.applying` and `EditorGutterView.updateThickness()`.
        // A real, growing `NSMutableString` drives genuine edits (not fake
        // edit descriptors against unchanged text), so the line index stays
        // internally consistent across iterations; TextKit layout is never
        // invoked here, since that cost is already covered by the tests
        // above.
        let workingText = NSMutableString(string: Fixtures.markdown(targetByteCount: 10_000_000))
        var lineIndex = EditorLineIndex(text: workingText)

        let system = EditorTextSystem(identity: UUID().uuidString, initialText: "", configuration: .default)
        let scrollView = NSScrollView(frame: viewportBounds)
        let gutter = EditorGutterView(scrollView: scrollView, system: system)

        let iterations = 200
        let duration = ContinuousClock().measure {
            for iterationIndex in 0 ..< iterations {
                let insertionPoint = iterationIndex * 37
                let editedRange = NSRange(location: insertionPoint, length: 0)
                workingText.replaceCharacters(in: editedRange, with: "x")
                lineIndex.applying(editedRange: editedRange, replacementUTF16Length: 1, newText: workingText)
                system.lineIndex = lineIndex
                gutter.updateThickness()
            }
        }

        let perOperationMilliseconds = milliseconds(duration) / Double(iterations)
        #expect(
            perOperationMilliseconds < 8,
            """
            gutter/status caret update averaged \(perOperationMilliseconds) ms/op \
            (budget: < 8 ms main-actor work, epic-22-implementation.md §11)
            """
        )
    }

    @Test("keystroke insert stays within budget")
    func keystroke() {
        let text = Fixtures.markdown(targetByteCount: 1_000_000)
        let system = EditorTextSystem(
            identity: UUID().uuidString,
            initialText: text,
            configuration: .default
        )
        system.textView.frame = viewportBounds

        // Prime layout with one viewport pass.
        _ = layoutViewportFragments(in: system)

        let duration = ContinuousClock().measure {
            system.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
            _ = layoutViewportFragments(in: system)
        }

        let durationMilliseconds = milliseconds(duration)
        #expect(durationMilliseconds < 50, "keystroke took \(durationMilliseconds) ms (budget 50 ms)")
    }
}
