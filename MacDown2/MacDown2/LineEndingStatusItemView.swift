import FileCore
import SwiftUI

/// The status bar's line-ending indicator (EPIC-22 §6.17, Slice 8c). Shows
/// what the document actually contains (including Mixed) and offers explicit
/// conversion; nothing is converted implicitly.
struct LineEndingStatusItemView: View {
    let profile: LineEndingProfile
    let onConvert: (LineEnding) -> Void

    var label: String {
        switch profile.kind {
        case .none: String(localized: "No Line Endings")
        case .lineFeed: "LF"
        case .crlf: "CRLF"
        case .carriageReturn: "CR"
        case .mixed: String(localized: "Mixed Line Endings")
        }
    }

    var body: some View {
        Menu(label) {
            ForEach(LineEndingChoice.allCases) { choice in
                Toggle(
                    choice.menuTitle,
                    isOn: Binding(
                        get: { profile.uniformEnding == choice.ending },
                        set: { _ in onConvert(choice.ending) }
                    )
                )
                .disabled(profile.kind == .none)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("statusBarLineEnding")
        .help("Line Endings")
    }
}
