import FileCore
import SwiftUI

/// File-menu encoding commands (EPIC-22 §6.17, Slice 8b).
enum EncodingChoices {
    /// Encodings offered first, with the Unicode variants that differ in
    /// BOM. The remainder of the OS catalogue sits under "Other".
    static let saveCommon: [FileEncodingMetadata] = [
        FileEncodingMetadata(encoding: .utf8, bom: .none),
        FileEncodingMetadata(encoding: .utf8, bom: .utf8),
        FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .utf16LittleEndian),
        FileEncodingMetadata(encoding: .utf16BigEndian, bom: .utf16BigEndian),
        FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .none),
        FileEncodingMetadata(encoding: .utf16BigEndian, bom: .none),
    ] + FileEncodingCatalog.curated.dropFirst(3).map { FileEncodingMetadata(encoding: $0, bom: .none) }

    static let reopenCommon: [String.Encoding] = FileEncodingCatalog.curated
    static let other: [String.Encoding] = Array(FileEncodingCatalog.all.dropFirst(FileEncodingCatalog.curated.count))
}

extension WorkspaceCommands {
    @ViewBuilder
    var encodingMenus: some View {
        let current = coordinator?.keyDocumentEncoding
        let enabled = coordinator?.keyDocumentSupportsEncodingChange == true

        Menu("Reopen with Encoding") {
            ForEach(EncodingChoices.reopenCommon, id: \.rawValue) { encoding in
                reopenButton(encoding, isCurrent: current?.encoding == encoding)
            }
            Menu("Other") {
                ForEach(EncodingChoices.other, id: \.rawValue) { encoding in
                    reopenButton(encoding, isCurrent: current?.encoding == encoding)
                }
            }
        }
        .disabled(!enabled)

        Menu("Save with Encoding") {
            ForEach(EncodingChoices.saveCommon, id: \.self) { metadata in
                saveButton(metadata, isCurrent: current == metadata)
            }
            Menu("Other") {
                ForEach(EncodingChoices.other, id: \.rawValue) { encoding in
                    let metadata = FileEncodingMetadata(encoding: encoding, bom: .none)
                    saveButton(metadata, isCurrent: current == metadata)
                }
            }
        }
        .disabled(!enabled)
    }

    private func reopenButton(_ encoding: String.Encoding, isCurrent: Bool) -> some View {
        Toggle(
            FileEncodingMetadata(encoding: encoding, bom: .none).displayName,
            isOn: Binding(get: { isCurrent }, set: { _ in coordinator?.reopenKeyDocument(withEncoding: encoding) })
        )
    }

    private func saveButton(_ metadata: FileEncodingMetadata, isCurrent: Bool) -> some View {
        Toggle(
            metadata.displayName,
            isOn: Binding(get: { isCurrent }, set: { _ in coordinator?.saveKeyDocument(withEncoding: metadata) })
        )
    }
}
