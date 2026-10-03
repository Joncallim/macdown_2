import Foundation

extension CMarkGFM {
    enum CMarkError: Error, LocalizedError, CustomStringConvertible {
        case parserCreationFailed
        case parseProducedNoDocument
        case renderFailed

        var description: String {
            switch self {
            case .parserCreationFailed: "cmark could not create a parser"
            case .parseProducedNoDocument: "cmark produced no document"
            case .renderFailed: "cmark could not render HTML"
            }
        }

        var errorDescription: String? {
            description
        }
    }
}
