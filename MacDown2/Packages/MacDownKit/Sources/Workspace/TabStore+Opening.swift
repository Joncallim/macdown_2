import FileCore
import Foundation

@MainActor
extension TabStore {
    /// Opens a file into a tab. If a tab for the same standardized file URL
    /// already exists, that tab is activated and no new tab is created.
    /// Returns the resulting tab, or the real reason the file could not be
    /// loaded — never fabricated, so a permission error is not misreported
    /// as "file not found."
    /// The tab already showing `standardized`, made active when this open request
    /// is still the newest one.
    private func activateOpenTab(for standardized: URL, requestGeneration: UInt) -> WorkspaceTab? {
        guard let existing = tabs.first(where: { $0.document.fileURL?.standardizedFileURL == standardized }) else {
            return nil
        }
        if requestGeneration == openRequestGeneration {
            activeTabID = existing.id
        }
        persist()
        return existing
    }

    @discardableResult
    public func openFileInTab(
        _ url: URL,
        encoding: FileEncodingMetadata? = nil
    ) async -> Result<WorkspaceTab, FileStoreError> {
        let url = url.resolvingFinalSymlink()
        openRequestGeneration &+= 1
        return await openFileInTab(url, encoding: encoding, requestGeneration: openRequestGeneration)
    }

    /// Automatic encoding retries belong to the original open intent, even when a newer open finishes meanwhile.
    private func openFileInTab(
        _ url: URL,
        encoding: FileEncodingMetadata?,
        requestGeneration: UInt
    ) async -> Result<WorkspaceTab, FileStoreError> {
        let standardized = url.standardizedFileURL

        if let existing = activateOpenTab(for: standardized, requestGeneration: requestGeneration) {
            return .success(existing)
        }

        let document: FileDocument
        do {
            document = try await FileDocument.create(
                fileURL: url,
                encoding: encoding ?? .utf8Default,
                recoveryBuffer: recoveryBuffer
            )
        } catch {
            return .failure((error as? FileStoreError) ?? .readFailed(underlying: error))
        }
        do {
            let (loaded, needsAutomaticDetection) = try await Task.detached(priority: .userInitiated) {
                let loaded = try document.load()
                let needsAutomaticDetection = encoding == nil
                    && loaded.text.unicodeScalars.contains("\u{0}")
                return (loaded, needsAutomaticDetection)
            }.value
            // The await above lets another intent open/activate this file.
            // Reuse that tab rather than publishing a duplicate completion.
            if let existing = activateOpenTab(for: standardized, requestGeneration: requestGeneration) {
                return .success(existing)
            }
            // BOM-less UTF-16 is "valid UTF-8" — full of NUL bytes. Text with a
            // NUL whose bytes unmistakably are UTF-16 is reopened as such rather
            // than shown (and saved back) as garbage.
            if needsAutomaticDetection,
               let detected = await automaticallyDetectedEncoding(at: url) {
                return await openFileInTab(url, encoding: detected, requestGeneration: requestGeneration)
            }
            if let existing = activateOpenTab(for: standardized, requestGeneration: requestGeneration) {
                return .success(existing)
            }
            let tab = WorkspaceTab(document: loaded)
            tabs.append(tab)
            if requestGeneration == openRequestGeneration {
                activeTabID = tab.id
            }
            persist()
            return .success(tab)
        } catch {
            let failure = (error as? FileStoreError) ?? .readFailed(underlying: error)
            // Neither BOM-marked nor valid UTF-8. Retry once if the bytes
            // themselves identify the encoding (BOM-less UTF-16); anything
            // ambiguous stays a failure that offers an explicit choice.
            if encoding == nil, failure.isUndecodableText,
               let detected = await automaticallyDetectedEncoding(at: url) {
                return await openFileInTab(url, encoding: detected, requestGeneration: requestGeneration)
            }
            if let existing = activateOpenTab(for: standardized, requestGeneration: requestGeneration) {
                return .success(existing)
            }
            return .failure(failure)
        }
    }

    /// Detection rereads and scans the file. Keep both operations away from the UI actor.
    private func automaticallyDetectedEncoding(at url: URL) async -> FileEncodingMetadata? {
        let beforeDetection = beforeAutomaticEncodingDetection
        return await Task.detached(priority: .userInitiated) {
            beforeDetection?()
            return FileStore().conservativelyDetectedEncoding(at: url)
        }.value
    }
}
