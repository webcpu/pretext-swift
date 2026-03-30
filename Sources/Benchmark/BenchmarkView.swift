import Foundation
import Pretext
import SwiftUI

private enum BenchmarkState: Equatable {
    case idle
    case running(String)
    case done
}

@MainActor
enum BenchmarkAutoRunPolicy {
    private static var hasAutoRunInSession = false

    static var hasRunInSession: Bool {
        hasAutoRunInSession
    }

    static func shouldAutoRun(isCLI: Bool) -> Bool {
        guard !isCLI, !hasAutoRunInSession else {
            return false
        }

        hasAutoRunInSession = true
        return true
    }

    static func resetForTests() {
        hasAutoRunInSession = false
    }
}

public struct BenchmarkView: View {
    private let isCLI = CommandLine.arguments.contains("--cli")
    @State private var state: BenchmarkState = .idle
    @State private var results: [BenchmarkResult] = []

    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 15 / 255, green: 15 / 255, blue: 20 / 255)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 50)
                    .padding(.bottom, 24)

                if results.isEmpty && state == .idle {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    resultsTable
                        .padding(.horizontal, 48)

                    Spacer(minLength: 16)
                }

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if state == .idle, BenchmarkAutoRunPolicy.shouldAutoRun(isCLI: isCLI) {
                runAllBenchmarks()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("PRETEXT BENCHMARK SUITE")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.5))

            Text("Pretext vs Core Text vs SwiftUI")
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(.white)

            runButton
        }
    }

    private var runButton: some View {
        Button(action: runAllBenchmarks) {
            Group {
                switch state {
                case .idle, .done:
                    Text(BenchmarkAutoRunPolicy.hasRunInSession ? "Run Again" : "Run Benchmarks")
                case let .running(test):
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(test)
                    }
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(state != .idle && state != .done)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("4 tests comparing text layout performance")
                .foregroundStyle(.white.opacity(0.4))
            Text("Batch \u{00B7} Reflow \u{00B7} Line-by-Line \u{00B7} Thrashing")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    private var resultsTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                tableCell("TEST", width: 260, alignment: .leading, isHeader: true)
                tableCell("PRETEXT", width: 100, isHeader: true)
                tableCell("CORE TEXT", width: 100, isHeader: true)
                tableCell("SWIFTUI", width: 100, isHeader: true)
                tableCell("VS CT", width: 80, isHeader: true)
                tableCell("VS SUI", width: 80, isHeader: true)
            }
            .padding(.vertical, 8)
            .background(.white.opacity(0.05))

            Divider().background(.white.opacity(0.1))

            // Result rows
            ForEach(results) { result in
                resultRow(result)
                Divider().background(.white.opacity(0.05))
            }
        }
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func resultRow(_ result: BenchmarkResult) -> some View {
        HStack(spacing: 0) {
            tableCell(result.name, width: 260, alignment: .leading)
            tableCell(formatMs(result.pretextMs), width: 100, color: .green)
            tableCell(formatMs(result.coreTextMs), width: 100)
            tableCell(result.swiftUIMs.map(formatMs) ?? "—", width: 100)
            tableCell(formatSpeedup(result.speedupVsCoreText), width: 80, color: speedupColor(result.speedupVsCoreText))
            tableCell(result.speedupVsSwiftUI.map(formatSpeedup) ?? "—", width: 80, color: result.speedupVsSwiftUI.map(speedupColor) ?? .white.opacity(0.3))
        }
        .padding(.vertical, 6)
    }

    private func tableCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .trailing,
        isHeader: Bool = false,
        color: Color = .white.opacity(0.7)
    ) -> some View {
        Text(text)
            .font(.system(size: isHeader ? 10 : 12, weight: isHeader ? .semibold : .medium, design: .monospaced))
            .foregroundStyle(isHeader ? .white.opacity(0.4) : color)
            .frame(width: width, alignment: alignment)
    }

    private var bottomBar: some View {
        HStack {
            Text("Median of 5 runs · 1 warmup · ContinuousClock timing")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
            Spacer()
            if !results.isEmpty {
                Text("Lower is better (ms)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.black.opacity(0.3))
    }

    private func formatMs(_ ms: Double) -> String {
        if ms < 1 {
            return String(format: "%.2fms", ms)
        } else if ms < 100 {
            return String(format: "%.1fms", ms)
        }
        return String(format: "%.0fms", ms)
    }

    private func formatSpeedup(_ factor: Double) -> String {
        if factor >= 100 {
            return String(format: "%.0fx", factor)
        }
        return String(format: "%.1fx", factor)
    }

    private func speedupColor(_ factor: Double) -> Color {
        if factor >= 10 { return .green }
        if factor >= 2 { return Color(red: 0.6, green: 0.9, blue: 0.3) }
        if factor >= 1 { return .yellow }
        return .red
    }

    private func runAllBenchmarks() {
        guard !isCLI else {
            return
        }

        results = []
        state = .running("Test 1/4: Batch Prepare + Layout...")

        Task.detached {
            let r1 = runBatchPrepareAndLayout()
            await MainActor.run {
                results.append(r1)
                state = .running("Test 2/4: Reflow at 100 Widths...")
            }

            let r2 = runReflowAtDifferentWidths()
            await MainActor.run {
                results.append(r2)
                state = .running("Test 3/4: Variable-Width Line-by-Line...")
            }

            let r3 = runVariableWidthLineByLine()
            await MainActor.run {
                results.append(r3)
                state = .running("Test 4/4: Interleaved Measure-Mutate...")
            }

            let r4 = runInterleavedMeasureMutate()
            await MainActor.run {
                results.append(r4)
                state = .done
            }
        }
    }
}

public func runBenchmarkCLI() {
    let result = runBatchPrepareAndLayout()

    PrepareProfile.reset()
    AnalysisSubProfile.reset()
    let texts = BenchmarkCorpus.texts
    let font = BenchmarkCorpus.font
    let width = BenchmarkCorpus.testWidth
    let lineHeight = BenchmarkCorpus.lineHeight
    for text in texts {
        let prepared = prepare(text, font: font)
        _ = layout(prepared, maxWidth: width, lineHeight: lineHeight)
    }

    print("=== Batch Prepare+Layout (500 texts) ===")
    print(String(format: "Pretext:    %8.2f ms", result.pretextMs))
    print(String(format: "Core Text:  %8.2f ms", result.coreTextMs))
    if let swiftUI = result.swiftUIMs {
        print(String(format: "SwiftUI:    %8.2f ms", swiftUI))
    }
    print(String(format: "Speedup vs Core Text: %.1fx", result.speedupVsCoreText))
    if let speedup = result.speedupVsSwiftUI {
        print(String(format: "Speedup vs SwiftUI:   %.1fx", speedup))
    }
    print()
    print(PrepareProfile.summary())
    print(AnalysisSubProfile.summary())

    exit(0)
}
