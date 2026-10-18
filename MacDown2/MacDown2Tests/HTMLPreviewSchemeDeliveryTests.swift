import Foundation
@testable import MacDown2
import Preview
import Testing
import WebKit

/// Ordered callbacks against the real handler; this is a reentrancy control, not native WebKit scheduling proof.
@MainActor
struct HTMLPreviewSchemeDeliveryTests {
    @Test(arguments: [false, true])
    func stopDuringDeliveryIsTerminal(afterData: Bool) {
        let fixture = Fixture()
        let task = fixture.task()
        let stop = {
            fixture.handler.webView(fixture.view, stop: task)
            fixture.handler.webView(fixture.view, stop: task)
        }
        if afterData {
            task.onData = stop
        } else {
            task.onResponse = stop
        }
        fixture.handler.webView(fixture.view, start: task)
        #expect(task.events == (afterData ? ["response", "data"] : ["response"]))
        task.clearCallbacks()
    }

    @Test(arguments: [false, true])
    func replacingOrDisposingTheRequestRevokesItsConsumers(dispose: Bool) {
        let fixture = Fixture()
        let task = fixture.task()
        task.onResponse = {
            fixture.handler.request = dispose ? nil : HTMLPreviewRequest(source: "replacement", baseURL: nil)
        }
        fixture.handler.webView(fixture.view, start: task)
        #expect(task.events == ["response"])
        task.clearCallbacks()
    }

    @Test func coordinatorDisposalDuringResponseRevokesDelivery() throws {
        let coordinator = HTMLPreviewView.Coordinator()
        let view = coordinator.makeWebView()
        defer { coordinator.dispose(webView: view) }
        let handler = try #require(view.configuration.urlSchemeHandler(forURLScheme: "macdown-preview")
            as? PreviewSchemeHandler)
        handler.request = HTMLPreviewRequest(source: "disposal-control", baseURL: nil)
        let task = Fixture().task()
        task.onResponse = { coordinator.dispose(webView: view) }
        handler.webView(view, start: task)
        #expect(task.events == ["response"])
        task.clearCallbacks()
    }

    @Test func stopBeforeAnErrorPreventsFailureDelivery() {
        let fixture = Fixture()
        let task = fixture.task(path: "missing.txt")
        task.onRequest = { fixture.handler.webView(fixture.view, stop: task) }
        fixture.handler.webView(fixture.view, start: task)
        #expect(task.events.isEmpty)
        task.clearCallbacks()
    }

    @Test func stopForAnotherViewOrTaskDoesNotCancelTheLiveAttempt() {
        let fixture = Fixture()
        let wrongView = Fixture.makeView()
        let task = fixture.task()
        let other = fixture.task()
        task.onResponse = {
            fixture.handler.webView(wrongView, stop: task)
            fixture.handler.webView(fixture.view, stop: other)
        }
        fixture.handler.webView(fixture.view, start: task)
        #expect(task.events == ["response", "data", "finish"])
        #expect(other.events.isEmpty)
        task.clearCallbacks()
    }

    @Test func nestedReuseCannotLetTheRetiredStackFrameFinishANewerAttempt() {
        let fixture = Fixture()
        let task = fixture.task()
        task.onResponse = {
            task.onResponse = nil
            fixture.handler.webView(fixture.view, stop: task)
            fixture.handler.webView(fixture.view, start: task)
        }
        fixture.handler.webView(fixture.view, start: task)
        #expect(task.events == ["response", "response", "data", "finish"])
        task.clearCallbacks()
    }

    @Test func duplicateStartDoesNotReplaceAnActiveAttempt() {
        let fixture = Fixture()
        let task = fixture.task()
        task.onResponse = {
            task.onResponse = nil
            fixture.handler.webView(fixture.view, start: task)
        }
        fixture.handler.webView(fixture.view, start: task)
        #expect(task.events == ["response", "data", "finish"])
        task.clearCallbacks()
    }

    @Test func stoppingOneTaskDoesNotRetireAnotherAdmittedTask() {
        let fixture = Fixture()
        let first = fixture.task()
        let second = fixture.task()
        first.onResponse = {
            second.onResponse = { fixture.handler.webView(fixture.view, stop: first) }
            fixture.handler.webView(fixture.view, start: second)
        }
        fixture.handler.webView(fixture.view, start: first)
        #expect(first.events == ["response"])
        #expect(second.events == ["response", "data", "finish"])
        first.clearCallbacks()
        second.clearCallbacks()
    }

    @Test(arguments: [false, true])
    func terminalCallbackReleasesAdmissionBeforeReentrancy(failing: Bool) {
        let fixture = Fixture()
        let task = fixture.task(path: failing ? "missing.txt" : "")
        task.onTerminal = {
            task.onTerminal = nil
            fixture.handler.webView(fixture.view, start: task)
        }
        fixture.handler.webView(fixture.view, start: task)
        #expect(task.events == (failing ? ["failure", "failure"] : [
            "response", "data", "finish", "response", "data", "finish",
        ]))
        task.clearCallbacks()
    }

    @Test func ordinaryMainDeliveryPreservesContentTypeAndCSP() throws {
        let fixture = Fixture()
        let task = fixture.task()
        fixture.handler.webView(fixture.view, start: task)
        #expect(task.events == ["response", "data", "finish"])
        let response = try #require(task.response as? HTTPURLResponse)
        #expect(response.value(forHTTPHeaderField: "Content-Type") == HTMLPreviewContentType.mainDocument)
        #expect(response.value(forHTTPHeaderField: "Content-Security-Policy") != nil)
        #expect(String(decoding: task.bytes, as: UTF8.self).contains("delivery-control"))
    }
}

private extension HTMLPreviewSchemeDeliveryTests {
    @MainActor
    final class Fixture {
        let handler = PreviewSchemeHandler()
        let view = makeView()

        init() {
            handler.request = HTMLPreviewRequest(source: "<p>delivery-control</p>", baseURL: nil)
        }

        func task(path: String = "") -> RecordedTask {
            guard let url = URL(string: "macdown-preview://document/\(path)") else {
                preconditionFailure("Invalid fixture URL")
            }
            return RecordedTask(url: url)
        }

        static func makeView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            return WKWebView(frame: .zero, configuration: configuration)
        }
    }

    @MainActor
    final class RecordedTask: NSObject, @MainActor WKURLSchemeTask {
        private let storedRequest: URLRequest
        var request: URLRequest {
            onRequest?()
            return storedRequest
        }

        var events: [String] = []
        var response: URLResponse?
        var bytes = Data()
        var onResponse: (() -> Void)?
        var onData: (() -> Void)?
        var onTerminal: (() -> Void)?
        var onRequest: (() -> Void)?

        init(url: URL) {
            storedRequest = URLRequest(url: url)
        }

        func didReceive(_ response: URLResponse) {
            self.response = response
            events.append("response")
            onResponse?()
        }

        func didReceive(_ data: Data) {
            bytes.append(data)
            events.append("data")
            onData?()
        }

        func didFinish() {
            events.append("finish"); onTerminal?()
        }

        func didFailWithError(_: Error) {
            events.append("failure"); onTerminal?()
        }

        func clearCallbacks() {
            onResponse = nil; onData = nil; onTerminal = nil; onRequest = nil
        }
    }
}
