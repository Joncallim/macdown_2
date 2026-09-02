@testable import Contributions
import MarkdownEngine
import Testing

@Suite("ContributionRegistry")
struct ContributionRegistryTests {
    @Test func standardRegistryContributesNothingYet() async throws {
        let results = try await ContributionRegistry.standard.run(
            document: Self.emptyDocument(), sourceText: "", sourceGeneration: 0
        )
        #expect(results.isEmpty)
    }

    @Test func aSucceedingContributionsResultIsReturned() async throws {
        let content = ContributionContent(sourceRange: 0 ..< 5, placement: .block, representation: .markdown("- one"))
        let registry = ContributionRegistry(contributions: [
            DeterministicTestContribution(behavior: .succeeds(content)),
        ])

        let results = try await registry.run(document: Self.emptyDocument(), sourceText: "[TOC]", sourceGeneration: 1)

        #expect(results.count == 1)
        #expect(results.first?.content == content)
        #expect(results.first?.sourceGeneration == 1)
        #expect(results.first?.diagnostics.isEmpty == true)
    }

    @Test func aContributionThatProducesNothingReportsNoDiagnostics() async throws {
        let registry = ContributionRegistry(contributions: [
            DeterministicTestContribution(behavior: .producesNothing),
        ])

        let results = try await registry.run(document: Self.emptyDocument(), sourceText: "", sourceGeneration: 0)

        #expect(results.isEmpty)
    }

    /// Isolation (epic-14-implementation.md §6.1, §14): a failing
    /// contribution's thrown error becomes its own diagnostic-bearing
    /// result; it does not prevent a different, succeeding contribution
    /// from placing its own result.
    @Test func aFailingContributionDoesNotPreventAnotherFromSucceeding() async throws {
        let content = ContributionContent(sourceRange: 0 ..< 3, placement: .inline, representation: .markdown("ok"))
        let registry = ContributionRegistry(contributions: [
            DeterministicTestContribution(id: "broken", behavior: .fails("boom")),
            DeterministicTestContribution(id: "fine", behavior: .succeeds(content)),
        ])

        let results = try await registry.run(document: Self.emptyDocument(), sourceText: "", sourceGeneration: 0)

        #expect(results.count == 2)

        let broken = try #require(results.first { $0.contributionID == "broken" })
        #expect(broken.content == nil)
        #expect(broken.diagnostics.count == 1)
        #expect(broken.diagnostics.first?.severity == .error)
        #expect(broken.diagnostics.first?.message.contains("boom") == true)

        let fine = try #require(results.first { $0.contributionID == "fine" })
        #expect(fine.content == content)
        #expect(fine.diagnostics.isEmpty)
    }

    /// Cancellation propagates rather than becoming "one more diagnostic"
    /// (epic-14-implementation.md §6.1, §8, §14).
    @Test func cancellationPropagatesOutOfTheRegistryRun() async {
        let registry = ContributionRegistry(contributions: [
            DeterministicTestContribution(behavior: .hangs),
        ])

        let task = Task {
            try await registry.run(document: Self.emptyDocument(), sourceText: "", sourceGeneration: 0)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation to propagate as an error")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
    }

    static func emptyDocument() -> MarkdownDocument {
        MarkdownDocument(
            body: "",
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: ""),
            revision: 0,
            options: .default
        )
    }
}
