import AppKit
@testable import EditorCore
import Foundation
import SwiftUI
import Testing

/// Mounted helpers: a real `NSWindow` is required for AppKit to post
/// `textDidChange` notifications and register undo items (shipping conditions).
@MainActor
enum EditingAssistIntegrationSupport {
    static func makeSystem(
        text: String = "",
        configuration: EditorConfiguration = .default
    ) -> EditorTextSystem {
        EditorTextSystem(
            identity: UUID().uuidString,
            initialText: text,
            configuration: configuration
        )
    }

    static func makeMarkdownSystem(text: String = "") -> EditorTextSystem {
        var configuration = EditorConfiguration.default
        configuration.editingAssists = .markdownDefault
        return makeSystem(text: text, configuration: configuration)
    }

    /// Mounts the text view in a real window (AppKit notification + undo); returned window keeps it alive.
    static func mountInWindow(_ system: EditorTextSystem) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = system.textView
        window.makeKeyAndOrderFront(nil)
        return window
    }

    static func makeCoordinator(system: EditorTextSystem) -> EditorView.Coordinator {
        let coordinator = EditorView.Coordinator()
        coordinator.system = system
        system.textView.delegate = coordinator
        return coordinator
    }

    /// Counts binding publications so tests can assert the final count.
    final class PublicationCounter {
        var count = 0
        var value = ""

        var isEmpty: Bool {
            // swiftlint:disable:next empty_count
            count == 0
        }
    }

    static func makeBinding() -> (Binding<String>, PublicationCounter) {
        let counter = PublicationCounter()
        let binding = Binding<String>(
            get: { counter.value },
            set: { newValue in
                counter.value = newValue
                counter.count += 1
            }
        )
        return (binding, counter)
    }
}

/// Mounted E10 integration: live source seam, one edit → one publication, undo/redo atomicity.
@MainActor
@Suite("Editing assists — integration")
struct EditingAssistIntegrationTests {
    private let support = EditingAssistIntegrationSupport.self

    // MARK: §16.1 — Live TextKit source seam

    @Test("current TextKit stack exposes an NSTextStorage-backed live source")
    func liveSourceExposesMutableStorage() {
        let system = support.makeMarkdownSystem(text: "hello")
        let source = system.assistTextSource
        #expect(source != nil)
        #expect(source?.length == 5)
        #expect(source?.substring(with: NSRange(location: 1, length: 3)) == "ell")
        #expect(system.contentStorage.attributedString is NSTextStorage)
    }

    @Test("live source reflects edits without a new whole-document snapshot")
    func liveSourceReflectsEdits() {
        let system = support.makeMarkdownSystem(text: "abc")
        system.textView.insertText("X", replacementRange: NSRange(location: 1, length: 0))
        #expect(system.assistTextSource?.substring(with: NSRange(location: 0, length: 4)) == "aXbc")
    }

    // MARK: §16.9 — Configuration gating

    @Test("default configuration is fail-closed disabled")
    func defaultConfigurationDisabled() {
        #expect(EditorConfiguration.default.editingAssists.isEnabled == false)
        #expect(EditorConfiguration.default.editingAssists == .disabled)
        #expect(EditorConfiguration.default.editingAssists == EditingAssistConfiguration.disabled)
    }

    @Test("indentationWidth is normalized to 1...8 in the initializer")
    func indentationWidthNormalized() {
        let wide = EditingAssistConfiguration(isEnabled: true, indentationWidth: 12)
        #expect(wide.indentationWidth == 8)
        let narrow = EditingAssistConfiguration(isEnabled: true, indentationWidth: 0)
        #expect(narrow.indentationWidth == 1)
        #expect(EditingAssistConfiguration.markdownDefault.indentationWidth == 4)
    }

    @Test("live configuration switch stops the very next assist")
    func liveConfigurationSwitchStopsAssists() throws {
        var markdown = EditorConfiguration.default
        markdown.editingAssists = .markdownDefault
        let system = support.makeSystem(text: "foo bar", configuration: markdown)

        // Paired with assists on.
        let handled = try system.applyAssistOutcome(
            MarkdownEditingAssistEngine.outcome(
                for: .replacement(range: NSRange(location: 3, length: 0), string: "("),
                text: #require(system.assistTextSource),
                selection: NSRange(location: 3, length: 0),
                configuration: .markdownDefault
            )
        )
        #expect(handled)
        #expect(system.text == "foo() bar")

        // Switch to the disabled default: the next assist passes through.
        system.apply(.default)
        let passthrough = try MarkdownEditingAssistEngine.outcome(
            for: .replacement(range: NSRange(location: 3, length: 0), string: "("),
            text: #require(system.assistTextSource),
            selection: NSRange(location: 3, length: 0),
            configuration: system.editingAssistConfiguration
        )
        #expect(passthrough == .passthrough)
    }

