import Foundation

/// Style for one capture class. `bold`/`italic` synthesise a font trait at apply time.
public struct TokenStyle: Sendable, Equatable {
    public var color: ThemeColor
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool

    public init(
        color: ThemeColor,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false
    ) {
        self.color = color
        self.bold = bold
        self.italic = italic
        self.underline = underline
    }
}

extension TokenStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case color
        case bold
        case italic
        case underline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decode(ThemeColor.self, forKey: .color)
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try container.decodeIfPresent(Bool.self, forKey: .underline) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(bold, forKey: .bold)
        try container.encode(italic, forKey: .italic)
        try container.encode(underline, forKey: .underline)
    }
}

/// Non-token editor colours (applied to the `NSTextView` itself, not per-run).
public struct EditorChrome: Codable, Sendable, Equatable {
    public var background: ThemeColor
    public var foreground: ThemeColor
    public var caret: ThemeColor
    public var selection: ThemeColor
    public var currentLine: ThemeColor?
    public var invisibles: ThemeColor?

    public init(
        background: ThemeColor,
        foreground: ThemeColor,
        caret: ThemeColor,
        selection: ThemeColor,
        currentLine: ThemeColor? = nil,
        invisibles: ThemeColor? = nil
    ) {
        self.background = background
        self.foreground = foreground
        self.caret = caret
        self.selection = selection
        self.currentLine = currentLine
        self.invisibles = invisibles
    }
}

public enum ThemeAppearance: String, Codable, Sendable, Equatable {
    case light
    case dark
}
