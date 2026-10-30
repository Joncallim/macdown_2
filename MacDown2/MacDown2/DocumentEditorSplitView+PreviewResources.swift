import FileCore
import Preview
import SwiftUI

extension DocumentEditorSplitView {
    @ViewBuilder
    var previewResourceAction: some View {
        if document.fileURL != nil, canRequestPreviewResources {
            HStack(spacing: 8) {
                if previewResourceWindowState?.hasGrant(for: document) == true {
                    Button("Change preview resources folder") {
                        coordinator?.allowPreviewResources(for: model, document: document, tabID: tab.id)
                    }
                    .accessibilityIdentifier("allowPreviewResources")
                } else {
                    Text("Preview resources unavailable")
                    Button("Allow preview resources") {
                        coordinator?.allowPreviewResources(for: model, document: document, tabID: tab.id)
                    }
                    .accessibilityIdentifier("allowPreviewResources")
                }
            }
            .font(.caption)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
    }

    private var canRequestPreviewResources: Bool {
        Self.resourceAccessAvailable(document: document, mode: tab.previewMode)
    }

    static func resourceAccessAvailable(document: FileCore.FileDocument, mode: PreviewMode?) -> Bool {
        guard document.fileURL != nil else { return false }
        switch PreviewRouter.previewKind(for: document.format) {
        case .markdown: return true
        case .html:
            return (mode ?? PreviewRouter.defaultPreviewMode(for: document.format)) != .source
        case .jsonOutline, .none: return false
        }
    }
}
