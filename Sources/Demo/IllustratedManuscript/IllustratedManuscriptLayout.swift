import Foundation
import Pretext

struct IllustratedManuscriptPageMetrics: Equatable {
    var pageRect: WrapRect
    var margin: Double
    var fontSize: Double
    var lineHeight: Double
    var scale: Double
}

struct IllustratedManuscriptSnapshot: Equatable {
    var pageMetrics: IllustratedManuscriptPageMetrics
    var dropCapCharacter: String
    var dropCapRect: WrapRect
    var dropCapDrawRect: WrapRect
    var lineTextInset: Double
    var bodyLines: [PositionedLine]
    var dragonWrapHull: [WrapPoint]
    var dragonWrapHorizontalPadding: Double
    var dragonWrapVerticalPadding: Double
    var dragonState: IllustratedDragonState
}

func illustratedManuscriptPageMetrics(
    viewportWidth: Double,
    viewportHeight: Double
) -> IllustratedManuscriptPageMetrics {
    let pageWidth = min(IllustratedManuscriptConstants.basePageWidth, viewportWidth - 40)
    let scale = pageWidth / IllustratedManuscriptConstants.basePageWidth
    let pageHeight = min(IllustratedManuscriptConstants.maxPageHeight, viewportHeight - 60)
    let margin = round(IllustratedManuscriptConstants.baseMargin * scale)
    let fontScale = 0.4 + 0.6 * scale
    let fontSize = max(14.0, round(IllustratedManuscriptConstants.baseFontSize * fontScale))
    let lineHeight = max(22.0, round(IllustratedManuscriptConstants.baseLineHeight * fontScale))

    return IllustratedManuscriptPageMetrics(
        pageRect: WrapRect(
            x: round((viewportWidth - pageWidth) / 2),
            y: round(max(20, (viewportHeight - pageHeight) / 2)),
            width: pageWidth,
            height: pageHeight
        ),
        margin: margin,
        fontSize: fontSize,
        lineHeight: lineHeight,
        scale: scale
    )
}

func evaluateIllustratedManuscriptSnapshot(
    viewportWidth: Double,
    viewportHeight: Double,
    dragonState: IllustratedDragonState
) -> IllustratedManuscriptSnapshot {
    let metrics = illustratedManuscriptPageMetrics(
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight
    )
    let dropCap = IllustratedManuscriptAssets.dropCapGeometry(
        pageRect: metrics.pageRect,
        margin: metrics.margin,
        lineHeight: metrics.lineHeight
    )
    let dragonHull = illustratedDragonWrapHull(for: dragonState)
    let lineTextInset = IllustratedManuscriptAssets.lineTextInset(
        fontSize: metrics.fontSize,
        lineHeight: metrics.lineHeight
    )

    var preparedBody = IllustratedManuscriptAssets.preparedStory(fontSize: metrics.fontSize)
    var cursor = IllustratedManuscriptAssets.bodyStartCursor
    let baseSlot = WrapInterval(
        left: metrics.pageRect.minX + metrics.margin,
        right: metrics.pageRect.maxX - metrics.margin
    )

    var bodyLines: [PositionedLine] = []
    var lineTop = metrics.pageRect.minY + metrics.margin

    while lineTop + metrics.lineHeight <= metrics.pageRect.maxY - metrics.margin {
        var blocked = getRectIntervalsForBand(
            rects: [dropCap.obstacleRect],
            bandTop: lineTop,
            bandBottom: lineTop + metrics.lineHeight,
            hPad: 0,
            vPad: 0
        )

        if let dragonInterval = getPolygonIntervalForBand(
            points: dragonHull,
            bandTop: lineTop,
            bandBottom: lineTop + metrics.lineHeight,
            hPad: illustratedDragonWrapHorizontalPadding(),
            vPad: illustratedDragonWrapVerticalPadding()
        ) {
            blocked.append(dragonInterval)
        }

        for particle in dragonState.fire {
            if let interval = circleIntervalForBand(
                cx: particle.x,
                cy: particle.y,
                r: particle.size / 2,
                bandTop: lineTop,
                bandBottom: lineTop + metrics.lineHeight,
                hPad: illustratedDragonFireWrapPadding(),
                vPad: illustratedDragonFireWrapPadding()
            ) {
                blocked.append(interval)
            }
        }

        let slots = carveTextLineSlots(
            base: baseSlot,
            blocked: blocked,
            minimumWidth: 40
        ).sorted { $0.left < $1.left }

        if slots.isEmpty {
            lineTop += metrics.lineHeight
            continue
        }

        var exhausted = false
        for slot in slots {
            guard let line = layoutNextLine(&preparedBody, start: cursor, maxWidth: slot.right - slot.left) else {
                exhausted = true
                break
            }
            if line.end == cursor {
                exhausted = true
                break
            }

            bodyLines.append(
                PositionedLine(
                    x: round(slot.left),
                    y: round(lineTop),
                    width: line.width,
                    text: line.text
                )
            )
            cursor = line.end
        }

        if exhausted {
            break
        }

        lineTop += metrics.lineHeight
    }

    return IllustratedManuscriptSnapshot(
        pageMetrics: metrics,
        dropCapCharacter: IllustratedManuscriptAssets.dropCapCharacter,
        dropCapRect: dropCap.obstacleRect,
        dropCapDrawRect: dropCap.drawRect,
        lineTextInset: lineTextInset,
        bodyLines: bodyLines,
        dragonWrapHull: dragonHull,
        dragonWrapHorizontalPadding: illustratedDragonWrapHorizontalPadding(),
        dragonWrapVerticalPadding: illustratedDragonWrapVerticalPadding(),
        dragonState: dragonState
    )
}
