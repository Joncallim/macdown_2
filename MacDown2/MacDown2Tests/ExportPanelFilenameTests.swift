import AppKit
@testable import MacDown2
import Testing

@MainActor
@Suite("Ordinary export panel filename")
struct ExportPanelFilenameTests {
    @Test(arguments: ["Untitled", "Untitled.html"])
    func initialFilenameReplacesTheSystemDefault(_ systemDefault: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = systemDefault

        ExportCoordinator.initializeFilename(.standaloneHTML, in: panel, defaultBaseName: "origin-A")

        #expect(panel.nameFieldStringValue == "origin-A.html")
    }

    @Test func formatChangesPreserveTheUserEnteredBasename() {
        let panel = NSSavePanel()
        ExportCoordinator.initializeFilename(.standaloneHTML, in: panel, defaultBaseName: "origin-A")
        panel.nameFieldStringValue = "Report v1.2.html"

        ExportCoordinator.apply(.pdf, to: panel, defaultBaseName: "origin-A")
        #expect(panel.nameFieldStringValue == "Report v1.2.pdf")

        ExportCoordinator.apply(.standaloneHTML, to: panel, defaultBaseName: "origin-A")
        #expect(panel.nameFieldStringValue == "Report v1.2.html")
    }
}
