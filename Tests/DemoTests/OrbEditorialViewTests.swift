import XCTest
@testable import Demo

final class OrbEditorialViewTests: XCTestCase {
    func testWatchPlatformUsesCompactEditorialLayoutWithoutWidthClass() {
        XCTAssertTrue(orbEditorialUsesCompactLayout(isCompactWidth: nil, platform: .watchOS))
        XCTAssertTrue(orbEditorialUsesCompactLayout(isCompactWidth: true, platform: .ios))
        XCTAssertFalse(orbEditorialUsesCompactLayout(isCompactWidth: nil, platform: .macOS))
    }

    func testForcedWatchPresentationUsesTapLayoutAndHidesDecorativeChrome() {
        let displayMode = resolveOrbEditorialDisplayMode(
            isCompactWidth: nil,
            platform: .macOS,
            forceWatchPresentation: true
        )

        XCTAssertEqual(displayMode.platform, .watchOS)
        XCTAssertEqual(displayMode.presentation, .watch)
        XCTAssertTrue(displayMode.isCompactLayout)
        XCTAssertFalse(displayMode.showsHint)
        XCTAssertFalse(displayMode.showsStatsBar)
        XCTAssertFalse(displayMode.showsDropCap)
        XCTAssertFalse(displayMode.showsPullquotes)
        XCTAssertEqual(displayMode.hintPauseVerb, "Tap")
    }
}
