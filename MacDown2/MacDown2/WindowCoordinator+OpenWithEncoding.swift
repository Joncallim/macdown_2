import AppKit
import FileCore
import Foundation

extension WindowCoordinator {
    /// File ▸ Open with Encoding…: choose a file, then how its bytes are read.
    func openFileWithEncoding(relativeTo controller: WindowController? = nil) {
        Task { @MainActor in
            let provider = controller.map { NSFilePanelProvider(window: $0.window) } ?? panelProvider
            guard let url = await provider.chooseFile() else { return }
            await openDocumentChoosingEncoding(at: url, relativeTo: controller?.window)
        }
    }

    /// Asks which encoding to read `url` with, then opens it that way. The text is
    /// decoded losslessly or not at all, and the chosen encoding is kept in the
    /// document so later saves write the same bytes' encoding.
    func openDocumentChoosingEncoding(at url: URL, relativeTo window: NSWindow? = nil) async {
        guard let encoding = promptForEncoding(opening: url) else { return }
        await openDocument(at: url, relativeTo: window, encoding: encoding)
    }

    private func promptForEncoding(opening url: URL) -> FileEncodingMetadata? {
        let encodings = FileEncodingCatalog.curated
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        for encoding in encodings {
            popup.addItem(withTitle: FileEncodingMetadata(encoding: encoding, bom: .none).displayName)
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Open \"\(url.lastPathComponent)\" With Encoding")
        alert.informativeText = String(
            localized: """
            Choose how the file's bytes should be read. Nothing is replaced: if the file does not fit \
            the encoding it will not open, and the file is never changed by opening it.
            """
        )
        alert.accessoryView = popup
        alert.addButton(withTitle: String(localized: "Open"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn,
              encodings.indices.contains(popup.indexOfSelectedItem)
        else { return nil }
        return FileEncodingMetadata(encoding: encodings[popup.indexOfSelectedItem], bom: .none)
    }
}
