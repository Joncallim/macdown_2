import Foundation

public enum FolderAvailability: Sendable, Equatable {
    case noRoot
    case loading
    case rootUnreadable(reason: String)
    case empty
    case emptyAfterFilter
    case ready
}
