import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

/// EPIC-22 Slice 2a — exercises `EditorView.makeNSView`/`dismantleNSView`
/// through the REAL SwiftUI `NSViewRepresentable` path (via
/// `NSHostingView`), not the lighter
/// `EditingAssistIntegrationSupport.makeSystem`/`makeCoordinator` helper
/// every other suite in this file uses.
///
/// This distinction is not academic: an earlier version of the
/// undo/redo-triggered gutter redraw registered its `NotificationCenter`
/// observer against `system.undoManager` evaluated inside `makeNSView`,
/// before the view had a window -- at which point it resolves to a
/// throwaway fallback manager, never the real one the window later
/// installs. Every OTHER test in this package mounts a bare
/// `EditorTextSystem`/`Coordinator` directly and never calls `makeNSView`
/// at all, so none of them could have caught that this specific
/// registration never actually fires in production. This suite exists
/// specifically to close that gap.
@MainActor
@Suite("EditorView real makeNSView path")
struct EditorViewRealMountTests {
    private struct Mounted {
        let hostingView: NSHostingView<EditorView>
        let window: NSWindow
        let store: EditorTextSystemStore
        let identity: String
    }

    private func mount(
        initialText: String,
        store: EditorTextSystemStore = EditorTextSystemStore(),
        identity: String = UUID().uuidString
    ) -> Mounted {
        let binding = Binding<String>(get: { initialText }, set: { _ in })

        let hostingView = NSHostingView(rootView: EditorView(
            text: binding,
            identity: identity,
            configuration: .default,
            store: store
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()

        return Mounted(hostingView: hostingView, window: window, store: store, identity: identity)
    }

    @Test func fullLifecycleThroughRealSwiftUIMountingEditUndoRedoAndDismantle() throws {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString

        // Captured BEFORE mounting: `EditorTextSystem.undoManager` resolves
        // to a temporary `fallbackUndoManager` here, since no window exists
        // yet for `textView.undoManager` to defer to.
        let systemBeforeMount = store.system(for: identity, initialText: "a", configuration: .default)
        let preMountUndoManagerIdentity = ObjectIdentifier(systemBeforeMount.undoManager)

        let mounted = mount(initialText: "a", store: store, identity: identity)
        defer { mounted.window.orderOut(nil) }

        let scrollView = try #require(Self.findScrollView(in: mounted.hostingView), "makeNSView did not run")
        let gutter = try #require(scrollView.verticalRulerView as? EditorGutterView)

        // The exact bug mechanism: mounting the SAME cached system in a
        // REAL window switches `undoManager`'s identity away from the
        // fallback captured above.
        let system = store.system(for: identity, initialText: "a", configuration: .default)
        #expect(
            preMountUndoManagerIdentity != ObjectIdentifier(system.undoManager),
            "expected undoManager identity to change once the text view is mounted in a real window"
        )

        assertUndoRedoDrivesGutter(system: system, gutter: gutter)
        try assertDismantleLeavesNoObserver(mounted: mounted, scrollView: scrollView, system: system)
    }

    /// Edit past a digit boundary, then undo/redo, asserting the gutter
    /// tracks each direction without any extra prompting.
    private func assertUndoRedoDrivesGutter(system: EditorTextSystem, gutter: EditorGutterView) {
        let grownText = (1 ... 200).map { "line \($0)" }.joined(separator: "\n")
        system.textView.insertText(
            grownText,
            replacementRange: NSRange(location: 0, length: (system.text as NSString).length)
        )
        gutter.updateThickness()
        let thicknessAfterGrowing = gutter.ruleThickness

        system.undoManager.undo()
        #expect(
            gutter.ruleThickness < thicknessAfterGrowing,
            "gutter did not shrink after undo through the real makeNSView-mounted path"
        )

        // Redo must grow it back too -- proving the fix isn't
        // one-directional (e.g. an observer that only happens to fire once).
        system.undoManager.redo()
        #expect(
            gutter.ruleThickness == thicknessAfterGrowing,
            "gutter did not grow back after redo through the real makeNSView-mounted path"
        )
    }

    /// Calls the REAL `EditorView.dismantleNSView(_:coordinator:)`
    /// directly, rather than trying to force SwiftUI's own view-identity
    /// switch to trigger it: empirically, in this headless test process
    /// (no live `NSApplication` run loop driving an actual display-link
    /// update cycle), switching a hosted branch and pumping the run loop
    /// does NOT reliably make `NSHostingView` tear down the outgoing
    /// `NSViewRepresentable` at all -- confirmed by a first version of this
    /// test, which found `coordinator.gutterView` still non-nil afterward.
    /// `dismantleNSView`'s body never reads `self` (only its two
    /// parameters), so calling it on a throwaway `EditorView` value with
    /// the REAL `scrollView`/`coordinator` is not a workaround; it
    /// exercises the exact same production code SwiftUI would call.
    ///
    /// A first version of the leak assertion itself only checked the
    /// ALREADY-mounted `gutter`'s `ruleThickness` afterward, which an
    /// independent hostile review correctly flagged as unable to
    /// distinguish "the observer was removed" from "the observer is still
    /// registered but harmlessly no-ops", since `dismantleNSView`
    /// unconditionally sets `coordinator.gutterView = nil` REGARDLESS of
    /// whether `removeObserver` also ran -- `Coordinator.undoManagerDidChange`'s
    /// entire body is `gutterView?.updateThickness()`, so that version
    /// would have passed even with `removeObserver` deleted entirely. This
    /// version reassigns a FRESH `gutterView` onto the same coordinator
    /// after dismantle, restoring a non-nil target so a still-registered
    /// observer would have something to visibly act on.
    private func assertDismantleLeavesNoObserver(
        mounted: Mounted,
        scrollView: NSScrollView,
        system: EditorTextSystem
    ) throws {
        let coordinator = try #require(
            system.textView.delegate as? EditorView.Coordinator,
            "expected the real Coordinator to still be the text view's delegate before dismantle"
        )

        let throwawayBinding = Binding<String>(get: { "" }, set: { _ in })
        let editorView = EditorView(
            text: throwawayBinding,
            identity: mounted.identity,
            configuration: .default,
            store: mounted.store
        )
        editorView.dismantleNSView(scrollView, coordinator: coordinator)

        #expect(coordinator.gutterView == nil, "dismantleNSView did not clear the coordinator's gutterView")

        // Grow the document (directly against `system`, bypassing the now
        // fully detached view) so a real `updateThickness()` call WOULD
        // produce a different thickness than this scratch gutter's own
        // freshly-computed one, giving a leaked observer something to
        // visibly change.
        let scratchScrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let scratchGutter = EditorGutterView(scrollView: scratchScrollView, system: system)
        coordinator.gutterView = scratchGutter
        system.textView.insertText(
            (1 ... 500).map { "line \($0)" }.joined(separator: "\n"),
            replacementRange: NSRange(location: 0, length: (system.text as NSString).length)
        )
        let thicknessBeforeSyntheticNotifications = scratchGutter.ruleThickness

        NotificationCenter.default.post(name: .NSUndoManagerDidUndoChange, object: system.undoManager)
        NotificationCenter.default.post(name: .NSUndoManagerDidRedoChange, object: system.undoManager)

        #expect(
            scratchGutter.ruleThickness == thicknessBeforeSyntheticNotifications,
            """
            a synthetic undo/redo notification still reached the coordinator after dismantle -- the \
            NotificationCenter observer was not actually removed, only masked by gutterView being nil
            """
        )
    }

    @Test func gutterResizesAfterAModelTextPushAcrossADigitBoundaryGrowing() throws {
        let mounted = mount(initialText: "a")
        defer { mounted.window.orderOut(nil) }

        let scrollView = try #require(Self.findScrollView(in: mounted.hostingView), "makeNSView did not run")
        let gutter = try #require(scrollView.verticalRulerView as? EditorGutterView)
        let thicknessBefore = gutter.ruleThickness
        let lineCountBefore = mounted.store.system(
            for: mounted.identity,
            initialText: "",
            configuration: .default
        ).lineIndex.lineCount

        // 9 -> 100 lines, through the BINDING (a model-driven change, e.g.
        // a document reload), not through `textView.insertText` -- this
        // goes through `updateNSView`'s `system.setText(text)` path, which
        // bypasses the incremental delegate hooks entirely.
        pushModelText((1 ... 100).map { "line \($0)" }.joined(separator: "\n"), into: mounted)

        let system = mounted.store.system(for: mounted.identity, initialText: "", configuration: .default)
        #expect(system.lineIndex.lineCount == 100)
        #expect(system.lineIndex.lineCount > lineCountBefore)
        #expect(
            gutter.ruleThickness > thicknessBefore,
            "gutter did not resize after a growing model text push crossing a digit boundary"
        )
    }

    @Test func gutterResizesAfterAModelTextPushAcrossADigitBoundaryShrinking() throws {
        let mounted = mount(initialText: (1 ... 100).map { "line \($0)" }.joined(separator: "\n"))
        defer { mounted.window.orderOut(nil) }

        let scrollView = try #require(Self.findScrollView(in: mounted.hostingView), "makeNSView did not run")
        let gutter = try #require(scrollView.verticalRulerView as? EditorGutterView)
        gutter.updateThickness()
        let thicknessBefore = gutter.ruleThickness

        // 100 -> 9 lines, the mirror direction: shrinking must update the
        // ruler immediately too, not just growing.
        pushModelText((1 ... 9).map { "line \($0)" }.joined(separator: "\n"), into: mounted)

        let system = mounted.store.system(for: mounted.identity, initialText: "", configuration: .default)
        #expect(system.lineIndex.lineCount == 9)
        #expect(
            gutter.ruleThickness < thicknessBefore,
            "gutter did not shrink after a shrinking model text push crossing a digit boundary"
        )
    }

    @Test func gutterExposesBasicAccessibilityMetadataWithoutPerLineChildren() throws {
        let mounted = mount(initialText: (1 ... 50).map { "line \($0)" }.joined(separator: "\n"))
        defer { mounted.window.orderOut(nil) }

        let scrollView = try #require(Self.findScrollView(in: mounted.hostingView), "makeNSView did not run")
        let gutter = try #require(scrollView.verticalRulerView as? EditorGutterView)

        #expect(gutter.isAccessibilityElement())
        #expect(gutter.accessibilityIdentifier() == "editorGutter")
        #expect(!(gutter.accessibilityLabel() ?? "").isEmpty)
        // A single accessibility element for the whole ruler -- VoiceOver
        // must not be asked to traverse one child per visible line.
        #expect((gutter.accessibilityChildren() ?? []).isEmpty)
    }

    private func pushModelText(_ newText: String, into mounted: Mounted) {
        let binding = Binding<String>(get: { newText }, set: { _ in })
        mounted.hostingView.rootView = EditorView(
            text: binding,
            identity: mounted.identity,
            configuration: .default,
            store: mounted.store
        )
        mounted.hostingView.layoutSubtreeIfNeeded()
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}
