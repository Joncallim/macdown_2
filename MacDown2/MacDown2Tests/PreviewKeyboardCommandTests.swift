import FileCore
import Foundation
@testable import MacDown2
import Testing

@MainActor
@Suite("Preview keyboard command availability")
struct PreviewKeyboardCommandTests {
    @Test func resourceCommandMatchesDocumentAndMode() {
        let markdown = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/fixture.md"))
        let html = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/fixture.html"))
        let json = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/fixture.json"))
        let untitled = FileDocument()
        #expect(DocumentEditorSplitView.resourceAccessAvailable(document: markdown, mode: nil))
        #expect(DocumentEditorSplitView.resourceAccessAvailable(document: html, mode: nil))
        #expect(DocumentEditorSplitView.resourceAccessAvailable(document: html, mode: .rendered))
        #expect(!DocumentEditorSplitView.resourceAccessAvailable(document: html, mode: .source))
        #expect(!DocumentEditorSplitView.resourceAccessAvailable(document: json, mode: .outline))
        #expect(!DocumentEditorSplitView.resourceAccessAvailable(document: untitled, mode: nil))
    }
}
