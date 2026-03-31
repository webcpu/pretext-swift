import XCTest
@testable import Demo

final class CameraSilhouetteLayoutTests: XCTestCase {
    func testBundledArticleWithoutSilhouetteUsesMostOfPageHeight() {
        let articleURL = URL(fileURLWithPath: "/Users/liang/Code/experiments/pretext-swift/Sources/Demo/Resources/camera-silhouette/article.txt")
        let article = (try? String(contentsOf: articleURL, encoding: .utf8)) ?? ""
        let snapshot = evaluateCameraSilhouetteSnapshot(
            article: article,
            viewportWidth: 390,
            viewportHeight: 844,
            silhouetteRows: []
        )

        guard let lastLine = snapshot.lines.last else {
            XCTFail("Expected bundled article to produce lines")
            return
        }

        XCTAssertGreaterThan(
            lastLine.y,
            snapshot.pageMetrics.contentRect.maxY - snapshot.pageMetrics.lineHeight * 4
        )
    }

    func testBlockedIntervalsAreEmptyWithoutOccupancy() {
        XCTAssertEqual(
            cameraSilhouetteBlockedIntervals(
                occupancy: [],
                pageWidth: 300
            ),
            []
        )
    }

    func testBlockedIntervalsClipToPageBounds() {
        XCTAssertEqual(
            cameraSilhouetteBlockedIntervals(
                occupancy: [
                    .init(minX: -0.2, maxX: 0.35),
                    .init(minX: 0.8, maxX: 1.4),
                ],
                pageWidth: 300
            ),
            [
                WrapInterval(left: 0, right: 105),
                WrapInterval(left: 240, right: 300),
            ]
        )
    }

    func testOpenSlotsIncludeBothSidesOfBlockedCenterBand() {
        XCTAssertEqual(
            cameraSilhouetteOpenSlots(
                base: WrapInterval(left: 0, right: 300),
                blocked: [
                    WrapInterval(left: 120, right: 180),
                ],
                minimumWidth: 24
            ),
            [
                WrapInterval(left: 0, right: 120),
                WrapInterval(left: 180, right: 300),
            ]
        )
    }

    func testFallbackLayoutUsesFullWidthWhenSilhouetteRowsAreEmpty() {
        let snapshot = evaluateCameraSilhouetteSnapshot(
            article: sampleArticle,
            viewportWidth: 390,
            viewportHeight: 844,
            silhouetteRows: []
        )

        XCTAssertTrue(snapshot.usesFallbackLayout)
        XCTAssertFalse(snapshot.lines.isEmpty)
        guard let firstLine = snapshot.lines.first else {
            XCTFail("Expected at least one laid out line")
            return
        }
        XCTAssertEqual(firstLine.x, snapshot.pageMetrics.pageRect.x + snapshot.pageMetrics.margin, accuracy: 0.5)
        XCTAssertTrue(snapshot.bands.allSatisfy { $0.blocked.isEmpty })
    }

    func testRepresentativeWrapAvoidsBlockedCenterBand() {
        let snapshot = evaluateCameraSilhouetteSnapshot(
            article: sampleArticle,
            viewportWidth: 430,
            viewportHeight: 932,
            silhouetteRows: centeredRows
        )

        let blockedBands = snapshot.bands.filter { !$0.blocked.isEmpty }
        XCTAssertFalse(blockedBands.isEmpty)
        XCTAssertFalse(snapshot.usesFallbackLayout)

        let linesByTop = Dictionary(grouping: snapshot.lines, by: \.y)
        let overlappingLines = blockedBands.flatMap { band in
            (linesByTop[band.top] ?? []).map { (band, $0) }
        }

        XCTAssertFalse(overlappingLines.isEmpty)
        for (band, line) in overlappingLines {
            for interval in band.blocked {
                XCTAssertTrue(
                    line.x + line.width <= interval.left + 1 ||
                        line.x >= interval.right - 1
                )
            }
        }
    }

    func testCenteredSilhouetteUsesBothReadableSideSlots() {
        let snapshot = evaluateCameraSilhouetteSnapshot(
            article: sampleArticle,
            viewportWidth: 430,
            viewportHeight: 932,
            silhouetteRows: centeredRows
        )

        let lineCountsByY = Dictionary(grouping: snapshot.lines, by: \.y)
            .mapValues(\.count)

        XCTAssertTrue(
            lineCountsByY.values.contains(where: { $0 >= 2 }),
            "Expected at least one blocked band to use both readable side slots."
        )
    }

    func testOpenSlotsFallBackToNarrowerSlotWhenIdealWidthIsUnavailable() {
        XCTAssertEqual(
            cameraSilhouetteOpenSlots(
                base: WrapInterval(left: 0, right: 300),
                blocked: [
                    WrapInterval(left: 0, right: 248)
                ],
                minimumWidth: 72
            ),
            [WrapInterval(left: 248, right: 300)]
        )
    }

