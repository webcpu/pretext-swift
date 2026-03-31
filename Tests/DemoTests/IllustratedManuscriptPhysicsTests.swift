import XCTest
@testable import Demo

final class IllustratedManuscriptPhysicsTests: XCTestCase {
    func testWatchDragonRestPoseScalesWholeDragonDownAndShiftsRight() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: 208,
            viewportHeight: 248,
            platform: .watchOS
        )
        let state = makeIllustratedDragonState(
            pageRect: metrics.pageRect,
            scale: metrics.scale,
            platform: .watchOS
        )
        let margin = round(IllustratedManuscriptConstants.baseMargin * metrics.scale)
        let lineHeightScale = 0.4 + 0.6 * metrics.scale
        let lineHeight = max(22.0, round(IllustratedManuscriptConstants.baseLineHeight * lineHeightScale))
        let dropCap = IllustratedManuscriptAssets.dropCapGeometry(
            pageRect: WrapRect(x: 0, y: 0, width: metrics.pageRect.width, height: metrics.pageRect.height),
            margin: margin,
            lineHeight: lineHeight,
            scale: illustratedManuscriptDropCapScale(for: .watchOS)
        )

        XCTAssertEqual(state.dragonScaleMultiplier, 0.68, accuracy: 0.001)
        XCTAssertEqual(
            state.segments[0].x,
            metrics.pageRect.x + margin + dropCap.obstacleRect.width * 1.05 + 24,
            accuracy: 0.001
        )
        XCTAssertEqual(
            state.segments[0].width,
            IllustratedManuscriptConstants.dragonWidths[0] * IllustratedManuscriptConstants.dragonSpriteScale * metrics.scale * 0.68,
            accuracy: 0.001
        )
        XCTAssertEqual(
            distance(state.segments[0], state.segments[1]),
            30.0 * 0.88 * metrics.scale * 0.68,
            accuracy: 0.001
        )
    }

    func testDragonReturnsTowardRestAfterIdleTimeout() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: 1440,
            viewportHeight: 960
        )
        var state = makeIllustratedDragonState(
            pageRect: metrics.pageRect,
            scale: metrics.scale
        )
        let restHead = state.segments[0]

        let activePointer = WrapPoint(
            x: metrics.pageRect.maxX - 40,
            y: metrics.pageRect.minY + 160
        )
        advanceIllustratedDragonState(
            &state,
            time: 100,
            pointer: activePointer,
            isPressing: false
        )
        advanceIllustratedDragonState(
            &state,
            time: 200,
            pointer: activePointer,
            isPressing: false
        )
        let movedHead = state.segments[0]

        XCTAssertGreaterThan(distance(movedHead, restHead), 1)

        advanceIllustratedDragonState(
            &state,
            time: 2500,
            pointer: nil,
            isPressing: false
        )
        advanceIllustratedDragonState(
            &state,
            time: 2600,
            pointer: nil,
            isPressing: false
        )

        XCTAssertLessThan(distance(state.segments[0], restHead), distance(movedHead, restHead))
    }

    func testPressingProducesFireAndReleasedParticlesDecayAway() {
        let metrics = illustratedManuscriptPageMetrics(
            viewportWidth: 1440,
            viewportHeight: 960
        )
        var state = makeIllustratedDragonState(
            pageRect: metrics.pageRect,
            scale: metrics.scale
        )
        let activePointer = WrapPoint(
            x: metrics.pageRect.maxX - 80,
            y: metrics.pageRect.minY + 100
        )

        for time in stride(from: 100, through: 900, by: 100) {
            advanceIllustratedDragonState(
                &state,
                time: Double(time),
                pointer: activePointer,
                isPressing: true
            )
        }

        XCTAssertFalse(state.fire.isEmpty)

        for time in stride(from: 1000, through: 4000, by: 100) {
            advanceIllustratedDragonState(
                &state,
                time: Double(time),
                pointer: nil,
                isPressing: false
            )
        }

        XCTAssertTrue(state.fire.isEmpty)
    }

    private func distance(_ a: IllustratedDragonSegment, _ b: IllustratedDragonSegment) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}
