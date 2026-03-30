import CoreText
import Foundation
import Pretext
import PretextUI
import SwiftUI

enum EditorialMetrics {
    static let bodyFontDescriptor = FontDescriptor(
        familyName: "Iowan Old Style",
        size: 20,
        weightValue: 0.1
    )
    static let creditFontDescriptor = FontDescriptor(
        familyName: "Helvetica Neue",
        size: 12,
        weightValue: 0
    )
    static let bodyLineHeight = 32.0
    static let creditLineHeight = 16.0
    static let hintPillSafeTop = 72.0
    static let narrowBreakpoint = 760.0
    static let narrowColumnMaxWidth = 430.0
    static let bodyLetterSpacing = bodyFontDescriptor.size * 0.002
    static let headlineLetterSpacing = -0.5
    static let creditLetterSpacing = creditFontDescriptor.size * 0.14
    static let creditNarrowLetterSpacing = 11.0 * 0.12

    static func bodyFont() -> CTFont {
        bodyFontDescriptor.makeCTFont()
    }

    static func creditFont() -> CTFont {
        creditFontDescriptor.makeCTFont()
    }

    static func headlineFont(size: Double) -> CTFont {
        FontDescriptor(
            familyName: "Iowan Old Style",
            size: size,
            symbolicTraits: .traitBold,
            weightValue: 0.4
        )
        .makeCTFont()
    }

    static func bodyDisplayFont() -> Font {
        bodyFontDescriptor.makeDisplayFont()
    }

    static func creditDisplayFont() -> Font {
        creditFontDescriptor.makeDisplayFont()
    }

    static func creditDisplayFont(isNarrow: Bool) -> Font {
        if isNarrow {
            return FontDescriptor(
                familyName: creditFontDescriptor.familyName,
                size: 11,
                weightValue: 0
            )
            .makeDisplayFont()
        }
        return creditDisplayFont()
    }

    static func headlineDisplayFont(size: Double) -> Font {
        Font(headlineFont(size: size))
    }
}

struct PositionedLine: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var text: String
}

enum ColumnSide: Equatable {
    case left
    case right
}

enum BandObstacle: Equatable {
    case polygon(points: [WrapPoint], horizontalPadding: Double, verticalPadding: Double)
    case rects(rects: [WrapRect], horizontalPadding: Double, verticalPadding: Double)
}

struct PageLayout {
    var isNarrow: Bool
    var gutter: Double
    var pageWidth: Double
    var pageHeight: Double
    var centerGap: Double
    var columnWidth: Double
    var headlineRegion: WrapRect
    var headlineFont: CTFont
    var headlineFontSize: Double
    var headlineLineHeight: Double
    var creditGap: Double
    var copyGap: Double
    var openaiRect: WrapRect
    var claudeRect: WrapRect
}

struct LogoHits {
    var openai: [WrapPoint]
    var claude: [WrapPoint]
}

struct EvaluatedLayout {
    var headlineLines: [PositionedLine]
    var creditLeft: Double
    var creditTop: Double
    var leftLines: [PositionedLine]
    var rightLines: [PositionedLine]
    var contentHeight: Double
    var hits: LogoHits
}

enum EditorialAssets {
    static let bodyPrepared = prepare(BodyText.bodyCopy, font: EditorialMetrics.bodyFont())
    static let creditDisplayText = BodyText.credit.uppercased()
    static let creditPrepared = prepare(creditDisplayText, font: EditorialMetrics.creditFont())
    static let creditWidth = singleLineWidth(creditPrepared)
    static let openaiLogo = loadBundledLogo(named: "openai-symbol", layoutSmoothRadius: 6, hitSmoothRadius: 3)
    static let claudeLogo = loadBundledLogo(named: "claude-symbol", layoutSmoothRadius: 6, hitSmoothRadius: 5)
    nonisolated(unsafe) private static var headlineCache: [String: PreparedText] = [:]

    static func preparedHeadline(font: CTFont) -> PreparedText {
        let key = headlineCacheKey(for: font)
        if let cached = headlineCache[key] {
            return cached
        }

        let prepared = prepare(BodyText.headline, font: font)
        headlineCache[key] = prepared
        return prepared
    }

    private static func headlineCacheKey(for font: CTFont) -> String {
        let postScriptName = CTFontCopyPostScriptName(font) as String
        return "\(postScriptName)#\(CTFontGetSize(font))"
    }
}