    func testNormalizedIntervalsMapStablyAcrossPageSizes() {
        let occupancy = [
            CameraSilhouetteNormalizedSpan(minX: 0.25, maxX: 0.6)
        ]

        let portrait = cameraSilhouetteBlockedIntervals(
            occupancy: occupancy,
            contentRect: WrapRect(x: 20, y: 40, width: 350, height: 760)
        )
        let landscape = cameraSilhouetteBlockedIntervals(
            occupancy: occupancy,
            contentRect: WrapRect(x: 90, y: 30, width: 640, height: 320)
        )

        XCTAssertEqual((portrait[0].left - 20) / 350, 0.25, accuracy: 0.001)
        XCTAssertEqual((portrait[0].right - 20) / 350, 0.6, accuracy: 0.001)
        XCTAssertEqual((landscape[0].left - 90) / 640, 0.25, accuracy: 0.001)
        XCTAssertEqual((landscape[0].right - 90) / 640, 0.6, accuracy: 0.001)
    }

    func testProjectionFromAspectFitPreviewClipsRowsIntoTargetRect() {
        let sourceRect = cameraSilhouetteAspectFitRect(
            sourceSize: CGSize(width: 720, height: 1280),
            viewportSize: CGSize(width: 390, height: 844)
        )
        let targetRect = WrapRect(x: 20, y: 100, width: 350, height: 640)
        let projected = projectCameraSilhouetteRows(
            [
                CameraSilhouetteMaskRow(
                    minY: 0.18,
                    maxY: 0.42,
                    occupied: [
                        CameraSilhouetteNormalizedSpan(minX: 0.18, maxX: 0.74)
                    ]
                )
            ],
            from: sourceRect,
            into: targetRect
        )

        XCTAssertEqual(projected.count, 1)
        XCTAssertGreaterThanOrEqual(projected[0].minY, 0)
        XCTAssertLessThanOrEqual(projected[0].maxY, 1)
        XCTAssertTrue(
            projected[0].occupied.allSatisfy { span in
                span.minX >= 0 && span.maxX <= 1 && span.maxX > span.minX
            }
        )
    }

    func testAspectFitRectPreservesSourceAspectRatioInsideViewport() {
        let rect = cameraSilhouetteAspectFitRect(
            sourceSize: CGSize(width: 720, height: 1280),
            viewportSize: CGSize(width: 390, height: 844)
        )

        XCTAssertEqual(rect.x, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 390, accuracy: 0.001)
        XCTAssertEqual(rect.height, 693.333, accuracy: 0.01)
        XCTAssertEqual(rect.y, 75.333, accuracy: 0.01)
    }

    func testPageMetricsUseSmallerArticleFont() {
        let metrics = cameraSilhouettePageMetrics(
            viewportWidth: 390,
            viewportHeight: 844
        )

        XCTAssertEqual(metrics.fontSize, 19, accuracy: 0.001)
        XCTAssertEqual(metrics.lineHeight, 30, accuracy: 0.001)
    }

    func testPageMetricsUseFullSafeAreaWidth() {
        let metrics = cameraSilhouettePageMetrics(
            viewportWidth: 390,
            viewportHeight: 844,
            topInset: 59,
            bottomInset: 34
        )

        XCTAssertEqual(metrics.pageRect.x, 0, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.y, 59, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.width, 390, accuracy: 0.001)
        XCTAssertEqual(metrics.pageRect.height, 751, accuracy: 0.001)
    }

    func testPreviewFrameUsesFullViewportForCameraMask() {
        let previewFrame = cameraSilhouettePreviewFrame(
            viewportWidth: 390,
            viewportHeight: 844,
            topInset: 59,
            bottomInset: 34
        )

        XCTAssertEqual(previewFrame.x, 0, accuracy: 0.001)
        XCTAssertEqual(previewFrame.y, 0, accuracy: 0.001)
        XCTAssertEqual(previewFrame.width, 390, accuracy: 0.001)
        XCTAssertEqual(previewFrame.height, 844, accuracy: 0.001)
    }

    func testSnapshotEvaluationUsesSameSafeAreaAwareMetricsAsProjection() {
        let metrics = cameraSilhouettePageMetrics(
            viewportWidth: 390,
            viewportHeight: 844,
            topInset: 59,
            bottomInset: 34
        )
        let projectedRows = projectCameraSilhouetteRows(
            [
                CameraSilhouetteMaskRow(
                    minY: 0.32,
                    maxY: 0.42,
                    occupied: [
                        CameraSilhouetteNormalizedSpan(minX: 0.28, maxX: 0.68)
                    ]
                )
            ],
            from: metrics.contentRect,
            into: metrics.contentRect
        )

        let snapshot = evaluateCameraSilhouetteSnapshot(
            article: sampleArticle,
            viewportWidth: 390,
            viewportHeight: 844,
            topInset: 59,
            bottomInset: 34,
            silhouetteRows: projectedRows
        )

        XCTAssertEqual(snapshot.pageMetrics, metrics)
        XCTAssertTrue(snapshot.bands.contains(where: { !$0.blocked.isEmpty }))
    }
}

private let sampleArticle = Array(repeating: """
The city keeps a second draft of every life in reflected glass, elevator mirrors, and late windows.
""", count: 24).joined(separator: " ")

private let centeredRows = stride(from: 0.14, through: 0.58, by: 0.03).map {
    CameraSilhouetteMaskRow(
        minY: $0,
        maxY: min($0 + 0.025, 1),
        occupied: [
            CameraSilhouetteNormalizedSpan(minX: 0.34, maxX: 0.68)
        ]
    )
}
