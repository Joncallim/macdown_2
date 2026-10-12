import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

private final class CompositionReplacementModel: ObservableObject {
    @Published var text = "hello world"
}

private struct CompositionReplacementHost: View {
    @ObservedObject var model: CompositionReplacementModel
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

/// Final-head review (bcaea668) P1: while marked text is open `updateNSView` skips the model push, and the commit then
/// published the view's STALE text over a model replacement (external reload, Use Disk Version, Replace in Folder),
/// after which the next Save overwrote the external content with no conflict prompt.
@MainActor
struct EditorCompositionModelReplacementTests {
    /// Opens a composition ("ni"), optionally replaces the model text meanwhile, commits "你好", and returns the model.
    private func commitComposition(replacingModelWith replacement: String?) -> String {
        let configuration = EditorConfiguration.default
        let store = EditorTextSystemStore()
        let identity = UUID().uuidString
        let model = CompositionReplacementModel()
        let hosting = NSHostingView(rootView: CompositionReplacementHost(
            model: model, store: store, identity: identity, configuration: configuration
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
            backing: .buffered, defer: false
        )
        window.animationBehavior = .none
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        let system = store.system(for: identity, initialText: model.text, configuration: configuration)
        window.makeFirstResponder(system.textView)
        system.selectedRange = NSRange(location: 5, length: 0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let unset = NSRange(location: NSNotFound, length: 0)
        system.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: unset)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        if let replacement {
            model.text = replacement
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        system.textView.insertText("你好", replacementRange: unset)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        return model.text
    }

    @Test func aModelReplacementDuringACompositionIsNotRevertedByTheCommit() {
        let result = commitComposition(replacingModelWith: "EXTERNAL VERSION FROM DISK")

        #expect(result.contains("EXTERNAL VERSION FROM DISK"), "model after commit: \(result)")
    }

    /// Control: without a model replacement the commit is published as before.
    @Test func anUndisturbedCompositionStillPublishesItsCommit() {
        let result = commitComposition(replacingModelWith: nil)

        #expect(result == "hello你好 world", "model after commit: \(result)")
    }
}
