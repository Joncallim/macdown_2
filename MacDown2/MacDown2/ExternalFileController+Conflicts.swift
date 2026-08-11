import FileCore
import Workspace

extension ExternalFileController {
    func resolveConflict(_ resolution: ConflictResolution) async {
        guard !disposed,
              let model,
              let document = model.activeDocument,
              document.state == .conflict
        else { return }
        guard resolution != .cancel else {
            notice = .conflict
            return
        }

        let context = OperationContext(document: document, generation: lifecycleGeneration)
        let observation: DocumentFileObservation = if resolution == .keepMine, let latestExternalSnapshot {
            .available(latestExternalSnapshot)
        } else {
            await monitor.snapshotNow()
        }
        guard isCurrent(context, in: model) else { return }

        await applyConflictObservation(observation, resolution: resolution, document: document, model: model)
    }

    private func applyConflictObservation(
        _ observation: DocumentFileObservation,
        resolution: ConflictResolution,
        document: FileDocument,
        model: WorkspaceModel
    ) async {
        switch observation {
        case let .available(snapshot):
            await applyConflictResolution(resolution, snapshot: snapshot, document: document, model: model)
        case let .moved(snapshot):
            await applyMove(snapshot, to: document, model: model)
            guard let rebound = model.activeDocument,
                  rebound.fileURL?.standardizedFileURL == snapshot.revision.url.standardizedFileURL,
                  rebound.state == .conflict
            else { return }
            await applyConflictResolution(resolution, snapshot: snapshot, document: rebound, model: model)
        case let .missing(url):
            guard url.standardizedFileURL == boundURL else { return }
            applyUnavailable(.missingOrMoved, to: document, model: model)
        case let .unavailable(url, issue):
            guard url.standardizedFileURL == boundURL else { return }
            applyUnavailable(issue, to: document, model: model)
        }
    }
}
