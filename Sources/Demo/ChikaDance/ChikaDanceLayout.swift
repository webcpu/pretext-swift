import CoreText
import Foundation
import Pretext

enum ChikaDanceMetrics {
    static let gutter = 48.0
    static let columnGap = 40.0
    static let statsBarHeight = 42.0
    static let bodyLineHeight = 28.0
    static let dropCapLines = 3
    static let dropCapSize = bodyLineHeight * Double(dropCapLines) - 4
    static let minSlotWidth = 50.0
    static let characterHPad = 20.0
    static let characterVPad = 6.0

    static let bodyFontDescriptor = FontDescriptor(
        familyName: "Iowan Old Style",
        size: 18
    )

    static func bodyFont() -> CTFont {
        bodyFontDescriptor.makeCTFont()
    }

    static func dropCapFont() -> CTFont {
        FontDescriptor(
            familyName: "Iowan Old Style",
            size: dropCapSize,
            symbolicTraits: .traitBold,
            weightValue: 0.4
        ).makeCTFont()
    }
}

enum ChikaDancePalette {
    static let background = Color(red: 12 / 255, green: 10 / 255, blue: 18 / 255)
    static let bodyText = Color(red: 232 / 255, green: 228 / 255, blue: 220 / 255)
    static let dropCap = Color(red: 255 / 255, green: 140 / 255, blue: 180 / 255)
    static let statsBarBackground = Color(red: 6 / 255, green: 6 / 255, blue: 10 / 255).opacity(0.88)
    static let statsLabel = Color.white.opacity(0.35)
    static let statsValue = Color.white.opacity(0.7)
    static let statsBorder = Color.white.opacity(0.06)
}

import SwiftUI

struct ChikaDanceSnapshot: Equatable {
    var bodyLines: [PositionedLine]
    var dropCapRect: WrapRect
    var dropCapPosition: WrapPoint
    var columnCount: Int
    var reflowMilliseconds: Double
    var characterRect: WrapRect
}

private enum ChikaDanceAssets {
    static let bodyPrepared = prepareWithSegments(OrbEditorialText.body, font: ChikaDanceMetrics.bodyFont())
    static let bodyStartCursor = LayoutCursor(segmentIndex: 0, graphemeIndex: 1)
    static let dropCapCharacter = String(OrbEditorialText.body.prefix(1))
    static let dropCapPrepared = prepareWithSegments(dropCapCharacter, font: ChikaDanceMetrics.dropCapFont())
    static let dropCapTotalWidth = ceil(singleLineWidth(dropCapPrepared)) + 10
}

func evaluateChikaDanceLayout(
    pageWidth: Double,
    pageHeight: Double,
    characterHull: [WrapPoint],
    characterRect: WrapRect
) -> ChikaDanceSnapshot {
    let start = CFAbsoluteTimeGetCurrent()
    let gutter = ChikaDanceMetrics.gutter
    let bodyTop = gutter
    let bodyHeight = max(0, pageHeight - bodyTop - ChikaDanceMetrics.statsBarHeight - 8)

    let columnCount = pageWidth > 640 ? 2 : 1
    let totalGutter = gutter * 2 + ChikaDanceMetrics.columnGap * Double(columnCount - 1)
    let columnWidth = floor((pageWidth - totalGutter) / Double(columnCount))
    let contentLeft = round(
        (pageWidth - (Double(columnCount) * columnWidth + Double(columnCount - 1) * ChikaDanceMetrics.columnGap)) / 2
    )

    let dropCapRect = WrapRect(
        x: contentLeft - 2,
        y: bodyTop - 2,
        width: ChikaDanceAssets.dropCapTotalWidth,
        height: Double(ChikaDanceMetrics.dropCapLines) * ChikaDanceMetrics.bodyLineHeight + 2
    )
    let dropCapPosition = WrapPoint(x: contentLeft, y: bodyTop)

    // Transform hull to screen coordinates
    let screenHull = transformWrapPoints(characterHull, rect: characterRect, angle: 0)

    var bodyLines: [PositionedLine] = []
    var cursor = ChikaDanceAssets.bodyStartCursor
    var preparedBody = ChikaDanceAssets.bodyPrepared

    for columnIndex in 0..<columnCount {
        let columnX = contentLeft + Double(columnIndex) * (columnWidth + ChikaDanceMetrics.columnGap)
        var rectObstacles: [WrapRect] = []
        if columnIndex == 0 {
            rectObstacles.append(dropCapRect)
        }

        let result = layoutChikaDanceColumn(
            prepared: &preparedBody,
            startCursor: cursor,
            regionX: columnX,
            regionY: bodyTop,
            regionWidth: columnWidth,
            regionHeight: bodyHeight,
            lineHeight: ChikaDanceMetrics.bodyLineHeight,
            characterHull: screenHull,
            rectObstacles: rectObstacles
        )
        bodyLines.append(contentsOf: result.lines)
        cursor = result.cursor
    }

    let reflowMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
    return ChikaDanceSnapshot(
        bodyLines: bodyLines,
        dropCapRect: dropCapRect,
        dropCapPosition: dropCapPosition,
        columnCount: columnCount,
        reflowMilliseconds: reflowMs,
        characterRect: characterRect
    )
}

private func layoutChikaDanceColumn(
    prepared: inout PreparedText,
    startCursor: LayoutCursor,
    regionX: Double,
    regionY: Double,
    regionWidth: Double,
    regionHeight: Double,
    lineHeight: Double,
    characterHull: [WrapPoint],
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

        if let interval = getPolygonIntervalForBand(
            points: characterHull,
            bandTop: bandTop,
            bandBottom: bandBottom,
            hPad: ChikaDanceMetrics.characterHPad,
            vPad: ChikaDanceMetrics.characterVPad
        ) {
            blocked.append(interval)
        }

        for rect in rectObstacles {
            if bandBottom <= rect.y || bandTop >= rect.y + rect.height { continue }
            blocked.append(WrapInterval(left: rect.x, right: rect.x + rect.width))
        }

        let slots = carveTextLineSlots(
            base: WrapInterval(left: regionX, right: regionX + regionWidth),
            blocked: blocked,
            minimumWidth: ChikaDanceMetrics.minSlotWidth
        ).sorted { $0.left < $1.left }

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
            lines.append(PositionedLine(
                x: round(slot.left),
                y: round(lineTop),
                width: line.width,
                text: line.text
            ))
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
