import SwiftUI

/// The `Settings { }` scene's pane container (`⌘,` / "MacDown 2 → Settings…").
struct SettingsView: View {
    @Environment(\.appSettings) private var appSettings

    var body: some View {
        VStack(spacing: 0) {
            settingsTabs
            if appSettings?.hasUnreadableSettings == true {
                Divider()
                Text(
                    """
                    Some saved settings cannot be read. Changes to those settings last only until you quit; \
                    their saved originals are preserved.
                    """
                )
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .accessibilityIdentifier("settingsPersistenceWarning")
            }
        }
        .frame(width: 480)
    }

    private var settingsTabs: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
            }
            Tab("Editor", systemImage: "character.cursor.ibeam") {
                EditorSettingsPane()
            }
            Tab("Markdown", systemImage: "text.badge.checkmark") {
                MarkdownSettingsPane()
            }
            Tab("Preview & Export", systemImage: "eye") {
                PreviewExportSettingsPane()
            }
            Tab("Formats", systemImage: "tablecells") {
                FormatSettingsPane()
            }
        }
        .frame(width: 480, height: 360)
    }
}
