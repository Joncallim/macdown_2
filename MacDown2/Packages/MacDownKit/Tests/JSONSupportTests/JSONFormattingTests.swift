import Foundation
@testable import JSONSupport
import Testing

/// EPIC-11 §3.5 — deterministic formatting: key sorting, indentation,
/// trailing newline, CRLF/BOM-aware line endings, canonical escaping,
/// idempotence, and invalid-input behavior.
@Suite("JSONFormatting")
struct JSONFormattingTests {
    @Test func prettyPrintsNestedDocument() {
        let input = #"{"b":1,"a":{"c":true},"d":[1,2]}"#
        let outcome = JSONFormatter.format(input)
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        let expected = """
        {
          "b": 1,
          "a": {
            "c": true
          },
          "d": [
            1,
            2
          ]
        }
        """
        // The formatter appends exactly one trailing line terminator.
        #expect(output == expected + "\n")
    }

    @Test func sortingUsesUnicodeScalarOrderRecursively() throws {
        let input = #"{"z":1,"é":2,"a":3,"e\u0301":4}"#
        let outcome = JSONFormatter.format(input, options: JSONFormatOptions(sortKeys: true))
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        // Unicode scalar order by code point: 'a' (0x61) < 'e' (0x65,
        // followed by combining mark 0x301) < 'z' (0x7A) < 'é' (0xE9).
        // Note 'z' sorts before 'é' because 0x7A < 0xE9.
        let aKeyBound = try #require(output.range(of: "\"a\": 3,")).lowerBound
        let eCombiningBound = try #require(output.range(of: "\"e\u{301}\": 4,")).lowerBound
        let zKeyBound = try #require(output.range(of: "\"z\": 1,")).lowerBound
        let eAcuteKeyBound = try #require(output.range(of: "\"é\": 2")).lowerBound // last member: no comma
        #expect(aKeyBound < eCombiningBound)
        #expect(eCombiningBound < zKeyBound)
        #expect(zKeyBound < eAcuteKeyBound)
    }

    @Test func sortingIsRecursiveInsideNestedObjects() throws {
        let input = #"{"o":{"y":1,"x":2},"k":0}"#
        let outcome = JSONFormatter.format(input, options: JSONFormatOptions(sortKeys: true))
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        let xKeyBound = try #require(output.range(of: "\"x\": 2")).lowerBound
        let yKeyBound = try #require(output.range(of: "\"y\": 1")).lowerBound
        #expect(xKeyBound < yKeyBound)
    }

    @Test func arraysRetainSourceOrder() throws {
        let input = #"{"a":[3,1,2]}"#
        let outcome = JSONFormatter.format(input, options: JSONFormatOptions(sortKeys: true))
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        let one = try #require(output.range(of: "1,")).lowerBound
        let two = try #require(output.range(of: "2")).lowerBound
        let three = try #require(output.range(of: "3,")).lowerBound
        #expect(three < one)
        #expect(one < two)
    }

    @Test func emptyContainersStayInline() {
        let input = #"{"a":{},"b":[],"c":1}"#
        let outcome = JSONFormatter.format(input)
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        #expect(output.contains("\"a\": {}"))
        #expect(output.contains("\"b\": []"))
    }

    @Test func scalarRootsFormatToTheirText() {
        for input in ["5", "\"hi\"", "true", "null", "1.5e-3"] {
            guard case let .formatted(output) = JSONFormatter.format(input) else {
                Issue.record("Expected formatted outcome for \(input)")
                continue
            }
            if input == "\"hi\"" {
                #expect(output == "\"hi\"\n")
            } else {
                #expect(output == "\(input)\n")
            }
        }
    }

    @Test func trailingNewlineCanBeDisabled() {
        let input = #"{"a":1}"#
        let outcome = JSONFormatter.format(input, options: JSONFormatOptions(trailingNewline: false))
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        #expect(output.hasSuffix("}"))
        #expect(!output.hasSuffix("\n"))
    }

    @Test func crlfSourceProducesCrlfOutput() {
        let input = "{\r\n\"a\": 1\r\n}"
        let outcome = JSONFormatter.format(input)
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        #expect(output == "{\r\n  \"a\": 1\r\n}\r\n")
    }

    @Test func mixedLineEndingsProduceLF() {
        let input = "{\r\n\"a\": 1\n}"
        let outcome = JSONFormatter.format(input)
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        #expect(output == "{\n  \"a\": 1\n}\n")
    }

    @Test func canonicalEscapingNormalizesRepresentations() {
        let input = #"{"k":"\u0041\u00e9"}"#
        let outcome = JSONFormatter.format(input)
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        #expect(output.contains("\"Aé\""))
    }

    @Test func controlCharactersAreEscaped() {
        // The JSON escape \u0001 (literal in the raw string) decodes to a
        // control character, which the formatter must re-escape.
        let input = #"{"k":"a\u0001b"}"#
        let outcome = JSONFormatter.format(input)
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        #expect(output.contains(#""a\u0001b""#))
    }

    @Test func slashesAreNotEscaped() {
        let input = #"{"k":"a/b"}"#
        let outcome = JSONFormatter.format(input)
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        #expect(output.contains("\"a/b\""))
    }

    @Test func numberRepresentationsArePreservedVerbatim() {
        let input = #"{"a":1.50,"b":1e10,"c":-0.25}"#
        let outcome = JSONFormatter.format(input)
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        #expect(output.contains("\"a\": 1.50"))
        #expect(output.contains("\"b\": 1e10"))
        #expect(output.contains("\"c\": -0.25"))
    }

    @Test func formattingIsIdempotent() {
        let input = #"{"z":[1,2],"a":{"x":true}}"#
        guard case let .formatted(first) = JSONFormatter.format(input) else {
            Issue.record("Expected formatted outcome")
            return
        }
        guard case let .formatted(second) = JSONFormatter.format(first) else {
            Issue.record("Expected formatted outcome")
            return
        }
        #expect(first == second)
    }

    @Test func invalidInputProducesDiagnosticNotOutput() {
        let input = #"{"a":1,"a":2}"#
        let outcome = JSONFormatter.format(input)
        guard case let .invalid(diagnostic) = outcome else {
            Issue.record("Expected invalid outcome")
            return
        }
        #expect(diagnostic.message.contains("Duplicate object key"))
    }

    @Test func formattingNeverRunsOnDuplicateKeyDocuments() {
        // Sorted formatting of a duplicate-key document must not produce
        // anything, including a silently merged object.
        let input = #"{"b":1,"a":2,"b":3}"#
        guard case .invalid = JSONFormatter.format(input, options: JSONFormatOptions(sortKeys: true)) else {
            Issue.record("Expected invalid outcome")
            return
        }
    }

    @Test func formattingRejectsInvalidNumbers() {
        let input = #"{"a": 01}"#
        guard case .invalid = JSONFormatter.format(input) else {
            Issue.record("Expected invalid outcome")
            return
        }
    }

    @Test func fourSpaceIndentIsHonored() {
        let input = #"{"a":{"b":1}}"#
        let outcome = JSONFormatter.format(input, options: JSONFormatOptions(indentWidth: 4))
        guard case let .formatted(output) = outcome else {
            Issue.record("Expected formatted outcome")
            return
        }
        #expect(output.contains("\n    \"a\": {\n"))
        #expect(output.contains("\n        \"b\": 1\n"))
    }
}
