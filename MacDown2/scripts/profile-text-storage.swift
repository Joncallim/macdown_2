import AppKit
import Foundation

// Hosted diagnostic only; this executable never opens a user document/window.
@MainActor
func profile() throws {
    _ = NSApplication.shared
    let content = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    let container = NSTextContainer()
    layout.textContainer = container
    content.addTextLayoutManager(layout)
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000), textContainer: container)
    let source = String(repeating: "a representative paragraph with text\n", count: 28_000)
    view.string = source
    func old() -> NSString? {
        if let storage = content.attributedString as? NSTextStorage { return storage.mutableString }
        return view.textStorage?.mutableString
    }
    func direct() -> NSString? { content.textStorage?.mutableString ?? view.textStorage?.mutableString }
    func measure(_ name: String, _ body: () -> NSString?) -> [String: Any] {
        var samples: [Double] = []
        var sum = 0
        for _ in 0..<7 {
            let start = ContinuousClock.now
            sum += body()?.length ?? 0
            let d = start.duration(to: .now).components
            samples.append(Double(d.seconds) * 1000 + Double(d.attoseconds) / 1e15)
        }
        return ["name": name, "milliseconds": samples, "lengthSum": sum]
    }
    guard old()?.length == source.utf16.count, direct()?.length == source.utf16.count else {
        throw NSError(domain: "InvalidStorageFixture", code: 1)
    }
    let result: [String: Any] = [
        "currentGetter": measure("attributedString-cast-or-view", old),
        "directGetter": measure("content.textStorage", direct),
        "sameLiveString": old() === direct(),
        "attributedDynamicType": String(describing: type(of: content.attributedString)),
        "backingDynamicType": String(describing: type(of: content.textStorage))
    ]
    let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys,.prettyPrinted])
    print(String(decoding: bytes, as: UTF8.self))
}
@main
struct StorageProfileMain {
    @MainActor static func main() throws { try profile() }
}
