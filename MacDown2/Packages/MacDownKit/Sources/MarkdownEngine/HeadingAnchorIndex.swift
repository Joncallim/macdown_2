import CryptoKit
import Foundation

/// The exact document lifetime and source/parse policy that produced a set of
/// heading fragments. Callers must reject this identity after an edit, Save As
/// identity change, or recovery-lifetime replacement before navigating.
public struct HeadingAnchorIdentity: Sendable, Equatable {
    public let documentID: String
    public let recoveryEpoch: UUID
    public let sourceGeneration: UInt
    public let sourceSHA256: String
    public let parseRevision: Int
    public let parseOptions: MarkdownParseOptions
    public let allocatorPolicyVersion: Int
}

/// One allocation pass over the parsed headings, after authored and generated
/// static IDs have been inventoried. This value does not claim that cmark has
/// emitted matching targets; Export verifies those targets before publishing
/// any generated TOC links.
public struct HeadingAnchorIndex: Sendable, Equatable {
    public enum Error: Swift.Error, Equatable {
        case sourceDoesNotMatchParse
    }

    public struct Heading: Sendable, Equatable {
        public let ordinal: Int
        public let sourceLineRange: ClosedRange<Int>
        public let sourceUTF16Range: Range<Int>
        public let level: Int
        public let title: String
        public let fragment: String
    }

    public let identity: HeadingAnchorIdentity
    public let headings: [Heading]

    /// `sourceText` must be the same immutable source snapshot used to create
    /// `document`. `reservedIDs` must contain exact, decoded DOM ID strings,
    /// including static contribution/template IDs; generated IDs never
    /// normalize or rewrite them.
    public init(
        document: MarkdownDocument,
        sourceText: String,
        documentID: String,
        recoveryEpoch: UUID,
        sourceGeneration: UInt,
        reservedIDs: Set<String>
    ) throws {
        let extraction = FrontMatterExtractor.extract(from: sourceText)
        guard SourceMap(text: sourceText) == document.sourceMap,
              (extraction?.body ?? sourceText) == document.body,
              (extraction?.closingLineNumber ?? 0) == document.bodyLineOffset,
              extraction?.raw == document.frontMatter?.raw
        else { throw Error.sourceDoesNotMatchParse }

        let digest = SHA256.hash(data: Data(sourceText.utf8))
        identity = HeadingAnchorIdentity(
            documentID: documentID,
            recoveryEpoch: recoveryEpoch,
            sourceGeneration: sourceGeneration,
            sourceSHA256: digest.map { String(format: "%02x", $0) }.joined(),
            parseRevision: document.revision,
            parseOptions: document.options,
            allocatorPolicyVersion: HeadingAnchorAllocator.policyVersion
        )

        var allocator = HeadingAnchorAllocator(reservedIDs: reservedIDs)
        headings = document.headings.enumerated().map { ordinal, item in
            let range = document.sourceMap.utf16Range(ofLines: item.lineRange)
            return Heading(
                ordinal: ordinal,
                sourceLineRange: item.lineRange,
                sourceUTF16Range: range.location ..< (range.location + range.length),
                level: item.level,
                title: item.title,
                fragment: allocator.allocate(title: item.title)
            )
        }
    }
}
