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

func compactBenchmarkMetrics(
    for result: BenchmarkResult,
    platform: BenchmarkPresentationPlatform = .current
) -> [BenchmarkMetricDisplay] {
    let leadingMetrics = [
        BenchmarkMetricDisplay(label: "Pretext", value: formatBenchmarkMs(result.pretextMs), tone: .accent),
        BenchmarkMetricDisplay(label: "Core Text", value: formatBenchmarkMs(result.coreTextMs), tone: .standard),
    ]
    let speedupMetric = BenchmarkMetricDisplay(
        label: "Vs CT",
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
                    label: "SwiftUI",
                    value: result.swiftUIMs.map(formatBenchmarkMs) ?? "—",
                    tone: result.swiftUIMs == nil ? .muted : .standard
                ),
                speedupMetric,
                BenchmarkMetricDisplay(
                    label: "Vs SUI",
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
