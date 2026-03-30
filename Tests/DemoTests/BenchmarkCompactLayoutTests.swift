import XCTest
@testable import BenchmarkSupport

final class BenchmarkCompactLayoutTests: XCTestCase {
    func testBenchmarkResultsLayoutUsesCardsOnCompactWidthClass() {
        XCTAssertEqual(BenchmarkResultsLayoutStyle.forWidthClass(isCompact: true), .cards)
        XCTAssertEqual(BenchmarkResultsLayoutStyle.forWidthClass(isCompact: false), .table)
        XCTAssertEqual(BenchmarkResultsLayoutStyle.forWidthClass(isCompact: nil), .table)
    }

    func testCompactBenchmarkMetricsIncludeEveryColumnValue() {
        let result = BenchmarkResult(
            name: "Batch Layout (500 texts)",
            pretextMs: 4.7,
            coreTextMs: 28.6,
            swiftUIMs: 64.8,
            speedupVsCoreText: 6.1,
            speedupVsSwiftUI: 13.8
        )

        XCTAssertEqual(
            compactBenchmarkMetrics(for: result).map(\.label),
            ["Pretext", "Core Text", "SwiftUI", "Vs CT", "Vs SUI"]
        )
        XCTAssertEqual(
            compactBenchmarkMetrics(for: result).map(\.value),
            ["4.7ms", "28.6ms", "64.8ms", "6.1x", "13.8x"]
        )
    }
}
