import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

// Extracted from `EditingAssistIntegrationTests.swift` to keep that file
// under its line-count limit — shares `EditingAssistIntegrationSupport`,
// defined there.

/// E10 safety integration: marked text, E18/model replacement regressions,
/// and the command boundary.
@MainActor
@Suite("Editing assists — safety integration")
struct EditingAssistSafetyTests {
    private let support = EditingAssistIntegrationSupport.self

    // MARK: §16.4 — IME safety

    @Test("hasMarkedText bypasses the engine")
    func markedTextBypassesEngine() {
        let system = support.makeMarkdownSystem(text: "foo bar")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)

        system.textView.setMarkedText(
            "f",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 0, length: 0)
        )
        #expect(system.textView.hasMarkedText())

        // While composing, a typed "(" must take the native path — no pair.
        let handled = coordinator.textView(
            system.textView,
            shouldChangeTextIn: NSRange(location: 1, length: 0),
            replacementString: "("
        )
        #expect(handled, "marked text must pass through natively")
        // The composed "f" was inserted by setMarkedText; no pair may appear.
        #expect(system.text.hasSuffix("(") == false)
        #expect(system.text.hasPrefix("(") == false)
        #expect(system.text == "ffoo bar")

        system.textView.unmarkText()

        // Final normal input after composition still works natively.
        let outcome = MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: 3, length: 0), string: "("),
            text: "foo bar" as NSString,
            selection: NSRange(location: 3, length: 0),
            configuration: .markdownDefault,
            profile: .plainText
        )
        #expect(outcome == .edit(EditingAssistEdit(
            replacementRange: NSRange(location: 3, length: 0),
            replacementString: "()",
            resultingSelection: NSRange(location: 4, length: 0),
            undoActionName: "Insert"
        )))
    }

    // MARK: §16.12 — E18 / model replacement regressions

    @Test("model push (isApplyingModelText) never triggers E10")
    func modelPushBypassesAssists() {
        let system = support.makeMarkdownSystem(text: "foo bar")
        let coordinator = support.makeCoordinator(system: system)
        coordinator.isApplyingModelText = true

        let handled = coordinator.textView(
            system.textView,
            shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementString: "("
        )
        #expect(handled, "model-driven replacement must take the native path")
    }

    @Test("external replacement never publishes through the editor binding")
    func externalReplacementBypassesAssists() {
        let system = support.makeMarkdownSystem(text: "foo bar")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        let (binding, counter) = support.makeBinding()
        coordinator.textBinding = binding

        // The E18 replacement raises isPerformingProgrammaticTextUpdate; the
        // coordinator's textDidChange guard must swallow the echo back.
        system.replaceTextFromExternal(
            "(- item",
            preserving: system.viewportSnapshot(),
            clearUndo: false
        )

        #expect(system.text == "(- item")
        #expect(counter.isEmpty, "external replacement must not publish to the binding")
        #expect(!system.isPerformingProgrammaticTextUpdate)
    }

    // MARK: — Command boundary

    @Test("performMarkdownCommand rejects invalid heading levels at the boundary")
    func invalidHeadingLevelsRejectedAtBoundary() {
        let system = support.makeMarkdownSystem(text: "foo")
        #expect(!system.performMarkdownCommand(.heading(level: 0)))
        #expect(!system.performMarkdownCommand(.heading(level: 7)))
        #expect(system.text == "foo")
    }

    @Test("performMarkdownCommand is disabled for non-Markdown configurations")
    func commandDisabledForNonMarkdown() {
        let system = support.makeSystem(text: "foo")
        #expect(!system.performMarkdownCommand(.bold))
        #expect(system.text == "foo")
    }
}
