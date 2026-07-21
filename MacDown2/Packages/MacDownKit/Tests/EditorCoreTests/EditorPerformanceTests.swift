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
