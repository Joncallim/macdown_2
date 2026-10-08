import Foundation

/// A line terminator convention. Detection and conversion are explicit,
/// user-visible operations; `FileStore` never rewrites terminators.
public enum LineEnding: Sendable, Equatable, CaseIterable {
    case lineFeed
    case crlf
    case carriageReturn

    /// The terminator as it appears in text.
    public var text: String {
        switch self {
        case .lineFeed: "\n"
        case .crlf: "\r\n"
        case .carriageReturn: "\r"
        }
    }
}

public extension LineEnding {
    /// `fragment` with every line break rewritten to the dominant terminator of
    /// `document`, so inserted text never adds a second line-ending convention
    /// (invariant #5). Returns `fragment` untouched when it has no line break
    /// (the common case, without scanning `document`) or when `document` has no
    /// terminator of its own to follow.
    static func adaptingLineBreaks(in fragment: String, toMatch document: String) -> String {
        guard fragment.containsLineBreak else { return fragment }
        return adaptingLineBreaks(in: fragment, to: LineEndingProfile(detecting: document).dominantEnding)
    }

    /// As above, for a caller that already knows the target ending; `nil`
    /// leaves `fragment` untouched.
    static func adaptingLineBreaks(in fragment: String, to target: LineEnding?) -> String {
        guard fragment.containsLineBreak, let target else { return fragment }
        return fragment
            .replacingOccurrences(of: "\r\n", with: "\n", options: .literal)
            .replacingOccurrences(of: "\r", with: "\n", options: .literal)
            .replacingOccurrences(of: "\n", with: target.text, options: .literal)
    }
}

private extension String {
    var containsLineBreak: Bool {
        utf8.contains { $0 == 0x0A || $0 == 0x0D }
    }
}

/// The terminators found in a piece of text. CRLF is one terminator, never an
/// LF plus a CR, which is why the scan works on UTF-8 bytes: `String` treats
/// CRLF as a single `Character`, and Unicode line separators (U+2028/2029,
/// NEL) are ordinary text here, not terminators.
public struct LineEndingProfile: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case none
        case lineFeed
        case crlf
        case carriageReturn
        case mixed
    }

    public let lfCount: Int
    public let crlfCount: Int
    public let crCount: Int

    public init(lfCount: Int = 0, crlfCount: Int = 0, crCount: Int = 0) {
        self.lfCount = lfCount
        self.crlfCount = crlfCount
        self.crCount = crCount
    }

    public init(detecting text: String) {
        var lineFeeds = 0, crlfs = 0, carriageReturns = 0
        var previousWasCR = false
        for byte in text.utf8 {
            switch byte {
            case 0x0A:
                if previousWasCR {
                    crlfs += 1
                    carriageReturns -= 1
                } else {
                    lineFeeds += 1
                }
                previousWasCR = false
            case 0x0D:
                carriageReturns += 1
                previousWasCR = true
            default:
                previousWasCR = false
            }
        }
        self.init(lfCount: lineFeeds, crlfCount: crlfs, crCount: carriageReturns)
    }

    public var kind: Kind {
        switch (lfCount > 0, crlfCount > 0, crCount > 0) {
        case (false, false, false): .none
        case (true, false, false): .lineFeed
        case (false, true, false): .crlf
        case (false, false, true): .carriageReturn
        default: .mixed
        }
    }

    /// The single terminator in use, or `nil` when there is none or several.
    public var uniformEnding: LineEnding? {
        switch kind {
        case .lineFeed: .lineFeed
        case .crlf: .crlf
        case .carriageReturn: .carriageReturn
        case .none, .mixed: nil
        }
    }

    /// The most frequent terminator (ties resolve LF, CRLF, CR), or `nil`
    /// when the text has none.
    public var dominantEnding: LineEnding? {
        guard kind != .none else { return nil }
        let ranked: [(LineEnding, Int)] = [(.lineFeed, lfCount), (.crlf, crlfCount), (.carriageReturn, crCount)]
        return ranked.max { $0.1 < $1.1 }?.0
    }
}
