import AppSettings
import SwiftUI

struct MarkdownSettingsPane: View {
    @Environment(\.appSettings) private var appSettings

    var body: some View {
        if let appSettings {
            MarkdownSettingsForm(appSettings: appSettings)
        } else {
            ContentUnavailableView("Settings Unavailable", systemImage: "gearshape")
        }
    }
}

private struct MarkdownSettingsForm: View {
    @Bindable var appSettings: AppSettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Parse block directives (`:::`)", isOn: $appSettings.markdown.parsesBlockDirectives)
            } footer: {
                Text(
                    "Tables, task lists, strikethrough, autolinks, and footnotes always parse — " +
                        "MacDown 2's current Markdown engine does not yet support turning them off individually."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
