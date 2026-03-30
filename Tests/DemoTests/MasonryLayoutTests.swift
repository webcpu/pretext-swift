import XCTest
@testable import Demo

final class MasonryLayoutTests: XCTestCase {

    // MARK: - Column formula

    func testSingleColumnBelowBreakpoint() {
        let columns = computeMasonryColumns(viewportWidth: 500)
        XCTAssertEqual(columns.colCount, 1)
    }

    func testSingleColumnWidthCappedAtMaxMinusMargins() {
        let columns = computeMasonryColumns(viewportWidth: 500)
        let expected = min(400.0, 500.0 - 12.0 * 2)
        XCTAssertEqual(columns.colWidth, expected, accuracy: 0.01)
    }

    func testSingleColumnWidthCappedAt400ForWideViewport() {
        let columns = computeMasonryColumns(viewportWidth: 480)
        XCTAssertLessThanOrEqual(columns.colWidth, 400)
    }

    func testMultipleColumnsAboveBreakpoint() {
        let columns = computeMasonryColumns(viewportWidth: 800)
        XCTAssertGreaterThanOrEqual(columns.colCount, 2)
    }

    func testColumnWidthNeverExceedsMax() {
        for width in stride(from: 600.0, through: 3000.0, by: 200) {
            let columns = computeMasonryColumns(viewportWidth: width)
            XCTAssertLessThanOrEqual(
                columns.colWidth, 400,
                "colWidth exceeded max at viewport width \(width)"
            )
        }
    }

    func testColumnCountMatchesJSFormula() {
        let gap = MasonryMetrics.gap
        for viewportWidth in [600.0, 800.0, 1000.0, 1200.0, 1600.0, 2000.0] {
            let minColWidth = 100 + viewportWidth * 0.1
            let expectedCount = max(2, Int(floor((viewportWidth + gap) / (minColWidth + gap))))
            let columns = computeMasonryColumns(viewportWidth: viewportWidth)
            XCTAssertEqual(
                columns.colCount, expectedCount,
                "Column count mismatch at viewport width \(viewportWidth)"
            )
        }
    }

    // MARK: - Grid centering

    func testGridIsCentered() {
        let viewportWidth = 1000.0
        let columns = computeMasonryColumns(viewportWidth: viewportWidth)
        let gap = MasonryMetrics.gap
        let contentWidth = Double(columns.colCount) * columns.colWidth
            + Double(columns.colCount - 1) * gap
        let expectedOffset = (viewportWidth - contentWidth) / 2
        XCTAssertEqual(columns.offsetLeft, expectedOffset, accuracy: 0.01)
    }

    // MARK: - Masonry placement

    func testShortestColumnPlacement() {
        let viewportWidth = 850.0
        let columns = computeMasonryColumns(viewportWidth: viewportWidth)
        let n = columns.colCount

        // Create n+1 cards: first card tall, rest short, last card should stack
        // on a short column (not the tall one)
        var heights = [200.0]  // first card is tall
        for _ in 1..<n { heights.append(50) }  // fill remaining columns
        heights.append(80)  // one extra card

        let result = computeMasonryLayout(
            viewportWidth: viewportWidth,
            cardHeights: heights
        )

        XCTAssertEqual(result.positionedCards.count, n + 1)

        let lastCard = result.positionedCards[n]  // the extra card
        let firstCard = result.positionedCards[0]

        // Last card should NOT be in the same column as card 0 (the tall one)
        XCTAssertNotEqual(lastCard.x, firstCard.x, accuracy: 0.01)

        // Last card should be stacked below a short card (y > gap)
        let gap = MasonryMetrics.gap
        XCTAssertEqual(lastCard.y, gap + 50 + gap, accuracy: 0.01)
    }

    func testContentHeightIsTallestColumn() {
        let viewportWidth = 850.0
        let columns = computeMasonryColumns(viewportWidth: viewportWidth)
        let n = columns.colCount

        // One tall card, rest short — tallest column is the first
        var heights = [200.0]
        for _ in 1..<n { heights.append(50) }

        let result = computeMasonryLayout(
            viewportWidth: viewportWidth,
            cardHeights: heights
        )

        let gap = MasonryMetrics.gap
        let expected = gap + 200 + gap  // tallest column: gap + height + trailing gap
        XCTAssertEqual(result.contentHeight, expected, accuracy: 0.01)
    }

    func testAllCardsStartAtGapOffset() {
        let result = computeMasonryLayout(
            viewportWidth: 850,
            cardHeights: [100, 100]
        )
        let gap = MasonryMetrics.gap
        // First card in each column starts at y = gap
        XCTAssertEqual(result.positionedCards[0].y, gap, accuracy: 0.01)
        XCTAssertEqual(result.positionedCards[1].y, gap, accuracy: 0.01)
    }

    // MARK: - Visibility culling

    func testVisibleCardsFiltering() {
        let cards = [
            PositionedCard(cardIndex: 0, x: 0, y: 0, height: 100),
            PositionedCard(cardIndex: 1, x: 0, y: 500, height: 100),
            PositionedCard(cardIndex: 2, x: 0, y: 1000, height: 100),
            PositionedCard(cardIndex: 3, x: 0, y: 2000, height: 100),
        ]

        let visible = visibleCardIndices(
            from: cards,
            scrollOffset: 500,
            viewportHeight: 800,
            overscan: 200
        )

        // viewTop = 500-200 = 300, viewBottom = 500+800+200 = 1500
        // Card 0: 0..100 — below viewTop=300 → hidden
        // Card 1: 500..600 — visible
        // Card 2: 1000..1100 — visible
        // Card 3: 2000..2100 — above viewBottom=1500 → hidden
        XCTAssertEqual(visible, [1, 2])
    }

    func testAllCardsVisibleWhenContentFitsViewport() {
        let cards = [
            PositionedCard(cardIndex: 0, x: 0, y: 0, height: 100),
            PositionedCard(cardIndex: 1, x: 0, y: 120, height: 100),
        ]

        let visible = visibleCardIndices(
            from: cards,
            scrollOffset: 0,
            viewportHeight: 1000,
            overscan: 200
        )

        XCTAssertEqual(visible, [0, 1])
    }
}
