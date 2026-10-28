@testable import DiagramRendering
import Diagrams
import Foundation
import Testing
import WebKit

@MainActor
struct MermaidHarnessNavigationCompletionTests {
    @Test func unrelatedNavigationCannotCompleteTheMermaidHarnessLoad() async throws {
        let completion = MermaidHarnessNavigationCompletion()
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
            completion.finish(for: unrelated, with: .failure(MermaidRenderError.rendererUnavailable))
            completion.finish(for: nil, with: .failure(MermaidRenderError.rendererUnavailable))
            #expect(completion.isPending)
            completion.finish(for: expected, with: .success(()))
        }
        #expect(!completion.isPending)

        do {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                completion.begin(continuation) { expected }
                completion.terminate(with: MermaidRenderError.rendererUnavailable)
                completion.finish(for: expected, with: .success(()))
            }
            Issue.record("a late navigation callback revived a torn-down harness load")
        } catch {
            #expect(error as? MermaidRenderError == .rendererUnavailable)
        }
        #expect(!completion.isPending)
    }
}
