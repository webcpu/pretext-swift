import AppKit
import Foundation

struct LoadedLogo {
    var image: NSImage
    var layoutHull: [WrapPoint]
    var hitHull: [WrapPoint]
}

enum LogoHullError: Error {
    case missingResource(String)
    case invalidSVG(String)
}

func loadBundledLogo(named resourceName: String, layoutSmoothRadius: Int, hitSmoothRadius: Int) -> LoadedLogo {
    do {
        let image = try loadBundledSVGImage(named: resourceName)
        return LoadedLogo(
            image: image,
            layoutHull: makeWrapHull(from: image, smoothRadius: layoutSmoothRadius, mode: .mean),
            hitHull: makeWrapHull(from: image, smoothRadius: hitSmoothRadius, mode: .mean)
        )
    } catch {
        let fallback = makeFallbackImage()
        let hull = [
            WrapPoint(x: 0.5, y: 0.0),
            WrapPoint(x: 1.0, y: 0.5),
            WrapPoint(x: 0.5, y: 1.0),
            WrapPoint(x: 0.0, y: 0.5),
        ]
        return LoadedLogo(image: fallback, layoutHull: hull, hitHull: hull)
    }
}

private func loadBundledSVGImage(named resourceName: String) throws -> NSImage {
    guard let url = Bundle.module.url(forResource: resourceName, withExtension: "svg") else {
        throw LogoHullError.missingResource(resourceName)
    }

    guard let image = NSImage(contentsOf: url) else {
        throw LogoHullError.invalidSVG("Unable to load \(resourceName).svg")
    }

    if resourceName == "openai-symbol" {
        image.isTemplate = true
    }

    return image
}

func makeWrapHull(from image: NSImage, smoothRadius: Int, mode: WrapHullMode) -> [WrapPoint] {
    let imageSize = image.size
    let aspect = max(0.1, imageSize.width / max(1, imageSize.height))
    let maxDimension = 320.0
    let width = aspect >= 1
        ? Int(maxDimension.rounded())
        : max(64, Int((maxDimension * aspect).rounded()))
    let height = aspect >= 1
        ? max(64, Int((maxDimension / aspect).rounded()))
        : Int(maxDimension.rounded())

    guard
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        return []
    }

    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
        return []
    }

    var lefts = Array<Double?>(repeating: nil, count: height)
    var rights = Array<Double?>(repeating: nil, count: height)
    let alphaThreshold: UInt8 = 12

    for y in 0..<height {
        var left = -1
        var right = -1
        for x in 0..<width {
            let alpha = data[(y * width + x) * 4 + 3]
            if alpha < alphaThreshold {
                continue
            }
            if left == -1 {
                left = x
            }
            right = x
        }
        if left != -1, right != -1 {
            lefts[y] = Double(left)
            rights[y] = Double(right + 1)
        }
    }

    let validRows = (0..<height).filter { lefts[$0] != nil && rights[$0] != nil }
    guard let boundTop = validRows.first, let boundBottom = validRows.last else {
        return []
    }

    var boundLeft = Double.infinity
    var boundRight = -Double.infinity
    for row in validRows {
        boundLeft = min(boundLeft, lefts[row] ?? .infinity)
        boundRight = max(boundRight, rights[row] ?? -.infinity)
    }

    let boundWidth = max(1, boundRight - boundLeft)
    let boundHeight = max(1, Double(boundBottom - boundTop))
    var smoothedLefts = Array(repeating: 0.0, count: height)
    var smoothedRights = Array(repeating: Double(width), count: height)

    for row in validRows {
        var leftSum = 0.0
        var rightSum = 0.0
        var count = 0.0
        var leftEdge = Double.infinity
        var rightEdge = -Double.infinity

        for offset in -smoothRadius...smoothRadius {
            let sampleIndex = row + offset
            guard sampleIndex >= 0, sampleIndex < height else {
                continue
            }
            guard let left = lefts[sampleIndex], let right = rights[sampleIndex] else {
                continue
            }

            leftSum += left
            rightSum += right
            leftEdge = min(leftEdge, left)
            rightEdge = max(rightEdge, right)
            count += 1
        }

        guard count > 0 else {
            continue
        }

        switch mode {
        case .envelope:
            smoothedLefts[row] = leftEdge
            smoothedRights[row] = rightEdge
        case .mean:
            smoothedLefts[row] = leftSum / count
            smoothedRights[row] = rightSum / count
        }
    }

    let step = max(1, validRows.count / 52)
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
        points.append(
            WrapPoint(
                x: (smoothedLefts[row] - boundLeft) / boundWidth,
                y: ((Double(row) + 0.5) - Double(boundTop)) / boundHeight
            )
        )
    }
    for row in sampledRows.reversed() {
        points.append(
            WrapPoint(
                x: (smoothedRights[row] - boundLeft) / boundWidth,
                y: ((Double(row) + 0.5) - Double(boundTop)) / boundHeight
            )
        )
    }

    return points
}

private func makeFallbackImage() -> NSImage {
    let size = CGSize(width: 160, height: 160)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 80, y: 10))
    path.line(to: NSPoint(x: 150, y: 80))
    path.line(to: NSPoint(x: 80, y: 150))
    path.line(to: NSPoint(x: 10, y: 80))
    path.close()
    path.fill()
    image.unlockFocus()
    return image
}
