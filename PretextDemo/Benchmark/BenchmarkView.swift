import SwiftUI

private enum BenchmarkState: Equatable {
    case idle
    case running(String)
    case done
}

struct BenchmarkView: View {
    @State private var state: BenchmarkState = .idle
    @State private var results: [BenchmarkResult] = []
    @State private var breakeven: BreakevenResult?

    var body: some View {
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

                    if let breakeven {
                        breakevenCard(breakeven)
                            .padding(.horizontal, 48)
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 16)
                }

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
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
                    Text(results.isEmpty ? "Run Benchmarks" : "Run Again")
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
            Text("Batch · Reflow · Line-by-Line · Thrashing")
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

    private func breakevenCard(_ b: BreakevenResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BREAKEVEN ANALYSIS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("Pretext pays for itself after \(b.breakevenReflows) reflows")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
            }

            Divider().background(.white.opacity(0.1))

            HStack(spacing: 32) {
                breakdownItem("prepare() cost", value: formatMs(b.prepareMs), subtitle: "one-time upfront")
                breakdownItem("CT first measure", value: formatMs(b.coreTextFirstMs), subtitle: "one-time upfront")
                breakdownItem("Pretext reflow", value: formatMs(b.pretextReflowPerCallMs), subtitle: "per width change")
                breakdownItem("CT reflow", value: formatMs(b.coreTextReflowPerCallMs), subtitle: "per width change")
            }

            Text("At 60fps animation, breakeven is reached in \(max(1, b.breakevenReflows / 60)) frame\(b.breakevenReflows / 60 == 1 ? "" : "s").")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func breakdownItem(_ label: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private func runAllBenchmarks() {
        results = []
        breakeven = nil
        state = .running("Test 1/5: Batch Prepare + Layout...")

        Task.detached {
            let r1 = runBatchPrepareAndLayout()
            await MainActor.run {
                results.append(r1)
                state = .running("Test 2/5: Reflow at 100 Widths...")
            }

            let r2 = runReflowAtDifferentWidths()
            await MainActor.run {
                results.append(r2)
                state = .running("Test 3/5: Variable-Width Line-by-Line...")
            }

            let r3 = runVariableWidthLineByLine()
            await MainActor.run {
                results.append(r3)
                state = .running("Test 4/5: Interleaved Measure-Mutate...")
            }

            let r4 = runInterleavedMeasureMutate()
            await MainActor.run {
                results.append(r4)
                state = .running("Test 5/5: Breakeven Analysis...")
            }

            let (r5, breakevenData) = runBreakevenAnalysis()
            await MainActor.run {
                results.append(r5)
                breakeven = breakevenData
                state = .done
            }
        }
    }
}
