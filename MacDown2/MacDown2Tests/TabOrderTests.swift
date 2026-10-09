import AppKit
@testable import MacDown2
import Testing

/// Review pass 1: a relaunch restored tabs in a scrambled order (A B C D came back A D C B),
/// and saving used creation order rather than the tab strip's order.
@MainActor
struct TabOrderTests {
    private func makeWindows(_ titles: [String]) -> [NSWindow] {
        titles.map { title in
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: true
            )
            window.title = title
            window.tabbingMode = .preferred
            window.tabbingIdentifier = "TabOrderTests-\(titles.joined())"
            window.isReleasedWhenClosed = false
            return window
        }
    }

    @Test func chainingEachTabAfterThePreviousOneKeepsTheOrder() throws {
        let windows = makeWindows(["A", "B", "C", "D"])
        for (previous, next) in zip(windows, windows.dropFirst()) {
            WindowCoordinator.attach(next, after: previous)
        }
        let group = try #require(windows.first?.tabGroup)
        #expect(group.windows.map(\.title) == ["A", "B", "C", "D"])
        windows.forEach { $0.close() }
    }

    @Test func savedOrderFollowsTheTabStripNotCreationOrder() {
        let windows = makeWindows(["A", "B", "C"])
        for (previous, next) in zip(windows, windows.dropFirst()) {
            WindowCoordinator.attach(next, after: previous)
        }
        // The user drags C to the front: the strip is C A B but creation order stays A B C.
        windows[1].tabGroup?.removeWindow(windows[2])
        windows[0].tabGroup?.insertWindow(windows[2], at: 0)

        let ordered = WindowCoordinator.inTabOrder(windows, window: { $0 })

        #expect(ordered.map(\.title) == ["C", "A", "B"])
        windows.forEach { $0.close() }
    }

    @Test func windowsWithoutATabGroupKeepTheirPlace() {
        #expect(WindowCoordinator.inTabOrder([1, 2, 3], window: { _ in nil }) == [1, 2, 3])
    }

    /// With the app inactive no window is key; the session used to record no active tab and relaunch on the first.
    @Test func theVisibleTabIsActiveWhenNoWindowIsKey() {
        let windows = makeWindows(["A", "B", "C"])
        for (previous, next) in zip(windows, windows.dropFirst()) {
            WindowCoordinator.attach(next, after: previous)
        }
        windows[0].tabGroup?.selectedWindow = windows[2]

        let active = WindowCoordinator.activeSessionItem(windows, window: { $0 }, mainWindow: nil)

        #expect(active?.title == "C")
        windows.forEach { $0.close() }
    }

    @Test func theMainWindowWinsOverTheTabGroupSelectionWhenNothingIsKey() {
        let windows = makeWindows(["A", "B"])
        WindowCoordinator.attach(windows[1], after: windows[0])

        let active = WindowCoordinator.activeSessionItem(windows, window: { $0 }, mainWindow: windows[1])

        #expect(active?.title == "B")
        windows.forEach { $0.close() }
    }
}
