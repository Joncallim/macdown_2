import FileCore
import Foundation
import LocalResourceAccess
@testable import MacDown2
import Preview
import Testing
import WebKit

@Suite("Immutable bounded HTML scheme delivery")
@MainActor
struct BoundedHTMLPreviewHandlerTests {
    @Test func savedRendersHaveDifferentAuthoritiesAndMainResponseKeepsCSP() throws {
        let document = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/preview-document.html"))
        let first = try BoundedHTMLPreviewLoad(document: document, source: "<p>first</p>", grant: nil)
        let second = try BoundedHTMLPreviewLoad(document: document, source: "<p>second</p>", grant: nil)
        #expect(first.authority != second.authority)
        let handler = BoundedHTMLPreviewHandler(load: first)
        let view = makeView()
        let wrong = RecordedHTMLTask(url: second.mainURL)
        handler.webView(view, start: wrong)
        #expect(wrong.events == ["failure"])

        let task = RecordedHTMLTask(url: first.mainURL)
        handler.webView(view, start: task)
        #expect(task.events == ["response", "data", "finish"])
        let response = try #require(task.response as? HTTPURLResponse)
        #expect(response.value(forHTTPHeaderField: "Content-Security-Policy") != nil)
        let html = try #require(String(bytes: task.bytes, encoding: .utf8))
        #expect(html.contains("first"))
        handler.dispose()
    }

    @Test func stoppingAtResponseNeverDeliversDataOrTerminalCallback() throws {
        let document = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/preview-document.html"))
        let load = try BoundedHTMLPreviewLoad(document: document, source: "<p>stopped</p>", grant: nil)
        let handler = BoundedHTMLPreviewHandler(load: load)
        let view = makeView()
        let task = RecordedHTMLTask(url: load.mainURL)
        task.onResponse = { handler.webView(view, stop: task) }
        handler.webView(view, start: task)
        #expect(task.events == ["response"])
        task.onResponse = nil
        handler.dispose()
    }

    @Test func stoppingAtDataNeverDeliversATerminalCallback() throws {
        let document = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/preview-document.html"))
        let load = try BoundedHTMLPreviewLoad(document: document, source: "<p>stopped</p>", grant: nil)
        let handler = BoundedHTMLPreviewHandler(load: load)
        let view = makeView()
        let task = RecordedHTMLTask(url: load.mainURL)
        task.onData = { handler.webView(view, stop: task) }
        handler.webView(view, start: task)
        #expect(task.events == ["response", "data"])
        task.onData = nil
        handler.dispose()
    }

    @Test func encodedSeparatorsAndParentTraversalAreRejectedBeforeRead() async throws {
        let fixture = try await makeGrant(filename: "image.png", text: "image")
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let load = try BoundedHTMLPreviewLoad(document: fixture.document, source: "hello", grant: fixture.token)
        let handler = BoundedHTMLPreviewHandler(load: load)
        let view = makeView()
        for suffix in ["%2Fprivate", "%2e%2e/image.png"] {
            let url = try #require(URL(string: load.mainURL.absoluteString + suffix))
            let task = RecordedHTMLTask(url: url)
            handler.webView(view, start: task)
            #expect(task.events == ["failure"])
        }
        handler.dispose()
        fixture.grant.revoke()
    }

    @Test func malformedAndRepeatedMainRequestsExhaustTheSameLoadLimit() throws {
        let document = FileDocument(fileURL: URL(fileURLWithPath: "/tmp/preview-document.html"))
        let load = try BoundedHTMLPreviewLoad(document: document, source: "<p>bounded</p>", grant: nil)
        let handler = BoundedHTMLPreviewHandler(load: load)
        let view = makeView()
        let malformed = try #require(URL(string: "macdown-preview://wrong-authority/"))
        for _ in 0 ..< PreviewResourceAdmission.requestLimit - 1 {
            let task = RecordedHTMLTask(url: malformed)
            handler.webView(view, start: task)
            #expect(task.events == ["failure"])
        }
        let finalAllowed = RecordedHTMLTask(url: load.mainURL)
        handler.webView(view, start: finalAllowed)
        #expect(finalAllowed.events == ["response", "data", "finish"])
        let exhausted = RecordedHTMLTask(url: load.mainURL)
        handler.webView(view, start: exhausted)
        #expect(exhausted.events == ["failure"])
        handler.dispose()
    }

