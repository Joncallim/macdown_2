import FileCore
import SwiftUI

/// The status bar's encoding indicator (EPIC-22 §6.17, Slice 8b). Always
/// shows the document's current encoding; when the document has a usable
/// backing file it is also a menu for reopening or saving in another one.
struct EncodingStatusItemView: View {
    let encoding: FileEncodingMetadata
    let isChangeable: Bool
    let onReopen: (String.Encoding) -> Void
    let onSave: (FileEncodingMetadata) -> Void

    var body: some View {
        if isChangeable {
            Menu(encoding.displayName) {
                Menu("Reopen with Encoding") {
                    ForEach(EncodingChoices.reopenCommon, id: \.rawValue) { candidate in
                        Toggle(
                            FileEncodingMetadata(encoding: candidate, bom: .none).displayName,
                            isOn: Binding(get: { candidate == encoding.encoding }, set: { _ in onReopen(candidate) })
                        )
                    }
                }
                Menu("Save with Encoding") {
                    ForEach(EncodingChoices.saveCommon, id: \.self) { candidate in
                        Toggle(
                            candidate.displayName,
                            isOn: Binding(get: { candidate == encoding }, set: { _ in onSave(candidate) })
                        )
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("statusBarEncoding")
            .help("Text Encoding")
        } else {
            Text(encoding.displayName)
                .accessibilityIdentifier("statusBarEncoding")
        }
    }
}
