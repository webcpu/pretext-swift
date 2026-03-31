import CoreText
import Foundation
import Pretext

enum OrbEditorialPresentation: Equatable {
    case standard
    case watch

    var bodyStartCursor: LayoutCursor {
        switch self {
        case .standard:
            OrbEditorialAssets.bodyStartCursor
        case .watch:
            .start
        }
    }

    var bottomChromeHeight: Double {
        switch self {
        case .standard:
            OrbEditorialMetrics.standardStatsBarHeight
        case .watch:
            0
        }
    }

    var includesDropCap: Bool {
        self == .standard
    }

    var includesPullquotes: Bool {
        self == .standard
    }
}

enum OrbEditorialMetrics {
    static let standardStatsBarHeight = 42.0
    static let watchStatsBarHeight = 80.0
    static let minSlotWidth = 50.0
    static let maxContentWidth = 1500.0
    static let circleHorizontalPadding = 14.0
    static let circleVerticalPadding = 4.0
    static let regularProfile = OrbEditorialLayoutProfile(
        cacheKey: "regular",
        gutter: 48,
        columnGap: 40,
        dropCapLines: 3,
        bodyLineHeight: 30,
        pullquoteLineHeight: 27,
        bodyTopGap: 20,
        bodyBottomInset: 8,
        headlineLineHeightScale: 0.93,
        headlineMinSize: 24,
        headlineMaxSize: 120,
        headlineMaxHeightFraction: 0.35,
        bodyFontSize: 18,
        pullquoteFontSize: 19
    )
    static let compactProfile = OrbEditorialLayoutProfile(
        cacheKey: "compact",
        gutter: 32,
        columnGap: 32,
        dropCapLines: 2,
        bodyLineHeight: 23,
        pullquoteLineHeight: 21,
        bodyTopGap: 12,
        bodyBottomInset: 8,
        headlineLineHeightScale: 0.93,
        headlineMinSize: 18,
        headlineMaxSize: 60,
        headlineMaxHeightFraction: 0.19,
        bodyFontSize: 15,
        pullquoteFontSize: 16
    )
    static let watchProfile = OrbEditorialLayoutProfile(
        cacheKey: "watch",
        gutter: 22,
        columnGap: 20,
        dropCapLines: 2,
        bodyLineHeight: 19,
        pullquoteLineHeight: 18,
        bodyTopGap: 8,
        bodyBottomInset: 4,
        headlineLineHeightScale: 0.9,
        headlineMinSize: 14,
        headlineMaxSize: 34,
        headlineMaxHeightFraction: 0.12,
        bodyFontSize: 12,
        pullquoteFontSize: 13
    )

    static func profile(
        for pageWidth: Double,
        presentation: OrbEditorialPresentation = .standard
    ) -> OrbEditorialLayoutProfile {
        if presentation == .watch {
            return watchProfile
        }

        return pageWidth <= 640 ? compactProfile : regularProfile
    }

    static func statsBarHeight(for pageWidth: Double) -> Double {
        pageWidth <= 220 ? watchStatsBarHeight : standardStatsBarHeight
    }

    static func bodyFontDescriptor(size: Double) -> FontDescriptor {
        FontDescriptor(
            familyName: "Iowan Old Style",
            size: size
        )
    }

    static func pullquoteFontDescriptor(size: Double) -> FontDescriptor {
        FontDescriptor(
            familyName: "Iowan Old Style",
            size: size,
            symbolicTraits: .traitItalic
        )
    }

    static func bodyFont(size: Double) -> CTFont {
        bodyFontDescriptor(size: size).makeCTFont()
    }

    static func pullquoteFont(size: Double) -> CTFont {
        pullquoteFontDescriptor(size: size).makeCTFont()
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

    static func dropCapFont(size: Double) -> CTFont {
        FontDescriptor(
            familyName: "Iowan Old Style",
            size: size,
            symbolicTraits: .traitBold,
            weightValue: 0.4
        )
        .makeCTFont()
    }
}

struct OrbEditorialLayoutProfile: Hashable {
    var cacheKey: String
    var gutter: Double
    var columnGap: Double
    var dropCapLines: Int
    var bodyLineHeight: Double
    var pullquoteLineHeight: Double
    var bodyTopGap: Double
    var bodyBottomInset: Double
    var headlineLineHeightScale: Double
    var headlineMinSize: Int
    var headlineMaxSize: Int
    var headlineMaxHeightFraction: Double
    var bodyFontSize: Double
    var pullquoteFontSize: Double

