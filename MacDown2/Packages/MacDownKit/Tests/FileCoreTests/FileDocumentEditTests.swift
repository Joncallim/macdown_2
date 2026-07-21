@testable import FileCore
import Foundation
import Testing

@Suite("FileDocument.edited(text:) transitions")
struct FileDocumentEditTests {
    @Test("editing clean text marks dirty and preserves identity")
    func editingCleanMarksDirty() {
        let document = FileDocument(text: "hello")
        let edited = document.edited(text: "hello world")

        #expect(edited.text == "hello world")
        #expect(edited.state == .dirty)
        #expect(edited.id == document.id)
        #expect(edited.fileURL == document.fileURL)
        #expect(edited.format.id == document.format.id)
    }

    @Test("editing with identical text still marks clean as dirty")
    func noOpEditMarksDirty() {
        let document = FileDocument(text: "unchanged")
        #expect(document.state == .clean)

        let edited = document.edited(text: "unchanged")

        #expect(edited.text == "unchanged")
        #expect(edited.state == .dirty)
    }

    @Test("editing an already dirty document stays dirty")
    func editingDirtyStaysDirty() {
        let document = FileDocument(text: "hello").edited(text: "hello!")
        #expect(document.state == .dirty)

        let edited = document.edited(text: "hello!!")

        #expect(edited.text == "hello!!")
        #expect(edited.state == .dirty)
    }

    @Test("editing while prompting close returns to dirty")
    func editingPromptingCloseReturnsToDirty() {
        let document = FileDocument(text: "hello").edited(text: "hello!")
        let (prompting, _) = document.requestClose()
        #expect(prompting.state == .promptingClose)

        let edited = prompting.edited(text: "hello!!")

        #expect(edited.text == "hello!!")
        #expect(edited.state == .dirty)
    }

    @Test("saving then editing re-dirties")
    func saveThenEditReDirties() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }

        var document = FileDocument(fileURL: url, text: "version 1")
        document = try document.save()
        #expect(document.state == .clean)

        let edited = document.edited(text: "version 2")
        #expect(edited.state == .dirty)
    }
}
