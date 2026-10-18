import Foundation
import Testing
import RangeState
@testable import Neon

@MainActor
private final class ProbeInterface: TextSystemInterface {
    let content = UnversionableContent(lengthProvider: { 10 })
    var applications: [TokenApplication] = []
    func applyStyles(for application: TokenApplication) { applications.append(application) }
}

@MainActor
private final class TokenGate {
    var continuation: CheckedContinuation<TokenApplication, Never>?
    func request() async -> TokenApplication {
        await withCheckedContinuation { continuation = $0 }
    }
}

@MainActor
@Test func anEditWhileTokensArePendingMustPreventStaleStyleApplication() async throws {
    let interface = ProbeInterface()
    let gate = TokenGate()
    let provider = TokenProvider(syncValue: { _ in nil }, mainActorAsyncValue: { _ in await gate.request() })
    let validator = TokenSystemValidator(textSystem: interface, tokenProvider: provider)
    let request = VersionedRange(NSRange(location: 0, length: 10), version: interface.content.currentVersion)
    let validation = Task { await validator.validationProvider.async(isolation: MainActor.shared, request) }
    for _ in 0 ..< 1000 where gate.continuation == nil { await Task.yield() }
    let continuation = try #require(gate.continuation)
    interface.content.contentChanged()
    continuation.resume(returning: TokenApplication(tokens: [Token(name: "old-revision", range: request.value)]))
    let result = await validation.value
    print("REVISION_PROBE request=\(request.version) current=\(interface.content.currentVersion) applied=\(interface.applications.count) validation=\(result)")
    #expect(interface.applications.isEmpty)
    #expect(result == .stale)
}
