import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Pretext

enum IllustratedManuscriptConstants {
    static let basePageWidth = 700.0
    static let baseMargin = 45.0
    static let baseFontSize = 21.0
    static let baseLineHeight = 34.0
    static let maxPageHeight = 960.0
    static let dragonSpriteScale = 0.24
    static let dragonWidths = [
        221.0, 130.0, 203.0, 223.0, 285.0,
        299.0, 281.0, 224.0, 192.0, 174.0,
        191.0, 156.0, 155.0, 122.0, 126.0,
        125.0, 107.0, 101.0, 101.0, 81.0,
    ]
}

enum IllustratedManuscriptPalette {
    static let paper = CGColor(red: 244 / 255, green: 238 / 255, blue: 224 / 255, alpha: 1)
    static let ink = CGColor(red: 42 / 255, green: 26 / 255, blue: 10 / 255, alpha: 1)
    static let ember = CGColor(red: 196 / 255, green: 64 / 255, blue: 42 / 255, alpha: 1)
    static let flame = CGColor(red: 224 / 255, green: 138 / 255, blue: 48 / 255, alpha: 1)
    static let glow = CGColor(red: 240 / 255, green: 192 / 255, blue: 48 / 255, alpha: 1)
}

struct IllustratedDropCapGeometry: Equatable {
    var drawRect: WrapRect
    var obstacleRect: WrapRect
}

struct IllustratedDragonSprites {
    var head: CGImage
    var tongue: CGImage
    var wingFront: CGImage
    var wingBack: CGImage
    var body: [CGImage]
}

enum IllustratedManuscriptAssets {
    static let attribution = "By Neither/Nor"
    static let bodyStartCursor = LayoutCursor(segmentIndex: 0, graphemeIndex: 1)
    static let story = loadText(named: "story", extension: "txt")
    static let dropCapCharacter = String(story.prefix(1))
    static let dropCapImage = loadImage(named: "dropcap", extension: "png")
    static let dragonSprites = loadDragonSprites()

    nonisolated(unsafe) private static var fontCache: [Int: CTFont] = [:]
    nonisolated(unsafe) private static var preparedCache: [Int: PreparedText] = [:]

    static func bodyFont(size: Double) -> CTFont {
        let cacheKey = Int(round(size * 10))
        if let cached = fontCache[cacheKey] {
            return cached
        }

        guard
            let url = Bundle.module.url(
                forResource: "furia-iii",
                withExtension: "ttf"
            ),
            let provider = CGDataProvider(url: url as CFURL),
            let cgFont = CGFont(provider)
        else {
            let fallback = CTFontCreateWithName("Georgia" as CFString, size, nil)
            fontCache[cacheKey] = fallback
            return fallback
        }

        let font = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
        fontCache[cacheKey] = font
        return font
    }

    static func preparedStory(fontSize: Double) -> PreparedText {
        let cacheKey = Int(round(fontSize * 10))
        if let cached = preparedCache[cacheKey] {
            return cached
        }

        let prepared = prepareWithSegments(story, font: bodyFont(size: fontSize))
        preparedCache[cacheKey] = prepared
        return prepared
    }

    static func lineTextInset(fontSize: Double, lineHeight: Double) -> Double {
        let capHeightApproximation = fontSize * 0.857
        return ((lineHeight - capHeightApproximation) / 2).rounded()
    }

    static func dropCapGeometry(pageRect: WrapRect, margin: Double, lineHeight: Double) -> IllustratedDropCapGeometry {
        let drawHeight = lineHeight * 7
        let drawWidth = Double(dropCapImage.width) * (drawHeight / Double(dropCapImage.height))
        let drawRect = WrapRect(
            x: pageRect.x + margin,
            y: pageRect.y + margin,
            width: drawWidth,
            height: drawHeight
        )

        return IllustratedDropCapGeometry(
            drawRect: drawRect,
            obstacleRect: WrapRect(
                x: drawRect.x - 4,
                y: drawRect.y - 4,
                width: drawWidth + 12,
                height: drawHeight
            )
        )
    }

    private static func loadText(named name: String, extension ext: String) -> String {
        guard
            let url = Bundle.module.url(
                forResource: name,
                withExtension: ext
            ),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return ""
        }

        return text
    }

    private static func loadImage(named name: String, extension ext: String) -> CGImage {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: ext),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            fatalError("Missing resource \(name).\(ext)")
        }

        return image
    }

    private static func loadDragonSprites() -> IllustratedDragonSprites {
        IllustratedDragonSprites(
            head: loadImage(named: "head", extension: "png"),
            tongue: loadImage(named: "tongue", extension: "png"),
            wingFront: loadImage(named: "wing-front", extension: "png"),
            wingBack: loadImage(named: "wing-back", extension: "png"),
            body: (1...19).map {
                loadImage(named: "body-\($0)", extension: "png")
            }
        )
    }
}