    // MARK: §16.10 — One action → one publication

    @Test("one pair assist produces one binding write with the final text")
    func pairAssistPublishesOnce() {
        let system = support.makeMarkdownSystem(text: "foo bar")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        let (binding, counter) = support.makeBinding()
        coordinator.textBinding = binding

        let handled = coordinator.textView(
            system.textView,
            shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementString: "("
        )

        #expect(!handled)
        #expect(system.text == "foo() bar")
        #expect(counter.value == "foo() bar")
        #expect(counter.count == 1, "expected exactly one binding publication, got \(counter.count)")
    }

    @Test("one list continuation produces one binding write")
    func listContinuationPublishesOnce() {
        let system = support.makeMarkdownSystem(text: "- item")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        let (binding, counter) = support.makeBinding()
        coordinator.textBinding = binding
        system.selectedRange = NSRange(location: 6, length: 0)

        let handled = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        #expect(handled)
        #expect(system.text == "- item\n- ")
        #expect(counter.count == 1, "expected exactly one binding publication, got \(counter.count)")
    }

    @Test("one formatting command produces one binding write")
    func formattingCommandPublishesOnce() {
        let system = support.makeMarkdownSystem(text: "foo")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        let (binding, counter) = support.makeBinding()
        coordinator.textBinding = binding
        system.selectedRange = NSRange(location: 0, length: 3)

        let handled = system.performMarkdownCommand(.bold)

        #expect(handled)
        #expect(system.text == "**foo**")
        #expect(counter.count == 1, "expected exactly one binding publication, got \(counter.count)")
    }

    // MARK: §16.11 — Undo / redo atomicity

    @Test("pair insertion is one undo step")
    func pairInsertionUndo() {
        let system = support.makeMarkdownSystem(text: "foo bar")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)

        _ = coordinator.textView(
            system.textView,
            shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementString: "("
        )
        #expect(system.text == "foo() bar")
        #expect(system.undoManager.canUndo)

        system.undoManager.undo()
        #expect(system.text == "foo bar")
        system.undoManager.redo()
        #expect(system.text == "foo() bar")
    }

    @Test("list continuation is one undo step")
    func listContinuationUndo() {
        let system = support.makeMarkdownSystem(text: "- item")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 6, length: 0)

        _ = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(system.text == "- item\n- ")
        #expect(system.undoManager.canUndo)

        system.undoManager.undo()
        #expect(system.text == "- item")
        system.undoManager.redo()
        #expect(system.text == "- item\n- ")
    }

    @Test("selected-line indent is one undo step")
    func indentUndo() {
        let system = support.makeMarkdownSystem(text: "ab\ncd")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: 5)

        _ = coordinator.textView(system.textView, doCommandBy: #selector(NSResponder.insertTab(_:)))
        #expect(system.text == "    ab\n    cd")
        #expect(system.undoManager.canUndo)

        system.undoManager.undo()
        #expect(system.text == "ab\ncd")
        system.undoManager.redo()
        #expect(system.text == "    ab\n    cd")
    }

    @Test("bold toggle is one undo step")
    func boldUndo() {
        let system = support.makeMarkdownSystem(text: "foo")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: 3)
        _ = system.performMarkdownCommand(.bold)
        #expect(system.text == "**foo**")
        #expect(system.undoManager.canUndo)

        system.undoManager.undo()
        #expect(system.text == "foo")
        system.undoManager.redo()
        #expect(system.text == "**foo**")
    }

    @Test("selection-only actions add no undo entry")
    func selectionOnlyAddsNoUndo() {
        let system = support.makeMarkdownSystem(text: "    foo")
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        let coordinator = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 7, length: 0)

        let handled = coordinator.textView(
            system.textView,
            doCommandBy: #selector(NSResponder.moveToLeftEndOfLine(_:))
        )
        #expect(handled)
        #expect(system.selectedRange == NSRange(location: 4, length: 0))
        #expect(!system.undoManager.canUndo)
    }
}

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
            configuration: .markdownDefault
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
