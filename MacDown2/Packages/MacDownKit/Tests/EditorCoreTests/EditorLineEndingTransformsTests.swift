import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Cross-feature audit findings: line transforms must keep the document's own
/// line endings (invariant #5) in CRLF and bare-CR documents.
@MainActor
@Suite("Line transforms keep the document's line endings")
struct EditorLineEndingTransformsTests {
    private let support = EditingAssistIntegrationSupport.self

    private func mounted(_ text: String, language: String? = nil) -> (EditorTextSystem, NSWindow) {
        var configuration = EditorConfiguration.default
        if let language {
            configuration.languageProfile = LanguageEditingProfileRegistry.profile(for: language)
        }
        let system = support.makeSystem(text: text, configuration: configuration)
        let window = support.mountInWindow(system)
        system.textView.delegate = support.makeCoordinator(system: system)
        return (system, window)
    }

    private func run(_ text: String, language: String? = nil, _ action: (EditorTextSystem) -> Bool) -> String {
        let (system, window) = mounted(text, language: language)
        defer { window.orderOut(nil) }
        system.selectedRange = NSRange(location: 0, length: (text as NSString).length)
        _ = action(system)
        return system.textView.string
    }

    // MARK: - Duplicate Line

    @Test func duplicatingTheWholeCRLFDocumentUsesCRLF() {
        #expect(run("a\r\nb") { $0.duplicateLines() } == "a\r\nb\r\na\r\nb")
    }

    @Test func duplicatingTheWholeBareCRDocumentUsesCR() {
        #expect(run("a\rb") { $0.duplicateLines() } == "a\rb\ra\rb")
    }

    @Test func duplicatingASingleLineDocumentStillUsesLinefeed() {
        #expect(run("only") { $0.duplicateLines() } == "only\nonly")
    }

    // MARK: - Toggle Comment

    @Test func toggleCommentOnABareCRDocumentCommentsEveryLine() {
        #expect(run("a\rb\rc", language: "yaml") { $0.toggleComment() } == "# a\r# b\r# c")
    }

    @Test func toggleCommentRoundTripsOnABareCRDocument() {
        #expect(run("# a\r# b", language: "yaml") { $0.toggleComment() } == "a\rb")
    }

    @Test func toggleCommentUncommentsACRLFBlockContainingABlankLine() {
        #expect(run("# a\r\n\r\n# b", language: "yaml") { $0.toggleComment() } == "a\r\n\r\nb")
    }

    @Test func toggleCommentCommentsACRLFBlockAndSkipsTheBlankLine() {
        #expect(run("a\r\n\r\nb", language: "yaml") { $0.toggleComment() } == "# a\r\n\r\n# b")
    }

    @Test func linefeedBehaviourIsUnchanged() {
        #expect(run("a\n\nb", language: "yaml") { $0.toggleComment() } == "# a\n\n# b")
    }

    // MARK: - Increase Indent

    @Test func increaseIndentOnABareCRDocumentIndentsEveryLine() {
        #expect(run("a\rb\rc") { $0.increaseIndent() } == "    a\r    b\r    c")
    }

    @Test func increaseIndentOnACRLFDocumentKeepsCRLF() {
        #expect(run("a\r\nb") { $0.increaseIndent() } == "    a\r\n    b")
    }

    /// Replaces the old single-separator choice (`lineSplitSeparator`, which split `a\rb\r\nc` on LF only and so
    /// skipped the bare-CR line): a block is split at every LF and lone CR; a CRLF's CR stays with its line.
    @Test func logicalLinesSplitAtEveryLFAndLoneCRPreservingEachSeparator() {
        let mixed = EditorLineTransforms.logicalLines(of: "a\rb\r\nc\nd")
        #expect(mixed.lines == ["a", "b\r", "c", "d"])
        #expect(mixed.separators == ["\r", "\n", "\n"])
        #expect(EditorLineTransforms.joinLogicalLines(mixed.lines, separators: mixed.separators) == "a\rb\r\nc\nd")
        #expect(EditorLineTransforms.logicalLines(of: "ab").lines == ["ab"])
        #expect(EditorLineTransforms.logicalLines(of: "a\n").lines == ["a", ""])
    }
}
