import AppSettings
import FileCore
import SwiftUI

/// The format↔extension table is read-only — this pane presents
/// `FileFormatRegistry.defaultFormats` for reference only; nothing here can
/// edit the registry (epic-13-implementation.md §4 invariant 5).
struct FormatSettingsPane: View {
    @Environment(\.appSettings) private var appSettings

    var body: some View {
        if let appSettings {
            FormatSettingsForm(appSettings: appSettings)
        } else {
            ContentUnavailableView("Settings Unavailable", systemImage: "gearshape")
        }
    }
}

private struct FormatSettingsForm: View {
    @Bindable var appSettings: AppSettingsModel

    var body: some View {
        Form {
            Section {
                Picker(
                    "Default encoding for new documents",
                    selection: $appSettings.formats.defaultEncodingForNewDocuments
                ) {
                    Text("UTF-8").tag("utf-8")
                    Text("UTF-16").tag("utf-16")
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("Default encoding for new documents")
            } footer: {
                Text("Applies the next time a new, untitled document is saved. Open documents keep their own encoding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Supported Formats") {
                ForEach(FileFormatRegistry.defaultFormats) { format in
                    LabeledContent(format.name, value: format.extensions.map { ".\($0)" }.joined(separator: ", "))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
