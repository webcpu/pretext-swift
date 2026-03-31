import CoreGraphics
import CoreVideo
import XCTest
@testable import Demo

final class CameraSilhouetteSegmentationTests: XCTestCase {
    func testCutoutRGBAUsesSourceColorAndMaskAlphaAtMatchingPixels() throws {
        let rgba = try XCTUnwrap(cameraSilhouetteCutoutRGBA(
            sourceWidth: 2,
            sourceHeight: 2,
            sourceBytesPerRow: 8,
            sourceBGRA: [
                10, 20, 30, 255, 40, 50, 60, 255,
                70, 80, 90, 255, 100, 110, 120, 255,
            ],
            outputWidth: 2,
            outputHeight: 2,
            alphaValues: [0, 64, 128, 255]
        ))

        XCTAssertEqual(Array(rgba[0..<4]), [0, 0, 0, 0])
        XCTAssertEqual(Array(rgba[4..<8]), [15, 13, 10, 64])
        XCTAssertEqual(Array(rgba[8..<12]), [45, 40, 35, 128])
        XCTAssertEqual(Array(rgba[12..<16]), [120, 110, 100, 255])
    }

    func testMaskImagePreservesSoftEdgeAlpha() throws {
        let pixelBuffer = try makeMaskPixelBuffer(
            width: 3,
            height: 1,
            values: [0, 160, 255]
        )

        let image = try XCTUnwrap(cameraSilhouetteMaskImage(from: pixelBuffer))
        let bytes = try XCTUnwrap(image.dataProvider?.data as Data?)

        XCTAssertEqual(bytes[3], 0)
        XCTAssertGreaterThan(bytes[7], 0)
        XCTAssertLessThan(bytes[7], 255)
        XCTAssertEqual(bytes[11], 255)
    }

    func testRefinedMaskSupportFillsSinglePixelHoleInsideForeground() {
        let support = cameraSilhouetteRefinedMaskSupport(
            width: 5,
            height: 5,
            rawValues: [
                0, 0, 0, 0, 0,
                0, 255, 255, 255, 0,
                0, 255, 0, 255, 0,
                0, 255, 255, 255, 0,
                0, 0, 0, 0, 0,
            ]
        )

        XCTAssertEqual(support[12], 255)
    }

    func testRefinedMaskSupportFillsMultiPixelInteriorHole() {
        let support = cameraSilhouetteRefinedMaskSupport(
            width: 7,
            height: 7,
            rawValues: [
                0, 0, 0, 0, 0, 0, 0,
                0, 255, 255, 255, 255, 255, 0,
                0, 255, 0, 0, 0, 255, 0,
                0, 255, 0, 0, 0, 255, 0,
                0, 255, 0, 0, 0, 255, 0,
                0, 255, 255, 255, 255, 255, 0,
                0, 0, 0, 0, 0, 0, 0,
            ]
        )

        XCTAssertEqual(support[2 * 7 + 2], 255)
        XCTAssertEqual(support[3 * 7 + 3], 255)
        XCTAssertEqual(support[4 * 7 + 4], 255)
    }

    func testMaskAlphaSuppressesBackgroundLeakage() {
        XCTAssertEqual(cameraSilhouetteMaskAlpha(for: 32), 0)
        XCTAssertEqual(cameraSilhouetteMaskAlpha(for: 96), 0)
        XCTAssertEqual(cameraSilhouetteMaskAlpha(for: 255), 255)
        XCTAssertLessThan(cameraSilhouetteMaskAlpha(for: 160), 255)
        XCTAssertGreaterThan(cameraSilhouetteMaskAlpha(for: 160), 0)
    }

    func testMaskImageFillsInteriorHoleWithoutPunchingTransparency() throws {
        let pixelBuffer = try makeMaskPixelBuffer(
            width: 5,
            height: 5,
            values: [
                0, 0, 0, 0, 0,
                0, 255, 255, 255, 0,
                0, 255, 0, 255, 0,
                0, 255, 255, 255, 0,
                0, 0, 0, 0, 0,
            ]
        )

        let image = try XCTUnwrap(cameraSilhouetteMaskImage(from: pixelBuffer))
        XCTAssertEqual(image.width, 5)
        XCTAssertEqual(image.height, 5)

        let bytes = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertEqual(bytes.count, 100)
        XCTAssertEqual(bytes[3], 0)
        XCTAssertEqual(bytes[(2 * 5 + 2) * 4 + 3], 255)
    }

    func testMaskRowsPreserveThinForegroundRunsForPreciseContours() throws {
        let pixelBuffer = try makeMaskPixelBuffer(
            width: 10,
            height: 4,
            values: [
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 255, 255, 0, 0, 0, 0,
                0, 0, 0, 0, 255, 255, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            ]
        )

        let rows = cameraSilhouetteMaskRows(from: pixelBuffer)
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            let occupied = try XCTUnwrap(row.occupied.first)
            XCTAssertEqual(occupied.minX, 0.4, accuracy: 0.001)
            XCTAssertEqual(occupied.maxX, 0.6, accuracy: 0.001)
        }
    }

    private func makeMaskPixelBuffer(
        width: Int,
        height: Int,
        values: [UInt8]
    ) throws -> CVPixelBuffer {
        XCTAssertEqual(values.count, width * height)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)

        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let destination = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                destination[y * bytesPerRow + x] = values[y * width + x]
            }
        }

        return buffer
    }
}
