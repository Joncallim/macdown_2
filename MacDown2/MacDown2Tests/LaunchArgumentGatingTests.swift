import Foundation
@testable import MacDown2
import Testing

/// The test-only launch hooks must exist in Debug (UI tests depend on them) and be inert in Release.
@MainActor
struct LaunchArgumentGatingTests {
    @Test func launchArgumentsAreHonouredOnlyInDebugBuilds() {
        #if DEBUG
            #expect(AppDelegate.launchArguments == ProcessInfo.processInfo.arguments)
        #else
            #expect(AppDelegate.launchArguments.isEmpty)
        #endif
    }
}
