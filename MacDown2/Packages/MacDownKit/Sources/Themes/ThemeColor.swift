import AppKit
import Foundation

/// A colour as sRGB components in 0...1.
///
/// Pure value type; no AppKit in the stored form. The bridge to `NSColor` is a
/// computed property so the type stays `Codable`/`Sendable`/`Equatable`.
public struct ThemeColor: Codable, Sendable, Equatable { // swiftlint:disable:this type_body_length
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Bridge to AppKit at the edge. Always sRGB.
    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Parse a CSS/hex/named colour string. Returns `nil` on any malformed input.
    ///
    /// Supported forms (case-insensitive, surrounding whitespace trimmed):
    /// - `#RGB` / `#RGBA` — nibbles doubled
    /// - `#RRGGBB` / `#RRGGBBAA`
    /// - `rgb(r,g,b)` — 0–255 integers
    /// - `rgba(r,g,b,a)` — a is 0–1 float
    /// - named colour — see `namedColors`
    public init?(cssString: String) {
        let raw = cssString.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }

        let lower = raw.lowercased()

        if lower.hasPrefix("#") {
            guard let color = Self.parseHex(String(lower.dropFirst())) else { return nil }
            self = color
            return
        }

        if lower.hasPrefix("rgba("), lower.hasSuffix(")") {
            guard let color = Self.parseRGBA(String(lower.dropFirst(5).dropLast())) else { return nil }
            self = color
            return
        }

        if lower.hasPrefix("rgb("), lower.hasSuffix(")") {
            guard let color = Self.parseRGB(String(lower.dropFirst(4).dropLast())) else { return nil }
            self = color
            return
        }

        if let hex = Self.namedColors[lower] {
            self = hex
            return
        }

