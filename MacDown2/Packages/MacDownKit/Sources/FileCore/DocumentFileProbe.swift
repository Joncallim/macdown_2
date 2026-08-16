import Foundation

public enum DocumentFileObservation: Sendable, Equatable {
    case available(FileSnapshot)
    case moved(FileSnapshot)
    case missing(URL)
    case unavailable(URL, FileBackingIssue)
}

/// Immutable monitor metadata travels with every emitted observation. The
/// controller uses both generations because a binding can remain the same
/// while an older detached probe is superseded by a newer signal.
public struct DocumentFileObservationContext: Sendable, Equatable {
    public let observation: DocumentFileObservation
    public let bindingGeneration: UInt
    public let requestGeneration: UInt
    public let expectedURL: URL
}

protocol DocumentFileProbing: Sendable {
    func observe(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?
    ) async -> DocumentFileObservation
}

struct DocumentFileProbe: DocumentFileProbing, Sendable {
    let fileStore: FileStore

    init(fileStore: FileStore = FileStore()) {
        self.fileStore = fileStore
    }

    func observe(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?
    ) async -> DocumentFileObservation {
        let store = fileStore
        return await Task.detached(priority: .utility) {
            Self.observeSynchronously(
                expectedURL: expectedURL.standardizedFileURL,
                priorFileObjectID: priorFileObjectID,
                fileStore: store
            )
        }.value
    }

    private static func observeSynchronously(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        fileStore: FileStore
    ) -> DocumentFileObservation {
        do {
            let snapshot = try fileStore.readSnapshot(from: expectedURL)
            guard let priorFileObjectID, let currentID = snapshot.revision.fileObjectID,
                  priorFileObjectID != currentID
            else {
                return .available(snapshot)
            }

            switch findMovedSnapshot(
                in: expectedURL.deletingLastPathComponent(),
                matching: priorFileObjectID,
                excluding: expectedURL,
                fileStore: fileStore
            ) {
            case let .one(snapshot): return .moved(snapshot)
            case .ambiguous: return .unavailable(expectedURL, .ambiguousMove)
            case let .unavailable(issue): return .unavailable(expectedURL, issue)
            case .none: return .available(snapshot)
            }
        } catch {
            return observation(
                after: error,
                expectedURL: expectedURL,
                priorFileObjectID: priorFileObjectID,
                fileStore: fileStore
            )
        }
    }

    private static func observation(
        after error: FileStoreError,
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        fileStore: FileStore
    ) -> DocumentFileObservation {
        switch error {
        case .fileMissing:
            missingOrMoved(
                expectedURL: expectedURL,
                priorFileObjectID: priorFileObjectID,
                fileStore: fileStore
            )
        case .permissionDenied:
            .unavailable(expectedURL, .permissionDenied)
        case .notRegularFile:
            .unavailable(expectedURL, .notRegularFile)
        case let .readFailed(underlying):
            .unavailable(expectedURL, classifyReadFailure(underlying))
        case .invalidURL, .encodingDetectionFailed, .fileChangedDuringRead, .writeFailed,
             .decodingFailed, .conditionalPublicationRecoveryRequired:
            .unavailable(expectedURL, .readFailed(String(describing: error)))
        }
    }

    private enum MoveSearchResult {
        case none
        case one(FileSnapshot)
        case ambiguous
        case unavailable(FileBackingIssue)
    }

    private static func missingOrMoved(
        expectedURL: URL,
        priorFileObjectID: PhysicalFileIdentity.FileObjectID?,
        fileStore: FileStore
    ) -> DocumentFileObservation {
        guard let priorFileObjectID else { return .missing(expectedURL) }
        switch findMovedSnapshot(
            in: expectedURL.deletingLastPathComponent(),
            matching: priorFileObjectID,
            excluding: expectedURL,
            fileStore: fileStore
        ) {
        case let .one(snapshot): return .moved(snapshot)
        case .ambiguous: return .unavailable(expectedURL, .ambiguousMove)
        case let .unavailable(issue): return .unavailable(expectedURL, issue)
        case .none: return .missing(expectedURL)
        }
    }

    private static func findMovedSnapshot(
        in directory: URL,
        matching objectID: PhysicalFileIdentity.FileObjectID,
        excluding expectedURL: URL,
        fileStore: FileStore
    ) -> MoveSearchResult {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .fileResourceIdentifierKey,
                    .volumeIdentifierKey,
                    .isRegularFileKey,
                ],
                options: []
            )
        } catch {
            return .unavailable(classifyParentReadFailure(error))
        }

        var matches: [FileSnapshot] = []
        for url in urls where url.standardizedFileURL != expectedURL.standardizedFileURL {
            // Directory enumeration prefetched the cheap identity metadata.
            // Only a candidate with the exact volume/file identity warrants a
            // full read and SHA-256 calculation; large sibling directories
            // must never hash every Markdown file just to detect a move.
            guard !Task.isCancelled,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let volume = attributes[.systemNumber] as? NSNumber,
                  let file = attributes[.systemFileNumber] as? NSNumber,
                  PhysicalFileIdentity.FileObjectID(
                      volume: volume.stringValue,
                      file: file.stringValue
                  ) == objectID,
                  let snapshot = try? fileStore.readSnapshot(from: url)
            else { continue }
            matches.append(snapshot)
            if matches.count > 1 {
                return .ambiguous
            }
        }
        guard let snapshot = matches.first else { return .none }
        return .one(snapshot)
    }

    private static func classifyReadFailure(_ error: Error) -> FileBackingIssue {
        let nsError = error as NSError
        if nsError.code == NSFileReadNoPermissionError {
            return .permissionDenied
        }
        return .readFailed(error.localizedDescription)
    }

    private static func classifyParentReadFailure(_ error: Error) -> FileBackingIssue {
        let nsError = error as NSError
        switch nsError.code {
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
            return .parentUnavailable
        case NSFileReadNoPermissionError:
            return .permissionDenied
        default:
            return .parentUnavailable
        }
    }
}
