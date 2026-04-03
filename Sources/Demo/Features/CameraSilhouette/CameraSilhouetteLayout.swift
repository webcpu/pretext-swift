import CoreText
import CoreGraphics
import Foundation
import Pretext

struct CameraSilhouetteNormalizedSpan: Equatable, Sendable {
    var minX: Double
    var maxX: Double
}

struct CameraSilhouetteMaskRow: Equatable, Sendable {
    var minY: Double
    var maxY: Double
    var occupied: [CameraSilhouetteNormalizedSpan]
}

struct CameraSilhouettePageMetrics: Equatable {
    var pageRect: WrapRect
    var pageRects: [WrapRect]
    var margin: Double
    var fontSize: Double
    var lineHeight: Double
    var minimumSlotWidth: Double

    var contentRects: [WrapRect] {
        pageRects.map { pageRect in
            WrapRect(
                x: pageRect.x + margin,
                y: pageRect.y + margin,
                width: max(0, pageRect.width - margin * 2),
                height: max(0, pageRect.height - margin * 2)
            )
        }
    }

    var contentRect: WrapRect {
        guard let firstRect = contentRects.first else {
            return WrapRect(x: pageRect.x, y: pageRect.y, width: 0, height: 0)
        }

        let minX = contentRects.map(\.minX).min() ?? firstRect.minX
        let maxX = contentRects.map(\.maxX).max() ?? firstRect.maxX
        let minY = contentRects.map(\.minY).min() ?? firstRect.minY
        let maxY = contentRects.map(\.maxY).max() ?? firstRect.maxY

        return WrapRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }
}

struct CameraSilhouetteBandSnapshot: Equatable {
    var top: Double
    var bottom: Double
    var blocked: [WrapInterval]
    var selectedSlots: [WrapInterval]
}

struct CameraSilhouetteSnapshot: Equatable {
    var pageMetrics: CameraSilhouettePageMetrics
    var lines: [PositionedLine]
    var bands: [CameraSilhouetteBandSnapshot]
    var usesFallbackLayout: Bool
}

private enum CameraSilhouetteLayoutDefaults {
    static let landscapeSpreadBreakpoint = 760.0
    static let landscapeOuterGutter = 52.0
    static let landscapeOuterGutterFraction = 0.048
    static let landscapeCenterGap = 28.0
    static let landscapeCenterGapFraction = 0.025
    static let minMargin = 20.0
    static let maxMargin = 28.0
    static let minFontSize = 14.0
    static let maxFontSize = 19.0
    static let minLineHeight = 22.0
    static let maxLineHeight = 30.0
    static let minimumSlotWidth = 72.0
    static let previewWidthFraction = 0.46
    static let previewMaxWidth = 210.0
    static let previewMinWidth = 160.0
    static let previewTopFraction = 0.15
    static let previewTopMinimum = 44.0
    static let previewBottomReserve = 88.0
    static let previewAspectRatio = 9.0 / 16.0
    static let bodyFontDescriptor = FontDescriptor(
        familyName: "Iowan Old Style",
        size: maxFontSize,
        weightValue: 0.1
    )
}

private struct CameraSilhouettePreparedCacheKey: Hashable {
    var article: String
    var fontSizeKey: Int
}

private enum CameraSilhouetteLayoutAssets {
    nonisolated(unsafe) private static var fontCache: [Int: CTFont] = [:]
    nonisolated(unsafe) private static var preparedCache: [CameraSilhouettePreparedCacheKey: PreparedText] = [:]

    static func bodyFont(size: Double) -> CTFont {
        let cacheKey = Int(round(size * 10))
        if let cached = fontCache[cacheKey] {
            return cached
        }

        let font = FontDescriptor(
            familyName: CameraSilhouetteLayoutDefaults.bodyFontDescriptor.familyName,
            size: size,
            weightValue: CameraSilhouetteLayoutDefaults.bodyFontDescriptor.weightValue
        ).makeCTFont()
        fontCache[cacheKey] = font
        return font
    }

    static func preparedArticle(_ article: String, fontSize: Double) -> PreparedText {
        let cacheKey = CameraSilhouettePreparedCacheKey(
            article: article,
            fontSizeKey: Int(round(fontSize * 10))
        )
        if let cached = preparedCache[cacheKey] {
            return cached
        }

        let prepared = prepare(article, font: bodyFont(size: fontSize))
        preparedCache[cacheKey] = prepared
        return prepared
    }
}

