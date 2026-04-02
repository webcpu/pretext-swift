import XCTest
@testable import Demo

final class DemoWatchCatalogTests: XCTestCase {
    func testWatchNavigationUsesWatchListStyle() {
        XCTAssertEqual(DemoNavigationStyle.forWidthClass(isCompact: true, platform: .watchOS), .watchList)
        XCTAssertEqual(DemoNavigationStyle.forWidthClass(isCompact: false, platform: .watchOS), .watchList)
        XCTAssertEqual(DemoNavigationStyle.forWidthClass(isCompact: nil, platform: .watchOS), .watchList)
    }

    func testWatchCatalogIncludesOnlyWatchSafeDemos() {
        XCTAssertEqual(
            DemoScreen.availableCases(for: .watchOS).map(\.title),
            [
                "Situational Awareness",
                "Editorial Engine",
                "Masonry",
                "Illustrated Manuscript",
                "Benchmark",
            ]
        )
    }

    func testWatchLaunchSelectionRejectsUnsupportedDemos() {
        XCTAssertNil(
            DemoScreen.launchSelection(
                arguments: ["Demo", "--demo-screen", DemoScreen.liveCameraSilhouette.rawValue],
                platform: .watchOS
            )
        )
        XCTAssertEqual(
            DemoScreen.launchSelection(
                arguments: ["Demo", "--demo-screen", DemoScreen.benchmark.rawValue],
                platform: .watchOS
            ),
            .benchmark
        )
        XCTAssertNil(
            DemoScreen.launchSelection(
                arguments: ["Demo", "--demo-screen", DemoScreen.fluid.rawValue],
                platform: .watchOS
            )
        )
    }

    func testWatchNavigationDestinationUsesNavigationBarRegion() {
        XCTAssertFalse(demoNavigationDestinationUsesSafeArea(platform: .watchOS))
        XCTAssertFalse(demoNavigationDestinationUsesSafeArea(platform: .ios))
        XCTAssertFalse(demoNavigationDestinationUsesSafeArea(platform: .macOS))
    }

    func testWatchNavigationDestinationHidesDetailTitle() {
        XCTAssertFalse(demoNavigationDestinationShowsTitle(platform: .watchOS))
        XCTAssertTrue(demoNavigationDestinationShowsTitle(platform: .ios))
        XCTAssertTrue(demoNavigationDestinationShowsTitle(platform: .macOS))
    }

    func testWatchNavigationDestinationFillsDetailContainer() {
        XCTAssertTrue(demoNavigationDestinationFillsContainer(platform: .watchOS))
        XCTAssertFalse(demoNavigationDestinationFillsContainer(platform: .ios))
        XCTAssertFalse(demoNavigationDestinationFillsContainer(platform: .macOS))
    }
}
