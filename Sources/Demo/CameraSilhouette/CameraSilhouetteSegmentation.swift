import CoreGraphics
import CoreVideo
import Foundation

private let cameraSilhouetteMaskLowerBound = UInt8(96)
private let cameraSilhouetteMaskUpperBound = UInt8(230)
private let cameraSilhouetteMaskOccupancyThreshold = UInt8(210)

private struct CameraSilhouetteMaskBuffer {
    var width: Int
    var height: Int
    var values: [UInt8]
}

private struct CameraSilhouetteRefinedMask {
    var width: Int
    var height: Int
    var support: [UInt8]
    var alpha: [UInt8]
}

private final class CameraSilhouettePixelBufferBox: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer

    init(_ pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

func cameraSilhouetteCutoutRGBA(
    sourceWidth: Int,
    sourceHeight: Int,
    sourceBytesPerRow: Int,
    sourceBGRA: [UInt8],
    alphaWidth: Int,
    alphaHeight: Int,
    alphaValues: [UInt8],
    outputWidth: Int,
    outputHeight: Int
) -> [UInt8]? {
    guard
        sourceWidth > 0,
        sourceHeight > 0,
        sourceBytesPerRow >= sourceWidth * 4,
        sourceBGRA.count == sourceHeight * sourceBytesPerRow,
        alphaWidth > 0,
        alphaHeight > 0,
        alphaValues.count == alphaWidth * alphaHeight,
        outputWidth > 0,
        outputHeight > 0
    else {
        return nil
    }

    var rgba = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)

    for y in 0..<outputHeight {
        let sourceY = min(
            sourceHeight - 1,
            Int((Double(y) + 0.5) * Double(sourceHeight) / Double(outputHeight))
        )
        let sourceRow = sourceY * sourceBytesPerRow
        let destinationRow = y * outputWidth * 4
        let alphaY = min(
            alphaHeight - 1,
            Int((Double(y) + 0.5) * Double(alphaHeight) / Double(outputHeight))
        )
        let alphaRow = alphaY * alphaWidth

        for x in 0..<outputWidth {
            let sourceX = min(
                sourceWidth - 1,
                Int((Double(x) + 0.5) * Double(sourceWidth) / Double(outputWidth))
            )
            let alphaX = min(
                alphaWidth - 1,
                Int((Double(x) + 0.5) * Double(alphaWidth) / Double(outputWidth))
            )
            let sourceOffset = sourceRow + sourceX * 4
            let destinationOffset = destinationRow + x * 4
            let alpha = Int(alphaValues[alphaRow + alphaX])
            rgba[destinationOffset] = UInt8((Int(sourceBGRA[sourceOffset + 2]) * alpha + 127) / 255)
            rgba[destinationOffset + 1] = UInt8((Int(sourceBGRA[sourceOffset + 1]) * alpha + 127) / 255)
            rgba[destinationOffset + 2] = UInt8((Int(sourceBGRA[sourceOffset]) * alpha + 127) / 255)
            rgba[destinationOffset + 3] = UInt8(alpha)
        }
    }

    return rgba
}

func cameraSilhouetteMaskAlpha(for raw: UInt8) -> UInt8 {
    if raw <= cameraSilhouetteMaskLowerBound {
        return 0
    }
    if raw >= cameraSilhouetteMaskUpperBound {
        return 255
    }

    let progress = Double(raw - cameraSilhouetteMaskLowerBound)
        / Double(cameraSilhouetteMaskUpperBound - cameraSilhouetteMaskLowerBound)
    return UInt8((progress * 255).rounded())
}

func cameraSilhouetteRefinedMaskSupport(
    width: Int,
    height: Int,
    rawValues: [UInt8]
) -> [UInt8] {
    cameraSilhouetteRefinedMask(
        width: width,
        height: height,
        rawValues: rawValues
    )?.support ?? []
}

func cameraSilhouetteMaskRows(from pixelBuffer: CVPixelBuffer) -> [CameraSilhouetteMaskRow] {
    guard let refinedMask = cameraSilhouetteRefinedMask(from: pixelBuffer) else {
        return []
    }
    return cameraSilhouetteMaskRows(
        width: refinedMask.width,
        height: refinedMask.height,
        support: refinedMask.support
    )
}

