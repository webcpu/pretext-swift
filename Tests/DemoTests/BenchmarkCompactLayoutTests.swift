import XCTest
@testable import BenchmarkSupport

final class BenchmarkCompactLayoutTests: XCTestCase {
    func testBenchmarkResultsLayoutUsesCardsOnCompactWidthClass() {
        XCTAssertEqual(BenchmarkResultsLayoutStyle.forWidthClass(isCompact: true, platform: .standard), .cards)
        XCTAssertEqual(BenchmarkResultsLayoutStyle.forWidthClass(isCompact: false, platform: .standard), .table)
        XCTAssertEqual(BenchmarkResultsLayoutStyle.forWidthClass(isCompact: nil, platform: .standard), .table)
    }

    func testBenchmarkResultsLayoutUsesWatchCardsOnWatch() {
        XCTAssertEqual(BenchmarkResultsLayoutStyle.forWidthClass(isCompact: true, platform: .watch), .watchCards)
        XCTAssertEqual(BenchmarkResultsLayoutStyle.forWidthClass(isCompact: false, platform: .watch), .watchCards)
        XCTAssertEqual(BenchmarkResultsLayoutStyle.forWidthClass(isCompact: nil, platform: .watch), .watchCards)
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
            compactBenchmarkMetrics(for: result, platform: .standard).map(\.label),
            ["Pretext", "Core Text", "SwiftUI", "Vs CT", "Vs SUI"]
        )
        XCTAssertEqual(
            compactBenchmarkMetrics(for: result, platform: .standard).map(\.value),
            ["4.7ms", "28.6ms", "64.8ms", "6.1x", "13.8x"]
        )
    }

    func testWatchCompactBenchmarkMetricsOmitMissingSwiftUIComparisons() {
        let result = BenchmarkResult(
            name: "Variable-Width Line-by-Line",
            pretextMs: 2.4,
            coreTextMs: 11.2,
            swiftUIMs: nil,
            speedupVsCoreText: 4.7,
            speedupVsSwiftUI: nil
        )

        XCTAssertEqual(
            compactBenchmarkMetrics(for: result, platform: .watch).map(\.label),
            ["Pretext", "Core Text", "Vs CT"]
        )
        XCTAssertEqual(
            compactBenchmarkMetrics(for: result, platform: .watch).map(\.value),
            ["2.4ms", "11.2ms", "4.7x"]
        )
    }
}
