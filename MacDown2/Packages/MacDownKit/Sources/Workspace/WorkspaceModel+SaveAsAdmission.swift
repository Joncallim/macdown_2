import FileCore
import Foundation

extension WorkspaceModel {
    /// Opaque admission for one document's Save As panel and publication.
    /// The app reserves this synchronously at command dispatch, before it
    /// starts any async work that could admit a second panel.
    public struct SaveAsAdmission: Sendable {
        fileprivate let lifetime: SavingDocumentLifetime
        fileprivate let id: UUID
    }

    public func reserveSaveAs(for document: FileDocument) -> SaveAsAdmission? {
        guard isCurrent(document) else { return nil }
        let lifetime = SavingDocumentLifetime(document)
        guard saveAsAdmissions[lifetime] == nil else { return nil }
        let admission = SaveAsAdmission(lifetime: lifetime, id: UUID())
        saveAsAdmissions[lifetime] = admission.id
        return admission
    }

    public func finishSaveAs(_ admission: SaveAsAdmission) {
        guard saveAsAdmissions[admission.lifetime] == admission.id else { return }
        saveAsAdmissions = saveAsAdmissions.filter { $0.value != admission.id }
    }

    func includeSaveAsLifetime(_ document: FileDocument, in admission: SaveAsAdmission) -> Bool {
        guard saveAsAdmissions[admission.lifetime] == admission.id else { return false }
        let lifetime = SavingDocumentLifetime(document)
        guard saveAsAdmissions[lifetime] == nil || saveAsAdmissions[lifetime] == admission.id else { return false }
        saveAsAdmissions[lifetime] = admission.id
        return true
    }

    func ownsSaveAs(_ admission: SaveAsAdmission, for document: FileDocument) -> Bool {
        let lifetime = SavingDocumentLifetime(document)
        return admission.lifetime == lifetime && saveAsAdmissions[lifetime] == admission.id
    }

    public func isAdmittedSaveAsCurrent(_ admission: SaveAsAdmission, for document: FileDocument) -> Bool {
        ownsSaveAs(admission, for: document) && isCurrent(document)
    }
}