private func cameraSilhouetteMaskRows(
    width: Int,
    height: Int,
    support: [UInt8]
) -> [CameraSilhouetteMaskRow] {
    guard width > 0, height > 0, support.count == width * height else {
        return []
    }

    let rowStep = max(1, height / 120)
    let minimumRunLength = max(2, width / 100)
    let occupancyThreshold = cameraSilhouetteMaskOccupancyThreshold

    var rows: [CameraSilhouetteMaskRow] = []
    var y = 0

    while y < height {
        let rowOffset = y * width
        var occupied: [CameraSilhouetteNormalizedSpan] = []
        var runStart: Int?

        for x in 0..<width {
            let value = support[rowOffset + x]
            if value >= occupancyThreshold {
                if runStart == nil {
                    runStart = x
                }
            } else if let currentRunStart = runStart {
                if x - currentRunStart >= minimumRunLength {
                    occupied.append(
                        CameraSilhouetteNormalizedSpan(
                            minX: Double(currentRunStart) / Double(width),
                            maxX: Double(x) / Double(width)
                        )
                    )
                }
                runStart = nil
            }
        }

        if let currentRunStart = runStart, width - currentRunStart >= minimumRunLength {
            occupied.append(
                CameraSilhouetteNormalizedSpan(
                    minX: Double(currentRunStart) / Double(width),
                    maxX: 1
                )
            )
        }

        if !occupied.isEmpty {
            rows.append(
                CameraSilhouetteMaskRow(
                    minY: Double(y) / Double(height),
                    maxY: Double(min(y + rowStep, height)) / Double(height),
                    occupied: occupied
                )
            )
        }

        y += rowStep
    }

    return rows
}

func cameraSilhouetteMaskImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
    guard let refinedMask = cameraSilhouetteRefinedMask(from: pixelBuffer) else {
        return nil
    }
    return cameraSilhouetteMaskImage(
        width: refinedMask.width,
        height: refinedMask.height,
        alphaValues: refinedMask.alpha
    )
}

