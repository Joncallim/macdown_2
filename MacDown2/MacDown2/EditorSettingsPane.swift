import AppKit
import AppSettings
import SwiftUI

struct EditorSettingsPane: View {
    @Environment(\.appSettings) private var appSettings

    var body: some View {
        if let appSettings {
            EditorSettingsForm(appSettings: appSettings)
        } else {
            ContentUnavailableView("Settings Unavailable", systemImage: "gearshape")
        }
    }
}

private struct EditorSettingsForm: View {
    @Bindable var appSettings: AppSettingsModel

    /// `NSFontManager` is the source of truth for what `NSFont(name:size:)`
    /// can actually resolve, so the picker never offers a name the editor
    /// couldn't use (epic-13-implementation.md §12).
    private var availableFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    var body: some View {
        Form {
            Section("Font") {
                Picker("Family", selection: $appSettings.editor.font.familyName) {
                    ForEach(availableFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(
                    "Size: \(Int(appSettings.editor.font.size))pt",
                    value: $appSettings.editor.font.size,
                    in: 9 ... 36,
                    step: 1
                )
            }

            Section("Layout") {
                Toggle("Wrap lines", isOn: $appSettings.editor.wrapsLines)
                Toggle("Show invisible characters", isOn: $appSettings.editor.showsInvisibles)
                Stepper(
                    "Indent width: \(appSettings.editor.indentationWidth) spaces",
                    value: $appSettings.editor.indentationWidth,
                    in: 1 ... 8
                )
            }

            Section("Editing Assists") {
                Toggle("Enable editing assists", isOn: $appSettings.editor.assistsEnabled)
                    .help("Markdown-aware assists below. Applies to Markdown documents only.")

                Toggle(
                    "Continue lists, quotes, and indentation on Return",
                    isOn: $appSettings.editor.continuesMarkdownPrefixes
                )
                .disabled(!appSettings.editor.assistsEnabled)

                Toggle(
                    "Auto-pair brackets and Markdown delimiters",
                    isOn: $appSettings.editor.completesMatchingCharacters
                )
                .disabled(!appSettings.editor.assistsEnabled)

                Toggle("Insert spaces for Tab", isOn: $appSettings.editor.convertsTabsToSpaces)
                    .disabled(!appSettings.editor.assistsEnabled)

                Toggle("Smart Home key", isOn: $appSettings.editor.smartHome)
                    .disabled(!appSettings.editor.assistsEnabled)

                Toggle(
                    "Auto-increment ordered list numbers",
                    isOn: $appSettings.editor.autoIncrementOrderedLists
                )
                .disabled(!appSettings.editor.assistsEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
