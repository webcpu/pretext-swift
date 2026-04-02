import CoreText
import Foundation
import Pretext

let fluidSitePhrases: [String] = [
    "GPU shaders are like tiny wizards, casting millions of pixel spells per second!",
    "Real-time ray tracing is basically teaching light how to play hide and seek in your GPU.",
    "Vertex shaders are the cosmic sculptors of the 3D universe, shaping digital realities.",
    "Fragment shaders are the pixel whisperers, convincing each dot to show its true colors.",
    "Tessellation shaders are digital plasticians, giving flat polygons an extreme makeover.",
    "Compute shaders turn your GPU into a math-crunching monster with an appetite for data.",
    "Deferred rendering is like a procrastinator's dream - putting off the hard work until later!",
    "PBR is the art of making virtual materials so real, you'll want to lick your screen.",
    "Ambient occlusion is the shadow puppeteer of the rendering world, adding depth with a flick of the wrist.",
    "Normal mapping is like giving your 3D models an instant facelift without the surgery.",
    "Temporal anti-aliasing is a time-bending technique that smooths edges by peeking into the future.",
    "Screen space reflections are mirror magic that works even when there's nothing to reflect!",
    "Volumetric lighting lets you slice through god rays with your mouse cursor.",
    "GPU instancing is cloning on steroids - copy-paste a million trees without breaking a sweat!",
    "Shader permutations are like a choose-your-own-adventure book, but for your GPU.",
]

enum FluidPhraseSeed {
    static let `default`: UInt64 = 0xF10D_BAAC_BEEF_2026
}

struct FluidPageMetrics: Equatable {
    var viewportRect: WrapRect
    var contentRect: WrapRect
    var layoutWidth: Double
    var fontSize: Double
    var lineHeight: Double
    var fieldColumns: Int
    var fieldRows: Int
    var cursorBaseSize: Double
}

struct FluidGlyphLayout: Equatable {
    var id: Int
    var character: String
    var fontGlyph: CGGlyph
    var restCenter: WrapPoint
    var drawOrigin: WrapPoint
    var baselineY: Double
    var width: Double
    var bounds: WrapRect
}

struct FluidLayoutSnapshot: Equatable {
    var pageMetrics: FluidPageMetrics
    var text: String
    var glyphs: [FluidGlyphLayout]

    init(
        pageMetrics: FluidPageMetrics,
        text: String,
        glyphs: [FluidGlyphLayout] = []
    ) {
        self.pageMetrics = pageMetrics
        self.text = text
        self.glyphs = glyphs
    }
}

private enum FluidLayoutDefaults {
    static let desktopFontSize = 16.0
    static let mobileFontSize = 12.0
    static let desktopCursorBaseSize = 22.0
    static let mobileCursorBaseSize = 18.0
}

private struct FluidPreparedCacheKey: Hashable {
    var fontSizeKey: Int
    var phraseCount: Int
}

private struct FluidSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private enum FluidLayoutAssets {
    static let lock = NSLock()
    nonisolated(unsafe) private static var preparedCache: [FluidPreparedCacheKey: PreparedText] = [:]

    static func preparedText(phraseCount: Int, fontSize: Double) -> PreparedText {
        let cacheKey = FluidPreparedCacheKey(
            fontSizeKey: Int(round(fontSize * 10)),
            phraseCount: phraseCount
        )
        lock.lock()
        let cachedPrepared = preparedCache[cacheKey]
        lock.unlock()
        if let cachedPrepared {
            return cachedPrepared
        }

        let prepared = prepare(
            fluidDisplayText(phraseCount: phraseCount),
            font: fluidBodyFont(size: fontSize)
        )
        lock.lock()
        preparedCache[cacheKey] = prepared
        lock.unlock()
        return prepared
    }
}

func fluidPhraseCount(for viewportWidth: Double) -> Int {
    max(1, Int((viewportWidth / 512.0 * 7.0).rounded()))
}

func fluidPhraseSequence(
    phraseCount: Int,
    seed: UInt64 = FluidPhraseSeed.default
) -> [String] {
    guard phraseCount > 0 else {
        return []
    }

    var rng = FluidSeededGenerator(seed: seed)
    var cycle = fluidSitePhrases
    cycle.shuffle(using: &rng)

    var phrases: [String] = []
    phrases.reserveCapacity(phraseCount)

    for index in 0..<phraseCount {
        if index > 0, index.isMultiple(of: fluidSitePhrases.count) {
            cycle = fluidSitePhrases
            cycle.shuffle(using: &rng)
        }
        phrases.append(cycle[index % fluidSitePhrases.count])
    }

    return phrases
}

func fluidBodyFont(size: Double) -> CTFont {
    FluidFontAssets.live.bodyFont(size: size)
}

