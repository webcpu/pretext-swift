import XCTest
@testable import Demo

final class ContentViewTests: XCTestCase {
    func testWatchLaunchSelectionSeedsInitialNavigationPath() {
        XCTAssertEqual(
            demoInitialNavigationPath(launchSelection: .illustratedManuscript, platform: .watchOS),
            [.illustratedManuscript]
        )
    }

    func testPhoneAndDesktopLaunchSelectionDoNotSeedNavigationPath() {
        XCTAssertEqual(
            demoInitialNavigationPath(launchSelection: .illustratedManuscript, platform: .ios),
            []
        )
        XCTAssertEqual(
            demoInitialNavigationPath(launchSelection: .illustratedManuscript, platform: .macOS),
            []
        )
    }

    func testNilLaunchSelectionLeavesWatchNavigationPathEmpty() {
        XCTAssertEqual(
            demoInitialNavigationPath(launchSelection: nil, platform: .watchOS),
            []
        )
    }

    func testIOSNavigationUsesTabBarInAnyWidthClass() {
        XCTAssertEqual(DemoNavigationStyle.forWidthClass(isCompact: true, platform: .ios), .tabBar)
        XCTAssertEqual(DemoNavigationStyle.forWidthClass(isCompact: false, platform: .ios), .tabBar)
        XCTAssertEqual(DemoNavigationStyle.forWidthClass(isCompact: nil, platform: .ios), .tabBar)
    }

    func testMacOSNavigationUsesToolbarPickerInAnyWidthClass() {
        XCTAssertEqual(DemoNavigationStyle.forWidthClass(isCompact: true, platform: .macOS), .toolbarPicker)
        XCTAssertEqual(DemoNavigationStyle.forWidthClass(isCompact: false, platform: .macOS), .toolbarPicker)
        XCTAssertEqual(DemoNavigationStyle.forWidthClass(isCompact: nil, platform: .macOS), .toolbarPicker)
    }

    func testMacOSToolbarPickerUsesCompactTitlesForAllScreens() {
        XCTAssertEqual(
            DemoScreen.availableCases(for: .macOS).map(\.toolbarPickerTitle),
            [
                "Aware",
                "Editorial",
                "Masonry",
                "Chika",
                "Script",
                "Camera",
                "Fluid",
                "Bench",
            ]
        )
    }

    func testDemoScreenIncludesFluidOptionBeforeBenchmark() {
        XCTAssertEqual(
            DemoScreen.allCases.map(\.title),
            [
                "Situational Awareness",
                "Editorial Engine",
                "Masonry",
                "Chika Dance",
                "Illustrated Manuscript",
                "Live Camera Silhouette",
                "Fluid",
                "Benchmark",
            ]
        )
    }
}
