import AppKit
@testable import MacDown2
import Testing

@Suite("Formatting command state refresh")
@MainActor
struct CommandStateRefreshTests {
    @Test("ordinary typing does not invalidate command state")
    func ordinaryTypingDoesNotRefresh() throws {
        let event = try #require(keyEvent(characters: "a", modifiers: []))
        #expect(!DocumentWindow.shouldRefreshCommandState(for: event))
    }

    @Test("focus transitions and Find opening refresh command state")
    func focusTransitionsRefresh() throws {
        let mouseDown = try #require(mouseEvent(type: .leftMouseDown))
        let appKitEvent = try #require(mouseEvent(type: .appKitDefined))
        #expect(DocumentWindow.shouldRefreshCommandState(for: mouseDown))
        #expect(DocumentWindow.shouldRefreshCommandState(for: appKitEvent))
        let find = try #require(keyEvent(characters: "f", modifiers: .command))
        #expect(DocumentWindow.shouldRefreshCommandState(for: find))
    }

    private func keyEvent(characters: String, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )
    }

    private func mouseEvent(type: NSEvent.EventType) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
    }
}
