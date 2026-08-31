import SwiftUI

/// A small, easy-to-miss-on-purpose indicator that a parse/analysis pass is
/// in flight — the preview otherwise gives no sign it may be a keystroke or
/// two behind the editor. Matches the folder sidebar's own
/// `ProgressView().controlSize(.small)` for a loading row.
struct PreviewBusyIndicator: View {
    let isVisible: Bool

    var body: some View {
        if isVisible {
            ProgressView()
                .controlSize(.small)
                .padding(8)
                .accessibilityIdentifier("previewBusyIndicator")
        }
    }
}
