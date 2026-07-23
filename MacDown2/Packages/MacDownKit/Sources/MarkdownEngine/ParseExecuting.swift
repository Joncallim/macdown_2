import Foundation

/// The seam (D5). The production conformer is ParseEngine; tests inject spies.
public protocol ParseExecuting: Sendable {
    func parse(
        _ text: String,
        options: MarkdownParseOptions,
        revision: Int
    ) async throws -> MarkdownDocument
}