func buildLayout(pageWidth: Double, pageHeight: Double, lineHeight: Double) -> PageLayout {
    let isNarrow = pageWidth < EditorialMetrics.narrowBreakpoint
    if isNarrow {
        let gutter = max(18, min(28, pageWidth * 0.06)).rounded()
        let centerGap = 0.0
        let columnWidth = min(pageWidth - gutter * 2, EditorialMetrics.narrowColumnMaxWidth).rounded()
        let headlineTop = 28.0
        let headlineWidth = pageWidth - gutter * 2
        let headlineFontSize = min(48, fitHeadlineFontSize(headlineWidth: headlineWidth, pageWidth: pageWidth))
        let headlineLineHeight = (headlineFontSize * 0.92).rounded()
        let creditGap = max(12, lineHeight * 0.5).rounded()
        let copyGap = max(18, lineHeight * 0.7).rounded()
        let claudeSize = min(92, pageWidth * 0.23, pageHeight * 0.11).rounded()
        let openaiSize = min(138, pageWidth * 0.34).rounded()

        return PageLayout(
            isNarrow: true,
            gutter: gutter,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            centerGap: centerGap,
            columnWidth: columnWidth,
            headlineRegion: WrapRect(
                x: gutter,
                y: headlineTop,
                width: headlineWidth,
                height: max(320, pageHeight - headlineTop - gutter)
            ),
            headlineFont: EditorialMetrics.headlineFont(size: headlineFontSize),
            headlineFontSize: headlineFontSize,
            headlineLineHeight: headlineLineHeight,
            creditGap: creditGap,
            copyGap: copyGap,
            openaiRect: WrapRect(
                x: gutter - (openaiSize * 0.22).rounded(),
                y: pageHeight - gutter - openaiSize + (openaiSize * 0.08).rounded(),
                width: openaiSize,
                height: openaiSize
            ),
            claudeRect: WrapRect(
                x: pageWidth - gutter - (claudeSize * 0.88).rounded(),
                y: 4,
                width: claudeSize,
                height: claudeSize
            )
        )
    }

    let gutter = max(52, pageWidth * 0.048).rounded()
    let centerGap = max(28, pageWidth * 0.025).rounded()
    let columnWidth = ((pageWidth - gutter * 2 - centerGap) / 2).rounded()
    let headlineTop = max(42, pageWidth * 0.04, EditorialMetrics.hintPillSafeTop).rounded()
    let headlineWidth = min(pageWidth - gutter * 2, max(columnWidth, pageWidth * 0.5)).rounded()
    let headlineFontSize = fitHeadlineFontSize(headlineWidth: headlineWidth, pageWidth: pageWidth)
    let headlineLineHeight = (headlineFontSize * 0.92).rounded()
    let creditGap = max(14, lineHeight * 0.6).rounded()
    let copyGap = max(20, lineHeight * 0.9).rounded()
    let openAIShrinkT = max(0, min(1, (960 - pageWidth) / 260))
    let openAISize = min(400 - openAIShrinkT * 56, pageHeight * 0.43).rounded()
    let claudeSize = max(276, min(500, pageWidth * 0.355, pageHeight * 0.45)).rounded()

    return PageLayout(
        isNarrow: false,
        gutter: gutter,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        centerGap: centerGap,
        columnWidth: columnWidth,
        headlineRegion: WrapRect(
            x: gutter,
            y: headlineTop,
            width: headlineWidth,
            height: pageHeight - headlineTop - gutter
        ),
        headlineFont: EditorialMetrics.headlineFont(size: headlineFontSize),
        headlineFontSize: headlineFontSize,
        headlineLineHeight: headlineLineHeight,
        creditGap: creditGap,
        copyGap: copyGap,
        openaiRect: WrapRect(
            x: gutter - (openAISize * 0.3).rounded(),
            y: pageHeight - gutter - openAISize + (openAISize * 0.2).rounded(),
            width: openAISize,
            height: openAISize
        ),
        claudeRect: WrapRect(
            x: pageWidth - (claudeSize * 0.69).rounded(),
            y: -(claudeSize * 0.22).rounded(),
            width: claudeSize,
            height: claudeSize
        )
    )
}

func fitHeadlineFontSize(headlineWidth: Double, pageWidth: Double) -> Double {
    var low = Int(ceil(max(22, pageWidth * 0.026)))
    var high = Int(floor(min(94.4, max(55.2, pageWidth * 0.055))))
    var best = low

    while low <= high {
        let size = Int(floor(Double(low + high) / 2))
        let preparedHeadline = EditorialAssets.preparedHeadline(font: EditorialMetrics.headlineFont(size: Double(size)))
        if !headlineBreaksInsideWord(preparedHeadline, maxWidth: headlineWidth) {
            best = size
            low = size + 1
        } else {
            high = size - 1
        }
    }

    return Double(best)
}