private func cameraSilhouetteMaskImage(
    width: Int,
    height: Int,
    alphaValues: [UInt8]
) -> CGImage? {
    guard width > 0, height > 0, alphaValues.count == width * height else {
        return nil
    }
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        let sourceRow = y * width
        let destinationRow = y * width * 4
        for x in 0..<width {
            let alpha = alphaValues[sourceRow + x]
            let offset = destinationRow + x * 4
            rgba[offset] = 255
            rgba[offset + 1] = 255
            rgba[offset + 2] = 255
            rgba[offset + 3] = alpha
        }
    }

    let provider = CGDataProvider(data: Data(rgba) as CFData)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return provider.flatMap {
        CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: [
                CGBitmapInfo.byteOrder32Big,
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            ],
            provider: $0,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

private func cameraSilhouetteCutoutImage(
    sourcePixelBuffer: CVPixelBuffer,
    alphaWidth: Int,
    alphaHeight: Int,
    alphaValues: [UInt8]
) -> CGImage? {
    guard
        alphaWidth > 0,
        alphaHeight > 0,
        alphaValues.count == alphaWidth * alphaHeight
    else {
        return nil
    }

    CVPixelBufferLockBaseAddress(sourcePixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(sourcePixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(sourcePixelBuffer) else {
        return nil
    }

    let sourceWidth = CVPixelBufferGetWidth(sourcePixelBuffer)
    let sourceHeight = CVPixelBufferGetHeight(sourcePixelBuffer)
    let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(sourcePixelBuffer)
    let sourceByteCount = sourceHeight * sourceBytesPerRow
    let sourcePointer = baseAddress.assumingMemoryBound(to: UInt8.self)
    let sourceBGRA = Array(UnsafeBufferPointer(start: sourcePointer, count: sourceByteCount))

    guard let rgba = cameraSilhouetteCutoutRGBA(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        sourceBytesPerRow: sourceBytesPerRow,
        sourceBGRA: sourceBGRA,
        alphaWidth: alphaWidth,
        alphaHeight: alphaHeight,
        alphaValues: alphaValues,
        outputWidth: sourceWidth,
        outputHeight: sourceHeight
    ) else {
        return nil
    }

    let provider = CGDataProvider(data: Data(rgba) as CFData)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return provider.flatMap {
        CGImage(
            width: sourceWidth,
            height: sourceHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: sourceWidth * 4,
            space: colorSpace,
            bitmapInfo: [
                CGBitmapInfo.byteOrder32Big,
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            ],
            provider: $0,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

private func cameraSilhouetteRefinedMask(from pixelBuffer: CVPixelBuffer) -> CameraSilhouetteRefinedMask? {
    guard let buffer = cameraSilhouetteMaskBuffer(from: pixelBuffer) else {
        return nil
    }
    return cameraSilhouetteRefinedMask(
        width: buffer.width,
        height: buffer.height,
        rawValues: buffer.values
    )
}

private func cameraSilhouetteRefinedMask(
    width: Int,
    height: Int,
    rawValues: [UInt8]
) -> CameraSilhouetteRefinedMask? {
    guard width > 0, height > 0, rawValues.count == width * height else {
        return nil
    }

    let candidateSupport = rawValues.map { $0 > cameraSilhouetteMaskLowerBound ? UInt8(255) : 0 }
    let filledSupport = cameraSilhouetteFillInteriorMaskGaps(
        width: width,
        height: height,
        support: candidateSupport
    )
    var alpha = rawValues.map { cameraSilhouetteMaskAlpha(for: $0) }

    for index in alpha.indices {
        if filledSupport[index] == 0 {
            alpha[index] = 0
        } else if candidateSupport[index] == 0 {
            alpha[index] = 255
        }
    }

    return CameraSilhouetteRefinedMask(
        width: width,
        height: height,
        support: filledSupport,
        alpha: alpha
    )
}

private func cameraSilhouetteMaskBuffer(from pixelBuffer: CVPixelBuffer) -> CameraSilhouetteMaskBuffer? {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        return nil
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let source = baseAddress.assumingMemoryBound(to: UInt8.self)
    var values = [UInt8](repeating: 0, count: width * height)

    for y in 0..<height {
        let sourceRow = y * bytesPerRow
        let destinationRow = y * width
        for x in 0..<width {
            values[destinationRow + x] = source[sourceRow + x]
        }
    }

    return CameraSilhouetteMaskBuffer(
        width: width,
        height: height,
        values: values
    )
}

private func cameraSilhouetteFillInteriorMaskGaps(
    width: Int,
    height: Int,
    support: [UInt8]
) -> [UInt8] {
    guard width > 0, height > 0, support.count == width * height else {
        return support
    }

    var reachableBackground = [Bool](repeating: false, count: support.count)
    var stack: [Int] = []

    func enqueue(_ index: Int) {
        guard support[index] == 0, !reachableBackground[index] else {
            return
        }
        reachableBackground[index] = true
        stack.append(index)
    }

    for x in 0..<width {
        enqueue(x)
        enqueue((height - 1) * width + x)
    }

    if height > 2 {
        for y in 1..<(height - 1) {
            enqueue(y * width)
            enqueue(y * width + width - 1)
        }
    }

    while let index = stack.popLast() {
        let x = index % width
        let y = index / width

        if x > 0 {
            enqueue(index - 1)
        }
        if x + 1 < width {
            enqueue(index + 1)
        }
        if y > 0 {
            enqueue(index - width)
        }
        if y + 1 < height {
            enqueue(index + width)
        }
    }

    var result = support

    for index in result.indices where support[index] == 0 && !reachableBackground[index] {
        result[index] = 255
    }

    return result
}

#if canImport(Vision)
import Vision

struct CameraSilhouetteSegmentationResult {
    var imageSize: CGSize
    var rows: [CameraSilhouetteMaskRow]
    var cutoutImage: CGImage?
}

final class CameraSilhouetteSegmentation: @unchecked Sendable {
    var onResult: (@MainActor @Sendable (CameraSilhouetteSegmentationResult?) -> Void)?

    private let queue = DispatchQueue(label: "camera.silhouette.segmentation", qos: .userInitiated)
    private let request: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    private var pendingPixelBuffer: CVPixelBuffer?
    private var isProcessing = false

    func process(pixelBuffer: CVPixelBuffer) {
        let pixelBufferBox = CameraSilhouettePixelBufferBox(pixelBuffer)
        queue.async {
            self.pendingPixelBuffer = pixelBufferBox.pixelBuffer
            guard !self.isProcessing else {
                return
            }

            self.isProcessing = true
            defer { self.isProcessing = false }

            while let nextPixelBuffer = self.pendingPixelBuffer {
                self.pendingPixelBuffer = nil
                let result = self.segment(pixelBuffer: nextPixelBuffer)
                let onResult = self.onResult
                Task { @MainActor in
                    onResult?(result)
                }
            }
        }
    }

    private func segment(pixelBuffer: CVPixelBuffer) -> CameraSilhouetteSegmentationResult? {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard
            let observation = request.results?.first as? VNPixelBufferObservation
        else {
            return CameraSilhouetteSegmentationResult(
                imageSize: CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                ),
                rows: [],
                cutoutImage: nil
            )
        }

        guard let refinedMask = cameraSilhouetteRefinedMask(from: observation.pixelBuffer) else {
            return CameraSilhouetteSegmentationResult(
                imageSize: CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                ),
                rows: [],
                cutoutImage: nil
            )
        }

        return CameraSilhouetteSegmentationResult(
            imageSize: CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            ),
            rows: cameraSilhouetteMaskRows(
                width: refinedMask.width,
                height: refinedMask.height,
                support: refinedMask.support
            ),
            cutoutImage: cameraSilhouetteCutoutImage(
                sourcePixelBuffer: pixelBuffer,
                alphaWidth: refinedMask.width,
                alphaHeight: refinedMask.height,
                alphaValues: refinedMask.alpha
            )
        )
    }
}
#endif
