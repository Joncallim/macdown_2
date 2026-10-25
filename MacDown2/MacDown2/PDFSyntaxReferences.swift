import Foundation

/// A bounded lexical pass over a classic PDF. It collects indirect references
/// from object dictionaries AND the trailer, without treating bytes in strings
/// or stream payloads as PDF syntax. Unknown stream lengths fail closed.
struct PDFSyntaxReferences {
    let referenced: Set<Int>
    let defined: Set<Int>

    private enum Token {
        case end
        case number(Int)
        case name(String)
        case word(String)
        case other
    }

    private struct Lexer {
        let bytes: UnsafeBufferPointer<UInt8>
        var cursor = 0

        private func isSpace(_ byte: UInt8) -> Bool {
            [0, 9, 10, 12, 13, 32].contains(byte)
        }

        private func isDelimiter(_ byte: UInt8) -> Bool {
            [37, 40, 41, 47, 60, 62, 91, 93, 123, 125].contains(byte)
        }

        mutating func next() -> Token? {
            skipTrivia()
            guard cursor < bytes.count else { return .end }
            let byte = bytes[cursor]
            if byte == 40 {
                return skipLiteralString() ? .other : nil
            }
            if byte == 60, cursor + 1 < bytes.count, bytes[cursor + 1] == 60 {
                cursor += 2
                return .other
            }
            if byte == 62, cursor + 1 < bytes.count, bytes[cursor + 1] == 62 {
                cursor += 2
                return .other
            }
            if byte == 60, cursor + 1 < bytes.count {
                return skipHexString() ? .other : nil
            }
            if isDelimiter(byte), byte != 47 {
                cursor += 1
                return .other
            }
            if byte == 47 {
                cursor += 1
                let name = readWord()
                return name.isEmpty ? nil : .name(name)
            }
            return parsedWord()
        }

        private mutating func skipTrivia() {
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if isSpace(byte) {
                    cursor += 1
                } else if byte == 37 { // comment, including the binary PDF header
                    while cursor < bytes.count, bytes[cursor] != 10, bytes[cursor] != 13 {
                        cursor += 1
                    }
                } else {
                    break
                }
            }
        }

        private mutating func parsedWord() -> Token? {
            let word = readWord()
            guard !word.isEmpty else { return nil }
            let digits = word.utf8.drop(while: { $0 == 43 || $0 == 45 })
            if !digits.isEmpty, digits.allSatisfy({ $0 >= 48 && $0 <= 57 }) {
                guard let value = Int(word) else { return nil }
                if value < 0 {
                    return .word(word)
                }
                return .number(value)
            }
            return .word(word)
        }

        private mutating func readWord() -> String {
            let start = cursor
            while cursor < bytes.count, !isSpace(bytes[cursor]), !isDelimiter(bytes[cursor]) {
                cursor += 1
            }
            // Very long unstructured tokens are not part of the writer's
            // classic PDF grammar; the caller rejects them via empty output.
            guard cursor - start <= 256,
                  let word = String(bytes: bytes[start ..< cursor], encoding: .ascii) else { return "" }
            return word
        }

        private mutating func skipLiteralString() -> Bool {
            cursor += 1
            var depth = 1
            while cursor < bytes.count {
                let byte = bytes[cursor]
                cursor += 1
                if byte == 92 { // escaped next byte, including a parenthesis
                    guard cursor < bytes.count else { return false }
                    cursor += 1
                } else if byte == 40 {
                    depth += 1
                } else if byte == 41 {
                    depth -= 1
                    if depth == 0 {
                        return true
                    }
                }
            }
            return false
        }

        private mutating func skipHexString() -> Bool {
            cursor += 1
            while cursor < bytes.count {
                let byte = bytes[cursor]
                cursor += 1
                if byte == 62 {
                    return true
                }
            }
            return false
        }

        mutating func skipStream(length: Int) -> Bool {
            guard length >= 0, cursor < bytes.count else { return false }
            if bytes[cursor] == 13, cursor + 1 < bytes.count, bytes[cursor + 1] == 10 {
                cursor += 2
            } else if bytes[cursor] == 10 {
                cursor += 1
            } else {
                return false
            }
            guard length <= bytes.count - cursor else { return false }
            cursor += length
            guard case .word("endstream") = next() else { return false }
            return true
        }
    }

    private struct State {
        var referenced = Set<Int>()
        var defined = Set<Int>()
        var previousNumbers: [Int] = []
        var awaitingLength = false
        var possibleIndirectLength = false
        var streamLength: Int?

        mutating func consume(_ token: Token, lexer: inout Lexer) -> Bool {
            guard acceptLength(token) else { return false }
            switch token {
            case .end:
                return true
            case let .number(value):
                previousNumbers.append(value)
                if previousNumbers.count > 2 {
                    previousNumbers.removeFirst()
                }
            case let .name(name):
                previousNumbers.removeAll()
                guard name != "ObjStm", name != "XRefStm", name != "Prev" else { return false }
                if name == "Length" {
                    awaitingLength = true
                }
            case let .word(word):
                guard consumeWord(word, lexer: &lexer) else { return false }
            case .other:
                previousNumbers.removeAll()
            }
            return true
        }

        private mutating func acceptLength(_ token: Token) -> Bool {
            if awaitingLength {
                guard case let .number(length) = token else { return false }
                streamLength = length
                awaitingLength = false
                possibleIndirectLength = true
            } else if possibleIndirectLength {
                if case .number = token {
                    return false
                } // indirect /Length
                possibleIndirectLength = false
            }
            return true
        }

        private mutating func consumeWord(_ word: String, lexer: inout Lexer) -> Bool {
            if previousNumbers.count == 2 {
                if word == "R" {
                    referenced.insert(previousNumbers[0])
                }
                if word == "obj" {
                    defined.insert(previousNumbers[0])
                }
            }
            previousNumbers.removeAll()
            if word == "obj" {
                streamLength = nil
            }
            if word == "stream" {
                guard let length = streamLength, lexer.skipStream(length: length) else { return false }
                streamLength = nil
            }
            return true
        }
    }

    static func scan(_ data: Data) -> PDFSyntaxReferences? {
        data.withUnsafeBytes { raw in
            var lexer = Lexer(bytes: raw.bindMemory(to: UInt8.self))
            var state = State()
            while true {
                guard let token = lexer.next() else { return nil }
                if case .end = token {
                    return PDFSyntaxReferences(referenced: state.referenced, defined: state.defined)
                }
                guard state.consume(token, lexer: &lexer) else { return nil }
            }
        }
    }
}
