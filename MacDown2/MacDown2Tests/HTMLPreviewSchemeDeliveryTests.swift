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
            if dispose {
                fixture.handler.retire()
            } else {
                _ = fixture.handler.install(
                    HTMLPreviewRequest(source: "replacement", baseURL: nil),
                    documentID: "replacement", recoveryEpoch: UUID(), generation: 2
                )
            }
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
        let url = try #require(handler.install(
            HTMLPreviewRequest(source: "disposal-control", baseURL: nil),
            documentID: "disposal-control", recoveryEpoch: UUID(), generation: 1
        ))
        let task = RecordedTask(url: url)
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
        let html = try #require(String(bytes: task.bytes, encoding: .utf8))
        #expect(html.contains("delivery-control"))
    }

    @Test func lateTasksCannotBorrowAnotherDocumentsResourceRoot() throws {
        let fixture = Fixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-task-\(UUID().uuidString)", isDirectory: true)
        let rootA = directory.appendingPathComponent("A", isDirectory: true)
        let rootB = directory.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("root-A-sentinel".utf8).write(to: rootA.appendingPathComponent("asset.txt"))
        try Data("root-B-sentinel".utf8).write(to: rootB.appendingPathComponent("asset.txt"))

        let oldURL = try #require(fixture.handler.install(
            HTMLPreviewRequest(source: "A", baseURL: rootA),
            documentID: "A", recoveryEpoch: UUID(), generation: 1
        ))
        let oldTask = RecordedTask(url: oldURL.appendingPathComponent("asset.txt"))
        let currentURL = try #require(fixture.handler.install(
            HTMLPreviewRequest(source: "B", baseURL: rootB),
            documentID: "B", recoveryEpoch: UUID(), generation: 1
        ))
        #expect(oldURL.host != currentURL.host)
        fixture.handler.webView(fixture.view, start: oldTask)
        #expect(oldTask.events == ["failure"])
        #expect(oldTask.bytes.isEmpty)

        let currentTask = RecordedTask(url: currentURL.appendingPathComponent("asset.txt"))
        fixture.handler.webView(fixture.view, start: currentTask)
        #expect(currentTask.events == ["response", "data", "finish"])
        #expect(String(bytes: currentTask.bytes, encoding: .utf8) == "root-B-sentinel")
    }

    @Test func repeatedSaveAndDisposalRejectEarlierMainDocumentTasks() throws {
        let fixture = Fixture()
        let request = HTMLPreviewRequest(source: "unchanged", baseURL: nil)
        let epoch = UUID()
        let firstURL = try #require(fixture.handler.install(
            request, documentID: "same-document", recoveryEpoch: epoch, generation: 1
        ))
        let secondURL = try #require(fixture.handler.install(
            request, documentID: "same-document", recoveryEpoch: epoch, generation: 2
        ))
        #expect(firstURL != secondURL)
        let oldTask = RecordedTask(url: firstURL)
        fixture.handler.webView(fixture.view, start: oldTask)
        #expect(oldTask.events == ["failure"])

        fixture.handler.retire()
        let disposedTask = RecordedTask(url: secondURL)
        fixture.handler.webView(fixture.view, start: disposedTask)
        #expect(disposedTask.events == ["failure"])
    }
}

private extension HTMLPreviewSchemeDeliveryTests {
    @MainActor
    final class Fixture {
        let handler = PreviewSchemeHandler()
        let view = makeView()
        let mainURL: URL

        init() {
            guard let url = handler.install(
                HTMLPreviewRequest(source: "<p>delivery-control</p>", baseURL: nil),
                documentID: "delivery-control", recoveryEpoch: UUID(), generation: 1
            ) else { preconditionFailure("Invalid fixture URL") }
            mainURL = url
        }

        func task(path: String = "") -> RecordedTask {
            let url = path.isEmpty ? mainURL : mainURL.appendingPathComponent(path)
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
