/// The consumer that will place a first-party contribution. A representation
/// is admitted for that consumer before any HTML or Markdown is published.
public enum ContributionDestination: Sendable, Equatable {
    case nativePreview
    case htmlExport
    case pdfExport
    case quickLook
}

/// A typed capability decision; consumers own the user-facing diagnostic and
/// preserve authored source when a representation is unsupported.
public enum ContributionAdmission: Sendable, Equatable {
    case accepted
    case unsupported(ContributionDestination)
}

public extension ContributionRepresentation {
    func admission(to destination: ContributionDestination) -> ContributionAdmission {
        switch self {
        case .markdown:
            .accepted
        case .html:
            switch destination {
            case .nativePreview:
                .unsupported(destination)
            case .htmlExport, .pdfExport, .quickLook:
                .accepted
            }
        }
    }
}