func layoutColumn(
    prepared: inout PreparedText,
    startCursor: LayoutCursor,
    region: WrapRect,
    lineHeight: Double,
    obstacles: [BandObstacle],
    side: ColumnSide
) -> (lines: [PositionedLine], cursor: LayoutCursor) {
    var cursor = startCursor
    var lineTop = region.y
    var lines: [PositionedLine] = []

    while true {
        if lineTop + lineHeight > region.y + region.height {
            break
        }

        let bandTop = lineTop
        let bandBottom = lineTop + lineHeight
        var blocked: [WrapInterval] = []

        for obstacle in obstacles {
            blocked.append(contentsOf: obstacleIntervals(for: obstacle, bandTop: bandTop, bandBottom: bandBottom))
        }

        let slots = carveTextLineSlots(
            base: WrapInterval(left: region.x, right: region.x + region.width),
            blocked: blocked
        )

        guard !slots.isEmpty else {
            lineTop += lineHeight
            continue
        }

        var slot = slots[0]
        for candidate in slots.dropFirst() {
            let bestWidth = slot.right - slot.left
            let candidateWidth = candidate.right - candidate.left
            if candidateWidth > bestWidth {
                slot = candidate
                continue
            }
            if candidateWidth < bestWidth {
                continue
            }
            switch side {
            case .left:
                if candidate.left > slot.left {
                    slot = candidate
                }
            case .right:
                if candidate.left < slot.left {
                    slot = candidate
                }
            }
        }

        let lineWidth = slot.right - slot.left
        guard let line = layoutNextLine(&prepared, start: cursor, maxWidth: lineWidth) else {
            break
        }
        if line.end == cursor {
            break
        }

        lines.append(
            PositionedLine(
                x: slot.left.rounded(),
                y: lineTop.rounded(),
                width: line.width,
                text: line.text
            )
        )
        cursor = line.end
        lineTop += lineHeight
    }

    return (lines, cursor)
}

func evaluateLayout(
    layout: PageLayout,
    lineHeight: Double,
    preparedBody: PreparedText,
    openaiLogo: LoadedLogo,
    claudeLogo: LoadedLogo,
    openaiAngle: Double,
    claudeAngle: Double
) -> EvaluatedLayout {
    let projection = logoProjection(
        layout: layout,
        lineHeight: lineHeight,
        openaiLogo: openaiLogo,
        claudeLogo: claudeLogo,
        openaiAngle: openaiAngle,
        claudeAngle: claudeAngle
    )

    var headlinePrepared = EditorialAssets.preparedHeadline(font: layout.headlineFont)
    let headlineResult = layoutColumn(
        prepared: &headlinePrepared,
        startCursor: .start,
        region: layout.headlineRegion,
        lineHeight: layout.headlineLineHeight,
        obstacles: [projection.openaiObstacle],
        side: .left
    )

    let headlineLines = headlineResult.lines
    let headlineRects = headlineLines.map {
        WrapRect(
            x: $0.x,
            y: $0.y,
            width: ceil($0.width),
            height: layout.headlineLineHeight
        )
    }
    let headlineBottom = headlineLines.isEmpty
        ? layout.headlineRegion.y
        : headlineLines.map { $0.y + layout.headlineLineHeight }.max() ?? layout.headlineRegion.y
    let creditTop = headlineBottom + layout.creditGap
    let creditRegion = WrapRect(
        x: layout.gutter + 4,
        y: creditTop,
        width: layout.headlineRegion.width,
        height: EditorialMetrics.creditLineHeight
    )
    let copyTop = creditTop + EditorialMetrics.creditLineHeight + layout.copyGap
    let titleObstacle = BandObstacle.rects(
        rects: headlineRects,
        horizontalPadding: (lineHeight * 0.95).rounded(),
        verticalPadding: (lineHeight * 0.3).rounded()
    )

    let creditBlocked = obstacleIntervals(for: projection.openaiObstacle, bandTop: creditRegion.y, bandBottom: creditRegion.y + creditRegion.height)
    let claudeCreditBlocked = obstacleIntervals(for: projection.claudeObstacle, bandTop: creditRegion.y, bandBottom: creditRegion.y + creditRegion.height)
    let creditSlots = carveTextLineSlots(
        base: WrapInterval(left: creditRegion.x, right: creditRegion.x + creditRegion.width),
        blocked: layout.isNarrow ? creditBlocked + claudeCreditBlocked : creditBlocked
    )

    var creditLeft = creditRegion.x
    for slot in creditSlots where slot.right - slot.left >= EditorialAssets.creditWidth {
        creditLeft = slot.left.rounded()
        break
    }

    if layout.isNarrow {
        var preparedBody = preparedBody
        let bodyRegion = WrapRect(
            x: ((layout.pageWidth - layout.columnWidth) / 2).rounded(),
            y: copyTop,
            width: layout.columnWidth,
            height: max(0, layout.pageHeight - copyTop - layout.gutter)
        )

        let bodyResult = layoutColumn(
            prepared: &preparedBody,
            startCursor: .start,
            region: bodyRegion,
            lineHeight: lineHeight,
            obstacles: [projection.claudeObstacle, projection.openaiObstacle],
            side: .left
        )

        return EvaluatedLayout(
            headlineLines: headlineLines,
            creditLeft: creditLeft,
            creditTop: creditTop,
            leftLines: bodyResult.lines,
            rightLines: [],
            contentHeight: layout.pageHeight,
            hits: projection.hits
        )
    }

    let leftRegion = WrapRect(
        x: layout.gutter,
        y: copyTop,
        width: layout.columnWidth,
        height: layout.pageHeight - copyTop - layout.gutter
    )
    let rightRegion = WrapRect(
        x: layout.gutter + layout.columnWidth + layout.centerGap,
        y: layout.headlineRegion.y,
        width: layout.columnWidth,
        height: layout.pageHeight - layout.headlineRegion.y - layout.gutter
    )

    var preparedBody = preparedBody
    let leftResult = layoutColumn(
        prepared: &preparedBody,
        startCursor: .start,
        region: leftRegion,
        lineHeight: lineHeight,
        obstacles: [projection.openaiObstacle],
        side: .left
    )

    let rightResult = layoutColumn(
        prepared: &preparedBody,
        startCursor: leftResult.cursor,
        region: rightRegion,
        lineHeight: lineHeight,
        obstacles: [titleObstacle, projection.claudeObstacle, projection.openaiObstacle],
        side: .right
    )

    return EvaluatedLayout(
        headlineLines: headlineLines,
        creditLeft: creditLeft,
        creditTop: creditTop,
        leftLines: leftResult.lines,
        rightLines: rightResult.lines,
        contentHeight: layout.pageHeight,
        hits: projection.hits
    )
}

