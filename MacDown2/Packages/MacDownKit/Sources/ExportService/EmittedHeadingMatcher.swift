import CryptoKit
import Foundation
import MarkdownEngine

/// Correlates the one source heading index with generated cmark heading nodes
/// after derived content has changed the body cmark sees. This proves parser
/// identity only; target IDs and final DOM uniqueness need separate checks.
enum EmittedHeadingMatcher {
    struct Match: Equatable {
        let indexed: HeadingAnchorIndex.Heading
        let emitted: CMarkGFM.HeadingLocation
    }

    static func match(
        index: HeadingAnchorIndex,
        document: MarkdownDocument,
        sourceText: String,
        derived: DerivedContentComposer.Result,
        rendered: CMarkGFM.Rendered
    ) -> [Match]? {
        let fullSourceMap = SourceMap(text: sourceText)
        guard (0 ... fullSourceMap.lineCount).contains(document.bodyLineOffset) else { return nil }
        let bodyStart = document.bodyLineOffset < fullSourceMap.lineCount
            ? fullSourceMap.lineStartOffsets[document.bodyLineOffset]
            : fullSourceMap.utf16Length
        guard (sourceText as NSString).substring(from: bodyStart) == document.body,
              let coordinates = derived.coordinates,
              coordinates.sourceSHA256 == sha256(document.body),
              coordinates.renderedSHA256 == sha256(derived.splicedBody),
              index.identity.sourceSHA256 == sha256(sourceText),
              document.sourceMap == fullSourceMap,
              rendered.headingSourceSHA256 == sha256(derived.splicedBody),
              index.identity.parseRevision == document.revision,
              index.identity.parseOptions == document.options,
              index.headings.count == document.headings.count,
              index.headings.count == rendered.headingLocations.count else { return nil }

        var emittedByLine: [Int: CMarkGFM.HeadingLocation] = [:]
        for heading in rendered.headingLocations {
            guard heading.line > 0, heading.column > 0,
                  emittedByLine.updateValue(heading, forKey: heading.line) == nil else { return nil }
        }

        let originalLines = SourceMap(text: document.body)
        let splicedLines = SourceMap(text: derived.splicedBody)
        var matches: [Match] = []
        matches.reserveCapacity(index.headings.count)
        for (indexed, source) in zip(index.headings, document.headings) {
            guard indexed.sourceLineRange == source.lineRange,
                  indexed.level == source.level,
                  indexed.title == source.title else { return nil }
            let bodyLine = indexed.sourceLineRange.lowerBound - document.bodyLineOffset
            guard (1 ... originalLines.lineCount).contains(bodyLine),
                  let offset = coordinates.renderedOffset(
                      forOriginalOffset: originalLines.lineStartOffsets[bodyLine - 1]
                  ) else { return nil }
            let renderedLine = splicedLines.line(atUTF16Offset: offset)
            guard let emitted = emittedByLine.removeValue(forKey: renderedLine),
                  emitted.level == indexed.level else { return nil }
            matches.append(Match(indexed: indexed, emitted: emitted))
        }
        return emittedByLine.isEmpty ? matches : nil
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
