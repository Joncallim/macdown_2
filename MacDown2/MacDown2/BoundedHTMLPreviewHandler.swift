import FileCore
import Foundation
import LocalResourceAccess
import Preview
import WebKit

enum BoundedHTMLPreviewError: Error {
    case denied
    case sourceTooLarge
}

/// One saved render's immutable authority. A new render needs a new handler and WKWebView configuration;
/// no delayed resource callback can consult a later document's URL, source or grant.
@MainActor
final class BoundedHTMLPreviewLoad {
    static let sourceLimit = 4 * 1024 * 1024
    static let encodedLimit = 8 * 1024 * 1024

    let id = UUID()
    let authority = UUID().uuidString.lowercased()
    let mainURL: URL
    let documentID: String
    let recoveryEpoch: UUID
    let savedGeneration: UInt
    let mainData: Data
    let grant: PreviewResourceLoad?
    let policy: HTMLPreviewPolicy
    let copyBudget = PreviewHTMLCopyBudget()
    private let mainReservation: PreviewHTMLCopyBudget.Reservation

    init(document: FileCore.FileDocument, source: String, grant: PreviewResourceLoad?,
         policy: HTMLPreviewPolicy = .v1) throws {
        let sourceBytes = source.utf8.count
        guard sourceBytes <= Self.sourceLimit else { throw BoundedHTMLPreviewError.sourceTooLarge }
        documentID = document.id
        recoveryEpoch = document.recoveryEpoch
        savedGeneration = document.mutationGeneration
        guard let mainURL = URL(string: "\(HTMLPreviewNavigationPolicy.previewURLScheme)://\(authority)/")
        else { throw BoundedHTMLPreviewError.denied }
        self.mainURL = mainURL
        self.grant = grant
        self.policy = policy
        mainReservation = try copyBudget.reserve(PreviewHTMLCopyBudget.hardeningCharge(for: sourceBytes))
        let hardened = PreviewSecurity.hardenedHTMLDocument(from: source)
        let encoded = Data(hardened.utf8)
        guard encoded.count <= Self.encodedLimit else { throw BoundedHTMLPreviewError.sourceTooLarge }
        mainData = encoded
    }
}

/// Charges additional app-owned HTML string/encoded copies separately from admitted file input bytes.
final class PreviewHTMLCopyBudget: @unchecked Sendable {
    static let limit = 128 * 1024 * 1024
    static let globalLimit = 256 * 1024 * 1024
    private static let globalLock = NSLock()
    private nonisolated(unsafe) static var globallyHeld = 0
    private let lock = NSLock()
    private var held = 0

    /// PreviewSecurity currently materializes an Array<Character> while finding an insertion point.
    /// A character cannot outnumber its UTF-8 input bytes. Reserve that array and the HTML string/data copies.
    static func hardeningCharge(for inputBytes: Int) -> Int {
        inputBytes * MemoryLayout<Character>.stride + 16 * 1024 * 1024
    }

    final class Reservation: @unchecked Sendable {
        private let budget: PreviewHTMLCopyBudget
        private let bytes: Int

        fileprivate init(budget: PreviewHTMLCopyBudget, bytes: Int) {
            self.budget = budget
            self.bytes = bytes
        }

        deinit { budget.release(bytes) }
    }

    func reserve(_ bytes: Int) throws -> Reservation {
        let admitted = Self.globalLock.withLock { () -> Bool in
            lock.withLock {
                guard bytes > 0, bytes <= Self.limit, held <= Self.limit - bytes,
                      bytes <= Self.globalLimit,
                      Self.globallyHeld <= Self.globalLimit - bytes else { return false }
                held += bytes
                Self.globallyHeld += bytes
                return true
            }
        }
        guard admitted else { throw BoundedHTMLPreviewError.denied }
        return Reservation(budget: self, bytes: bytes)
    }

    private func release(_ bytes: Int) {
        Self.globalLock.withLock {
            lock.withLock {
                held -= bytes
                Self.globallyHeld -= bytes
            }
        }
    }
}

/// This handler is constructed once with a saved load and never retargeted. Delivery callbacks are checked after
/// each reentrant WebKit call; a stopped task loses callback permission immediately while its admitted read drains.
@MainActor
final class BoundedHTMLPreviewHandler: NSObject, WKURLSchemeHandler {
    private struct Attempt {
        let task: any WKURLSchemeTask
        let viewID: ObjectIdentifier
        let token: UUID
        var worker: Task<Void, Never>?
    }

    let load: BoundedHTMLPreviewLoad
    private let admission: PreviewResourceAdmission
    private var attempts: [ObjectIdentifier: Attempt] = [:]
    private var requestCount = 0
    private var disposed = false
    var activeAttemptCount: Int {
        attempts.count
    }