func cameraSilhouettePageMetrics(
    viewportWidth: Double,
    viewportHeight: Double,
    topInset: Double = 0,
    bottomInset: Double = 0
) -> CameraSilhouettePageMetrics {
    let pageWidth = max(0, viewportWidth)
    let pageHeight = max(0, viewportHeight - topInset - bottomInset)
    let pageY = round(topInset)
    let usesLandscapeSpread = pageWidth >= CameraSilhouetteLayoutDefaults.landscapeSpreadBreakpoint && pageWidth > pageHeight
    let pageRects: [WrapRect]
    let layoutWidth: Double

    if usesLandscapeSpread {
        let outerGutter = round(
            max(
                CameraSilhouetteLayoutDefaults.landscapeOuterGutter,
                pageWidth * CameraSilhouetteLayoutDefaults.landscapeOuterGutterFraction
            )
        )
        let centerGap = round(
            max(
                CameraSilhouetteLayoutDefaults.landscapeCenterGap,
                pageWidth * CameraSilhouetteLayoutDefaults.landscapeCenterGapFraction
            )
        )
        let singlePageWidth = max(0, round((pageWidth - outerGutter * 2 - centerGap) / 2))
        let leftPageX = outerGutter
        let rightPageX = pageWidth - outerGutter - singlePageWidth

        pageRects = [
            WrapRect(x: leftPageX, y: pageY, width: singlePageWidth, height: pageHeight),
            WrapRect(x: rightPageX, y: pageY, width: singlePageWidth, height: pageHeight),
        ]
        layoutWidth = singlePageWidth
    } else {
        pageRects = [
            WrapRect(x: 0, y: pageY, width: pageWidth, height: pageHeight)
        ]
        layoutWidth = pageWidth
    }

    let scale = min(1, max(0.55, layoutWidth / 390))
    let margin = round(
        min(
            CameraSilhouetteLayoutDefaults.maxMargin,
            max(CameraSilhouetteLayoutDefaults.minMargin, 18 + 10 * scale)
        )
    )
    let fontSize = round(
        max(
            CameraSilhouetteLayoutDefaults.minFontSize,
            CameraSilhouetteLayoutDefaults.minFontSize
                + (CameraSilhouetteLayoutDefaults.maxFontSize - CameraSilhouetteLayoutDefaults.minFontSize) * scale
        )
    )
    let lineHeight = round(
        max(
            CameraSilhouetteLayoutDefaults.minLineHeight,
            CameraSilhouetteLayoutDefaults.minLineHeight
                + (CameraSilhouetteLayoutDefaults.maxLineHeight - CameraSilhouetteLayoutDefaults.minLineHeight) * scale
        )
    )

    return CameraSilhouettePageMetrics(
        pageRect: WrapRect(
            x: 0,
            y: pageY,
            width: pageWidth,
            height: pageHeight
        ),
        pageRects: pageRects,
        margin: margin,
        fontSize: fontSize,
        lineHeight: lineHeight,
        minimumSlotWidth: CameraSilhouetteLayoutDefaults.minimumSlotWidth
    )
}

func cameraSilhouettePreviewFrame(
    viewportWidth: Double,
    viewportHeight: Double,
    topInset: Double = 0,
    bottomInset: Double = 0
) -> WrapRect {
    return WrapRect(
        x: 0,
        y: 0,
        width: max(0, viewportWidth),
        height: max(0, viewportHeight)
    )
}

func cameraSilhouetteBlockedIntervals(
    occupancy: [CameraSilhouetteNormalizedSpan],
    pageWidth: Double
) -> [WrapInterval] {
    cameraSilhouetteBlockedIntervals(
        occupancy: occupancy,
        contentRect: WrapRect(x: 0, y: 0, width: pageWidth, height: 1)
    )
}

func cameraSilhouetteBlockedIntervals(
    occupancy: [CameraSilhouetteNormalizedSpan],
    contentRect: WrapRect
) -> [WrapInterval] {
    let intervals = occupancy.compactMap { span -> WrapInterval? in
        let left = max(contentRect.minX, min(contentRect.maxX, contentRect.x + span.minX * contentRect.width))
        let right = max(contentRect.minX, min(contentRect.maxX, contentRect.x + span.maxX * contentRect.width))
        guard right > left else {
            return nil
        }
        return WrapInterval(left: left, right: right)
    }

    return mergeCameraSilhouetteIntervals(intervals)
}

