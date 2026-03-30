import XCTest
@testable import Demo

final class ContentViewTests: XCTestCase {
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

    func testDemoScreenIncludesIllustratedManuscriptOption() {
        XCTAssertEqual(
            DemoScreen.allCases.map(\.title),
            [
                "Situational Awareness",
                "Editorial Engine",
                "Masonry",
                "Chika Dance",
                "Illustrated Manuscript",
                "Benchmark",
            ]
        )
    }
}