func fluidDisplayText(phraseCount: Int) -> String {
    fluidPhraseSequence(phraseCount: phraseCount)
        .map { $0.uppercased() + " " }
        .joined()
}

func fluidPageMetrics(
    viewportWidth: Double,
    viewportHeight: Double,
    platform: DemoNavigationPlatform = .current
) -> FluidPageMetrics {
    let width = max(0, viewportWidth)
    let height = max(0, viewportHeight)
    let usesDesktopSizing = platform == .macOS
    let viewportRect = WrapRect(x: 0, y: 0, width: width, height: height)
    let fontSize = usesDesktopSizing ? FluidLayoutDefaults.desktopFontSize : FluidLayoutDefaults.mobileFontSize
    let font = fluidBodyFont(size: fontSize)
    let lineHeight = Double(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))

    return FluidPageMetrics(
        viewportRect: viewportRect,
        contentRect: viewportRect,
        layoutWidth: width,
        fontSize: fontSize,
        lineHeight: lineHeight,
        fieldColumns: max(18, Int(width / (usesDesktopSizing ? 28 : 22))),
        fieldRows: max(12, Int(height / (usesDesktopSizing ? 28 : 24))),
        cursorBaseSize: usesDesktopSizing ? FluidLayoutDefaults.desktopCursorBaseSize : FluidLayoutDefaults.mobileCursorBaseSize
    )
}

func evaluateFluidLayout(
    viewportWidth: Double,
    viewportHeight: Double,
    platform: DemoNavigationPlatform = .current
) -> FluidLayoutSnapshot {
    let metrics = fluidPageMetrics(
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        platform: platform
    )

    guard metrics.viewportRect.width > 0, metrics.viewportRect.height > 0 else {
        return FluidLayoutSnapshot(
            pageMetrics: metrics,
            text: "",
            glyphs: []
        )
    }

    let phraseCount = fluidPhraseCount(for: viewportWidth)
    let text = fluidDisplayText(phraseCount: phraseCount)
    let font = fluidBodyFont(size: metrics.fontSize)
    let ascent = Double(CTFontGetAscent(font))
    let descent = Double(CTFontGetDescent(font))
    let leading = max(0, metrics.lineHeight - (ascent + descent))
    let baselineOffset = ascent

    var prepared = FluidLayoutAssets.preparedText(
        phraseCount: phraseCount,
        fontSize: metrics.fontSize
    )
    var cursor = LayoutCursor.start
    var lineTop = -max(descent, leading / 2)
    var nextGlyphID = 0
    var glyphs: [FluidGlyphLayout] = []

    while lineTop < metrics.viewportRect.maxY {
        guard let layoutLine = layoutNextLine(
            &prepared,
            start: cursor,
            maxWidth: metrics.layoutWidth
        ) else {
            break
        }
        guard layoutLine.end != cursor else {
            break
        }

        let hasMoreText = layoutNextLine(
            prepared,
            start: layoutLine.end,
            maxWidth: metrics.layoutWidth
        ) != nil

        let lineGlyphs = fluidMakeLineGlyphs(
            text: layoutLine.text,
            baselineY: lineTop + baselineOffset,
            viewportRect: metrics.viewportRect,
            layoutWidth: metrics.layoutWidth,
            font: font,
            justify: hasMoreText,
            startingGlyphID: nextGlyphID
        )

        glyphs.append(contentsOf: lineGlyphs)
        nextGlyphID += lineGlyphs.count

        cursor = layoutLine.end
        lineTop += metrics.lineHeight
    }

    glyphs = fluidVerticallyCenteredGlyphs(
        glyphs,
        viewport: metrics.viewportRect
    )

    return FluidLayoutSnapshot(
        pageMetrics: metrics,
        text: text,
        glyphs: glyphs
    )
}

