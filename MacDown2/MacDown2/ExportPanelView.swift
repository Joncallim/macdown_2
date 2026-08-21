import AppKit
import ExportService
import SwiftUI
import UniformTypeIdentifiers

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

    /// The content type the save panel must enforce for this format, so the
    /// saved file's extension always matches what was actually written.
    var contentType: UTType {
        switch self {
        case .standaloneHTML, .selfContainedHTML: .html
        case .pdf: .pdf
        }
    }

    var fileExtension: String {
        contentType.preferredFilenameExtension ?? (self == .pdf ? "pdf" : "html")
    }

    /// Every extension the panel may have appended for some other format, so
    /// switching format replaces the extension instead of appending to it.
    static let knownExtensions = ["html", "htm", "pdf"]

    var explanation: String? {
        switch self {
        case .standaloneHTML: nil
        case .selfContainedHTML: "Embeds the stylesheet and every image into one file that opens anywhere."
        case .pdf: "Embeds every image and prints through the macOS render system."
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
    /// Called when the format changes so the save panel's filename extension and
    /// allowed content type can follow the selection.
    var onFormatChange: (ExportFormatOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Format", selection: $model.format) {
                ForEach(ExportFormatOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Export format")

            if model.format == .standaloneHTML {
                Picker("Style", selection: $model.style) {
                    Text("Embedded CSS").tag(ExportStyleEmbedding.embedded)
                    Text("Linked CSS").tag(ExportStyleEmbedding.linked)
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("Stylesheet delivery")
            } else if let explanation = model.format.explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .frame(width: 380, alignment: .leading)
        .onChange(of: model.format) { _, newValue in
            onFormatChange(newValue)
        }
    }
}
