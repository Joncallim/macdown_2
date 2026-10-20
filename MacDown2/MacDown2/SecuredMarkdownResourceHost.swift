import FileCore
import Preview
import SwiftUI

/// A document/revision-bound host for Textual attachment work. The existing preview does not use this host until
/// HTML and Markdown both enforce the grant contract; tests can exercise it without changing the current renderer.
@MainActor
struct SecuredMarkdownResourceHost<Content: View>: View {
    struct Identity: Hashable {
        let tabID: UUID
        let documentID: String
        let recoveryEpoch: UUID
        let fileURL: URL?
        let sourceGeneration: UInt
        let grantRevision: UUID
    }

    private struct Slot {
        let identity: Identity
        let loadID: UUID
        let context: PreviewResourceLoad?
    }

    let tabID: UUID
    let document: FileCore.FileDocument
    let sourceGeneration: UInt
    let content: (PreviewResourceImageLoader, UUID?) -> Content

    @Environment(\.previewResourceWindowState) private var owner
    @State private var slot: Slot?

    private var identity: Identity {
        Identity(
            tabID: tabID, documentID: document.id,
            recoveryEpoch: document.recoveryEpoch, fileURL: document.fileURL,
            sourceGeneration: sourceGeneration,
            grantRevision: owner?.revision ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        )
    }

    var body: some View {
        let currentIdentity = identity
        let current = slot?.identity == currentIdentity ? slot : nil
        let loader = PreviewResourceImageProvider.loader(for: current?.context)
        content(loader, current?.loadID)
            .id(currentIdentity)
            .task(id: currentIdentity) {
                guard identity == currentIdentity else { return }
                let context = owner?.beginLoad(for: document, consumer: .markdown)
                slot = Slot(identity: currentIdentity, loadID: UUID(), context: context)
            }
            .onDisappear {
                if let context = current?.context {
                    owner?.retire(.markdown, matching: context)
                }
            }
    }
}
