import AppKit

/// Test-only experiment for register row H5 (NOT shipped): makes Neon reparse
/// every edit on its background queue by describing each edit to Neon over a
/// range of at least 2,048 UTF-16 units.
///
/// Neon decides sync vs background per edit with constants that cannot be
/// configured (`BackgroundingLanguageLayerTree.synchronousLengthThreshold` =
/// 2,048 and `synchronousDocumentSize` = 1,048,576, `static let` on an internal
/// type; `TextViewHighlighter.Configuration` and `TreeSitterClient.Configuration`
/// expose neither). An edit whose old range is at least 2,048 units long takes
/// Neon's background path, so this delegate sits between `NSTextStorage` and
/// Neon's storage delegate and reports the real edit plus unchanged text around
/// it as "replaced by itself" — a truthful description of the change.
///
/// It removes the keystroke freeze, but it is not shipped: a replacement edit
/// whose old range contains whole inline-injection ranges leaves the inline
/// sublayer stale (see `NeonReplacementEditTests`), and widening turns every
/// keystroke into such an edit.
final class EditWideningStorageDelegate: NSObject, NSTextStorageDelegate {
    static let neonSynchronousLengthThreshold = 2048

    private weak var downstream: NSTextStorageDelegate?

    init(downstream: NSTextStorageDelegate) {
        self.downstream = downstream
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        downstream?.textStorage?(
            textStorage,
            willProcessEditing: editedMask,
            range: forwarded(editedMask, editedRange, delta, textStorage.length),
            changeInLength: delta
        )
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        downstream?.textStorage?(
            textStorage,
            didProcessEditing: editedMask,
            range: forwarded(editedMask, editedRange, delta, textStorage.length),
            changeInLength: delta
        )
    }

    private func forwarded(_ mask: NSTextStorageEditActions, _ range: NSRange, _ delta: Int, _ length: Int) -> NSRange {
        mask.contains(.editedCharacters) ? Self.widen(range, delta: delta, documentLength: length) : range
    }

    /// Widens a post-edit range (NSTextStorage's convention) so its pre-edit
    /// length reaches Neon's threshold, extending left first (Neon clamps a
    /// mutation's right edge to the processed prefix) and never leaving
    /// `0 ..< documentLength`.
    static func widen(_ editedRange: NSRange, delta: Int, documentLength: Int) -> NSRange {
        let threshold = neonSynchronousLengthThreshold
        let oldLength = editedRange.length - delta
        guard oldLength < threshold, delta < threshold else { return editedRange }

        let extra = threshold - oldLength
        let left = min(extra, editedRange.location)
        let right = min(extra - left, documentLength - NSMaxRange(editedRange))
        guard left + right == extra else { return editedRange }

        return NSRange(location: editedRange.location - left, length: editedRange.length + extra)
    }
}
