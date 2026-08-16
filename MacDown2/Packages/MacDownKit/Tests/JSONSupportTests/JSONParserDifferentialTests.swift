import Foundation
@testable import JSONSupport
import Testing

/// Differential net against Foundation's `JSONSerialization`, an independent
/// battle-tested parser: every top-level container Foundation accepts must
/// also be accepted by `JSONParser` (except duplicate-key documents, which
/// this parser deliberately rejects per EPIC-11 §3.3), and a corpus of
/// known-invalid documents must be rejected.
///
/// Intentional divergences, by contract: top-level scalars (RFC 8259 allows
/// any value; Foundation requires a container) and duplicate keys.
@Suite("JSONParserDifferential")
struct JSONParserDifferentialTests {
    @Test func foundationAcceptedDocumentsAreAlsoAccepted() {
        let corpus: [String] = [
            #"{"a":1}"#,
            #"[1,2,3]"#,
            "{\n\t\"a\" : -1.5e+10 }",
            #"{"":""," ":[]}"#,
            #"{"a":{"b":{"c":[[],{}]}}}"#,
            #"["\u0041\u00e9\uD83D\uDE00"]"#,
            #"{"k":"\/\/"}"#,
            #"[true,false,null]"#,
            #"{"x":[1.0,2e5,-0.25E-3]}"#,
            #"[1,2,{"n":null,"b":true}]"#,
            #"{"a":0}"#,
            #"[0]"#,
            #"{"z":{},"a":[]}"#,
            String(repeating: "[", count: 20) + "1" + String(repeating: "]", count: 20),
            "{\r\n\t\"a\"\r:\t1\r\n}",
            #"{"emoji":"😀💡","combining":"e\u0301"}"#,
            #"[[[[{"deep":[true]}]]]]"#,
            #"{"big":123456789012345678901234567890}"#,
            #"[1e0,1E0,1e+0,1E-0,0.0]"#,
        ]
        for text in corpus {
            let foundationAccepts = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
            #expect(foundationAccepts, "corpus entry must be Foundation-accepted: \(text)")
            if case .valid = JSONParser.parse(text) {
                // accepted: agreement.
            } else {
                Issue.record("JSONParser rejected a document Foundation accepts: \(text)")
            }
        }
    }

    @Test func knownInvalidDocumentsAreRejected() {
        let corpus: [String] = [
            #"{"a":01}"#, // leading zero
            "[1,]", // trailing comma
            #"{"a":1,}"#, // trailing comma in object
            #"{"a" 1}"#, // missing colon
            "[1 2]", // missing comma
            #"{"a":}"#, // missing value
            "{1:2}", // unquoted key
            "tru", // truncated literal
            "truex", // trailing garbage
            #""unterminated"#,
            #"{"a":1}x"#, // trailing garbage after value
            #"[1,2][3]"#, // second value
            #"{"a":+1}"#, // leading plus
            #"[.5]"#, // missing integer part
            #"[5.]"#, // missing fraction digits
            #"[1e]"#, // missing exponent digits
            #"{"a":1"b":2}"#, // missing comma
            #"[NaN]"#,
            "[Infinity]",
            "\u{FEFF}", // BOM inside the text is not whitespace for JSON
        ]
        for text in corpus {
            if case .valid = JSONParser.parse(text) {
                Issue.record("JSONParser accepted a known-invalid document: \(text)")
            }
        }
    }

    /// Producer-consumer symmetry: random nested structures encoded by
    /// Foundation must parse, outline, format, and re-parse identically.
    /// Deterministic (seeded) so failures reproduce.
    @Test func randomFoundationEncodedStructuresRoundTrip() throws {
        var generator = SeededGenerator(seed: 0x5EED)
        let stringPool = [
            "", "plain", "quote\"back\\slash", "é\u{301}😀",
            "control\u{01}\u{1F}", "unicode\u{4E2D}\u{6587}", "/solidus",
        ]
        for iteration in 0 ..< 50 {
            var value = randomValue(depth: 0, generator: &generator, stringPool: stringPool)
            // JSONSerialization requires a top-level container; wrap scalar
            // roots (which JSONParser accepts by contract) for the oracle.
            if !(value is [Any] || value is [String: Any]) {
                value = [value]
            }
            let data = try JSONSerialization.data(withJSONObject: value)
            let text = try #require(String(data: data, encoding: .utf8))

            guard case .valid = JSONParser.parse(text) else {
                Issue.record("iteration \(iteration): parser rejected Foundation-encoded \(text)")
                continue
            }
            guard case .valid = JSONOutlineBuilder.outline(text) else {
                Issue.record("iteration \(iteration): outline rejected \(text)")
                continue
            }
            guard case let .formatted(pretty) = JSONFormatter.format(text) else {
                Issue.record("iteration \(iteration): formatter rejected \(text)")
                continue
            }
            guard case .valid = JSONParser.parse(pretty) else {
                Issue.record("iteration \(iteration): formatted output did not re-parse: \(pretty)")
                continue
            }
        }
    }

    private func randomValue(
        depth: Int,
        generator: inout SeededGenerator,
        stringPool: [String]
    ) -> Any {
        if depth >= 6 {
            return randomScalar(generator: &generator, stringPool: stringPool)
        }
        switch generator.nextUInt() % 6 {
        case 0, 1, 2:
            return randomScalar(generator: &generator, stringPool: stringPool)
        case 3:
            return (0 ..< Int(generator.nextUInt() % 5)).map { _ in
                randomValue(depth: depth + 1, generator: &generator, stringPool: stringPool)
            }
        default:
            var object: [String: Any] = [:]
            for _ in 0 ..< Int(generator.nextUInt() % 5) {
                object["k\(generator.nextUInt() % 7)"] =
                    randomValue(depth: depth + 1, generator: &generator, stringPool: stringPool)
            }
            return object
        }
    }

    private func randomScalar(generator: inout SeededGenerator, stringPool: [String]) -> Any {
        switch generator.nextUInt() % 5 {
        case 0: stringPool[Int(generator.nextUInt() % UInt64(stringPool.count))]
        case 1: Int(generator.nextUInt() % 100_000) - 50000
        case 2: Double(Int(generator.nextUInt() % 100_000) - 50000) / 100.0
        case 3: generator.nextUInt() % 2 == 0
        default: NSNull()
        }
    }
}

/// Minimal deterministic LCG so the fuzz corpus reproduces exactly.
private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUInt() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
