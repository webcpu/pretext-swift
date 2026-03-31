import XCTest
@testable import Demo

final class IllustratedManuscriptLayoutTests: XCTestCase {
    func testWatchSizedSnapshotShrinksDropCapToQuarterScale() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: 198,
            viewportHeight: 242
        )
        let dragonState = makeIllustratedDragonState(
            pageRect: metrics.pageRect,
            scale: metrics.scale,
            platform: .watchOS
        )

        let snapshot = evaluateIllustratedManuscriptSnapshot(
            viewportWidth: 198,
            viewportHeight: 242,
            dragonState: dragonState,
            platform: .watchOS
        )

        XCTAssertEqual(snapshot.dropCapDrawRect.height, 38.5, accuracy: 0.001)
    }

    func testPhoneSizedSnapshotKeepsFullDropCapScale() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: 390,
            viewportHeight: 844
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
            viewportHeight: 960
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
            viewportHeight: 844
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
            viewportHeight: 844
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
            viewportHeight: 960
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
}