func cameraSilhouetteAspectFillRect(
    sourceSize: CGSize,
    viewportSize: CGSize
) -> WrapRect {
    guard
        sourceSize.width > 0,
        sourceSize.height > 0,
        viewportSize.width > 0,
        viewportSize.height > 0
    else {
        return WrapRect(x: 0, y: 0, width: viewportSize.width, height: viewportSize.height)
    }

    let widthScale = viewportSize.width / sourceSize.width
    let heightScale = viewportSize.height / sourceSize.height
    let scale = max(widthScale, heightScale)
    let drawnWidth = sourceSize.width * scale
    let drawnHeight = sourceSize.height * scale

    return WrapRect(
        x: (viewportSize.width - drawnWidth) / 2,
        y: (viewportSize.height - drawnHeight) / 2,
        width: drawnWidth,
        height: drawnHeight
    )
}

func cameraSilhouetteAspectFitRect(
    sourceSize: CGSize,
    viewportSize: CGSize
) -> WrapRect {
    guard
        sourceSize.width > 0,
        sourceSize.height > 0,
        viewportSize.width > 0,
        viewportSize.height > 0
    else {
        return WrapRect(x: 0, y: 0, width: viewportSize.width, height: viewportSize.height)
    }

    let widthScale = viewportSize.width / sourceSize.width
    let heightScale = viewportSize.height / sourceSize.height
    let scale = min(widthScale, heightScale)
    let drawnWidth = sourceSize.width * scale
    let drawnHeight = sourceSize.height * scale

    return WrapRect(
        x: (viewportSize.width - drawnWidth) / 2,
        y: (viewportSize.height - drawnHeight) / 2,
        width: drawnWidth,
        height: drawnHeight
    )
}

func projectCameraSilhouetteRows(
    _ rows: [CameraSilhouetteMaskRow],
    from sourceRect: WrapRect,
    into targetRect: WrapRect
) -> [CameraSilhouetteMaskRow] {
    guard targetRect.width > 0, targetRect.height > 0 else {
        return []
    }

    return rows.compactMap { row in
        let sourceTop = sourceRect.y + row.minY * sourceRect.height
        let sourceBottom = sourceRect.y + row.maxY * sourceRect.height
        let clippedTop = max(sourceTop, targetRect.minY)
        let clippedBottom = min(sourceBottom, targetRect.maxY)

        guard clippedBottom > clippedTop else {
            return nil
        }

        let projectedSpans = row.occupied.compactMap { span -> CameraSilhouetteNormalizedSpan? in
            let sourceLeft = sourceRect.x + span.minX * sourceRect.width
            let sourceRight = sourceRect.x + span.maxX * sourceRect.width
            let clippedLeft = max(sourceLeft, targetRect.minX)
            let clippedRight = min(sourceRight, targetRect.maxX)

            guard clippedRight > clippedLeft else {
                return nil
            }

            return CameraSilhouetteNormalizedSpan(
                minX: (clippedLeft - targetRect.x) / targetRect.width,
                maxX: (clippedRight - targetRect.x) / targetRect.width
            )
        }

        guard !projectedSpans.isEmpty else {
            return nil
        }

        return CameraSilhouetteMaskRow(
            minY: (clippedTop - targetRect.y) / targetRect.height,
            maxY: (clippedBottom - targetRect.y) / targetRect.height,
            occupied: projectedSpans
        )
    }
}

func cameraSilhouetteOpenSlots(
    base: WrapInterval,
    blocked: [WrapInterval],
    minimumWidth: Double
) -> [WrapInterval] {
    let preferredSlots = carveTextLineSlots(
        base: base,
        blocked: blocked,
        minimumWidth: minimumWidth
    )
    if !preferredSlots.isEmpty {
        return preferredSlots.sorted(by: cameraSilhouetteSlotStartsEarlier)
    }

    let fallbackMinimumWidth = max(40, minimumWidth * 0.55)
    return carveTextLineSlots(
        base: base,
        blocked: blocked,
        minimumWidth: fallbackMinimumWidth
    )
    .sorted(by: cameraSilhouetteSlotStartsEarlier)
}

private func cameraSilhouetteSlotStartsEarlier(
    _ lhs: WrapInterval,
    _ rhs: WrapInterval
) -> Bool {
    if lhs.left == rhs.left {
        return lhs.right < rhs.right
    }
    return lhs.left < rhs.left
}

