import XCTest
@testable import Demo

final class ChikaDanceLayoutTests: XCTestCase {
    func testCharacterRectPreservesAspectWhenPortraitWidthCapApplies() {
        let bounds = WrapRect(x: 0.45, y: 0.18, width: 0.32, height: 0.84)
        let rect = computeChikaCharacterRect(
            boundsFraction: bounds,
            pageWidth: 390,
            pageHeight: 844
        )

        let expectedAspect = (bounds.width / bounds.height) * (1920.0 / 1080.0)

        XCTAssertEqual(rect.width / rect.height, expectedAspect, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(rect.width, 390 * 0.45 + 0.0001)
    }
}
