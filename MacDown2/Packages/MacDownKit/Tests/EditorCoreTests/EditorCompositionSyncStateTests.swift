import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

private final class SyncStateModel: ObservableObject {
    @Published var text = "hello world"
}

private struct SyncStateHost: View {
    @ObservedObject var model: SyncStateModel
    let store: EditorTextSystemStore
    let identity: String
    let configuration: EditorConfiguration
    @State private var selection = NSRange(location: 0, length: 0)

    var body: some View {
        VStack {
            EditorView(
                text: Binding(get: { model.text }, set: { model.text = $0 }),
                identity: identity, configuration: configuration, store: store,
                onSelectionChange: { selection = $0 }
            )
            Text("sel \(selection.location)")
        }
    }
}

/// Round-4 review (b17bcf15) P1: #436 tracked the last agreed text but undo/redo and external replacement did not
/// update it, so the first IME/dead-key composition after either looked like a model replacement and its commit
/// was discarded.
@MainActor
struct EditorCompositionSyncStateTests {
    private struct Mounted {
        let model: SyncStateModel
        let system: EditorTextSystem
        let window: NSWindow
    }

    private func spin(_ seconds: Double = 0.1) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func mount() -> Mounted {
        let configuration = EditorConfiguration.default
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        let model = SyncStateModel()
        let hosting = NSHostingView(rootView: SyncStateHost(
            model: model,
            store: store,
            identity: identity,
            configuration: configuration
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        let system = store.system(for: identity, initialText: model.text, configuration: configuration)
        window.makeFirstResponder(system.textView)
        system.selectedRange = NSRange(location: 5, length: 0)
        spin(0.05)
        return Mounted(model: model, system: system, window: window)
    }

    /// Replacement during a composition, composition CANCELLED, later a plain keystroke.
    @Test func cancelledCompositionThenKeystroke() {
        let mounted = mount()
        let (model, system) = (mounted.model, mounted.system)
        defer { mounted.window.orderOut(nil) }
        let unset = NSRange(location: NSNotFound, length: 0)
        system.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: unset)
        spin()
        model.text = "EXTERNAL"
        spin()
        system.textView.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: unset)
        system.textView.unmarkText()
        spin()
        let afterCancel = model.text
        let viewAfterCancel = system.text
        system.selectedRange = NSRange(location: (system.text as NSString).length, length: 0)
        system.textView.insertText("Z", replacementRange: unset)
        spin()
        #expect(
            model.text.contains("Z"),
            "afterCancel model=\(afterCancel) view=\(viewAfterCancel); final model=\(model.text) view=\(system.text)"
        )
    }

    /// Undo publishes without noteSynced; a later dead-key composition is then treated as diverged.
    @Test func undoThenComposition() {
        let mounted = mount()
        let (model, system) = (mounted.model, mounted.system)
        defer { mounted.window.orderOut(nil) }
        let unset = NSRange(location: NSNotFound, length: 0)
        system.textView.insertText("abc", replacementRange: unset)
        system.textView.breakUndoCoalescing()
        spin()
        #expect(model.text == "helloabc world")
        system.undoManager.undo()
        spin()
        let afterUndo = model.text
        system.textView.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: unset)
        spin()
        system.textView.insertText("é", replacementRange: unset)
        spin()
        #expect(model.text.contains("é"), "afterUndo=\(afterUndo) final model=\(model.text) view=\(system.text)")
        #expect(system.text.contains("é"), "view=\(system.text)")
    }

    /// External reload (ExternalFileController.replaceEditorText) then a dead-key composition.
    @Test func externalReplaceThenComposition() {
        let mounted = mount()
        let (model, system) = (mounted.model, mounted.system)
        defer { mounted.window.orderOut(nil) }
        let unset = NSRange(location: NSNotFound, length: 0)
        model.text = "reloaded from disk"
        system.replaceTextFromExternal("reloaded from disk", preserving: system.viewportSnapshot(), clearUndo: true)
        spin()
        system.selectedRange = NSRange(location: 8, length: 0)
        spin()
        system.textView.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: unset)
        spin()
        system.textView.insertText("é", replacementRange: unset)
        spin()
        #expect(model.text.contains("é"), "final model=\(model.text) view=\(system.text)")
    }

    /// Round-5 review (c64da714) P2: the flag was only set from `updateNSView`, so a view publish that came BEFORE
    /// SwiftUI rendered a model-only replacement still reverted it. The check now happens at publish time.
    @Test func aKeystrokeBeforeTheModelReplacementIsPushedDoesNotRevertIt() {
        let mounted = mount()
        defer { mounted.window.orderOut(nil) }
        let unset = NSRange(location: NSNotFound, length: 0)
        mounted.model.text = "EXTERNAL"
        mounted.system.textView.insertText("Z", replacementRange: unset)
        spin()
        #expect(mounted.model.text.contains("EXTERNAL"), "model=\(mounted.model.text) view=\(mounted.system.text)")
    }

    @Test func aCompositionCommitBeforeTheModelReplacementIsRenderedDoesNotRevertIt() {
        let mounted = mount()
        defer { mounted.window.orderOut(nil) }
        let unset = NSRange(location: NSNotFound, length: 0)
        mounted.system.textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: unset
        )
        spin()
        mounted.model.text = "EXTERNAL"
        mounted.system.textView.insertText("你好", replacementRange: unset)
        spin()
        #expect(mounted.model.text.contains("EXTERNAL"), "model=\(mounted.model.text) view=\(mounted.system.text)")
    }
}
