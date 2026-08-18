import AppKit
import ExportService
import SwiftUI

/// The selectable export format in the export panel.
enum ExportFormatOption: String, CaseIterable, Identifiable {
    case standaloneHTML
    case selfContainedHTML
    case pdf

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .standaloneHTML: "HTML"
        case .selfContainedHTML: "Self-contained HTML"
        case .pdf: "PDF"
        }
    }
}

/// The user's in-panel export choices. Held by reference so the coordinator can
/// read the final values after the save panel closes.
@MainActor
@Observable
final class ExportSelectionModel {
    var format: ExportFormatOption = .standaloneHTML
    var style: ExportStyleEmbedding = .embedded
}

/// The export panel (Slice 5): format and, for standalone HTML, CSS style. It is
/// hosted as the `NSSavePanel` accessory view, matching the legacy MacDown
/// export panel accessory without importing any of its Objective-C.
struct ExportPanelView: View {
    @Bindable var model: ExportSelectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Format", selection: $model.format) {
                ForEach(ExportFormatOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.format == .standaloneHTML {
                Picker("Style", selection: $model.style) {
                    Text("Embedded CSS").tag(ExportStyleEmbedding.embedded)
                    Text("Linked CSS").tag(ExportStyleEmbedding.linked)
                }
                .pickerStyle(.radioGroup)
            } else {
                Text(
                    model.format == .pdf
                        ? "PDF embeds all resources and prints through the macOS render system."
                        : "Self-contained HTML embeds CSS and images into one file."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .frame(minWidth: 280)
    }
}
