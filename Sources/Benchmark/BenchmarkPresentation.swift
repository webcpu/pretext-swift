import SwiftUI

enum BenchmarkPresentationPlatform: Equatable {
    case standard
    case watch

    static var current: Self {
        #if os(watchOS)
        .watch
        #else
        .standard
        #endif
    }
}

struct BenchmarkViewProfile: Equatable {
    var headerTopPadding: CGFloat
    var headerBottomPadding: CGFloat
    var suiteLabel: String
    var suiteFontSize: CGFloat
    var suiteTracking: CGFloat
    var headline: String
    var showsHeadlineInHeader: Bool
    var headlineFontSize: CGFloat
    var headlineHorizontalPadding: CGFloat
    var buttonFontSize: CGFloat
    var buttonHorizontalPadding: CGFloat
    var buttonVerticalPadding: CGFloat
    var resultsContentFillsHeight: Bool
    var metricLayoutStyle: BenchmarkMetricLayoutStyle
    var showsBottomBar: Bool
    var resultsHorizontalPadding: CGFloat
    var resultsBottomPadding: CGFloat
    var resultsSpacing: CGFloat
    var cardPadding: CGFloat
    var cardTitleFontSize: CGFloat
    var metricValueFontSize: CGFloat
    var bottomBarHorizontalPadding: CGFloat
    var bottomBarVerticalPadding: CGFloat
}

enum BenchmarkMetricLayoutStyle: Equatable {
    case tileGrid
    case stackedRows
}

enum BenchmarkResultsLayoutStyle: Equatable {
    case table
    case cards
    case watchCards

    static func forWidthClass(
        isCompact: Bool?,
        platform: BenchmarkPresentationPlatform = .current
    ) -> Self {
        switch platform {
        case .standard:
            isCompact == true ? .cards : .table
        case .watch:
            .watchCards
        }
    }
}

enum BenchmarkLabels {
    static let test = "TEST"
    static let pretext = "PRETEXT"
    static let coreText = "CORE TEXT"
    static let swiftUI = "SWIFTUI"
    static let speedupVsCoreText = "VS CT"
    static let speedupVsSwiftUI = "VS SWIFTUI"

    static let compactPretext = "Pretext"
    static let compactCoreText = "Core Text"
    static let compactSwiftUI = "SwiftUI"
    static let compactSpeedupVsCoreText = "Vs CT"
    static let compactSpeedupVsSwiftUI = "Vs SwiftUI"
}

func benchmarkViewProfile(for layoutStyle: BenchmarkResultsLayoutStyle) -> BenchmarkViewProfile {
    switch layoutStyle {
    case .table:
        BenchmarkViewProfile(
            headerTopPadding: 50,
            headerBottomPadding: 24,
            suiteLabel: "PRETEXT BENCHMARK SUITE",
            suiteFontSize: 14,
            suiteTracking: 2,
            headline: "Pretext vs Core Text vs SwiftUI",
            showsHeadlineInHeader: true,
            headlineFontSize: 28,
            headlineHorizontalPadding: 0,
            buttonFontSize: 13,
            buttonHorizontalPadding: 20,
            buttonVerticalPadding: 8,
            resultsContentFillsHeight: false,
            metricLayoutStyle: .tileGrid,
            showsBottomBar: true,
            resultsHorizontalPadding: 48,
            resultsBottomPadding: 16,
            resultsSpacing: 12,
            cardPadding: 14,
            cardTitleFontSize: 14,
            metricValueFontSize: 16,
            bottomBarHorizontalPadding: 24,
            bottomBarVerticalPadding: 10
        )
    case .cards:
        BenchmarkViewProfile(
            headerTopPadding: 50,
            headerBottomPadding: 24,
            suiteLabel: "PRETEXT BENCHMARK SUITE",
            suiteFontSize: 14,
            suiteTracking: 2,
            headline: "Pretext vs Core Text vs SwiftUI",
            showsHeadlineInHeader: true,
            headlineFontSize: 20,
            headlineHorizontalPadding: 20,
            buttonFontSize: 13,
            buttonHorizontalPadding: 20,
            buttonVerticalPadding: 8,
            resultsContentFillsHeight: false,
            metricLayoutStyle: .tileGrid,
            showsBottomBar: true,
            resultsHorizontalPadding: 16,
            resultsBottomPadding: 16,
            resultsSpacing: 12,
            cardPadding: 14,
            cardTitleFontSize: 14,
            metricValueFontSize: 16,
            bottomBarHorizontalPadding: 24,
            bottomBarVerticalPadding: 10
        )
    case .watchCards:
        BenchmarkViewProfile(
            headerTopPadding: 0,
            headerBottomPadding: 6,
            suiteLabel: "",
            suiteFontSize: 11,
            suiteTracking: 1.2,
            headline: "Pretext vs CoreText",
            showsHeadlineInHeader: true,
            headlineFontSize: 11,
            headlineHorizontalPadding: 0,
            buttonFontSize: 11,
            buttonHorizontalPadding: 8,
            buttonVerticalPadding: 5,
            resultsContentFillsHeight: true,
            metricLayoutStyle: .stackedRows,
            showsBottomBar: false,
            resultsHorizontalPadding: 8,
            resultsBottomPadding: 6,
            resultsSpacing: 6,
            cardPadding: 10,
            cardTitleFontSize: 13,
            metricValueFontSize: 12,
            bottomBarHorizontalPadding: 12,
            bottomBarVerticalPadding: 6
        )
    }
}

