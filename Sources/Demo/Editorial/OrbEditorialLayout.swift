import CoreText
import Foundation
import Pretext

enum OrbEditorialMetrics {
    static let gutter = 48.0
    static let columnGap = 40.0
    static let statsBarHeight = 42.0
    static let dropCapLines = 3
    static let minSlotWidth = 50.0
    static let maxContentWidth = 1500.0
    static let bodyLineHeight = 30.0
    static let pullquoteLineHeight = 27.0
    static let circleHorizontalPadding = 14.0
    static let circleVerticalPadding = 4.0
    static let bodyTopGap = 20.0
    static let bodyBottomInset = 8.0
    static let headlineLineHeightScale = 0.93
    static let headlineMinSize = 24
    static let headlineMaxSize = 120
    static let dropCapSize = bodyLineHeight * Double(dropCapLines) - 4

    static let bodyFontDescriptor = FontDescriptor(
        familyName: "Iowan Old Style",
        size: 18
    )
    static let pullquoteFontDescriptor = FontDescriptor(
        familyName: "Iowan Old Style",
        size: 19,
        symbolicTraits: .traitItalic
    )

    static func bodyFont() -> CTFont {
        bodyFontDescriptor.makeCTFont()
    }

    static func pullquoteFont() -> CTFont {
        pullquoteFontDescriptor.makeCTFont()
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

    static func dropCapFont() -> CTFont {
        FontDescriptor(
            familyName: "Iowan Old Style",
            size: dropCapSize,
            symbolicTraits: .traitBold,
            weightValue: 0.4
        )
        .makeCTFont()
    }
}

struct OrbEditorialPullquoteBlock: Equatable {
    var rect: WrapRect
    var lines: [PositionedLine]
    var columnIndex: Int
}

struct OrbEditorialSnapshot: Equatable {
    var headlineLines: [PositionedLine]
    var headlineFontSize: Double
    var headlineLineHeight: Double
    var bodyLines: [PositionedLine]
    var pullquotes: [OrbEditorialPullquoteBlock]
    var dropCapRect: WrapRect
    var dropCapPosition: WrapPoint
    var columnCount: Int
    var reflowMilliseconds: Double
}

private struct OrbCircleObstacle: Equatable {
    var cx: Double
    var cy: Double
    var radius: Double
    var hPad: Double
    var vPad: Double
}

private enum OrbPullquoteSide {
    case left
    case right
}

private struct OrbPullquotePlacement {
    var columnIndex: Int
    var yFraction: Double
    var widthFraction: Double
    var side: OrbPullquoteSide
}

private enum OrbEditorialAssets {
    static let bodyPrepared = prepareWithSegments(OrbEditorialText.body, font: OrbEditorialMetrics.bodyFont())
    static let pullquotePrepared = OrbEditorialText.pullquotes.map {
        prepareWithSegments($0, font: OrbEditorialMetrics.pullquoteFont())
    }
    static let bodyStartCursor = LayoutCursor(segmentIndex: 0, graphemeIndex: 1)
    static let dropCapCharacter = String(OrbEditorialText.body.prefix(1))
    static let dropCapPrepared = prepareWithSegments(dropCapCharacter, font: OrbEditorialMetrics.dropCapFont())
    static let dropCapTotalWidth = ceil(singleLineWidth(dropCapPrepared)) + 10

    nonisolated(unsafe) private static var headlinePreparedCache: [Int: PreparedText] = [:]
    nonisolated(unsafe) private static var fittedHeadlineCache: [String: (fontSize: Double, lineHeight: Double, lines: [PositionedLine])] = [:]

    static func preparedHeadline(size: Int) -> PreparedText {
        if let cached = headlinePreparedCache[size] {
            return cached
        }

        let prepared = prepareWithSegments(OrbEditorialText.headline, font: OrbEditorialMetrics.headlineFont(size: Double(size)))
        headlinePreparedCache[size] = prepared
        return prepared
    }

    static func cachedHeadline(
        maxWidth: Double,
        maxHeight: Double
    ) -> (fontSize: Double, lineHeight: Double, lines: [PositionedLine])? {
        fittedHeadlineCache[headlineCacheKey(maxWidth: maxWidth, maxHeight: maxHeight)]
    }

    static func storeHeadline(
        maxWidth: Double,
        maxHeight: Double,
        value: (fontSize: Double, lineHeight: Double, lines: [PositionedLine])
    ) {
        fittedHeadlineCache[headlineCacheKey(maxWidth: maxWidth, maxHeight: maxHeight)] = value
    }

