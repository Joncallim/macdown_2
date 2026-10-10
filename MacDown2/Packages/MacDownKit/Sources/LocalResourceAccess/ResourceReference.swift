import Foundation

/// A normalized, root-relative reference parsed from the path of a preview URL.
///
/// Parsing is purely lexical and happens once: the query and fragment are stripped structurally, each path component is
/// percent-decoded exactly once (so `%252e` stays the literal text `%2e`), and `.`/`..` are resolved without ever
/// leaving the root. A component that decodes to a separator, contains NUL, or is a malformed escape rejects the whole
/// reference. Distinct Unicode names are never normalized. The result authorises nothing by itself: the reader still
/// opens it relative to a pinned directory descriptor.
public struct ResourceReference: Equatable, Sendable {
    public let components: [String]

    public var relativePath: String {
        components.joined(separator: "/")
    }

    public init(components: [String]) {
        self.components = components
    }

    /// Parses `rawPath` (an RFC 3986 path, optionally followed by `?query` / `#fragment`). A leading `/` is the load's
    /// root, not the filesystem root.
    public static func parse(_ rawPath: String) throws(ResourceReadError) -> ResourceReference {
        let structural = rawPath.prefix { $0 != "?" && $0 != "#" }
        var resolved: [String] = []
        for rawComponent in structural.split(separator: "/", omittingEmptySubsequences: true) {
            let component = try decodeOnce(String(rawComponent))
            switch component {
            case ".":
                continue
            case "..":
                guard resolved.popLast() != nil else { throw .denied }
            default:
                resolved.append(component)
            }
        }
        guard !resolved.isEmpty else { throw .invalidReference }
        return ResourceReference(components: resolved)
    }

    private static func decodeOnce(_ component: String) throws(ResourceReadError) -> String {
        var bytes: [UInt8] = []
        let units = Array(component.utf8)
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == UInt8(ascii: "%") {
                guard index + 2 < units.count, let high = hexValue(units[index + 1]),
                      let low = hexValue(units[index + 2]) else { throw .invalidReference }
                bytes.append(high << 4 | low)
                index += 3
            } else {
                bytes.append(unit)
                index += 1
            }
        }
        guard !bytes.contains(0), !bytes.contains(UInt8(ascii: "/")),
              let decoded = String(validating: bytes, as: UTF8.self)
        else { throw .invalidReference }
        return decoded
    }

    private static func hexValue(_ unit: UInt8) -> UInt8? {
        switch unit {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"): unit - UInt8(ascii: "0")
        case UInt8(ascii: "a") ... UInt8(ascii: "f"): unit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A") ... UInt8(ascii: "F"): unit - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
