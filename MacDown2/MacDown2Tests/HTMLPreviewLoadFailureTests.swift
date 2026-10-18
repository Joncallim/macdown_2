import Foundation
@testable import MacDown2
import Testing

@MainActor
struct HTMLPreviewLoadFailureTests {
    @Test func onlyAnUncancelledMainDocumentFailureRearmsTheLoad() throws {
        let mainURL = try #require(URL(string: "macdown-preview://document/"))
        let frameURL = try #require(URL(string: "macdown-preview://document/frame.html"))
        func failure(_ code: Int, _ url: URL?) -> NSError {
            let info = url.map { [NSURLErrorFailingURLErrorKey: $0] } ?? [:]
            return NSError(domain: NSURLErrorDomain, code: code, userInfo: info)
        }
        let cases: [(error: NSError, expected: Bool)] = [
            (failure(NSURLErrorTimedOut, mainURL), true),
            (failure(NSURLErrorTimedOut, frameURL), false),
            (failure(NSURLErrorTimedOut, nil), false),
            (failure(NSURLErrorCancelled, mainURL), false),
            (failure(102, mainURL), false),
        ]
        for testCase in cases {
            #expect(HTMLPreviewView.Coordinator.isMainDocumentLoadFailure(testCase.error) == testCase.expected)
        }
    }
}