private func singleLineWidth(_ prepared: PreparedText) -> Double {
    var prepared = prepared
    var width = 0.0
    walkLineRanges(&prepared, maxWidth: 100_000) { lineWidth, _, _ in
        width = lineWidth
    }
    return width
}

private func headlineBreaksInsideWord(_ prepared: PreparedText, maxWidth: Double) -> Bool {
    var prepared = prepared
    var breaksInsideWord = false
    walkLineRanges(&prepared, maxWidth: maxWidth) { _, _, end in
        if end.graphemeIndex != 0 {
            breaksInsideWord = true
        }
    }
    return breaksInsideWord
}

private func obstacleIntervals(for obstacle: BandObstacle, bandTop: Double, bandBottom: Double) -> [WrapInterval] {
    switch obstacle {
    case let .polygon(points, horizontalPadding, verticalPadding):
        if let interval = getPolygonIntervalForBand(
            points: points,
            bandTop: bandTop,
            bandBottom: bandBottom,
            hPad: horizontalPadding,
            vPad: verticalPadding
        ) {
            return [interval]
        }
        return []

    case let .rects(rects, horizontalPadding, verticalPadding):
        return getRectIntervalsForBand(
            rects: rects,
            bandTop: bandTop,
            bandBottom: bandBottom,
            hPad: horizontalPadding,
            vPad: verticalPadding
        )
    }
}

private func logoProjection(
    layout: PageLayout,
    lineHeight: Double,
    openaiLogo: LoadedLogo,
    claudeLogo: LoadedLogo,
    openaiAngle: Double,
    claudeAngle: Double
) -> (
    openaiObstacle: BandObstacle,
    claudeObstacle: BandObstacle,
    hits: LogoHits
) {
    let openaiWrap = transformWrapPoints(openaiLogo.layoutHull, rect: layout.openaiRect, angle: openaiAngle)
    let claudeWrap = transformWrapPoints(claudeLogo.layoutHull, rect: layout.claudeRect, angle: claudeAngle)

    return (
        openaiObstacle: .polygon(
            points: openaiWrap,
            horizontalPadding: (lineHeight * 0.82).rounded(),
            verticalPadding: (lineHeight * 0.26).rounded()
        ),
        claudeObstacle: .polygon(
            points: claudeWrap,
            horizontalPadding: (lineHeight * 0.28).rounded(),
            verticalPadding: (lineHeight * 0.12).rounded()
        ),
        hits: LogoHits(
            openai: transformWrapPoints(openaiLogo.hitHull, rect: layout.openaiRect, angle: openaiAngle),
            claude: transformWrapPoints(claudeLogo.hitHull, rect: layout.claudeRect, angle: claudeAngle)
        )
    )
}
