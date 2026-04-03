import CoreGraphics
import CoreVideo
import Foundation

struct ChromaKeyFrame {
    var hull: [WrapPoint]
    var boundsFraction: WrapRect
    var image: CGImage
}

func processChromaKeyFrame(
    _ pixelBuffer: CVPixelBuffer,
    smoothRadius: Int = 4,
    rowSampleCount: Int = 60
) -> ChromaKeyFrame? {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let src = baseAddress.assumingMemoryBound(to: UInt8.self)

    // Scan rows for leftmost/rightmost non-green pixels (BGRA format)
    let greenThreshold = 40
    var lefts = [Double?](repeating: nil, count: height)
    var rights = [Double?](repeating: nil, count: height)

    for y in 0..<height {
        let rowBase = y * bytesPerRow
        var leftX = -1
        var rightX = -1

        for x in 0..<width {
            let offset = rowBase + x * 4
            let g = Int(src[offset + 1])
            let r = Int(src[offset + 2])
            let b = Int(src[offset])
            if !(g > r + greenThreshold && g > b + greenThreshold) {
                if leftX == -1 { leftX = x }
                rightX = x
            }
        }

        if leftX != -1 {
            lefts[y] = Double(leftX)
            rights[y] = Double(rightX + 1)
        }
    }

    // Bounding box
    let validRows = (0..<height).filter { lefts[$0] != nil }
    guard let boundTop = validRows.first, let boundBottom = validRows.last else { return nil }

    var boundLeft = Double.infinity
    var boundRight = -Double.infinity
    for row in validRows {
        boundLeft = min(boundLeft, lefts[row] ?? .infinity)
        boundRight = max(boundRight, rights[row] ?? -.infinity)
    }

    let bLeft = Int(boundLeft)
    let bTop = boundTop
    let bW = Int(boundRight) - bLeft
    let bH = boundBottom - bTop
    guard bW > 0, bH > 0 else { return nil }

    let boundWidth = Double(bW)
    let boundHeight = Double(bH)

    // Smooth edges
    var smoothedLefts = [Double](repeating: 0, count: height)
    var smoothedRights = [Double](repeating: Double(width), count: height)

    for row in validRows {
        var leftSum = 0.0, rightSum = 0.0, count = 0.0
        for offset in -smoothRadius...smoothRadius {
            let s = row + offset
            guard s >= 0, s < height, let left = lefts[s], let right = rights[s] else { continue }
            leftSum += left
            rightSum += right
            count += 1
        }
        guard count > 0 else { continue }
        smoothedLefts[row] = leftSum / count
        smoothedRights[row] = rightSum / count
    }

    // Subsample rows into polygon points
    let step = max(1, validRows.count / rowSampleCount)
    var sampledRows: [Int] = []
    var index = 0
    while index < validRows.count {
        sampledRows.append(validRows[index])
        index += step
    }
    if sampledRows.last != validRows.last {
        sampledRows.append(validRows.last!)
    }

    var points: [WrapPoint] = []
    for row in sampledRows {
        points.append(WrapPoint(
            x: (smoothedLefts[row] - Double(bLeft)) / boundWidth,
            y: (Double(row) + 0.5 - Double(bTop)) / boundHeight
        ))
    }
    for row in sampledRows.reversed() {
        points.append(WrapPoint(
            x: (smoothedRights[row] - Double(bLeft)) / boundWidth,
            y: (Double(row) + 0.5 - Double(bTop)) / boundHeight
        ))
    }

    let boundsFraction = WrapRect(
        x: Double(bLeft) / Double(width),
        y: Double(bTop) / Double(height),
        width: boundWidth / Double(width),
        height: boundHeight / Double(height)
    )

    // Build CGImage directly from pixel buffer — no CIImage, no coordinate confusion.
    // Copy cropped region with green pixels set to transparent. BGRA → RGBA.
    let outBPR = bW * 4
    let outData = UnsafeMutablePointer<UInt8>.allocate(capacity: bH * outBPR)
    let gThresh = 30

    for row in 0..<bH {
        let srcRow = (bTop + row) * bytesPerRow + bLeft * 4
        let dstRow = row * outBPR
        for col in 0..<bW {
            let si = srcRow + col * 4
            let di = dstRow + col * 4
            let sb = Int(src[si])
            let sg = Int(src[si + 1])
            let sr = Int(src[si + 2])
            if sg > sr + gThresh && sg > sb + gThresh {
                outData[di] = 0; outData[di + 1] = 0; outData[di + 2] = 0; outData[di + 3] = 0
            } else {
                outData[di] = src[si + 2]     // R (from BGRA offset 2)
                outData[di + 1] = src[si + 1] // G
                outData[di + 2] = src[si]     // B (from BGRA offset 0)
                outData[di + 3] = 255         // A
            }
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let provider = CGDataProvider(data: Data(
        bytesNoCopy: outData, count: bH * outBPR, deallocator: .custom { ptr, _ in ptr.deallocate() }
    ) as CFData) else {
        outData.deallocate()
        return nil
    }

    guard let cgImage = CGImage(
        width: bW, height: bH,
        bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: outBPR,
        space: colorSpace, bitmapInfo: bitmapInfo,
        provider: provider, decode: nil,
        shouldInterpolate: true, intent: .defaultIntent
    ) else { return nil }

    return ChromaKeyFrame(hull: points, boundsFraction: boundsFraction, image: cgImage)
}
