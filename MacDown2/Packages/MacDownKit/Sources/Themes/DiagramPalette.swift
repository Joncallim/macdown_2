import Foundation

/// The one default presentation policy for first-party diagram artwork.
/// Explicit colors in authored diagrams remain the renderer's responsibility.
public struct DiagramPalette: Codable, Sendable, Equatable, Hashable {
    public let policyID: String
    public let canvas: String
    public let text: String
    public let stroke: String
    public let nodeFill: String
    public let accent: String
    public let secondary: String
    /// The fixed twelve-color sequence belongs to this policy rather than
    /// individual render contexts crossing actor boundaries.
    public var pieColors: [String] {
        [
            "#4E79A7", "#F28E2B", "#59A14F", "#E15759", "#B07AA1", "#76B7B2",
            "#EDC949", "#FF9DA7", "#9C755F", "#BAB0AC", "#86BCB6", "#D37295",
        ]
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
        nodeFill: "#F3F5F8",
        accent: "#285EA8",
        secondary: "#526274"
    )

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
        guard candidate == .neutralLight,
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
