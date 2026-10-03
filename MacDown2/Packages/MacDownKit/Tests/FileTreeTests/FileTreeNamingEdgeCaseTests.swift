@testable import FileTree
import Foundation
import Testing

struct FileTreeNamingEdgeCaseTests {
    @Test func aCompressedTarballDuplicatesWithItsWholeExtension() {
        #expect(FileTreeNaming.duplicateName(of: "archive.tar.gz", existing: []) == "archive copy.tar.gz")
        #expect(FileTreeNaming
            .duplicateName(of: "archive.tar.gz", existing: ["archive copy.tar.gz"]) == "archive copy 2.tar.gz")
        #expect(FileTreeNaming.duplicateName(of: "data.tar.XZ", existing: []) == "data copy.tar.XZ")
    }

    @Test func ordinaryNamesDuplicateAsBefore() {
        #expect(FileTreeNaming.duplicateName(of: "notes.md", existing: []) == "notes copy.md")
        #expect(FileTreeNaming.duplicateName(of: "v1.2.notes.md", existing: []) == "v1.2.notes copy.md")
        #expect(FileTreeNaming.duplicateName(of: "backup.gz", existing: []) == "backup copy.gz")
        #expect(FileTreeNaming.duplicateName(of: ".gitignore", existing: []) == ".gitignore copy")
        #expect(FileTreeNaming.duplicateName(of: "README", existing: []) == "README copy")
    }

    @Test func dotAndDotDotAreNotValidNames() {
        #expect(FileTreeNaming.validate(".", existing: [], currentName: nil) == .nameReserved("."))
        #expect(FileTreeNaming.validate("..", existing: [], currentName: nil) == .nameReserved(".."))
        #expect(FileTreeNaming.validate("...", existing: [], currentName: nil) == nil)
        #expect(FileTreeNaming.validate(".hidden", existing: [], currentName: nil) == nil)
    }

    @Test func aWhitespaceOnlyNameIsEmpty() {
        #expect(FileTreeNaming.validate("   ", existing: [], currentName: nil) == .nameEmpty)
        #expect(FileTreeNaming.validate("\t\n", existing: [], currentName: nil) == .nameEmpty)
    }
}
