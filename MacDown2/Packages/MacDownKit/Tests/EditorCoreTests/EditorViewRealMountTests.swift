import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

/// EPIC-22 Slice 2a — exercises `EditorView.makeNSView` through the REAL
/// SwiftUI `NSViewRepresentable` path (via `NSHostingView`), not the
/// lighter `EditingAssistIntegrationSupport.makeSystem`/`makeCoordinator`
/// helper every other suite in this file uses.
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
    @Test func gutterRedrawsAfterUndoWhenMountedThroughTheRealSwiftUIPath() throws {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        var text = "a"
        let binding = Binding<String>(get: { text }, set: { text = $0 })

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
        defer { window.orderOut(nil) }

        let scrollView = try #require(Self.findScrollView(in: hostingView), "makeNSView did not run")
        let gutter = try #require(scrollView.verticalRulerView as? EditorGutterView)

        // The same cached system `makeNSView` created for `identity` --
        // driving edits through it exercises the exact same
        // NSTextView/undoManager the mounted gutter is watching.
        let system = store.system(for: identity, initialText: text, configuration: .default)
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
            "gutter did not redraw/resize after undo through the real makeNSView-mounted path"
        )
    }

    @Test func gutterResizesAfterAModelTextPushAcrossADigitBoundary() throws {
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        var text = "a"
        let binding = Binding<String>(get: { text }, set: { text = $0 })

        func makeRootView() -> EditorView {
            EditorView(text: binding, identity: identity, configuration: .default, store: store)
        }

        let hostingView = NSHostingView(rootView: makeRootView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        let scrollView = try #require(Self.findScrollView(in: hostingView), "makeNSView did not run")
        let gutter = try #require(scrollView.verticalRulerView as? EditorGutterView)
        let thicknessBefore = gutter.ruleThickness

        // Push a 100-line document through the BINDING (a model-driven
        // change, e.g. a document reload) rather than through
        // `textView.insertText` -- this goes through `updateNSView`'s
        // `system.setText(text)` path, which bypasses the incremental
        // delegate hooks entirely and must resize the gutter itself.
        text = (1 ... 100).map { "line \($0)" }.joined(separator: "\n")
        hostingView.rootView = makeRootView()
        hostingView.layoutSubtreeIfNeeded()

        #expect(
            gutter.ruleThickness > thicknessBefore,
            "gutter did not resize after a model text push crossing a digit boundary"
        )
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
