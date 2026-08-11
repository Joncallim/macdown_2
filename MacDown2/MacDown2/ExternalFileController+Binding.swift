import FileCore
import Foundation

extension ExternalFileController {
    func start() {
        synchronize(with: model?.activeDocument)
    }

    /// Reinstalls a watcher only after activation or an explicit user retry.
    /// Bounded recovery never devolves into background polling.
    func retryMonitoring() {
        guard !disposed, let document = model?.activeDocument, let url = document.fileURL else { return }
        let generation = lifecycleGeneration
        let standardized = url.standardizedFileURL
        bindRetryTask?.cancel()
        bindTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await monitor.retryWatching()
                guard isBindingCurrent(generation: generation, url: standardized) else { return }
                bindRetryAttempt = 0
                if case .monitorFailed = notice {
                    notice = .none
                }
            } catch {
                guard isBindingCurrent(generation: generation, url: standardized), isCurrentDocument(document) else {
                    return
                }
                notice = .monitorFailed(error.localizedDescription)
            }
        }
    }

    func synchronize(with document: FileDocument?) {
        guard !disposed else { return }

        if updateExistingBinding(with: document) {
            return
        }

        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        bindTask?.cancel()
        bindRetryTask?.cancel()
        guard let document, let fileURL = document.fileURL else {
            boundURL = nil
            bindTask = Task { [monitor] in await monitor.cancel() }
            return
        }

        bind(fileURL: fileURL.standardizedFileURL, document: document, generation: generation)
    }

    private func updateExistingBinding(with document: FileDocument?) -> Bool {
        guard let document,
              let fileURL = document.fileURL,
              boundURL == fileURL.standardizedFileURL
        else { return false }
        let priorFileObjectID = document.lastKnownRevision?.fileObjectID
        let expectedURL = fileURL.standardizedFileURL
        let generation = lifecycleGeneration
        Task { @MainActor [weak self] in
            guard let self,
                  isBindingCurrent(generation: generation, url: expectedURL)
            else { return }
            await monitor.updatePriorFileObjectID(priorFileObjectID, expectedURL: expectedURL)
        }
        return true
    }

    private func isCurrentDocument(_ document: FileDocument) -> Bool {
        guard let current = model?.activeDocument else { return false }
        return current.id == document.id && current.mutationGeneration == document.mutationGeneration
    }

    private func bind(fileURL: URL, document: FileDocument, generation: UInt) {
        boundURL = fileURL
        let priorID = document.lastKnownRevision?.fileObjectID
        bindTask = Task { [weak self] in
            guard let self else { return }
            await monitor.cancel()
            guard isBindingCurrent(generation: generation, url: fileURL) else { return }
            do {
                try await monitor.bind(
                    to: fileURL,
                    priorFileObjectID: priorID,
                    onObservation: { [weak self] observation in
                        Task { @MainActor [weak self] in
                            self?.handle(observation, generation: generation)
                        }
                    },
                    onHealthChange: { [weak self] health in
                        Task { @MainActor [weak self] in
                            self?.handleMonitorHealth(health, generation: generation)
                        }
                    }
                )
                guard isBindingCurrent(generation: generation, url: fileURL) else { return }
                bindRetryAttempt = 0
                if case .monitorFailed = notice {
                    notice = .none
                }
            } catch {
                guard isBindingCurrent(generation: generation, url: fileURL) else { return }
                notice = .monitorFailed(error.localizedDescription)
                scheduleBindRetry(for: document, generation: generation)
            }
        }
    }
}
