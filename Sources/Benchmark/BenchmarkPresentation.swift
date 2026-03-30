import SwiftUI

enum BenchmarkResultsLayoutStyle: Equatable {
    case table
    case cards

    static func forWidthClass(isCompact: Bool?) -> Self {
        isCompact == true ? .cards : .table
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

func compactBenchmarkMetrics(for result: BenchmarkResult) -> [BenchmarkMetricDisplay] {
    [
        BenchmarkMetricDisplay(label: "Pretext", value: formatBenchmarkMs(result.pretextMs), tone: .accent),
        BenchmarkMetricDisplay(label: "Core Text", value: formatBenchmarkMs(result.coreTextMs), tone: .standard),
        BenchmarkMetricDisplay(
            label: "SwiftUI",
            value: result.swiftUIMs.map(formatBenchmarkMs) ?? "—",
            tone: result.swiftUIMs == nil ? .muted : .standard
        ),
        BenchmarkMetricDisplay(
            label: "Vs CT",
            value: formatBenchmarkSpeedup(result.speedupVsCoreText),
            tone: benchmarkSpeedupTone(result.speedupVsCoreText)
        ),
        BenchmarkMetricDisplay(
            label: "Vs SUI",
            value: result.speedupVsSwiftUI.map(formatBenchmarkSpeedup) ?? "—",
            tone: result.speedupVsSwiftUI.map(benchmarkSpeedupTone) ?? .muted
        ),
    ]
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
