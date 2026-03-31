import XCTest
@testable import Demo

final class IllustratedManuscriptLayoutTests: XCTestCase {
    private let watchViewport = (width: 198.0, height: 242.0)
    private let largeWatchViewport = (width: 208.0, height: 248.0)

    func testWatchManualCGDrawingUsesLocalVerticalFlip() {
        XCTAssertTrue(illustratedManuscriptUsesLocalVerticalFlipForRawCG(platform: .watchOS))
    }

    func testPhoneAndDesktopManualCGDrawingKeepDefaultOrientation() {
        XCTAssertFalse(illustratedManuscriptUsesLocalVerticalFlipForRawCG(platform: .ios))
        XCTAssertFalse(illustratedManuscriptUsesLocalVerticalFlipForRawCG(platform: .macOS))
    }

    func testWatchSizedSnapshotShrinksDropCapToQuarterScale() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: watchViewport.width,
            viewportHeight: watchViewport.height,
            platform: .watchOS
        )
        let dragonState = makeIllustratedDragonState(
            pageRect: metrics.pageRect,
            scale: metrics.scale,
            platform: .watchOS
        )

        let snapshot = evaluateIllustratedManuscriptSnapshot(
            viewportWidth: watchViewport.width,
            viewportHeight: watchViewport.height,
            dragonState: dragonState,
            platform: .watchOS
        )

        XCTAssertEqual(
            snapshot.dropCapDrawRect.height,
            metrics.lineHeight * IllustratedManuscriptConstants.dropCapLineHeightMultiplier * IllustratedManuscriptConstants.watchDropCapScale,
            accuracy: 0.001
        )
    }

    func testWatchPageMetricsUseTopAndBottomRegions() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: watchViewport.width,
            viewportHeight: watchViewport.height,
            platform: .watchOS
        )

        XCTAssertEqual(metrics.pageRect.y, 20, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.height, 202, accuracy: 0.001)
    }

    func testLargeWatchPageMetricsUseTopAndBottomRegions() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: largeWatchViewport.width,
            viewportHeight: largeWatchViewport.height,
            platform: .watchOS
        )

        XCTAssertEqual(metrics.pageRect.y, 20, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.height, 208, accuracy: 0.001)
    }

    func testWatchPageMetricsUseSmallerBodyFont() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: largeWatchViewport.width,
            viewportHeight: largeWatchViewport.height,
            platform: .watchOS
        )

        XCTAssertEqual(metrics.fontSize, 12, accuracy: 0.001)
        XCTAssertEqual(metrics.lineHeight, 20, accuracy: 0.001)
    }

    func testWatchSnapshotContinuesLayoutAfterNarrowLeadingSlots() {
        let snapshot = makeWatchSnapshot()

        XCTAssertGreaterThanOrEqual(snapshot.bodyLines.count, 7)
        XCTAssertGreaterThan(
            snapshot.bodyLines.last?.y ?? 0,
            snapshot.pageMetrics.pageRect.midY
        )
    }

    func testWatchSnapshotKeepsDragonWrapToTopBands() {
        let snapshot = makeWatchSnapshot()
        let firstBandTop = snapshot.bodyLines[0].y
        let firstBandBottom = firstBandTop + snapshot.pageMetrics.lineHeight
        let fourthBandTop = firstBandTop + snapshot.pageMetrics.lineHeight * 3
        let fourthBandBottom = fourthBandTop + snapshot.pageMetrics.lineHeight

        XCTAssertNotNil(
            getPolygonIntervalForBand(
                points: snapshot.dragonWrapHull,
                bandTop: firstBandTop,
                bandBottom: firstBandBottom,
                hPad: snapshot.dragonWrapHorizontalPadding,
                vPad: snapshot.dragonWrapVerticalPadding
            )
        )
        XCTAssertNil(
            getPolygonIntervalForBand(
                points: snapshot.dragonWrapHull,
                bandTop: fourthBandTop,
                bandBottom: fourthBandBottom,
                hPad: snapshot.dragonWrapHorizontalPadding,
                vPad: snapshot.dragonWrapVerticalPadding
            )
        )
    }

    func testWatchSnapshotAddsLeadingClearanceToDragonOverlapBands() throws {
        let snapshot = makeWatchSnapshot()
        let overlappingLine = try XCTUnwrap(
            snapshot.bodyLines.first { line in
                dragonInterval(for: line, snapshot: snapshot) != nil
            }
        )
        let rawInterval = try XCTUnwrap(
            getPolygonIntervalForBand(
                points: snapshot.dragonWrapHull,
                bandTop: overlappingLine.y,
                bandBottom: overlappingLine.y + snapshot.pageMetrics.lineHeight,
                hPad: 0,
                vPad: 0
            )
        )

        XCTAssertGreaterThanOrEqual(overlappingLine.x, rawInterval.right + 16)
    }

    func testWatchSnapshotLeavesWideTrailingSlotInFirstDragonBand() throws {
        let snapshot = makeWatchSnapshot()
        let overlappingLine = try XCTUnwrap(
            snapshot.bodyLines.first { line in
                dragonInterval(for: line, snapshot: snapshot) != nil
            }
        )

        XCTAssertGreaterThan(overlappingLine.width, 92)
    }

    func testPhoneSizedSnapshotKeepsFullDropCapScale() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: 390,
            viewportHeight: 844,
            platform: .ios
        )
        let dragonState = makeIllustratedDragonState(
            pageRect: metrics.pageRect,
            scale: metrics.scale,
            platform: .ios
        )

        let snapshot = evaluateIllustratedManuscriptSnapshot(
            viewportWidth: 390,
            viewportHeight: 844,
            dragonState: dragonState,
            platform: .ios
        )

        XCTAssertEqual(snapshot.dropCapDrawRect.height, 168, accuracy: 0.001)
    }

    func testDesktopPageMetricsMatchSourceComposition() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: 1440,
            viewportHeight: 960,
            platform: .macOS
        )

        XCTAssertEqual(metrics.pageRect.x, 370, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.y, 30, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.width, 700, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.height, 900, accuracy: 0.001)
        XCTAssertEqual(metrics.margin, 45, accuracy: 0.001)
        XCTAssertEqual(metrics.fontSize, 21, accuracy: 0.001)
        XCTAssertEqual(metrics.lineHeight, 34, accuracy: 0.001)
    }

    func testPhonePageMetricsMatchSourceComposition() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: 390,
            viewportHeight: 844,
            platform: .ios
        )

        XCTAssertEqual(metrics.pageRect.x, 20, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.y, 30, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.width, 350, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.height, 784, accuracy: 0.001)
        XCTAssertEqual(metrics.margin, 23, accuracy: 0.001)
        XCTAssertEqual(metrics.fontSize, 15, accuracy: 0.001)
        XCTAssertEqual(metrics.lineHeight, 24, accuracy: 0.001)
    }

    func testSnapshotSkipsDropCapCharacterAndKeepsTopLinesOutOfDropCap() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: 390,
            viewportHeight: 844,
            platform: .ios
        )
        let dragonState = makeIllustratedDragonState(
            pageRect: metrics.pageRect,
            scale: metrics.scale
        )

        let snapshot = evaluateIllustratedManuscriptSnapshot(
            viewportWidth: 390,
            viewportHeight: 844,
            dragonState: dragonState
        )

        XCTAssertFalse(snapshot.bodyLines.isEmpty)
        XCTAssertFalse(snapshot.bodyLines[0].text.hasPrefix(snapshot.dropCapCharacter))

        let overlappingLines = snapshot.bodyLines.filter { line in
            let lineBottom = line.y + snapshot.pageMetrics.lineHeight
            return lineBottom > snapshot.dropCapRect.minY && line.y < snapshot.dropCapRect.maxY
        }

        XCTAssertFalse(overlappingLines.isEmpty)
        XCTAssertTrue(
            overlappingLines.allSatisfy { line in
                line.x >= snapshot.dropCapRect.maxX - 0.5
            }
        )
    }

    func testDesktopSnapshotKeepsBodyLinesOutOfDragonHull() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: 1440,
            viewportHeight: 960,
            platform: .macOS
        )
        let dragonState = makeIllustratedDragonState(
            pageRect: metrics.pageRect,
            scale: metrics.scale
        )

        let snapshot = evaluateIllustratedManuscriptSnapshot(
            viewportWidth: 1440,
            viewportHeight: 960,
            dragonState: dragonState
        )

        let overlappingLines = snapshot.bodyLines.compactMap { line -> (PositionedLine, WrapInterval)? in
            guard let interval = getPolygonIntervalForBand(
                points: snapshot.dragonWrapHull,
                bandTop: line.y,
                bandBottom: line.y + snapshot.pageMetrics.lineHeight,
                hPad: snapshot.dragonWrapHorizontalPadding,
                vPad: snapshot.dragonWrapVerticalPadding
            ) else {
                return nil
            }

            return (line, interval)
        }

        XCTAssertFalse(overlappingLines.isEmpty)
        XCTAssertTrue(
            overlappingLines.allSatisfy { line, interval in
                line.x + line.width <= interval.left || line.x >= interval.right
            }
        )
    }

    private func makeWatchSnapshot() -> IllustratedManuscriptSnapshot {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: watchViewport.width,
            viewportHeight: watchViewport.height,
            platform: .watchOS
        )
        let dragonState = makeIllustratedDragonState(
            pageRect: metrics.pageRect,
            scale: metrics.scale,
            platform: .watchOS
        )

        return evaluateIllustratedManuscriptSnapshot(
            viewportWidth: watchViewport.width,
            viewportHeight: watchViewport.height,
            dragonState: dragonState,
            platform: .watchOS
        )
    }

    private func dragonInterval(
        for line: PositionedLine,
        snapshot: IllustratedManuscriptSnapshot
    ) -> WrapInterval? {
        getPolygonIntervalForBand(
            points: snapshot.dragonWrapHull,
            bandTop: line.y,
            bandBottom: line.y + snapshot.pageMetrics.lineHeight,
            hPad: snapshot.dragonWrapHorizontalPadding,
            vPad: snapshot.dragonWrapVerticalPadding
        )
    }
}
