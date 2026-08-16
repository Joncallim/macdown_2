import Foundation

/// A stable, value-typed diagnostic for invalid JSON, safe to cross actors.
///
/// All offsets are UTF-16 code-unit offsets into the immutable editor text
/// snapshot — the same coordinate system as editor selections and
/// `NSString`/AppKit text APIs.
public struct JSONDiagnostic: Sendable, Equatable {
    public let message: String
    /// 1-based physical line.
    public let line: Int
    /// 1-based UTF-16 column within the physical line.
    public let column: Int
    /// Half-open UTF-16 code-unit range into the editor text snapshot, or
    /// `nil` when the error has no meaningful extent (e.g. empty input).
    public let range: Range<Int>?

    public init(message: String, line: Int, column: Int, range: Range<Int>?) {
        self.message = message
        self.line = line
        self.column = column
        self.range = range
    }
}

/// The outcome of parsing a JSON document.
public enum JSONParseOutcome: Sendable, Equatable {
    /// The text is a valid JSON document.
    case valid(JSONNode)
    /// The text is invalid; the diagnostic describes the first error.
    case invalid(JSONDiagnostic)
}

/// The outcome of a formatting request.
public enum JSONFormatOutcome: Sendable, Equatable {
    /// `text` is the deterministic formatting of the valid document.
    case formatted(String)
    /// The document is invalid; no formatting is produced.
    case invalid(JSONDiagnostic)
}

/// The outcome of an outline request.
public enum JSONOutlineOutcome: Sendable, Equatable {
    case valid([ContentOutlineItem])
    case invalid(JSONDiagnostic)
}

/// One node of a parsed JSON document with its exact source location.
public struct JSONNode: Sendable, Equatable {
    public let value: JSONScalarValue
    /// Half-open UTF-16 range of this value (no surrounding whitespace).
    public let sourceRange: Range<Int>
    /// 1-based physical line span covering the value.
    public let lineRange: ClosedRange<Int>

    public init(value: JSONScalarValue, sourceRange: Range<Int>, lineRange: ClosedRange<Int>) {
        self.value = value
        self.sourceRange = sourceRange
        self.lineRange = lineRange
    }
}

public enum JSONScalarValue: Sendable, Equatable {
    /// Object members in source order. Duplicate keys are rejected by the
    /// parser, so a member key uniquely identifies its node within the object.
    case object([JSONObjectMember])
    case array([JSONNode])
    /// Decoded string content (escapes resolved).
    case string(String)
    /// The raw source text of the number, preserved verbatim so formatting
    /// never changes a number's representation.
    case number(String)
    case boolean(Bool)
    case null
}

/// One key/value pair of an object.
public struct JSONObjectMember: Sendable, Equatable {
    /// The decoded key (escapes resolved).
    public let key: String
    /// Half-open UTF-16 range of the key (including quotes).
    public let keyRange: Range<Int>
    public let value: JSONNode

    public init(key: String, keyRange: Range<Int>, value: JSONNode) {
        self.key = key
        self.keyRange = keyRange
        self.value = value
    }
}
