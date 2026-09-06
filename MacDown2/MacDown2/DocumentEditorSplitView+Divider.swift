import SwiftUI
import Workspace

/// The draggable divider between editor and preview. Split out of
/// `DocumentEditorSplitView.swift` to stay under the type-body-length lint
/// budget, matching `DocumentEditorSplitView+AppSettings.swift`'s reason for
/// existing — that file uses static, parameter-driven conversions to avoid
/// needing any instance access; this one genuinely needs drag state, so
/// `dragOriginFraction`, `currentSplitFraction`, and `coordinator` are
/// internal (not `private`) in the main file instead.
extension DocumentEditorSplitView {
    func divider(in geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(.separator)
            .frame(width: dividerWidth)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let total = geometry.size.width
                        guard total > 0 else { return }
                        if dragOriginFraction == nil {
                            guard let currentSplitFraction else {
                                assertionFailure("Drag origin captured in non-split layout")
                                return
                            }
                            dragOriginFraction = currentSplitFraction
                        }
                        let fraction = (dragOriginFraction ?? 0.5) + value.translation.width / total
                        model.tabStore.setPreviewLayout(
                            .split(fraction: fraction),
                            for: tab.id
                        )
                        coordinator?.scheduleSaveSession()
                    }
                    .onEnded { _ in
                        dragOriginFraction = nil
                    }
            )
            .accessibilityLabel("Resize editor and preview")
    }
}
