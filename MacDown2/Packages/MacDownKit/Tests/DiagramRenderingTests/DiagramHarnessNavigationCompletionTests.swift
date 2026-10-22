@testable import DiagramWebKitPool
import Foundation
import Testing
import WebKit

@MainActor
struct DiagramHarnessNavigationCompletionTests {
    @Test func unrelatedNavigationCannotCompleteTheHarnessLoad() async throws {
        let completion = DiagramHarnessNavigationCompletion()
        let expectedView = WKWebView(frame: .zero)
        let unrelatedView = WKWebView(frame: .zero)
        defer {
            expectedView.stopLoading()
            unrelatedView.stopLoading()
        }
        let expected = try #require(expectedView.loadHTMLString("expected", baseURL: nil))
        let unrelated = try #require(unrelatedView.loadHTMLString("unrelated", baseURL: nil))

        let _: Void = try await withCheckedThrowingContinuation { continuation in
            completion.begin(continuation) { expected }
            completion.finish(for: unrelated, with: .failure(DiagramPoolError.pageUnavailable))
            completion.finish(for: nil, with: .failure(DiagramPoolError.pageUnavailable))
            #expect(completion.isPending)
            completion.finish(for: expected, with: .success(()))
        }
        #expect(!completion.isPending)

        do {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                completion.begin(continuation) { expected }
                completion.terminate(with: DiagramPoolError.pageUnavailable)
                completion.finish(for: expected, with: .success(()))
            }
            Issue.record("a navigation callback revived a terminated load")
        } catch {
            #expect(error as? DiagramPoolError == .pageUnavailable)
        }
        #expect(!completion.isPending)
    }
}
