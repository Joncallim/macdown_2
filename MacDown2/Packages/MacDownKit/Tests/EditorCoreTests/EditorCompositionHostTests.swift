import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

/// A SwiftUI update pass during an IME / dead-key composition used to crash the app: the binding still held the
/// pre-composition text (marked-text updates post no `didChange`), `updateNSView` pushed it with `setText`, the
/// marked range was cleared mid-composition and the commit's edit scanned a stale line index out of bounds
/// (`NSRangeException`, abort). The host mirrors the app: `onSelectionChange` writes @State, so every marked-text
/// update causes an update pass.
private final class CompositionModel: ObservableObject {
    @Published var text = "hello world"
}

private struct CompositionHost: View {
    @ObservedObject var model: CompositionModel
    let store: EditorTextSystemStore
    let identity: String
    let configuration: EditorConfiguration
    @State private var selection = NSRange(location: 0, length: 0)

    var body: some View {
        VStack {
            EditorView(
                text: Binding(get: { model.text }, set: { model.text = $0 }),
                identity: identity,
                configuration: configuration,
                store: store,
                onSelectionChange: { selection = $0 }
            )
            Text("sel \(selection.location)")
        }
    }
}

@MainActor
struct EditorCompositionHostTests {
    @Test func aCompositionSurvivesSwiftUIUpdatePassesAndCommitsConsistently() {
        var configuration = EditorConfiguration.default
        configuration.editingAssists = .markdownDefault
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        let model = CompositionModel()
        let hosting = NSHostingView(rootView: CompositionHost(
            model: model, store: store, identity: identity, configuration: configuration
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        let system = store.system(for: identity, initialText: model.text, configuration: configuration)
        window.makeFirstResponder(system.textView)
        system.selectedRange = NSRange(location: 5, length: 0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let unset = NSRange(location: NSNotFound, length: 0)
        system.textView.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0), replacementRange: unset)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        system.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: unset)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        // Still composing: the model push must not have cleared the marked text.
        #expect(system.textView.hasMarkedText())
        #expect(system.text == "helloni world")

        system.textView.insertText("你好", replacementRange: unset)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        #expect(system.text == "hello你好 world")
        #expect(model.text == system.text)
        #expect(system.lineIndex == EditorLineIndex(text: system.text as NSString))
    }

    /// Cancelling a composition started over a selection published nothing, so the next SwiftUI pass pushed the
    /// stale binding back with `setText`: the text reverted and the whole undo history was wiped.
    @Test func cancellingACompositionOverASelectionKeepsTheTextAndUndoHistory() {
        var configuration = EditorConfiguration.default
        configuration.editingAssists = .markdownDefault
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        let model = CompositionModel()
        model.text = "alpha beta"
        let hosting = NSHostingView(rootView: CompositionHost(
            model: model, store: store, identity: identity, configuration: configuration
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        let system = store.system(for: identity, initialText: model.text, configuration: configuration)
        window.makeFirstResponder(system.textView)
        let unset = NSRange(location: NSNotFound, length: 0)
        system.textView.insertText("!", replacementRange: NSRange(location: 10, length: 0))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        #expect(system.undoManager.canUndo)

        system.textView.setSelectedRange(NSRange(location: 0, length: 5))
        system.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: unset)
        system.textView.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: unset)
        system.textView.unmarkText()
        system.textView.setSelectedRange(NSRange(location: 2, length: 0)) // a SwiftUI update pass follows
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        #expect(model.text == system.text)
        #expect(system.text == " beta!")
        #expect(system.undoManager.canUndo)
    }
}