    var dropCapSize: Double {
        bodyLineHeight * Double(dropCapLines) - 4
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
    var bodyFontSize: Double
    var bodyLineHeight: Double
    var pullquoteFontSize: Double
    var pullquoteLineHeight: Double
    var dropCapSize: Double
    var bodyLines: [PositionedLine]
    var pullquotes: [OrbEditorialPullquoteBlock]
    var dropCapRect: WrapRect
    var dropCapPosition: WrapPoint
    var columnCount: Int
    var contentBottom: Double
    var bodyExhausted: Bool
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
    static let bodyStartCursor = LayoutCursor(segmentIndex: 0, graphemeIndex: 1)
    static let dropCapCharacter = String(OrbEditorialText.body.prefix(1))

    nonisolated(unsafe) private static var bodyPreparedCache: [String: PreparedText] = [:]
    nonisolated(unsafe) private static var pullquotePreparedCache: [String: [PreparedText]] = [:]
    nonisolated(unsafe) private static var dropCapPreparedCache: [String: PreparedText] = [:]
    nonisolated(unsafe) private static var dropCapTotalWidthCache: [String: Double] = [:]
    nonisolated(unsafe) private static var headlinePreparedCache: [Int: PreparedText] = [:]
    nonisolated(unsafe) private static var fittedHeadlineCache: [String: (fontSize: Double, lineHeight: Double, lines: [PositionedLine])] = [:]

    static func preparedBody(for profile: OrbEditorialLayoutProfile) -> PreparedText {
        if let cached = bodyPreparedCache[profile.cacheKey] {
            return cached
        }

        let prepared = prepareWithSegments(
            OrbEditorialText.body,
            font: OrbEditorialMetrics.bodyFont(size: profile.bodyFontSize)
        )
        bodyPreparedCache[profile.cacheKey] = prepared
        return prepared
    }

    static func preparedPullquotes(for profile: OrbEditorialLayoutProfile) -> [PreparedText] {
        if let cached = pullquotePreparedCache[profile.cacheKey] {
            return cached
        }

        let prepared = OrbEditorialText.pullquotes.map {
            prepareWithSegments($0, font: OrbEditorialMetrics.pullquoteFont(size: profile.pullquoteFontSize))
        }
        pullquotePreparedCache[profile.cacheKey] = prepared
        return prepared
    }

    static func dropCapPrepared(for profile: OrbEditorialLayoutProfile) -> PreparedText {
        if let cached = dropCapPreparedCache[profile.cacheKey] {
            return cached
        }

        let prepared = prepareWithSegments(
            dropCapCharacter,
            font: OrbEditorialMetrics.dropCapFont(size: profile.dropCapSize)
        )
        dropCapPreparedCache[profile.cacheKey] = prepared
        return prepared
    }

    static func dropCapTotalWidth(for profile: OrbEditorialLayoutProfile) -> Double {
        if let cached = dropCapTotalWidthCache[profile.cacheKey] {
            return cached
        }

        let width = ceil(singleLineWidth(dropCapPrepared(for: profile))) + 10
        dropCapTotalWidthCache[profile.cacheKey] = width
        return width
    }

    static func preparedHeadline(size: Int) -> PreparedText {
        if let cached = headlinePreparedCache[size] {
            return cached
        }

        let prepared = prepareWithSegments(OrbEditorialText.headline, font: OrbEditorialMetrics.headlineFont(size: Double(size)))
        headlinePreparedCache[size] = prepared
        return prepared
    }

    static func cachedHeadline(
        profile: OrbEditorialLayoutProfile,
        maxWidth: Double,
        maxHeight: Double
    ) -> (fontSize: Double, lineHeight: Double, lines: [PositionedLine])? {
        fittedHeadlineCache[headlineCacheKey(profile: profile, maxWidth: maxWidth, maxHeight: maxHeight)]
    }

    static func storeHeadline(
        profile: OrbEditorialLayoutProfile,
        maxWidth: Double,
        maxHeight: Double,
        value: (fontSize: Double, lineHeight: Double, lines: [PositionedLine])
    ) {
        fittedHeadlineCache[headlineCacheKey(profile: profile, maxWidth: maxWidth, maxHeight: maxHeight)] = value
    }

    private static func headlineCacheKey(
        profile: OrbEditorialLayoutProfile,
        maxWidth: Double,
        maxHeight: Double
    ) -> String {
        "\(profile.cacheKey):\(maxWidth.rounded()):\(maxHeight.rounded())"
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
    compositionHeight: Double? = nil,
    orbs: [OrbState],
    presentation: OrbEditorialPresentation = .standard
) -> OrbEditorialSnapshot {
    let start = CFAbsoluteTimeGetCurrent()
    let profile = OrbEditorialMetrics.profile(for: pageWidth, presentation: presentation)
    let gutter = profile.gutter
    let bottomChromeHeight = presentation.bottomChromeHeight
    let resolvedCompositionHeight = min(max(compositionHeight ?? pageHeight, 1), pageHeight)
    let headlineWidth = min(pageWidth - gutter * 2, 1000)
    let headlineMaxHeight = floor(resolvedCompositionHeight * profile.headlineMaxHeightFraction)
    let headline = fitOrbHeadline(maxWidth: headlineWidth, maxHeight: headlineMaxHeight, profile: profile)
    let positionedHeadlineLines = headline.lines.map {
        PositionedLine(
            x: gutter + $0.x,
            y: gutter + $0.y,
            width: $0.width,
            text: $0.text
        )
    }

    let headlineHeight = Double(positionedHeadlineLines.count) * headline.lineHeight
    let bodyTop = gutter + headlineHeight + profile.bodyTopGap
    let compositionBodyHeight = max(
        0,
        resolvedCompositionHeight - bodyTop - bottomChromeHeight - profile.bodyBottomInset
    )
    let bodyHeight = max(0, pageHeight - bodyTop - bottomChromeHeight - profile.bodyBottomInset)
    let columnCount = orbEditorialColumnCount(for: pageWidth)
    let totalGutter = gutter * 2 + profile.columnGap * Double(columnCount - 1)
    let contentWidth = min(pageWidth, OrbEditorialMetrics.maxContentWidth)
    let columnWidth = floor((contentWidth - totalGutter) / Double(columnCount))
    let contentLeft = round(
        (pageWidth - (Double(columnCount) * columnWidth + Double(columnCount - 1) * profile.columnGap)) / 2
    )
    let firstColumnX = contentLeft
    let dropCapRect = if presentation.includesDropCap {
        WrapRect(
            x: firstColumnX - 2,
            y: bodyTop - 2,
            width: OrbEditorialAssets.dropCapTotalWidth(for: profile),
            height: Double(profile.dropCapLines) * profile.bodyLineHeight + 2
        )
    } else {
        WrapRect(x: firstColumnX, y: bodyTop, width: 0, height: 0)
    }
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

    let placements: [OrbPullquotePlacement] = if presentation.includesPullquotes {
        [
            OrbPullquotePlacement(columnIndex: 0, yFraction: 0.48, widthFraction: 0.52, side: .right),
            OrbPullquotePlacement(columnIndex: min(1, columnCount - 1), yFraction: 0.32, widthFraction: 0.5, side: .left),
        ]
    } else {
        []
    }

    var pullquotes: [OrbEditorialPullquoteBlock] = []
    for (index, placement) in placements.enumerated() {
        if placement.columnIndex >= columnCount {
            continue
        }

        let pullquoteWidth = round(columnWidth * placement.widthFraction)
        let columnX = contentLeft + Double(placement.columnIndex) * (columnWidth + profile.columnGap)
        let pullquoteX = placement.side == .right ? columnX + columnWidth - pullquoteWidth : columnX
        let pullquoteY = round(bodyTop + compositionBodyHeight * placement.yFraction)
        var prepared = OrbEditorialAssets.preparedPullquotes(for: profile)[index]
        let layoutResult = layout(&prepared, maxWidth: pullquoteWidth - 20, lineHeight: profile.pullquoteLineHeight)
        let (_, rawLines) = layoutWithLines(
            &prepared,
            maxWidth: pullquoteWidth - 20,
            lineHeight: profile.pullquoteLineHeight
        )
        let positionedLines = rawLines.enumerated().map { lineIndex, line in
            PositionedLine(
                x: pullquoteX + 20,
                y: pullquoteY + 8 + Double(lineIndex) * profile.pullquoteLineHeight,
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
    var cursor = presentation.bodyStartCursor
    var preparedBody = OrbEditorialAssets.preparedBody(for: profile)
    for columnIndex in 0..<columnCount {
        let columnX = contentLeft + Double(columnIndex) * (columnWidth + profile.columnGap)
        var rectObstacles: [WrapRect] = []
        if columnIndex == 0, presentation.includesDropCap {
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
            lineHeight: profile.bodyLineHeight,
            circleObstacles: circleObstacles,
            rectObstacles: rectObstacles
        )
        bodyLines.append(contentsOf: result.lines)
        cursor = result.cursor
    }

    let bodyExhausted = layoutNextLine(preparedBody, start: cursor, maxWidth: columnWidth) == nil
    let headlineBottom = positionedHeadlineLines.map { $0.y + headline.lineHeight }.max() ?? gutter
    let bodyBottom = bodyLines.map { $0.y + profile.bodyLineHeight }.max() ?? bodyTop
    let pullquoteBottom = pullquotes.map { $0.rect.y + $0.rect.height }.max() ?? 0
    let contentBottom = max(headlineBottom, bodyBottom, pullquoteBottom, dropCapRect.y + dropCapRect.height)
    let reflowMilliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000
    return OrbEditorialSnapshot(
        headlineLines: positionedHeadlineLines,
        headlineFontSize: headline.fontSize,
        headlineLineHeight: headline.lineHeight,
        bodyFontSize: profile.bodyFontSize,
        bodyLineHeight: profile.bodyLineHeight,
        pullquoteFontSize: profile.pullquoteFontSize,
        pullquoteLineHeight: profile.pullquoteLineHeight,
        dropCapSize: profile.dropCapSize,
        bodyLines: bodyLines,
        pullquotes: pullquotes,
        dropCapRect: dropCapRect,
        dropCapPosition: dropCapPosition,
        columnCount: columnCount,
        contentBottom: contentBottom,
        bodyExhausted: bodyExhausted,
        reflowMilliseconds: reflowMilliseconds
    )
}

func orbEditorialPhoneContentHeight(
    viewportWidth: Double,
    viewportHeight: Double,
    orbs: [OrbState],
    presentation: OrbEditorialPresentation = .standard
) -> Double {
    let profile = OrbEditorialMetrics.profile(for: viewportWidth, presentation: presentation)
    var pageHeight = max(viewportHeight * 2, 2000)

    for _ in 0..<8 {
        let snapshot = evaluateOrbEditorialLayout(
            pageWidth: viewportWidth,
            pageHeight: pageHeight,
            compositionHeight: viewportHeight,
            orbs: orbs,
            presentation: presentation
        )
        let paddedBottom = snapshot.contentBottom + presentation.bottomChromeHeight + profile.gutter

        if snapshot.bodyExhausted {
            return max(pageHeight, paddedBottom)
        }

        pageHeight = max(pageHeight * 1.5, paddedBottom + viewportHeight)
    }

    return pageHeight
}

private func fitOrbHeadline(
    maxWidth: Double,
    maxHeight: Double,
    profile: OrbEditorialLayoutProfile
) -> (fontSize: Double, lineHeight: Double, lines: [PositionedLine]) {
    if let cached = OrbEditorialAssets.cachedHeadline(profile: profile, maxWidth: maxWidth, maxHeight: maxHeight) {
        return cached
    }

    var low = profile.headlineMinSize
    var high = profile.headlineMaxSize
    var bestSize = low
    var bestLineHeight = round(Double(low) * profile.headlineLineHeightScale)
    var bestLines: [PositionedLine] = []

    while low <= high {
        let size = Int(floor(Double(low + high) / 2))
        let lineHeight = round(Double(size) * profile.headlineLineHeightScale)
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
    OrbEditorialAssets.storeHeadline(profile: profile, maxWidth: maxWidth, maxHeight: maxHeight, value: result)
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