func benchmarkNavigationTitle(
    platform: BenchmarkPresentationPlatform = .current
) -> String? {
    switch platform {
    case .watch:
        nil
    case .standard:
        nil
    }
}

enum BenchmarkMetricTone: Equatable {
    case accent
    case standard
    case positive
    case caution
    case danger
    case muted

    var color: Color {
        switch self {
        case .accent:
            .green
        case .standard:
            .white.opacity(0.72)
        case .positive:
            .green
        case .caution:
            .yellow
        case .danger:
            .red
        case .muted:
            .white.opacity(0.3)
        }
    }
}

struct BenchmarkMetricDisplay: Equatable, Identifiable {
    var id: String { label }
    var label: String
    var value: String
    var tone: BenchmarkMetricTone
}

func benchmarkDisplayName(
    _ text: String,
    platform: BenchmarkPresentationPlatform = .current
) -> String {
    guard platform == .watch else {
        return text
    }

    return switch text {
    case "Batch Prepare + Layout (500 texts)":
        "Batch Layout"
    case "Reflow 100 Widths (50k calls)":
        "Reflow"
    case "Variable-Width Line-by-Line":
        "Line by Line"
    case "Interleaved Measure-Mutate (500x)":
        "Measure-Mutate"
    case "Masonry Heights":
        "Masonry"
    default:
        text
    }
}

func benchmarkRunStatusLabel(
    _ text: String,
    platform: BenchmarkPresentationPlatform = .current
) -> String {
    guard platform == .watch else {
        return text
    }

    return switch text {
    case "Test 1/5: Batch Prepare + Layout...":
        "1/5 Batch"
    case "Test 2/5: Reflow at 100 Widths...":
        "2/5 Reflow"
    case "Test 3/5: Variable-Width Line-by-Line...":
        "3/5 Line by Line"
    case "Test 4/5: Interleaved Measure-Mutate...":
        "4/5 Measure"
    case "Test 5/5: Masonry Heights...":
        "5/5 Masonry"
    default:
        text
    }
}

func benchmarkPrimaryActionLabel(
    hasRunInSession: Bool,
    platform: BenchmarkPresentationPlatform = .current
) -> String {
    switch platform {
    case .watch:
        hasRunInSession ? "Again" : "Run"
    case .standard:
        hasRunInSession ? "Run Again" : "Run Benchmarks"
    }
}

func compactBenchmarkMetrics(
    for result: BenchmarkResult,
    platform: BenchmarkPresentationPlatform = .current
) -> [BenchmarkMetricDisplay] {
    let leadingMetrics = [
        BenchmarkMetricDisplay(label: BenchmarkLabels.compactPretext, value: formatBenchmarkMs(result.pretextMs), tone: .accent),
        BenchmarkMetricDisplay(label: BenchmarkLabels.compactCoreText, value: formatBenchmarkMs(result.coreTextMs), tone: .standard),
    ]
    let speedupMetric = BenchmarkMetricDisplay(
        label: BenchmarkLabels.compactSpeedupVsCoreText,
        value: formatBenchmarkSpeedup(result.speedupVsCoreText),
        tone: benchmarkSpeedupTone(result.speedupVsCoreText)
    )

    switch platform {
    case .watch:
        return leadingMetrics + [speedupMetric]
    case .standard:
        return leadingMetrics
            + [
                BenchmarkMetricDisplay(
                    label: BenchmarkLabels.compactSwiftUI,
                    value: result.swiftUIMs.map(formatBenchmarkMs) ?? "—",
                    tone: result.swiftUIMs == nil ? .muted : .standard
                ),
                speedupMetric,
                BenchmarkMetricDisplay(
                    label: BenchmarkLabels.compactSpeedupVsSwiftUI,
                    value: result.speedupVsSwiftUI.map(formatBenchmarkSpeedup) ?? "—",
                    tone: result.speedupVsSwiftUI.map(benchmarkSpeedupTone) ?? .muted
                ),
            ]
    }
}

func formatBenchmarkMs(_ ms: Double) -> String {
    if ms < 1 {
        return String(format: "%.2fms", ms)
    } else if ms < 100 {
        return String(format: "%.1fms", ms)
    }
    return String(format: "%.0fms", ms)
}

func formatBenchmarkSpeedup(_ factor: Double) -> String {
    if factor >= 100 {
        return String(format: "%.0fx", factor)
    }
    return String(format: "%.1fx", factor)
}

func benchmarkSpeedupTone(_ factor: Double) -> BenchmarkMetricTone {
    if factor >= 10 { return .positive }
    if factor >= 2 { return .positive }
    if factor >= 1 { return .caution }
    return .danger
}