    private static func headlineCacheKey(maxWidth: Double, maxHeight: Double) -> String {
        "\(maxWidth.rounded()):\(maxHeight.rounded())"
    }
}

func orbEditorialColumnCount(for width: Double) -> Int {
    if width > 1000 {
        return 3
    }
    if width > 640 {
        return 2
    }
    return 1
}

func evaluateOrbEditorialLayout(
    pageWidth: Double,
    pageHeight: Double,
    orbs: [OrbState]
) -> OrbEditorialSnapshot {
    let start = CFAbsoluteTimeGetCurrent()
    let gutter = OrbEditorialMetrics.gutter
    let headlineWidth = min(pageWidth - gutter * 2, 1000)
    let headlineMaxHeight = floor(pageHeight * 0.35)
    let headline = fitOrbHeadline(maxWidth: headlineWidth, maxHeight: headlineMaxHeight)
    let positionedHeadlineLines = headline.lines.map {
        PositionedLine(
            x: gutter + $0.x,
            y: gutter + $0.y,
            width: $0.width,
            text: $0.text
        )
    }

    let headlineHeight = Double(positionedHeadlineLines.count) * headline.lineHeight
    let bodyTop = gutter + headlineHeight + OrbEditorialMetrics.bodyTopGap
    let bodyHeight = max(0, pageHeight - bodyTop - OrbEditorialMetrics.statsBarHeight - OrbEditorialMetrics.bodyBottomInset)
    let columnCount = orbEditorialColumnCount(for: pageWidth)
    let totalGutter = gutter * 2 + OrbEditorialMetrics.columnGap * Double(columnCount - 1)
    let contentWidth = min(pageWidth, OrbEditorialMetrics.maxContentWidth)
    let columnWidth = floor((contentWidth - totalGutter) / Double(columnCount))
    let contentLeft = round(
        (pageWidth - (Double(columnCount) * columnWidth + Double(columnCount - 1) * OrbEditorialMetrics.columnGap)) / 2
    )
    let firstColumnX = contentLeft
    let dropCapRect = WrapRect(
        x: firstColumnX - 2,
        y: bodyTop - 2,
        width: OrbEditorialAssets.dropCapTotalWidth,
        height: Double(OrbEditorialMetrics.dropCapLines) * OrbEditorialMetrics.bodyLineHeight + 2
    )
    let dropCapPosition = WrapPoint(x: firstColumnX, y: bodyTop)

    let circleObstacles = orbs.map {
        OrbCircleObstacle(
            cx: $0.x,
            cy: $0.y,
            radius: $0.radius,
            hPad: OrbEditorialMetrics.circleHorizontalPadding,
            vPad: OrbEditorialMetrics.circleVerticalPadding
        )
    }

    let placements = [
        OrbPullquotePlacement(columnIndex: 0, yFraction: 0.48, widthFraction: 0.52, side: .right),
        OrbPullquotePlacement(columnIndex: min(1, columnCount - 1), yFraction: 0.32, widthFraction: 0.5, side: .left),
    ]

    var pullquotes: [OrbEditorialPullquoteBlock] = []
    for (index, placement) in placements.enumerated() {
        if placement.columnIndex >= columnCount {
            continue
        }

        let pullquoteWidth = round(columnWidth * placement.widthFraction)
        let columnX = contentLeft + Double(placement.columnIndex) * (columnWidth + OrbEditorialMetrics.columnGap)
        let pullquoteX = placement.side == .right ? columnX + columnWidth - pullquoteWidth : columnX
        let pullquoteY = round(bodyTop + bodyHeight * placement.yFraction)
        var prepared = OrbEditorialAssets.pullquotePrepared[index]
        let layoutResult = layout(&prepared, maxWidth: pullquoteWidth - 20, lineHeight: OrbEditorialMetrics.pullquoteLineHeight)
        let (_, rawLines) = layoutWithLines(
            &prepared,
            maxWidth: pullquoteWidth - 20,
            lineHeight: OrbEditorialMetrics.pullquoteLineHeight
        )
        let positionedLines = rawLines.enumerated().map { lineIndex, line in
            PositionedLine(
                x: pullquoteX + 20,
                y: pullquoteY + 8 + Double(lineIndex) * OrbEditorialMetrics.pullquoteLineHeight,
                width: line.width,
                text: line.text
            )
        }
        pullquotes.append(
            OrbEditorialPullquoteBlock(
                rect: WrapRect(
                    x: pullquoteX,
                    y: pullquoteY,
                    width: pullquoteWidth,
                    height: layoutResult.height + 16
                ),
                lines: positionedLines,
                columnIndex: placement.columnIndex
            )
        )
    }

    var bodyLines: [PositionedLine] = []
    var cursor = OrbEditorialAssets.bodyStartCursor
    var preparedBody = OrbEditorialAssets.bodyPrepared
    for columnIndex in 0..<columnCount {
        let columnX = contentLeft + Double(columnIndex) * (columnWidth + OrbEditorialMetrics.columnGap)
        var rectObstacles: [WrapRect] = []
        if columnIndex == 0 {
            rectObstacles.append(dropCapRect)
        }
        rectObstacles.append(contentsOf: pullquotes.filter { $0.columnIndex == columnIndex }.map(\.rect))

        let result = layoutOrbEditorialColumn(
            prepared: &preparedBody,
            startCursor: cursor,
            regionX: columnX,
            regionY: bodyTop,
            regionWidth: columnWidth,
            regionHeight: bodyHeight,
            lineHeight: OrbEditorialMetrics.bodyLineHeight,
            circleObstacles: circleObstacles,
            rectObstacles: rectObstacles
        )
        bodyLines.append(contentsOf: result.lines)
        cursor = result.cursor
    }

    let reflowMilliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000
    return OrbEditorialSnapshot(
        headlineLines: positionedHeadlineLines,
        headlineFontSize: headline.fontSize,
        headlineLineHeight: headline.lineHeight,
        bodyLines: bodyLines,
        pullquotes: pullquotes,
        dropCapRect: dropCapRect,
        dropCapPosition: dropCapPosition,
        columnCount: columnCount,
        reflowMilliseconds: reflowMilliseconds
    )
}

private func fitOrbHeadline(maxWidth: Double, maxHeight: Double) -> (fontSize: Double, lineHeight: Double, lines: [PositionedLine]) {
    if let cached = OrbEditorialAssets.cachedHeadline(maxWidth: maxWidth, maxHeight: maxHeight) {
        return cached
    }

    var low = OrbEditorialMetrics.headlineMinSize
    var high = OrbEditorialMetrics.headlineMaxSize
    var bestSize = low
    var bestLineHeight = round(Double(low) * OrbEditorialMetrics.headlineLineHeightScale)
    var bestLines: [PositionedLine] = []

    while low <= high {
        let size = Int(floor(Double(low + high) / 2))
        let lineHeight = round(Double(size) * OrbEditorialMetrics.headlineLineHeightScale)
        var prepared = OrbEditorialAssets.preparedHeadline(size: size)
        var lineCount = 0
        var breaksWord = false

        walkLineRanges(&prepared, maxWidth: maxWidth) { _, _, end in
            lineCount += 1
            if end.graphemeIndex != 0 {
                breaksWord = true
            }
        }

        let totalHeight = Double(lineCount) * lineHeight
        if !breaksWord, totalHeight <= maxHeight {
            bestSize = size
            bestLineHeight = lineHeight
            let (_, lines) = layoutWithLines(&prepared, maxWidth: maxWidth, lineHeight: lineHeight)
            bestLines = lines.enumerated().map { index, line in
                PositionedLine(
                    x: 0,
                    y: Double(index) * lineHeight,
                    width: line.width,
                    text: line.text
                )
            }
            low = size + 1
        } else {
            high = size - 1
        }
    }

    let result = (
        fontSize: Double(bestSize),
        lineHeight: bestLineHeight,
        lines: bestLines
    )
    OrbEditorialAssets.storeHeadline(maxWidth: maxWidth, maxHeight: maxHeight, value: result)
    return result
}

private func layoutOrbEditorialColumn(
    prepared: inout PreparedText,
    startCursor: LayoutCursor,
    regionX: Double,
    regionY: Double,
    regionWidth: Double,
    regionHeight: Double,
    lineHeight: Double,
    circleObstacles: [OrbCircleObstacle],
    rectObstacles: [WrapRect]
) -> (lines: [PositionedLine], cursor: LayoutCursor) {
    var cursor = startCursor
    var lineTop = regionY
    var lines: [PositionedLine] = []
    var textExhausted = false

    while lineTop + lineHeight <= regionY + regionHeight, !textExhausted {
        let bandTop = lineTop
        let bandBottom = lineTop + lineHeight
        var blocked: [WrapInterval] = []

        for obstacle in circleObstacles {
            if let interval = circleIntervalForBand(
                cx: obstacle.cx,
                cy: obstacle.cy,
                r: obstacle.radius,
                bandTop: bandTop,
                bandBottom: bandBottom,
                hPad: obstacle.hPad,
                vPad: obstacle.vPad
            ) {
                blocked.append(interval)
            }
        }

        for rect in rectObstacles {
            if bandBottom <= rect.y || bandTop >= rect.y + rect.height {
                continue
            }
            blocked.append(WrapInterval(left: rect.x, right: rect.x + rect.width))
        }

        let slots = carveTextLineSlots(
            base: WrapInterval(left: regionX, right: regionX + regionWidth),
            blocked: blocked,
            minimumWidth: OrbEditorialMetrics.minSlotWidth
        )
        .sorted { $0.left < $1.left }

        if slots.isEmpty {
            lineTop += lineHeight
            continue
        }

        for slot in slots {
            let slotWidth = slot.right - slot.left
            guard let line = layoutNextLine(&prepared, start: cursor, maxWidth: slotWidth) else {
                textExhausted = true
                break
            }

            if line.end == cursor {
                textExhausted = true
                break
            }

            lines.append(
                PositionedLine(
                    x: round(slot.left),
                    y: round(lineTop),
                    width: line.width,
                    text: line.text
                )
            )
            cursor = line.end
        }

        lineTop += lineHeight
    }

    return (lines, cursor)
}

private func singleLineWidth(_ prepared: PreparedText) -> Double {
    var prepared = prepared
    var width = 0.0
    walkLineRanges(&prepared, maxWidth: 100_000) { lineWidth, _, _ in
        width = lineWidth
    }
    return width
}
