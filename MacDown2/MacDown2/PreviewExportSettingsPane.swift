import AppSettings
import SwiftUI

struct PreviewExportSettingsPane: View {
    @Environment(\.appSettings) private var appSettings

    var body: some View {
        if let appSettings {
            PreviewExportSettingsForm(appSettings: appSettings)
        } else {
            ContentUnavailableView("Settings Unavailable", systemImage: "gearshape")
        }
    }
}

private struct PreviewExportSettingsForm: View {
    @Bindable var appSettings: AppSettingsModel

    var body: some View {
        Form {
            Section("Preview") {
                Picker("Default layout for new tabs", selection: $appSettings.previewExport.defaultPreviewLayout) {
                    Text("Editor Only").tag(PreviewExportSettings.DefaultPreviewLayout.editorOnly)
                    Text("Split Editor & Preview").tag(PreviewExportSettings.DefaultPreviewLayout.split)
                    Text("Preview Only").tag(PreviewExportSettings.DefaultPreviewLayout.previewOnly)
                }
            }

            Section("Export") {
                Picker("Default format", selection: $appSettings.previewExport.defaultExportFormat) {
                    Text("HTML").tag(PreviewExportSettings.DefaultExportFormat.standaloneHTML)
                    Text("Self-contained HTML").tag(PreviewExportSettings.DefaultExportFormat.selfContainedHTML)
                    Text("PDF").tag(PreviewExportSettings.DefaultExportFormat.pdf)
                }

                if appSettings.previewExport.defaultExportFormat == .standaloneHTML {
                    Picker("Default stylesheet delivery", selection: $appSettings.previewExport.defaultExportStyle) {
                        Text("Embedded CSS").tag(PreviewExportSettings.DefaultExportStyle.embedded)
                        Text("Linked CSS").tag(PreviewExportSettings.DefaultExportStyle.linked)
                    }
                }
            } footer: {
                Text("These are starting points for the export panel — every export can still change them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
