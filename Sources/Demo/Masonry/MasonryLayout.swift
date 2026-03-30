import Foundation
import Pretext
import PretextUI
import SwiftUI

enum MasonryMetrics {
    static let fontSize: Double = 15
    static let lineHeight: Double = 22
    static let cardPadding: Double = 16
    static let gap: Double = 12
    static let maxColWidth: Double = 400
    static let singleColumnMaxViewportWidth: Double = 520
    static let cardCornerRadius: Double = 8
    static let overscan: Double = 200

    static let cardFontDescriptor = FontDescriptor(
        familyName: "Helvetica Neue",
        size: fontSize
    )

    static func cardCTFont() -> CTFont {
        cardFontDescriptor.makeCTFont()
    }

    static func cardDisplayFont() -> Font {
        cardFontDescriptor.makeDisplayFont()
    }
}

enum MasonryPalette {
    static let background = Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255)
    static let cardBackground = Color.white
    static let cardText = Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255)
    static let cardShadowColor = Color.black.opacity(0.08)
}

struct PositionedCard: Sendable {
    var cardIndex: Int
    var x: Double
    var y: Double
    var height: Double
}

struct MasonryLayoutResult: Sendable {
    var colWidth: Double
    var colCount: Int
    var contentHeight: Double
    var positionedCards: [PositionedCard]
}

struct MasonryColumns: Sendable {
    var colCount: Int
    var colWidth: Double
    var offsetLeft: Double
}

func computeMasonryColumns(viewportWidth: Double) -> MasonryColumns {
    let gap = MasonryMetrics.gap
    let colCount: Int
    let colWidth: Double

    if viewportWidth <= MasonryMetrics.singleColumnMaxViewportWidth {
        colCount = 1
        colWidth = min(MasonryMetrics.maxColWidth, viewportWidth - gap * 2)
    } else {
        let minColWidth = 100 + viewportWidth * 0.1
        colCount = max(2, Int(floor((viewportWidth + gap) / (minColWidth + gap))))
        colWidth = min(
            MasonryMetrics.maxColWidth,
            (viewportWidth - Double(colCount + 1) * gap) / Double(colCount)
        )
    }

    let contentWidth = Double(colCount) * colWidth + Double(colCount - 1) * gap
    let offsetLeft = (viewportWidth - contentWidth) / 2

    return MasonryColumns(colCount: colCount, colWidth: colWidth, offsetLeft: offsetLeft)
}

func computeMasonryLayout(
    viewportWidth: Double,
    cardHeights: [Double]
) -> MasonryLayoutResult {
    let gap = MasonryMetrics.gap
    let columns = computeMasonryColumns(viewportWidth: viewportWidth)

    var colHeights = [Double](repeating: gap, count: columns.colCount)
    var positionedCards: [PositionedCard] = []
    positionedCards.reserveCapacity(cardHeights.count)

    for i in 0..<cardHeights.count {
        var shortest = 0
        for c in 1..<columns.colCount {
            if colHeights[c] < colHeights[shortest] {
                shortest = c
            }
        }

        let totalHeight = cardHeights[i]
        positionedCards.append(PositionedCard(
            cardIndex: i,
            x: columns.offsetLeft + Double(shortest) * (columns.colWidth + gap),
            y: colHeights[shortest],
            height: totalHeight
        ))

        colHeights[shortest] += totalHeight + gap
    }

    let contentHeight = colHeights.max() ?? 0

    return MasonryLayoutResult(
        colWidth: columns.colWidth,
        colCount: columns.colCount,
        contentHeight: contentHeight,
        positionedCards: positionedCards
    )
}

func computeCardHeights(
    prepared: [PreparedText],
    colWidth: Double
) -> [Double] {
    let textWidth = colWidth - MasonryMetrics.cardPadding * 2
    return prepared.map { p in
        let result = layout(p, maxWidth: textWidth, lineHeight: MasonryMetrics.lineHeight)
        return result.height + MasonryMetrics.cardPadding * 2
    }
}

func visibleCardIndices(
    from positionedCards: [PositionedCard],
    scrollOffset: Double,
    viewportHeight: Double,
    overscan: Double = MasonryMetrics.overscan
) -> [Int] {
    let viewTop = scrollOffset - overscan
    let viewBottom = scrollOffset + viewportHeight + overscan

    var indices: [Int] = []
    for i in 0..<positionedCards.count {
        let card = positionedCards[i]
        let cardBottom = card.y + card.height
        if cardBottom >= viewTop && card.y <= viewBottom {
            indices.append(i)
        }
    }
    return indices
}
