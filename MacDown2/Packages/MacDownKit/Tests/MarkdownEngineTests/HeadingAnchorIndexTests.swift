import Foundation
@testable import MarkdownEngine
import Testing

struct HeadingAnchorIndexTests {
    @Test func repeatedHeadingsCarrySourceLocationsAndReserveAuthoredIDs() async throws {
        let source = "---\ntitle: Sample\n---\n# A\n# A\n# A-1\n"
        let parsed = try await ParseEngine().parse(source, revision: 7)
        let epoch = UUID()
        let index = try HeadingAnchorIndex(
            document: parsed, sourceText: source, documentID: "doc-1",
            recoveryEpoch: epoch, sourceGeneration: 9, reservedIDs: ["a", "a-1"]
        )

        #expect(index.headings.map(\.fragment) == ["a-2", "a-3", "a-1-1"])
        #expect(index.headings.map(\.sourceLineRange) == [4 ... 4, 5 ... 5, 6 ... 6])
        #expect(index.headings.map(\.ordinal) == [0, 1, 2])
        #expect(index.headings[0].sourceUTF16Range.lowerBound == (source as NSString).range(of: "# A").location)
        #expect(index.identity.documentID == "doc-1")
        #expect(index.identity.recoveryEpoch == epoch)
        #expect(index.identity.sourceGeneration == 9)
        #expect(index.identity.parseRevision == 7)
        #expect(index.identity.allocatorPolicyVersion == HeadingAnchorAllocator.policyVersion)
    }

    @Test func exactSourceAndLifetimeDefineIndexIdentity() async throws {
        let source = "# Café 東京\n"
        let parsed = try await ParseEngine().parse(source, revision: 3)
        let epoch = UUID()
        let first = try HeadingAnchorIndex(
            document: parsed, sourceText: source, documentID: "doc-1",
            recoveryEpoch: epoch, sourceGeneration: 1, reservedIDs: []
        )
        let same = try HeadingAnchorIndex(
            document: parsed, sourceText: source, documentID: "doc-1",
            recoveryEpoch: epoch, sourceGeneration: 1, reservedIDs: []
        )
        let newLifetime = try HeadingAnchorIndex(
            document: parsed, sourceText: source, documentID: "doc-1",
            recoveryEpoch: UUID(), sourceGeneration: 1, reservedIDs: []
        )
        let changedSource = source + "more"
        let reparsed = try await ParseEngine().parse(changedSource, revision: 4)
        let newSource = try HeadingAnchorIndex(
            document: reparsed, sourceText: changedSource, documentID: "doc-1",
            recoveryEpoch: epoch, sourceGeneration: 2, reservedIDs: []
        )

        #expect(first == same)
        #expect(first.identity != newLifetime.identity)
        #expect(first.identity.sourceSHA256 != newSource.identity.sourceSHA256)
        #expect(first.headings.map(\.fragment) == ["café-東京"])
    }

    @Test func staleParseCannotBeAssignedANewerSourceIdentity() async throws {
        let source = "# Original\n"
        let parsed = try await ParseEngine().parse(source, revision: 1)
        do {
            _ = try HeadingAnchorIndex(
                document: parsed, sourceText: "# Replaced\n", documentID: "doc-1",
                recoveryEpoch: UUID(), sourceGeneration: 2, reservedIDs: []
            )
            Issue.record("A stale parse must not acquire a newer source identity")
        } catch {
            #expect(error as? HeadingAnchorIndex.Error == .sourceDoesNotMatchParse)
        }
    }
}