private func fluidMakeLineGlyphs(
    text: String,
    baselineY: Double,
    viewportRect: WrapRect,
    layoutWidth: Double,
    font: CTFont,
    justify: Bool,
    startingGlyphID: Int
) -> [FluidGlyphLayout] {
    guard !text.isEmpty else {
        return []
    }

    let attributes: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: font,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let baseLine = CTLineCreateWithAttributedString(attributed)
    let line = justify
        ? (CTLineCreateJustifiedLine(baseLine, 1.0, layoutWidth) ?? baseLine)
        : baseLine

    let nsText = text as NSString
    var visibleGlyphs: [FluidGlyphLayout] = []
    var nextGlyphID = startingGlyphID

    let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
    for run in runs {
        let glyphCount = CTRunGetGlyphCount(run)
        guard glyphCount > 0 else {
            continue
        }

        var runGlyphs = Array(repeating: CGGlyph(), count: glyphCount)
        var runPositions = Array(repeating: CGPoint.zero, count: glyphCount)
        var runAdvances = Array(repeating: CGSize.zero, count: glyphCount)
        var runStringIndices = Array(repeating: 0, count: glyphCount)

        CTRunGetGlyphs(run, CFRangeMake(0, 0), &runGlyphs)
        CTRunGetPositions(run, CFRangeMake(0, 0), &runPositions)
        CTRunGetAdvances(run, CFRangeMake(0, 0), &runAdvances)
        CTRunGetStringIndices(run, CFRangeMake(0, 0), &runStringIndices)

        let runAttributes = CTRunGetAttributes(run) as NSDictionary
        let runFont = (runAttributes[kCTFontAttributeName] as! CTFont?) ?? font

        for index in 0..<glyphCount {
            let stringIndex = runStringIndices[index]
            guard stringIndex != kCFNotFound,
                  stringIndex >= 0,
                  stringIndex < nsText.length
            else {
                continue
            }

            let characterCode = nsText.character(at: stringIndex)
            guard let scalar = UnicodeScalar(characterCode) else {
                continue
            }
            let character = String(scalar)
            guard !character.allSatisfy(\.isWhitespace) else {
                continue
            }

            var glyph = runGlyphs[index]
            var glyphBounds = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(runFont, .default, &glyph, &glyphBounds, 1)
            guard !glyphBounds.isEmpty else {
                continue
            }

            let drawOrigin = WrapPoint(
                x: viewportRect.minX + runPositions[index].x,
                y: baselineY + runPositions[index].y
            )
            let bounds = WrapRect(
                x: drawOrigin.x + glyphBounds.minX,
                y: drawOrigin.y - glyphBounds.maxY,
                width: glyphBounds.width,
                height: glyphBounds.height
            )
            guard fluidBoundsIntersectViewport(bounds, viewport: viewportRect) else {
                continue
            }
            let restCenter = WrapPoint(x: bounds.midX, y: bounds.midY)

            visibleGlyphs.append(
                FluidGlyphLayout(
                    id: nextGlyphID,
                    character: character,
                    fontGlyph: glyph,
                    restCenter: restCenter,
                    drawOrigin: drawOrigin,
                    baselineY: drawOrigin.y,
                    width: runAdvances[index].width,
                    bounds: bounds
                )
            )
            nextGlyphID += 1
        }
    }

    return visibleGlyphs
}

private func fluidBoundsIntersectViewport(
    _ bounds: WrapRect,
    viewport: WrapRect
) -> Bool {
    bounds.maxX > viewport.minX &&
        bounds.minX < viewport.maxX &&
        bounds.maxY > viewport.minY &&
        bounds.minY < viewport.maxY
}

func fluidTranslatedGlyphBounds(
    _ glyph: FluidGlyphLayout,
    center: WrapPoint
) -> WrapRect {
    let offsetX = center.x - glyph.restCenter.x
    let offsetY = center.y - glyph.restCenter.y
    return WrapRect(
        x: glyph.bounds.x + offsetX,
        y: glyph.bounds.y + offsetY,
        width: glyph.bounds.width,
        height: glyph.bounds.height
    )
}

private func fluidVerticallyCenteredGlyphs(
    _ glyphs: [FluidGlyphLayout],
    viewport: WrapRect
) -> [FluidGlyphLayout] {
    guard
        let minY = glyphs.map(\.bounds.minY).min(),
        let maxY = glyphs.map(\.bounds.maxY).max()
    else {
        return glyphs
    }

    let offsetY = viewport.midY - (minY + maxY) * 0.5
    guard abs(offsetY) > 0.001 else {
        return glyphs
    }

    return glyphs.map { glyph in
        var shifted = glyph
        shifted.restCenter.y += offsetY
        shifted.drawOrigin.y += offsetY
        shifted.baselineY += offsetY
        shifted.bounds.y += offsetY
        return shifted
    }
}

private struct FluidGlyphMetrics {
    var glyph: CGGlyph
    var advance: Double
    var bounds: CGRect
}

private func fluidGlyphMetrics(
    for grapheme: String,
    font: CTFont
) -> FluidGlyphMetrics? {
    let utf16 = grapheme.utf16
    guard utf16.count == 1, let codeUnit = utf16.first else {
        return nil
    }

    var character = UniChar(codeUnit)
    var glyph = CGGlyph()
    guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else {
        return nil
    }

    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(font, .default, &glyph, &advance, 1)

    var bounds = CGRect.zero
    CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, &bounds, 1)

    return FluidGlyphMetrics(
        glyph: glyph,
        advance: Double(advance.width),
        bounds: bounds
    )
}
