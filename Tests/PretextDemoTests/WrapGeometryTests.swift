import XCTest
@testable import PretextDemo

final class WrapGeometryTests: XCTestCase {
    func testCarveTextLineSlotsSplitsAroundBlockedInterval() {
        let slots = carveTextLineSlots(
            base: WrapInterval(left: 80, right: 420),
            blocked: [WrapInterval(left: 200, right: 310)]
        )

        XCTAssertEqual(
            slots,
            [
                WrapInterval(left: 80, right: 200),
                WrapInterval(left: 310, right: 420),
            ]
        )
    }

    func testTransformWrapPointsMapsNormalizedPointIntoRect() {
        let points = transformWrapPoints(
            [WrapPoint(x: 0.5, y: 0.5)],
            rect: WrapRect(x: 20, y: 40, width: 200, height: 100),
            angle: 0
        )

        XCTAssertEqual(points, [WrapPoint(x: 120, y: 90)])
    }

    func testCircleIntervalForBandUsesOrbRadiusAndPadding() {
        let interval = circleIntervalForBand(
            cx: 100,
            cy: 100,
            r: 50,
            bandTop: 90,
            bandBottom: 120,
            hPad: 10,
            vPad: 5
        )

        XCTAssertNotNil(interval)
        XCTAssertEqual(interval?.left ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(interval?.right ?? 0, 160, accuracy: 0.001)
    }
}
