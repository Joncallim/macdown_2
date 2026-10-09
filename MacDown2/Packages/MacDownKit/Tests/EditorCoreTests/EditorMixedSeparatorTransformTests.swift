import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Tenth review R10-04: Indent and Toggle Comment chose ONE separator for the whole selected block (LF whenever any LF
/// appeared) and split only on it, although the line index treats LF, CRLF and lone CR as logical boundaries. Select
/// all
/// of `a\rb\nc`: Increase Indent gave `  a\rb\n  c`, Toggle Comment `// a\rb\n// c` — the bare-CR line was skipped.
@MainActor
struct EditorMixedSeparatorTransformTests {
    private let support = EditingAssistIntegrationSupport.self
    private let separators = ["\n", "\r", "\r\n"]

    private func run(_ text: String, language: String? = nil, _ action: (EditorTextSystem) -> Bool) -> String {
        var configuration = EditorConfiguration.default
        if let language {
            configuration.languageProfile = LanguageEditingProfileRegistry.profile(for: language)
        }
        let system = support.makeSystem(text: text, configuration: configuration)
        let window = support.mountInWindow(system)
        defer { window.orderOut(nil) }
        system.textView.delegate = support.makeCoordinator(system: system)
        system.selectedRange = NSRange(location: 0, length: (text as NSString).length)
        _ = action(system)
        return system.textView.string
    }

    @Test func increaseIndentTransformsEveryLogicalLineAndKeepsEachSeparator() {
        for first in separators {
            for second in separators {
                let text = "a\(first)b\(second)c"
                #expect(
                    run(text) { $0.increaseIndent() } == "    a\(first)    b\(second)    c",
                    "separators \(first.debugDescription) \(second.debugDescription)"
                )
            }
        }
    }

    @Test func decreaseIndentTransformsEveryLogicalLine() {
        for first in separators {
            for second in separators {
                let text = "    a\(first)    b\(second)    c"
                #expect(
                    run(text) { $0.decreaseIndent() } == "a\(first)b\(second)c",
                    "separators \(first.debugDescription) \(second.debugDescription)"
                )
            }
        }
    }

    @Test func toggleCommentTransformsEveryLogicalLineAndRoundTrips() {
        for first in separators {
            for second in separators {
                let text = "a\(first)b\(second)c"
                let commented = run(text, language: "yaml") { $0.toggleComment() }
                #expect(
                    commented == "# a\(first)# b\(second)# c",
                    "separators \(first.debugDescription) \(second.debugDescription)"
                )
                #expect(run(commented, language: "yaml") { $0.toggleComment() } == text)
            }
        }
    }
}
