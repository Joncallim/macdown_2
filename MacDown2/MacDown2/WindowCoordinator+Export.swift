import Workspace

/// Tracks which documents currently have an export in flight. `ExportCoordinator`
/// is a stateless value type re-created per menu evaluation (see its own doc
/// comment), so this — the one piece of state an in-flight export actually
/// needs — lives on the coordinator, which persists across evaluations.
/// Scoped per `WorkspaceModel` (one per window) rather than app-wide, so
/// exporting two different documents in two different windows at the same
/// time is unaffected; only re-firing export for the *same* document while
/// its own export is still running is blocked.
extension WindowCoordinator {
    func isExporting(_ model: WorkspaceModel) -> Bool {
        exportingModels.contains(ObjectIdentifier(model))
    }

    func setExporting(_ isExporting: Bool, for model: WorkspaceModel) {
        if isExporting {
            exportingModels.insert(ObjectIdentifier(model))
        } else {
            exportingModels.remove(ObjectIdentifier(model))
        }
    }
}
