import Foundation

/// Checks the classic cross-reference table emitted by the local PDF writers.
/// A WebKit/CoreGraphics PDF may reserve an object number without emitting its
/// body, then incorrectly mark that slot in use at byte zero. Only an absent,
/// unreferenced slot may be converted to a free entry before publication.
enum PDFCrossReferenceIntegrity {
    private static let maxBytes = 256 * 1024 * 1024
    // Repair copies the Data once; keep that exceptional path below the
    // separate PDF admission cap rather than doubling a 256 MiB allocation.
    private static let maxRepairBytes = 32 * 1024 * 1024
    private static let maxObjects = 100_000
    private static let maxRepairSlots = 16

    private struct Line {
        let start: Int
        let end: Int
        let next: Int
    }

    private struct Entry {
        let offset: Int
        let generation: Int
        let flag: UInt8
        let position: Int
    }

    private struct Table {
        let entries: [Entry]
        let xref: Int
    }

    private struct Reader {
        let bytes: UnsafeBufferPointer<UInt8>

        var count: Int {
            bytes.count
        }

        func matches(_ token: String, at offset: Int) -> Bool {
            let text = Array(token.utf8)
            guard offset >= 0, offset <= count - text.count else { return false }
            return text.indices.allSatisfy { bytes[offset + $0] == text[$0] }
        }

        func number(_ lower: Int, _ upper: Int) -> Int? {
            guard lower < upper else { return nil }
            var value = 0
            for index in lower ..< upper {
                let digit = bytes[index]
                guard digit >= 48, digit <= 57,
                      value <= (Int.max - Int(digit - 48)) / 10 else { return nil }
                value = value * 10 + Int(digit - 48)
            }
            return value
        }

        func line(at start: Int) -> Line? {
            guard start < count else { return nil }
            var end = start
            while end < count, bytes[end] != 10, bytes[end] != 13 {
                end += 1
                guard end - start <= 128 else { return nil }
            }
            guard end < count else { return nil }
            let next = end + ((bytes[end] == 13 && end + 1 < count && bytes[end + 1] == 10) ? 2 : 1)
            return Line(start: start, end: end, next: next)
        }

        func finalXrefOffset() -> Int? {
            // This repair does not rewrite incremental revisions or xref streams.
            let tailStart = max(0, count - 2048)
            let positions = (tailStart ..< max(tailStart, count - 9)).filter { matches("startxref", at: $0) }
            guard let marker = positions.last else { return nil }
            var digits = marker + 9
            while digits < count, bytes[digits] == 10 || bytes[digits] == 13 || bytes[digits] == 32 {
                digits += 1
            }
            let start = digits
            while digits < count, bytes[digits] >= 48, bytes[digits] <= 57 {
                digits += 1
            }
            guard let xref = number(start, digits), xref > 0, xref < marker,
                  matches("xref", at: xref) else { return nil }
            return xref
        }

        func entry(at cursor: Int) -> (Entry, Int)? {
            guard let row = line(at: cursor), row.end - row.start == 19,
                  bytes[row.start + 10] == 32, bytes[row.start + 16] == 32,
                  bytes[row.start + 18] == 32,
                  let offset = number(row.start, row.start + 10),
                  let generation = number(row.start + 11, row.start + 16) else { return nil }
            let flag = bytes[row.start + 17]
            guard flag == 102 || flag == 110 else { return nil } // f or n
            return (Entry(offset: offset, generation: generation, flag: flag, position: row.start), row.next)
        }

        func table() -> Table? {
            guard let xref = finalXrefOffset(),
                  let header = line(at: xref + 4), header.start == header.end,
                  let subsection = line(at: header.next), subsection.end - subsection.start >= 3,
                  bytes[subsection.start] == 48, bytes[subsection.start + 1] == 32,
                  let objectCount = number(subsection.start + 2, subsection.end),
                  objectCount > 1, objectCount <= PDFCrossReferenceIntegrity.maxObjects else { return nil }
            var cursor = subsection.next
            var entries: [Entry] = []
            entries.reserveCapacity(objectCount)
            var usedOffsets = Set<Int>()
            for object in 0 ..< objectCount {
                guard let (entry, next) = entry(at: cursor) else { return nil }
                if entry.flag == 110, entry.offset > 0 {
                    let prefix = "\(object) \(entry.generation) obj"
                    guard entry.offset < xref, matches(prefix, at: entry.offset),
                          usedOffsets.insert(entry.offset).inserted else { return nil }
                }
                entries.append(entry)
                cursor = next
            }
            guard matches("trailer", at: cursor), entries[0].flag == 102,
                  entries[0].generation == 65535 else { return nil }
            let trailerEnd = min(count, cursor + 4096)
            guard let trailer = String(bytes: bytes[cursor ..< trailerEnd], encoding: .utf8),
                  trailer.contains("/Size \(objectCount)"), trailer.contains("/Root "),
                  !trailer.contains("/Prev"), !trailer.contains("/XRefStm") else { return nil }
            return Table(entries: entries, xref: xref)
        }
    }

    static func normalized(_ data: Data) -> Data? {
        guard let changes = inspect(data, allowRepair: true) else { return nil }
        guard !changes.isEmpty else { return data }
        guard data.count <= maxRepairBytes else { return nil }
        var result = data
        for (position, value) in changes {
            result[position] = value
        }
        guard inspect(result, allowRepair: false)?.isEmpty == true else { return nil }
        return result
    }

    private static func inspect(_ data: Data, allowRepair: Bool) -> [(Int, UInt8)]? {
        guard !data.isEmpty, data.count <= maxBytes else { return nil }
        return data.withUnsafeBytes { raw in
            let reader = Reader(bytes: raw.bindMemory(to: UInt8.self))
            guard let table = reader.table() else { return nil }
            let entries = table.entries
            let orphans = entries.indices.dropFirst().filter { entries[$0].flag == 110 && entries[$0].offset == 0 }
            if orphans.isEmpty {
                return validFreeChain(entries) ? [] : nil
            }
            guard allowRepair, data.count <= maxRepairBytes, orphans.count <= maxRepairSlots,
                  entries[0].offset == 0,
                  !entries.dropFirst().contains(where: { $0.flag == 102 }) else { return nil }
            guard let syntax = PDFSyntaxReferences.scan(data) else { return nil }
            for object in orphans {
                guard entries[object].generation == 0,
                      !syntax.defined.contains(object),
                      !syntax.referenced.contains(object) else { return nil }
            }
            return freeSlotChanges(entries, orphans: orphans)
        }
    }

    private static func validFreeChain(_ entries: [Entry]) -> Bool {
        var seen = Set<Int>()
        var next = entries[0].offset
        while next != 0 {
            guard next < entries.count, entries[next].flag == 102,
                  seen.insert(next).inserted else { return false }
            next = entries[next].offset
        }
        return seen.count == entries.dropFirst().filter { $0.flag == 102 }.count
    }

    private static func freeSlotChanges(_ entries: [Entry], orphans: [Int]) -> [(Int, UInt8)] {
        var changes: [(Int, UInt8)] = []
        let chain = [0] + orphans
        for index in chain.indices {
            let next = index + 1 < chain.count ? chain[index + 1] : 0
            let field = Array(String(format: "%010d", next).utf8)
            let entry = entries[chain[index]]
            for digit in 0 ..< 10 {
                changes.append((entry.position + digit, field[digit]))
            }
            if index > 0 {
                changes.append((entry.position + 17, 102))
            }
        }
        return changes
    }
}
