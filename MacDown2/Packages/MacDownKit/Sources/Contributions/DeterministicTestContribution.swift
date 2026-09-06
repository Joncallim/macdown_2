import Foundation
import MarkdownEngine

/// A controllable `Contributing` implementation with no real content of its
/// own, used to prove registration, isolation, and cancellation behaviour
/// deterministically (issue #15 deliverable 1) without depending on TOC's
/// own logic. Public, not test-only, because it is also exercised from the
/// app target's own Preview/Export adapter tests
/// (epic-14-implementation.md §14).
public struct DeterministicTestContribution: Contributing {
    public enum Behavior: Sendable {
        /// Always returns this one result.
        case succeeds(ContributionContent)
        /// Returns no results, as if it found nothing to do.
        case producesNothing
        /// Throws immediately, exercising `ContributionRegistry.run`'s
        /// per-contribution isolation.
        case fails(String)
        /// Sleeps far longer than any real test waits, exercising
        /// cancellation propagation: cancelling the caller makes
        /// `Task.sleep` itself throw `CancellationError` before this case
        /// can produce anything.
        case hangs
        /// Deliberately non-cooperative: catches its own `Task.sleep`
        /// cancellation and returns a normal successful result anyway,
        /// proving `ContributionRegistry.run`'s own post-await cancellation
        /// check catches what an individual contribution failed to.
        case ignoresCancellationAndSucceeds(ContributionContent)
    }

    public let id: String
    private let behavior: Behavior

    public init(id: String = "deterministic-test", behavior: Behavior) {
        self.id = id
        self.behavior = behavior
    }

    public func run(
        document _: MarkdownDocument,
        sourceText _: String,
        sourceGeneration: UInt
    ) async throws -> [ContributionResult] {
        switch behavior {
        case let .succeeds(content):
            return [ContributionResult(contributionID: id, content: content, sourceGeneration: sourceGeneration)]
        case .producesNothing:
            return []
        case let .fails(message):
            throw DeterministicTestContributionError(message: message)
        case .hangs:
            try await Task.sleep(for: .seconds(3600))
            return []
        case let .ignoresCancellationAndSucceeds(content):
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch is CancellationError {
                // Deliberately swallowed: this behavior exists to prove the
                // registry's own cancellation check does not depend on it.
            }
            return [ContributionResult(contributionID: id, content: content, sourceGeneration: sourceGeneration)]
        }
    }
}

struct DeterministicTestContributionError: Error, LocalizedError, Equatable {
    let message: String
    var errorDescription: String? {
        message
    }
}