        return nil
    }

    // MARK: - Parsers

    private static func parseHex(_ string: String) -> ThemeColor? {
        let chars = Array(string)
        let length = chars.count

        guard length == 3 || length == 4 || length == 6 || length == 8 else { return nil }

        let digitsPerChannel: Int
        let hasAlpha: Bool

        switch length {
        case 3:
            digitsPerChannel = 1
            hasAlpha = false
        case 4:
            digitsPerChannel = 1
            hasAlpha = true
        case 6:
            digitsPerChannel = 2
            hasAlpha = false
        case 8:
            digitsPerChannel = 2
            hasAlpha = true
        default:
            return nil
        }

        var values: [Double] = []
        for index in stride(from: 0, to: length, by: digitsPerChannel) {
            let slice = chars[index ..< index + digitsPerChannel]
            let repeated = digitsPerChannel == 1 ? slice + slice : slice
            let hex = String(repeated)
            guard let value = UInt8(hex, radix: 16) else { return nil }
            values.append(Double(value) / 255.0)
        }

        let red = values[0]
        let green = values[1]
        let blue = values[2]
        let alpha = hasAlpha ? values[3] : 1.0

        return ThemeColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func parseRGB(_ string: String) -> ThemeColor? {
        let components = string.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count == 3 else { return nil }

        guard let red = Double(components[0]),
              let green = Double(components[1]),
              let blue = Double(components[2]),
              (0 ... 255).contains(red),
              (0 ... 255).contains(green),
              (0 ... 255).contains(blue) else { return nil }

        return ThemeColor(
            red: red / 255.0,
            green: green / 255.0,
            blue: blue / 255.0,
            alpha: 1.0
        )
    }

    private static func parseRGBA(_ string: String) -> ThemeColor? {
        let components = string.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count == 4 else { return nil }

        guard let red = Double(components[0]),
              let green = Double(components[1]),
              let blue = Double(components[2]),
              let alpha = Double(components[3]),
              (0 ... 255).contains(red),
              (0 ... 255).contains(green),
              (0 ... 255).contains(blue),
              (0 ... 1).contains(alpha) else { return nil }

        return ThemeColor(
            red: red / 255.0,
            green: green / 255.0,
            blue: blue / 255.0,
            alpha: alpha
        )
    }

    // MARK: - Named colours

    /// Named-colour table ported from the original MacDown `NSColor+HTML`.
    /// Includes the 16 CSS basics plus the full legacy table.
    public static let namedColors: [String: ThemeColor] = {
        let entries: [(String, String)] = [
            ("aliceblue", "F0F8FF"),
            ("antiquewhite", "FAEBD7"),
            ("aqua", "00FFFF"),
            ("aquamarine", "7FFFD4"),
            ("azure", "F0FFFF"),
            ("beige", "F5F5DC"),
            ("bisque", "FFE4C4"),
            ("black", "000000"),
            ("blanchedalmond", "FFEBCD"),
            ("blue", "0000FF"),
            ("blueviolet", "8A2BE2"),
            ("brown", "A52A2A"),
            ("burlywood", "DEB887"),
            ("cadetblue", "5F9EA0"),
            ("chartreuse", "7FFF00"),
            ("chocolate", "D2691E"),
            ("coral", "FF7F50"),
            ("cornflowerblue", "6495ED"),
            ("cornsilk", "FFF8DC"),
            ("crimson", "DC143C"),
            ("cyan", "00FFFF"),
            ("darkblue", "00008B"),
            ("darkcyan", "008B8B"),
            ("darkgoldenrod", "B8860B"),
            ("darkgray", "A9A9A9"),
            ("darkgrey", "A9A9A9"),
            ("darkgreen", "006400"),
            ("darkkhaki", "BDB76B"),
            ("darkmagenta", "8B008B"),
            ("darkolivegreen", "556B2F"),
            ("darkorange", "FF8C00"),
            ("darkorchid", "9932CC"),
            ("darkred", "8B0000"),
            ("darksalmon", "E9967A"),
            ("darkseagreen", "8FBC8F"),
            ("darkslateblue", "483D8B"),
            ("darkslategray", "2F4F4F"),
            ("darkslategrey", "2F4F4F"),
            ("darkturquoise", "00CED1"),
            ("darkviolet", "9400D3"),
            ("deeppink", "FF1493"),
            ("deepskyblue", "00BFFF"),
            ("dimgray", "696969"),
            ("dimgrey", "696969"),
            ("dodgerblue", "1E90FF"),
            ("firebrick", "B22222"),
            ("floralwhite", "FFFAF0"),
            ("forestgreen", "228B22"),
            ("fuchsia", "FF00FF"),
            ("gainsboro", "DCDCDC"),
            ("ghostwhite", "F8F8FF"),
            ("gold", "FFD700"),
            ("goldenrod", "DAA520"),
            ("gray", "808080"),
            ("grey", "808080"),
            ("green", "008000"),
            ("greenyellow", "ADFF2F"),
            ("honeydew", "F0FFF0"),
            ("hotpink", "FF69B4"),
            ("indianred", "CD5C5C"),
            ("indigo", "4B0082"),
            ("ivory", "FFFFF0"),
            ("khaki", "F0E68C"),
            ("lavender", "E6E6FA"),
            ("lavenderblush", "FFF0F5"),
            ("lawngreen", "7CFC00"),
            ("lemonchiffon", "FFFACD"),
            ("lightblue", "ADD8E6"),
            ("lightcoral", "F08080"),
            ("lightcyan", "E0FFFF"),
            ("lightgoldenrodyellow", "FAFAD2"),
            ("lightgray", "D3D3D3"),
            ("lightgrey", "D3D3D3"),
            ("lightgreen", "90EE90"),
            ("lightpink", "FFB6C1"),
            ("lightsalmon", "FFA07A"),
            ("lightseagreen", "20B2AA"),
            ("lightskyblue", "87CEFA"),
            ("lightslategray", "778899"),
            ("lightslategrey", "778899"),
            ("lightsteelblue", "B0C4DE"),
            ("lightyellow", "FFFFE0"),
            ("lime", "00FF00"),
            ("limegreen", "32CD32"),
            ("linen", "FAF0E6"),
            ("magenta", "FF00FF"),
            ("maroon", "800000"),
            ("mediumaquamarine", "66CDAA"),
            ("mediumblue", "0000CD"),
            ("mediumorchid", "BA55D3"),
            ("mediumpurple", "9370D8"),
            ("mediumseagreen", "3CB371"),
            ("mediumslateblue", "7B68EE"),
            ("mediumspringgreen", "00FA9A"),
            ("mediumturquoise", "48D1CC"),
            ("mediumvioletred", "C71585"),
            ("midnightblue", "191970"),
            ("mintcream", "F5FFFA"),
            ("mistyrose", "FFE4E1"),
            ("moccasin", "FFE4B5"),
            ("navajowhite", "FFDEAD"),
            ("navy", "000080"),
            ("oldlace", "FDF5E6"),
            ("olive", "808000"),
            ("olivedrab", "6B8E23"),
            ("orange", "FFA500"),
            ("orangered", "FF4500"),
            ("orchid", "DA70D6"),
            ("palegoldenrod", "EEE8AA"),
            ("palegreen", "98FB98"),
            ("paleturquoise", "AFEEEE"),
            ("palevioletred", "D87093"),
            ("papayawhip", "FFEFD5"),
            ("peachpuff", "FFDAB9"),
            ("peru", "CD853F"),
            ("pink", "FFC0CB"),
            ("plum", "DDA0DD"),
            ("powderblue", "B0E0E6"),
            ("purple", "800080"),
            ("red", "FF0000"),
            ("rosybrown", "BC8F8F"),
            ("royalblue", "4169E1"),
            ("saddlebrown", "8B4513"),
            ("salmon", "FA8072"),
            ("sandybrown", "F4A460"),
            ("seagreen", "2E8B57"),
            ("seashell", "FFF5EE"),
            ("sienna", "A0522D"),
            ("silver", "C0C0C0"),
            ("skyblue", "87CEEB"),
            ("slateblue", "6A5ACD"),
            ("slategray", "708090"),
            ("slategrey", "708090"),
            ("snow", "FFFAFA"),
            ("springgreen", "00FF7F"),
            ("steelblue", "4682B4"),
            ("tan", "D2B48C"),
            ("teal", "008080"),
            ("thistle", "D8BFD8"),
            ("tomato", "FF6347"),
            ("turquoise", "40E0D0"),
            ("violet", "EE82EE"),
            ("wheat", "F5DEB3"),
            ("white", "FFFFFF"),
            ("whitesmoke", "F5F5F5"),
            ("yellow", "FFFF00"),
            ("yellowgreen", "9ACD32"),
        ]

        var map: [String: ThemeColor] = [:]
        for (name, hex) in entries {
            guard let color = parseHex(hex) else { continue }
            map[name] = color
        }
        return map
    }()
}
