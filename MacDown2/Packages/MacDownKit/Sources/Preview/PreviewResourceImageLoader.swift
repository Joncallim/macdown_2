import AppKit
import Foundation
import SwiftUI
import Textual

/// The resource bytes and their admission owner's lifetime travel together into Textual's attachment cache.
/// The preview module does not know which app-owned ledger supplied the bytes.
public struct PreviewImageBytes: Sendable {
    public let data: Data
    public let reservation: any Sendable

    public init(data: Data, reservation: any Sendable) {
        self.data = data
        self.reservation = reservation
    }
}

/// Textual receives the authored URL here before its default loader can fetch a file or remote image.
/// The app supplies the only permitted reader; an absent provider denies every image.
public struct PreviewResourceImageLoader: AttachmentLoader {
    public typealias Provider = @Sendable (URL) async throws -> PreviewImageBytes

    private let provider: Provider?
    private let isLive: @Sendable () -> Bool

    public init(provider: Provider? = nil, isLive: @escaping @Sendable () -> Bool = { true }) {
        self.provider = provider
        self.isLive = isLive
    }

    public func attachment(
        for url: URL,
        text: String,
        environment _: ColorEnvironmentValues
    ) async throws -> PreviewImageAttachment {
        guard let provider, isLive() else { throw PreviewImageLoadError.denied }
        let bytes = try await provider(url)
        guard !Task.isCancelled, isLive() else { throw CancellationError() }
        let attachment = try await MainActor.run {
            guard !Task.isCancelled, isLive() else { throw CancellationError() }
            guard let platformImage = NSImage(data: bytes.data),
                  platformImage.size.width > 0, platformImage.size.height > 0
            else { throw PreviewImageLoadError.invalidImage }
            return PreviewImageAttachment(
                image: Image(nsImage: platformImage), size: platformImage.size,
                description: text, reservation: bytes.reservation
            )
        }
        guard !Task.isCancelled, isLive() else { throw CancellationError() }
        return attachment
    }
}

public enum PreviewImageLoadError: Error, Sendable {
    case denied
    case invalidImage
}

/// Hash/equality describe this admitted attachment, not its image bytes. Its reservation survives Textual caching.
public struct PreviewImageAttachment: Attachment {
    private let id = UUID()
    private let image: Image
    private let size: CGSize
    public let description: String
    private let reservation: any Sendable

    init(image: Image, size: CGSize, description: String, reservation: any Sendable) {
        self.image = image
        self.size = size
        self.description = description
        self.reservation = reservation
    }

    public var body: some View {
        PreviewImageBody(image: image, reservation: reservation)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
        guard let width = proposal.width, width < size.width else { return size }
        return CGSize(width: width, height: width * size.height / size.width)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct PreviewImageBody: View {
    let image: Image
    /// SwiftUI may keep the child view after Textual drops the attachment value.
    let reservation: any Sendable

    var body: some View {
        image.resizable().scaledToFit()
    }
}
