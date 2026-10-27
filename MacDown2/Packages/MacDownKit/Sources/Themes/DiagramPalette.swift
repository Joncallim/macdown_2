import Foundation

/// Screen artwork follows preview colors; paper has its own readable defaults.
public enum DiagramDestination: String, Sendable, Codable, Hashable {
    case screen
    case print
}

/// The resolved default presentation policy for first-party diagram artwork.
/// Explicit colors in authored diagrams remain the renderer's responsibility.
public struct DiagramPalette: Codable, Sendable, Equatable, Hashable {
    public let policyID: String
    public let canvas: String
    public let text: String
    public let stroke: String
    public let nodeFill: String
    public let accent: String
    public let secondary: String
    /// Generated categories use the resolved foreground. Source-level
    /// renderer styles remain the only way a diagram acquires colour.
    public var pieColors: [String] {
        Array(repeating: text, count: 12)
    }

    /// The separator and fixed, validated values make this a stable, lossless
    /// content identity. It is not an authorization or cryptographic digest.
    public var fingerprint: String {
        ([policyID, canvas, text, stroke, nodeFill, accent, secondary] + pieColors).joined(separator: "|")
    }

    /// Values cross the WebKit boundary as arguments, never interpolated script.
    public var rendererArguments: [String: String] {
        var values = [
            "policyID": policyID,
            "canvas": canvas,
            "text": text,
            "stroke": stroke,
            "nodeFill": nodeFill,
            "accent": accent,
            "secondary": secondary,
        ]
        for (index, color) in pieColors.enumerated() {
            values["pie\(index + 1)"] = color
        }
        return values
    }

    public static let neutralLight = DiagramPalette(
        policyID: "neutral-light-v1",
        canvas: "#FFFFFF",
        text: "#1A1A1A",
        stroke: "#1A1A1A",
        nodeFill: "#FFFFFF",
        accent: "#1A1A1A",
        secondary: "#1A1A1A"
    )

    /// Preview text and canvas are separate inputs, resolved before rendering.
    /// Print never inherits screen colors baked into SVG or PNG artwork.
    public static func resolved(
        for destination: DiagramDestination, foreground: ThemeColor, background: ThemeColor
    ) -> DiagramPalette {
        guard destination == .screen else { return .neutralLight }
        let text = hex(foreground, fallback: neutralLight.text)
        let canvas = hex(background, fallback: neutralLight.canvas)
        return DiagramPalette(
            policyID: "preview-context-v1", canvas: canvas, text: text, stroke: text,
            nodeFill: canvas, accent: text, secondary: text
        )
    }

    private static func hex(_ color: ThemeColor, fallback: String) -> String {
        let components = [color.red, color.green, color.blue]
        guard components.allSatisfy(\.isFinite) else { return fallback }
        return "#" + components.map {
            String(format: "%02X", Int((min(max($0, 0), 1) * 255).rounded()))
        }.joined()
    }

    init(policyID: String, canvas: String, text: String, stroke: String,
         nodeFill: String, accent: String, secondary: String) {
        self.policyID = policyID
        self.canvas = canvas
        self.text = text
        self.stroke = stroke
        self.nodeFill = nodeFill
        self.accent = accent
        self.secondary = secondary
    }

    private enum CodingKeys: String, CodingKey {
        case policyID, canvas, text, stroke, nodeFill, accent, secondary, pieColors
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let candidate = try DiagramPalette(
            policyID: fields.decode(String.self, forKey: .policyID),
            canvas: fields.decode(String.self, forKey: .canvas),
            text: fields.decode(String.self, forKey: .text),
            stroke: fields.decode(String.self, forKey: .stroke),
            nodeFill: fields.decode(String.self, forKey: .nodeFill),
            accent: fields.decode(String.self, forKey: .accent),
            secondary: fields.decode(String.self, forKey: .secondary)
        )
        let colors = [
            candidate.canvas, candidate.text, candidate.stroke,
            candidate.nodeFill, candidate.accent, candidate.secondary,
        ]
        let supported = candidate == .neutralLight || (
            candidate.policyID == "preview-context-v1" && colors.allSatisfy {
                $0.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil
            }
        )
        guard supported,
              try fields.decode([String].self, forKey: .pieColors) == candidate.pieColors else {
            throw DecodingError.dataCorruptedError(
                forKey: .policyID, in: fields, debugDescription: "Unsupported diagram palette policy"
            )
        }
        self = candidate
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(policyID, forKey: .policyID)
        try fields.encode(canvas, forKey: .canvas)
        try fields.encode(text, forKey: .text)
        try fields.encode(stroke, forKey: .stroke)
        try fields.encode(nodeFill, forKey: .nodeFill)
        try fields.encode(accent, forKey: .accent)
        try fields.encode(secondary, forKey: .secondary)
        try fields.encode(pieColors, forKey: .pieColors)
    }
}
