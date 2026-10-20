import AppKit
import Foundation
import ImageIO
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
    private let decodeBudget: PreviewImageDecodeBudget

    public init(
        provider: Provider? = nil,
        isLive: @escaping @Sendable () -> Bool = { true },
        decodeBudget: PreviewImageDecodeBudget = PreviewImageDecodeBudget()
    ) {
        self.provider = provider
        self.isLive = isLive
        self.decodeBudget = decodeBudget
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
            let decoded = try PreviewImageDecoder.decode(bytes.data, budget: decodeBudget)
            guard !Task.isCancelled, isLive() else { throw CancellationError() }
            return PreviewImageAttachment(
                image: Image(nsImage: decoded.image), size: decoded.image.size,
                description: text,
                reservation: PreviewImageResources(input: bytes.reservation, decoded: decoded.reservation),
                isLive: isLive
            )
        }
        guard !Task.isCancelled, isLive() else { throw CancellationError() }
        return attachment
    }
}

public enum PreviewImageLoadError: Error, Sendable {
    case denied
    case invalidImage
    case decodedLimitExceeded
}

private struct PreviewImageResources: Sendable {
    let input: any Sendable
    let decoded: PreviewImageDecodeBudget.Reservation
}

/// Accounts for app-owned decoded image output retained by one Textual load. The input-byte ledger is separate.
/// ImageIO and SwiftUI may allocate temporary/internal copies, which require Release memory measurements.
public final class PreviewImageDecodeBudget: @unchecked Sendable {
    public static let imageLimit = 32 * 1024 * 1024
    public static let loadLimit = 64 * 1024 * 1024

    final class Reservation: @unchecked Sendable {
        private let budget: PreviewImageDecodeBudget
        let bytes: Int

        fileprivate init(budget: PreviewImageDecodeBudget, bytes: Int) {
            self.budget = budget
            self.bytes = bytes
        }

        deinit { budget.release(bytes) }
    }

    private let lock = NSLock()
    private var held = 0

    public init() {}

    var reservedBytes: Int {
        lock.withLock { held }
    }

    func reserve(_ bytes: Int) throws -> Reservation {
        let accepted = lock.withLock { () -> Bool in
            guard bytes > 0, bytes <= Self.imageLimit,
                  held <= Self.loadLimit - bytes else { return false }
            held += bytes
            return true
        }
        guard accepted else { throw PreviewImageLoadError.decodedLimitExceeded }
        return Reservation(budget: self, bytes: bytes)
    }

    private func release(_ bytes: Int) {
        lock.withLock { held -= bytes }
    }
}

@MainActor
enum PreviewImageDecoder {
    struct Decoded {
        let image: NSImage
        let reservation: PreviewImageDecodeBudget.Reservation
    }

    static func decode(_ data: Data, budget: PreviewImageDecodeBudget) throws -> Decoded {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
        ), CGImageSourceGetCount(source) == 1,
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
        width > 0, height > 0, width <= 8192, height <= 8192
        else { throw PreviewImageLoadError.invalidImage }

        // Reserve a conservative eight bytes per pixel before asking ImageIO to create decoded output.
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (reserved, byteOverflow) = pixels.multipliedReportingOverflow(by: 8)
        guard !pixelOverflow, !byteOverflow else { throw PreviewImageLoadError.decodedLimitExceeded }
        let reservation = try budget.reserve(reserved)
        guard let raster = CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        ) else { throw PreviewImageLoadError.invalidImage }

        let (actual, actualOverflow) = raster.bytesPerRow.multipliedReportingOverflow(by: raster.height)
        guard !actualOverflow, raster.width == width, raster.height == height, actual <= reserved
        else { throw PreviewImageLoadError.decodedLimitExceeded }
        return Decoded(
            image: NSImage(cgImage: raster, size: NSSize(width: width, height: height)),
            reservation: reservation
        )
    }
}

/// Hash/equality describe this admitted attachment, not its image bytes. Its reservation survives Textual caching.
public struct PreviewImageAttachment: Attachment {
    private let id = UUID()
    private let image: Image
    private let size: CGSize
    public let description: String
    private let reservation: any Sendable
    private let isLive: @Sendable () -> Bool

    init(
        image: Image, size: CGSize, description: String, reservation: any Sendable,
        isLive: @escaping @Sendable () -> Bool = { true }
    ) {
        self.image = image
        self.size = size
        self.description = description
        self.reservation = reservation
        self.isLive = isLive
    }

    public var body: some View {
        PreviewImageBody(image: image, reservation: reservation, isLive: isLive)
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

    /// Textual's default is intentional: this attachment does not create an unreserved PNG copy for export.
    public func pngData() -> Data? {
        nil
    }
}

private struct PreviewImageBody: View {
    let image: Image
    /// SwiftUI may keep the child view after Textual drops the attachment value.
    let reservation: any Sendable
    let isLive: @Sendable () -> Bool

    var body: some View {
        if isLive() {
            image.resizable().scaledToFit()
        }
    }
}