    init(load: BoundedHTMLPreviewLoad, admission: PreviewResourceAdmission = .shared) {
        self.load = load
        self.admission = admission
        super.init()
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task)
        guard !disposed, attempts[taskID] == nil else { return }
        guard requestCount < PreviewResourceAdmission.requestLimit,
              !(load.grant?.isRevoked ?? false) else {
            task.didFailWithError(BoundedHTMLPreviewError.denied)
            return
        }
        requestCount += 1
        let token = UUID()
        attempts[taskID] = Attempt(task: task, viewID: ObjectIdentifier(webView), token: token)
        guard let url = task.request.url, isLive(taskID, token: token),
              let reference = reference(for: url)
        else { fail(taskID, token: token); return }

        if reference == nil {
            deliver(load.mainData, contentType: HTMLPreviewContentType.mainDocument,
                    url: url, taskID: taskID, token: token)
            return
        }
        guard let reference, let grant = load.grant, !grant.isRevoked else {
            fail(taskID, token: token)
            return
        }
        let admission = admission
        let worker = Task { [weak self] in
            do {
                let payload = try await admission.read(reference, in: grant)
                self?.deliver(payload, url: url, taskID: taskID, token: token)
            } catch {
                self?.fail(taskID, token: token)
            }
        }
        attempts[taskID]?.worker = worker
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task)
        guard attempts[taskID]?.viewID == ObjectIdentifier(webView) else { return }
        attempts.removeValue(forKey: taskID)?.worker?.cancel()
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        let workers = attempts.values.compactMap(\.worker)
        attempts.removeAll()
        for worker in workers {
            worker.cancel()
        }
        if let grant = load.grant {
            grant.revoke()
            let admission = admission
            Task { await admission.retire(grant) }
        }
    }

    private func reference(for url: URL) -> ResourceReference?? {
        guard url.scheme?.lowercased() == HTMLPreviewNavigationPolicy.previewURLScheme,
              url.host == load.authority, url.user == nil, url.password == nil, url.port == nil,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath
        else { return nil }
        if path.isEmpty || path == "/" {
            return .some(nil)
        }
        guard let reference = try? ResourceReference.parse(path) else { return nil }
        return .some(reference)
    }

    private func isLive(_ taskID: ObjectIdentifier, token: UUID) -> Bool {
        !disposed && attempts[taskID]?.token == token && !(load.grant?.isRevoked ?? false)
    }

    private func fail(_ taskID: ObjectIdentifier, token: UUID) {
        guard attempts[taskID]?.token == token else { return }
        guard isLive(taskID, token: token) else {
            attempts.removeValue(forKey: taskID)?.worker?.cancel()
            return
        }
        guard let attempt = attempts.removeValue(forKey: taskID) else { return }
        attempt.task.didFailWithError(BoundedHTMLPreviewError.denied)
    }

    private func deliver(_ payload: PreviewResourcePayload, url: URL,
                         taskID: ObjectIdentifier, token: UUID) {
        guard isLive(taskID, token: token) else {
            removeRevokedAttempt(taskID, token: token)
            return
        }
        let snapshot = payload.snapshot
        let fileExtension = (snapshot.name as NSString).pathExtension
        var contentType = HTMLPreviewContentType.forFileExtension(fileExtension)
        var bytes = snapshot.bytes
        var copyReservation: PreviewHTMLCopyBudget.Reservation?
        if HTMLPreviewContentType.isHTML(fileExtension) {
            // Bound HTML hardening input before creating extra String and Data allocations.
            guard bytes.count <= BoundedHTMLPreviewLoad.sourceLimit,
                  let reservation = try? load.copyBudget.reserve(
                      PreviewHTMLCopyBudget.hardeningCharge(for: bytes.count)
                  )
            else { fail(taskID, token: token); return }
            copyReservation = reservation
            if let decoded = String(bytes: bytes, encoding: .utf8) {
                bytes = Data(PreviewSecurity.hardenedHTMLDocument(from: decoded).utf8)
                guard bytes.count <= BoundedHTMLPreviewLoad.encodedLimit else {
                    fail(taskID, token: token)
                    return
                }
                contentType = HTMLPreviewContentType.mainDocument
            }
        }
        withExtendedLifetime((payload, copyReservation)) {
            deliver(bytes, contentType: contentType, url: url, taskID: taskID, token: token)
        }
    }

    private func deliver(_ data: Data, contentType: String, url: URL,
                         taskID: ObjectIdentifier, token: UUID) {
        guard isLive(taskID, token: token), let attempt = attempts[taskID],
              let response = HTTPURLResponse(
                  url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                  headerFields: HTMLPreviewResponseHeaders.headers(for: load.policy, contentType: contentType)
              ) else { fail(taskID, token: token); return }
        attempt.task.didReceive(response)
        guard isLive(taskID, token: token) else {
            removeRevokedAttempt(taskID, token: token)
            return
        }
        attempt.task.didReceive(data)
        guard isLive(taskID, token: token) else {
            removeRevokedAttempt(taskID, token: token)
            return
        }
        attempts.removeValue(forKey: taskID)
        attempt.task.didFinish()
    }

    private func removeRevokedAttempt(_ taskID: ObjectIdentifier, token: UUID) {
        guard !isLive(taskID, token: token), attempts[taskID]?.token == token else { return }
        attempts.removeValue(forKey: taskID)?.worker?.cancel()
    }
}
