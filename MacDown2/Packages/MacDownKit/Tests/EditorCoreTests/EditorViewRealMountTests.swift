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
    /// A thin wrapper whose branch SwiftUI can switch, which is the
    /// standard way to force a REAL `dismantleNSView` call on the outgoing
    /// `NSViewRepresentable` -- reassigning properties on the SAME
    /// `EditorView` value only ever calls `updateNSView`, never
    /// `dismantleNSView`; switching the `if` branch changes the view
    /// tree's identity at that position, which SwiftUI tears down and
    /// remakes.
    private struct HostedContent: View {
        var showsEditor: Bool
        let binding: Binding<String>
        let identity: String
        let store: EditorTextSystemStore

        var body: some View {
            if showsEditor {
                EditorView(text: binding, identity: identity, configuration: .default, store: store)
            } else {
                Color.clear
            }
        }
    }

    private struct Mounted {
        let hostingView: NSHostingView<HostedContent>
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

        let hostingView = NSHostingView(rootView: HostedContent(
            showsEditor: true,
            binding: binding,
            identity: identity,
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
        try assertDismantleLeavesNoObserver(mounted: mounted, system: system, gutter: gutter)
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

    /// Switches the hosted branch away from `EditorView`, forcing SwiftUI
    /// to tear down the outgoing `NSViewRepresentable` (reassigning
    /// properties on the same value only calls `updateNSView`; a
    /// branch/identity change is what triggers `dismantleNSView`), then
    /// proves no observer survived it.
    private func assertDismantleLeavesNoObserver(
        mounted: Mounted,
        system: EditorTextSystem,
        gutter: EditorGutterView
    ) throws {
        let binding = Binding<String>(get: { "" }, set: { _ in })
        mounted.hostingView.rootView = HostedContent(
            showsEditor: false,
            binding: binding,
            identity: mounted.identity,
            store: mounted.store
        )
        mounted.hostingView.layoutSubtreeIfNeeded()

        // A synthetic undo/redo notification posted AFTER dismantle must
        // not change the (still strongly referenced, merely detached)
        // gutter's thickness at all.
        let thicknessAfterDismantle = gutter.ruleThickness
        NotificationCenter.default.post(name: .NSUndoManagerDidUndoChange, object: system.undoManager)
        NotificationCenter.default.post(name: .NSUndoManagerDidRedoChange, object: system.undoManager)
        #expect(
            gutter.ruleThickness == thicknessAfterDismantle,
            "gutter reacted to undo/redo notifications after dismantle -- an observer leaked"
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
        mounted.hostingView.rootView = HostedContent(
            showsEditor: true,
            binding: binding,
            identity: mounted.identity,
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
