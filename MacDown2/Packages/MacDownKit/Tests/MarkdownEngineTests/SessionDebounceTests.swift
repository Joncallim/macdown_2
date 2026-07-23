import Foundation
@testable import MarkdownEngine
import Testing

@MainActor
struct SessionDebounceTests {
    @Test func rapidKeystrokesCoalesce() async throws {
        let spy = ParseSpy(delay: .milliseconds(5))
        let session = MarkdownParseSession(engine: spy, debounce: .milliseconds(50))

        for index in 0 ..< 20 {
            session.textDidChange("text \(index)")
            try await Task.sleep(for: .milliseconds(5))
        }

        // Wait for the final debounced parse to start, then give any
        // in-flight parses time to finish before asserting coalescing.
        await Fixtures.wait(timeout: .seconds(2)) { await spy.calls.count >= 1 }
        try await Task.sleep(for: .milliseconds(200))

        #expect(session.completedParseCount <= 3, "Expected coalescing; got \(session.completedParseCount)")
    }

    @Test func parseNowBypassesDebounce() async {
        let spy = ParseSpy(delay: .milliseconds(20))
        let session = MarkdownParseSession(engine: spy, debounce: .seconds(10))

        _ = await session.parseNow("now")

        #expect(session.completedParseCount == 1)
        #expect(session.document?.body == "now")
    }

    @Test func parseNowCancelsPendingDebounce() async {
        let spy = ParseSpy(delay: .milliseconds(20))
        let session = MarkdownParseSession(engine: spy, debounce: .milliseconds(50))

        session.textDidChange("debounced")
        _ = await session.parseNow("immediate")

        #expect(session.document?.body == "immediate")
    }

    @Test func staleRevisionResultNotPublished() async {
        let spy = ParseSpy()
        let session = MarkdownParseSession(engine: spy, debounce: .milliseconds(10))

        await spy.stub(1, with: .success(MarkdownDocument(
            body: "old",
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: "old"),
            revision: 1,
            options: .default
        )))
        await spy.stub(2, with: .success(MarkdownDocument(
            body: "second",
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: "second"),
            revision: 2,
            options: .default
        )))

        _ = await session.parseNow("first")
        _ = await session.parseNow("second")

        #expect(session.document?.body == "second")
        #expect(session.completedParseCount == 2)
    }

    @Test func olderDocumentRevisionIsDropped() async {
        let spy = ParseSpy()
        let session = MarkdownParseSession(engine: spy, debounce: .milliseconds(10))

        await spy.stub(1, with: .success(MarkdownDocument(
            body: "first",
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: "first"),
            revision: 1,
            options: .default
        )))
        await spy.stub(2, with: .success(MarkdownDocument(
            body: "second",
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: "second"),
            revision: 2,
            options: .default
        )))

        _ = await session.parseNow("first")
        _ = await session.parseNow("second")
        // A hypothetical conformer returns revision 1 again.
        await spy.stub(3, with: .success(MarkdownDocument(
            body: "stale",
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: "stale"),
            revision: 1,
            options: .default
        )))
        _ = await session.parseNow("third")

        #expect(session.document?.body == "second")
        #expect(session.completedParseCount == 2)
    }

    @Test func engineErrorKeepsPreviousDocument() async {
        let spy = ParseSpy()
        let session = MarkdownParseSession(engine: spy, debounce: .milliseconds(10))

        await spy.stub(1, with: .success(MarkdownDocument(
            body: "ok",
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: "ok"),
            revision: 1,
            options: .default
        )))
        await spy.stub(2, throwing: TestError.planned)

        _ = await session.parseNow("ok")
        _ = await session.parseNow("bad")

        #expect(session.document?.body == "ok")
        #expect(session.completedParseCount == 1)
    }

    @Test func revisionsAreMonotonic() async throws {
        let spy = ParseSpy()
        let session = MarkdownParseSession(engine: spy, debounce: .milliseconds(10))

        session.textDidChange("one")
        session.textDidChange("two")
        _ = await session.parseNow("three")

        await Fixtures.wait(timeout: .seconds(2)) { await spy.calls.count >= 1 }
        try await Task.sleep(for: .milliseconds(100))

        let revisions = await spy.calls.map(\.revision)
        #expect(revisions == revisions.sorted())
        #expect(Set(revisions).count == revisions.count)
    }

    @Test func parsesOffMainThread() async throws {
        let engine = ParseEngine()
        let document = try await engine.parse("# Hello\n", revision: 1)

        #expect(document.headings.count == 1)
        #expect(document.headings[0].title == "Hello")
    }

    @Test func rapidChangeDuringParseKeepsParsingStateTrue() async throws {
        let spy = ParseSpy(delay: .milliseconds(100))
        let session = MarkdownParseSession(engine: spy, debounce: .milliseconds(10))

        session.textDidChange("first")
        try await Task.sleep(for: .milliseconds(50))
        session.textDidChange("second")
        try await Task.sleep(for: .milliseconds(70))

        #expect(session.isParsing == true, "A newer parse is still pending/running")
    }

    @Test func parsingStateClearsAfterDebouncedParseCompletes() async {
        // Regression: the pre-increment generation capture meant clearIfCurrent
        // never matched, so isParsing stuck true after every debounced parse.
        let spy = ParseSpy()
        let session = MarkdownParseSession(engine: spy, debounce: .milliseconds(10))

        session.textDidChange("done soon")
        await Fixtures.wait { await MainActor.run { session.completedParseCount >= 1 && !session.isParsing } }

        #expect(session.completedParseCount == 1)
        #expect(session.isParsing == false, "Completed debounced parse must clear isParsing")
    }
}

private enum TestError: Error {
    case planned
}
