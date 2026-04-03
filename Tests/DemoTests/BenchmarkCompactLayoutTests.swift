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
            ["Pretext", "Core Text", "SwiftUI", "Vs CT", "Vs SwiftUI"]
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

    func testWatchViewProfileUsesCondensedHeaderCopyAndTighterSpacing() {
        let standardProfile = benchmarkViewProfile(for: .cards)
        let watchProfile = benchmarkViewProfile(for: .watchCards)

        XCTAssertEqual(standardProfile.suiteLabel, "PRETEXT BENCHMARK SUITE")
        XCTAssertEqual(standardProfile.headline, "Pretext vs Core Text vs SwiftUI")
        XCTAssertNil(benchmarkNavigationTitle(platform: .standard))

        XCTAssertEqual(watchProfile.suiteLabel, "")
        XCTAssertEqual(watchProfile.headline, "Pretext vs CoreText")
        XCTAssertTrue(watchProfile.showsHeadlineInHeader)
        XCTAssertTrue(watchProfile.resultsContentFillsHeight)
        XCTAssertFalse(standardProfile.resultsContentFillsHeight)
        XCTAssertNil(benchmarkNavigationTitle(platform: .watch))
        XCTAssertEqual(watchProfile.metricLayoutStyle, .stackedRows)
        XCTAssertTrue(standardProfile.showsBottomBar)
        XCTAssertFalse(watchProfile.showsBottomBar)
        XCTAssertLessThan(watchProfile.headerTopPadding, standardProfile.headerTopPadding)
        XCTAssertLessThan(watchProfile.headlineFontSize, standardProfile.headlineFontSize)
        XCTAssertLessThan(watchProfile.headlineHorizontalPadding, standardProfile.headlineHorizontalPadding)
        XCTAssertLessThan(watchProfile.buttonHorizontalPadding, standardProfile.buttonHorizontalPadding)
        XCTAssertLessThan(watchProfile.cardPadding, standardProfile.cardPadding)
        XCTAssertLessThan(watchProfile.bottomBarVerticalPadding, standardProfile.bottomBarVerticalPadding)
    }

    func testWatchPresentationCondensesLongBenchmarkLabels() {
        XCTAssertEqual(
            benchmarkDisplayName("Interleaved Measure-Mutate (500x)", platform: .watch),
            "Measure-Mutate"
        )
        XCTAssertEqual(
            benchmarkDisplayName("Interleaved Measure-Mutate (500x)", platform: .standard),
            "Interleaved Measure-Mutate (500x)"
        )
        XCTAssertEqual(
            benchmarkRunStatusLabel("Test 2/5: Reflow at 100 Widths...", platform: .watch),
            "2/5 Reflow"
        )
        XCTAssertEqual(
            benchmarkRunStatusLabel("Test 2/5: Reflow at 100 Widths...", platform: .standard),
            "Test 2/5: Reflow at 100 Widths..."
        )
        XCTAssertEqual(
            benchmarkPrimaryActionLabel(hasRunInSession: false, platform: .watch),
            "Run"
        )
        XCTAssertEqual(
            benchmarkPrimaryActionLabel(hasRunInSession: true, platform: .watch),
            "Again"
        )
        XCTAssertEqual(
            benchmarkPrimaryActionLabel(hasRunInSession: false, platform: .standard),
            "Run Benchmarks"
        )
    }
}