func evaluateCameraSilhouetteSnapshot(
    article: String,
    viewportWidth: Double,
    viewportHeight: Double,
    topInset: Double = 0,
    bottomInset: Double = 0,
    silhouetteRows: [CameraSilhouetteMaskRow]
) -> CameraSilhouetteSnapshot {
    let metrics = cameraSilhouettePageMetrics(
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        topInset: topInset,
        bottomInset: bottomInset
    )
    let spreadContentRect = metrics.contentRect
    let effectiveRows = silhouetteRows.filter { !$0.occupied.isEmpty }

    var preparedArticle = CameraSilhouetteLayoutAssets.preparedArticle(
        article,
        fontSize: metrics.fontSize
    )
    var cursor = LayoutCursor.start
    var lines: [PositionedLine] = []
    var bands: [CameraSilhouetteBandSnapshot] = []
    var encounteredBlockedBand = false

layoutLoop:
    for contentRect in metrics.contentRects {
        let baseSlot = WrapInterval(left: contentRect.minX, right: contentRect.maxX)
        var lineTop = contentRect.minY

        while lineTop + metrics.lineHeight <= contentRect.maxY {
            let bandBottom = lineTop + metrics.lineHeight
            let blocked = clipCameraSilhouetteIntervals(
                cameraSilhouetteBlockedIntervals(
                    rows: effectiveRows,
                    bandTop: lineTop,
                    bandBottom: bandBottom,
                    contentRect: spreadContentRect
                ),
                to: baseSlot
            )
            let selectedSlots: [WrapInterval]

            if blocked.isEmpty {
                selectedSlots = [baseSlot]
            } else {
                encounteredBlockedBand = true
                selectedSlots = cameraSilhouetteOpenSlots(
                    base: baseSlot,
                    blocked: blocked,
                    minimumWidth: metrics.minimumSlotWidth
                )
            }

            let roundedTop = round(lineTop)
            bands.append(
                CameraSilhouetteBandSnapshot(
                    top: roundedTop,
                    bottom: round(bandBottom),
                    blocked: blocked,
                    selectedSlots: selectedSlots
                )
            )

            guard !selectedSlots.isEmpty else {
                lineTop += metrics.lineHeight
                continue
            }

            for selectedSlot in selectedSlots {
                guard let line = layoutNextLine(
                    &preparedArticle,
                    start: cursor,
                    maxWidth: selectedSlot.right - selectedSlot.left
                ) else {
                    break layoutLoop
                }
                if line.end == cursor {
                    break layoutLoop
                }

                lines.append(
                    PositionedLine(
                        x: round(selectedSlot.left),
                        y: roundedTop,
                        width: line.width,
                        text: line.text
                    )
                )
                cursor = line.end
            }

            lineTop += metrics.lineHeight
        }
    }

    return CameraSilhouetteSnapshot(
        pageMetrics: metrics,
        lines: lines,
        bands: bands,
        usesFallbackLayout: !encounteredBlockedBand
    )
}

private func cameraSilhouetteBlockedIntervals(
    rows: [CameraSilhouetteMaskRow],
    bandTop: Double,
    bandBottom: Double,
    contentRect: WrapRect
) -> [WrapInterval] {
    let intervals = rows.flatMap { row -> [WrapInterval] in
        let rowTop = contentRect.y + row.minY * contentRect.height
        let rowBottom = contentRect.y + row.maxY * contentRect.height
        guard bandBottom > rowTop, bandTop < rowBottom else {
            return []
        }
        return cameraSilhouetteBlockedIntervals(
            occupancy: row.occupied,
            contentRect: contentRect
        )
    }

    return mergeCameraSilhouetteIntervals(intervals)
}

private func clipCameraSilhouetteIntervals(
    _ intervals: [WrapInterval],
    to base: WrapInterval
) -> [WrapInterval] {
    intervals.compactMap { interval in
        let left = max(base.left, interval.left)
        let right = min(base.right, interval.right)
        guard right > left else {
            return nil
        }
        return WrapInterval(left: left, right: right)
    }
}

private func mergeCameraSilhouetteIntervals(_ intervals: [WrapInterval]) -> [WrapInterval] {
    guard !intervals.isEmpty else {
        return []
    }

    let sorted = intervals.sorted { lhs, rhs in
        if lhs.left == rhs.left {
            return lhs.right < rhs.right
        }
        return lhs.left < rhs.left
    }

    var merged: [WrapInterval] = [sorted[0]]

    for interval in sorted.dropFirst() {
        let lastIndex = merged.index(before: merged.endIndex)
        if interval.left <= merged[lastIndex].right {
            merged[lastIndex].right = max(merged[lastIndex].right, interval.right)
        } else {
            merged.append(interval)
        }
    }

    return merged
}
