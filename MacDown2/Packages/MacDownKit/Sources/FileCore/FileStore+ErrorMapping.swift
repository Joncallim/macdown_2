import Foundation

extension FileStore {
    func mapReadError(_ error: Error) -> FileStoreError {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            switch POSIXErrorCode(rawValue: Int32(nsError.code)) {
            case .ENOENT, .ENOTDIR:
                return .fileMissing
            case .EACCES, .EPERM:
                return .permissionDenied
            default:
                break
            }
        }
        switch nsError.code {
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
            return .fileMissing
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
            return .permissionDenied
        default:
            return .readFailed(underlying: error)
        }
    }

    func mapWriteError(_ error: Error) -> FileStoreError {
        if let fileStoreError = error as? FileStoreError {
            return fileStoreError
        }
        return switch mapReadError(error) {
        case .fileMissing:
            .fileMissing
        case .permissionDenied:
            .permissionDenied
        default:
            .writeFailed(underlying: error)
        }
    }
}
