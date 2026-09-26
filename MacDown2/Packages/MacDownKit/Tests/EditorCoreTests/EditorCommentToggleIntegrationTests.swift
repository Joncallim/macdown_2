import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.13, Slice 4c-iii — `EditorTextSystem.toggleComment()`, mounted
/// against a real `NSTextView`/window -- `EditorCommentToggle` itself
/// already has its own exhaustive pure-logic suite; these tests are
/// specifically about the ADAPTER's own wiring (profile/format resolution,
/// undo registration), not the transform logic.
@MainActor
@Suite("EditorTextSystem toggleComment() (Slice 4c-iii)")
struct EditorCommentToggleIntegrationTests {
    private let support = EditingAssistIntegrationSupport.self

    @Test func toggleCommentOnAMarkdownDocumentUsesItsOwnBlockComment() {
        // `makeMarkdownSystem` only sets `configuration.editingAssists` --
        // `languageProfile` (what actually drives `toggleComment()`, since
        // it isn't gated on E10's own `isEnabled`) must be set explicitly
        // here, matching how the app target's own document-open path
        // resolves a format's profile from `LanguageEditingProfileRegistry`.
        var configuration = EditorConfiguration.default
        configuration.editingAssists = .markdownDefault
        configuration.languageProfile = LanguageEditingProfileRegistry.profile(for: "markdown")
        let system = support.makeSystem(text: "foo", configuration: configuration)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 3)

        let handled = system.toggleComment()

        #expect(handled)
        #expect(system.textView.string == "<!--foo-->")
        #expect(system.textView.undoManager?.canUndo == true)
        system.textView.undoManager?.undo()
        #expect(system.textView.string == "foo")
    }

    @Test func toggleCommentDeclinesForAPlainTextDocumentWithNoCommentSyntax() {
        let system = support.makeSystem(text: "foo")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 0)

        #expect(system.toggleComment() == false)
        #expect(system.textView.string == "foo")
    }

    @Test func toggleCommentOnAnEmptyDocumentDoesNothing() {
        let system = support.makeSystem(text: "")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }

        #expect(system.toggleComment() == false)
        #expect(system.textView.string == "")
    }
}
