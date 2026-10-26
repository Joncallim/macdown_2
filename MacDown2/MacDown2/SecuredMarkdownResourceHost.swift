import FileCore
import Preview
import SwiftUI

/// Binds each Textual attachment load to its document and grant revision. A changed identity denies the old
/// loader immediately, then starts a fresh token if this window still owns the document and folder selection.
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
        ZStack(alignment: .topLeading) {
            content(loader, current?.loadID)
        }
        .task(id: currentIdentity) {
            guard !Task.isCancelled, identity == currentIdentity else { return }
            let context = owner?.beginPreviewLoad(
                for: document, tabID: tabID,
                sourceGeneration: sourceGeneration, grantRevision: currentIdentity.grantRevision,
                consumer: .markdown
            )
            guard !Task.isCancelled, identity == currentIdentity else {
                if let context {
                    owner?.retire(.markdown, matching: context)
                }
                return
            }
            slot = Slot(identity: currentIdentity, loadID: UUID(), context: context)
        }
        .onDisappear {
            if let context = current?.context {
                owner?.retire(.markdown, matching: context)
            }
        }
    }
}