    @Test func anAlreadyRevokedGrantNeverRetainsARequest() async throws {
        let fixture = try await makeGrant(filename: "image.png", text: "image")
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let load = try BoundedHTMLPreviewLoad(document: fixture.document, source: "hello", grant: fixture.token)
        let handler = BoundedHTMLPreviewHandler(load: load)
        let view = makeView()
        fixture.token.revoke()
        let task = try RecordedHTMLTask(url: #require(URL(string: load.mainURL.absoluteString + "image.png")))
        handler.webView(view, start: task)
        #expect(task.events == ["failure"])
        #expect(handler.activeAttemptCount == 0)
        handler.dispose()
        fixture.grant.revoke()
    }

    @Test func delayedOldReadCannotDeliverIntoANewSavedRender() async throws {
        let first = try await makeGrant(filename: "slow.txt", text: "A bytes")
        let second = try await makeGrant(filename: "fast.txt", text: "B bytes")
        defer {
            try? FileManager.default.removeItem(at: first.folder)
            try? FileManager.default.removeItem(at: second.folder)
        }
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let admission = PreviewResourceAdmission(readOperation: { reference, directory, cancellation in
            if reference.relativePath == "slow.txt" {
                entered.signal()
                release.wait()
            }
            return try ContainedResourceReader.read(
                reference, in: directory,
                maxBytes: PreviewResourceAdmission.resourceLimit, cancellation: cancellation
            )
        })
        let oldLoad = try BoundedHTMLPreviewLoad(document: first.document, source: "A", grant: first.token)
        let newLoad = try BoundedHTMLPreviewLoad(document: second.document, source: "B", grant: second.token)
        let oldHandler = BoundedHTMLPreviewHandler(load: oldLoad, admission: admission)
        let newHandler = BoundedHTMLPreviewHandler(load: newLoad, admission: admission)
        let view = makeView()
        let oldTask = try RecordedHTMLTask(url: #require(URL(string: oldLoad.mainURL.absoluteString + "slow.txt")))
        oldHandler.webView(view, start: oldTask)
        let didEnter = await Task.detached { Self.waitForSignal(entered) }.value
        #expect(didEnter)

        oldHandler.dispose()
        let newTask = try RecordedHTMLTask(url: #require(URL(string: newLoad.mainURL.absoluteString + "fast.txt")))
        newHandler.webView(view, start: newTask)
        try await waitForTerminal(newTask)
        #expect(newTask.events == ["response", "data", "finish"])
        #expect(newTask.bytes == Data("B bytes".utf8))
        release.signal()
        try await waitForDrain(of: first.token, in: admission)
        #expect(oldTask.events.isEmpty)
        newHandler.dispose()
        first.grant.revoke()
        second.grant.revoke()
    }

    @Test func externalRevocationDropsALateSuccessfulReadWithoutCallbacks() async throws {
        let fixture = try await makeGrant(filename: "image.png", text: "image")
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let admission = PreviewResourceAdmission(readOperation: { reference, directory, _ in
            entered.signal()
            release.wait()
            return try ContainedResourceReader.read(
                reference, in: directory, maxBytes: PreviewResourceAdmission.resourceLimit,
                cancellation: ResourceCancellation()
            )
        })
        let load = try BoundedHTMLPreviewLoad(document: fixture.document, source: "hello", grant: fixture.token)
        let handler = BoundedHTMLPreviewHandler(load: load, admission: admission)
        let view = makeView()
        let task = try RecordedHTMLTask(url: #require(URL(string: load.mainURL.absoluteString + "image.png")))
        handler.webView(view, start: task)
        #expect(await Task.detached { Self.waitForSignal(entered) }.value)
        fixture.token.revoke()
        release.signal()
        try await waitForAttemptDrain(in: handler)
        #expect(task.events.isEmpty)
        handler.dispose()
        fixture.grant.revoke()
    }

    private struct GrantFixture {
        let folder: URL
        let document: FileDocument
        let grant: PreviewDirectoryGrantBacking
        let token: PreviewResourceLoad
    }

    private func makeGrant(filename: String, text: String) async throws -> GrantFixture {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appendingPathComponent(filename))
        let document = FileDocument(fileURL: folder.appendingPathComponent("story.html"))
        let url = try #require(document.fileURL)
        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: url, folderURL: folder
        ))
        let grant = try await PreviewDirectoryGrantBacking.acquire(
            selection: selection, currentDocumentURL: url, epoch: UUID()
        )
        return GrantFixture(
            folder: folder, document: document, grant: grant,
            token: PreviewResourceLoad(grant: grant)
        )
    }

    private func waitForTerminal(_ task: RecordedHTMLTask) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !task.events.contains("finish"), !task.events.contains("failure") {
            guard ContinuousClock.now < deadline else {
                Issue.record("Scheme task did not reach a terminal callback")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func waitForDrain(of token: PreviewResourceLoad, in admission: PreviewResourceAdmission) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await admission.status(for: token) != nil {
            guard ContinuousClock.now < deadline else {
                Issue.record("Retired HTML read did not drain")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func waitForAttemptDrain(in handler: BoundedHTMLPreviewHandler) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while handler.activeAttemptCount != 0 {
            guard ContinuousClock.now < deadline else {
                Issue.record("Revoked HTML attempt was retained after its read completed")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuration)
    }

    private nonisolated static func waitForSignal(_ signal: DispatchSemaphore) -> Bool {
        signal.wait(timeout: .now() + 2) == .success
    }
}

@MainActor
private final class RecordedHTMLTask: NSObject, @MainActor WKURLSchemeTask {
    let request: URLRequest
    var events: [String] = []
    var bytes = Data()
    var response: URLResponse?
    var onResponse: (() -> Void)?
    var onData: (() -> Void)?

    init(url: URL) {
        request = URLRequest(url: url)
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
        events.append("finish")
    }

    func didFailWithError(_: Error) {
        events.append("failure")
    }
}
