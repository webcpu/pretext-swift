import XCTest
@testable import Demo

final class ContentViewTests: XCTestCase {
    func testDemoScreenIncludesBenchmarkOption() {
        XCTAssertEqual(
            DemoScreen.allCases.map(\.title),
            ["Situational Awareness", "Editorial Engine", "Benchmark"]
        )
    }
}
