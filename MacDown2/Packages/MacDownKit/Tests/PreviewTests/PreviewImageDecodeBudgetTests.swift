import AppKit
@testable import Preview
import SwiftUI
import Testing

@Suite("Preview image decoded-output admission", .serialized)
@MainActor
struct PreviewImageDecodeBudgetTests {
    @Test func smallImageRetainsItsOutputReservationAndDoesNotOfferAnUnchargedPNGCopy() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let budget = PreviewImageDecodeBudget()
        let decoded = try PreviewImageDecoder.decode(data, budget: budget)
        #expect(decoded.image.size == NSSize(width: 8, height: 8))
        #expect(budget.reservedBytes == 8 * 8 * 8)

        let attachment = PreviewImageAttachment(
            image: Image(nsImage: decoded.image), size: decoded.image.size,
            description: "small", reservation: decoded.reservation
        )
        #expect(attachment.pngData() == nil)
    }

    @Test func repeatedImagesCannotOversubscribeOneLoadAndReleasingReturnsCapacity() throws {
        let budget = PreviewImageDecodeBudget()
        var first: PreviewImageDecodeBudget.Reservation? = try budget.reserve(PreviewImageDecodeBudget.imageLimit)
        let second = try budget.reserve(PreviewImageDecodeBudget.imageLimit)
        #expect(budget.reservedBytes == PreviewImageDecodeBudget.loadLimit)
        #expect(throws: PreviewImageLoadError.self) {
            _ = try budget.reserve(1)
        }
        first = nil
        #expect(budget.reservedBytes == PreviewImageDecodeBudget.imageLimit)
        let replacement = try budget.reserve(PreviewImageDecodeBudget.imageLimit)
        #expect(replacement.bytes == PreviewImageDecodeBudget.imageLimit)
        #expect(second.bytes == PreviewImageDecodeBudget.imageLimit)
        #expect(first == nil)
    }

    @Test func singleOversizeImageIsRejectedBeforeDecode() {
        let budget = PreviewImageDecodeBudget()
        #expect(throws: PreviewImageLoadError.self) {
            _ = try budget.reserve(PreviewImageDecodeBudget.imageLimit + 1)
        }
        #expect(budget.reservedBytes == 0)
    }

    @Test func retainedImagesAcrossLoadsShareOneGlobalCap() throws {
        let first = PreviewImageDecodeBudget()
        let second = PreviewImageDecodeBudget()
        let third = PreviewImageDecodeBudget()
        var firstReservations: [PreviewImageDecodeBudget.Reservation] = try [
            first.reserve(PreviewImageDecodeBudget.imageLimit),
            first.reserve(PreviewImageDecodeBudget.imageLimit),
        ]
        let secondReservations = try [
            second.reserve(PreviewImageDecodeBudget.imageLimit),
            second.reserve(PreviewImageDecodeBudget.imageLimit),
        ]
        #expect(PreviewImageDecodeBudget.globallyReservedBytes == PreviewImageDecodeBudget.globalLimit)
        #expect(throws: PreviewImageLoadError.self) {
            _ = try third.reserve(1)
        }
        firstReservations.removeAll()
        #expect(PreviewImageDecodeBudget.globallyReservedBytes == PreviewImageDecodeBudget.loadLimit)
        let resumed = try third.reserve(PreviewImageDecodeBudget.imageLimit)
        #expect(resumed.bytes == PreviewImageDecodeBudget.imageLimit)
        #expect(secondReservations.count == 2)
    }
}
