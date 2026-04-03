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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let isCLI = CommandLine.arguments.contains("--cli")
    @State private var state: BenchmarkState = .idle
    @State private var results: [BenchmarkResult] = []

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 15 / 255, green: 15 / 255, blue: 20 / 255)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.top, viewProfile.headerTopPadding)
                        .padding(.bottom, viewProfile.headerBottomPadding)

                    if results.isEmpty && state == .idle {
                        Spacer()
                        emptyState
                        Spacer()
                    } else {
                        framedResultsContent
                    }

                    bottomBar
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .preferredColorScheme(.dark)
        .applyBenchmarkNavigationTitle(benchmarkNavigationTitle(platform: presentationPlatform))
        .onAppear {
            if state == .idle, BenchmarkAutoRunPolicy.shouldAutoRun(isCLI: isCLI) {
                runAllBenchmarks()
            }
        }
    }

    private var presentationPlatform: BenchmarkPresentationPlatform {
        .current
    }

    private var layoutStyle: BenchmarkResultsLayoutStyle {
        BenchmarkResultsLayoutStyle.forWidthClass(
            isCompact: horizontalSizeClass.map { $0 == .compact },
            platform: presentationPlatform
        )
    }

    private var viewProfile: BenchmarkViewProfile {
        benchmarkViewProfile(for: layoutStyle)
    }

    private var header: some View {
        Group {
            if layoutStyle == .watchCards {
                HStack(spacing: 10) {
                    runButton

                    if viewProfile.showsHeadlineInHeader {
                        Spacer(minLength: 0)

                        Text(viewProfile.headline)
                            .font(.system(size: viewProfile.headlineFontSize, weight: .medium, design: .default))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            } else {
                VStack(alignment: .center, spacing: viewProfile.resultsSpacing) {
                    if !viewProfile.suiteLabel.isEmpty {
                        Text(viewProfile.suiteLabel)
                            .font(.system(size: viewProfile.suiteFontSize, weight: .semibold, design: .monospaced))
                            .tracking(viewProfile.suiteTracking)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    if viewProfile.showsHeadlineInHeader {
                        Text(viewProfile.headline)
                            .font(.system(size: viewProfile.headlineFontSize, weight: .bold, design: .default))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, viewProfile.headlineHorizontalPadding)
                    }

                    runButton
                }
            }
        }
        .padding(.horizontal, layoutStyle == .watchCards ? viewProfile.resultsHorizontalPadding : 0)
        .frame(maxWidth: .infinity, alignment: layoutStyle == .watchCards ? .leading : .center)
    }

    private var runButton: some View {
        Button(action: runAllBenchmarks) {
            Group {
                switch state {
                case .idle, .done:
                    Text(
                        benchmarkPrimaryActionLabel(
                            hasRunInSession: BenchmarkAutoRunPolicy.hasRunInSession,
                            platform: presentationPlatform
                        )
                    )
                case let .running(test):
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(benchmarkRunStatusLabel(test, platform: presentationPlatform))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
            .font(.system(size: viewProfile.buttonFontSize, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, viewProfile.buttonHorizontalPadding)
            .padding(.vertical, viewProfile.buttonVerticalPadding)
            .background(.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(state != .idle && state != .done)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("5 tests comparing text layout performance")
                .foregroundStyle(.white.opacity(0.4))
            Text(emptyStateDetailText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
    }

    private var resultsTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                tableCell(BenchmarkLabels.test, width: 260, alignment: .leading, isHeader: true)
                tableCell(BenchmarkLabels.pretext, width: 100, isHeader: true)
                tableCell(BenchmarkLabels.coreText, width: 100, isHeader: true)
                tableCell(BenchmarkLabels.swiftUI, width: 100, isHeader: true)
                tableCell(BenchmarkLabels.speedupVsCoreText, width: 80, isHeader: true)
                tableCell(BenchmarkLabels.speedupVsSwiftUI, width: 80, isHeader: true)
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

    private var resultsContent: some View {
        Group {
            switch layoutStyle {
            case .table:
                VStack(spacing: 0) {
                    resultsTable
                        .padding(.horizontal, viewProfile.resultsHorizontalPadding)

                    Spacer(minLength: 16)
                }
            case .cards:
                ScrollView {
                    VStack(spacing: viewProfile.resultsSpacing) {
                        if results.isEmpty {
                            compactResultsPlaceholder
                        } else {
                            ForEach(results) { result in
                                compactResultCard(result)
                            }
                        }
                    }
                    .padding(.horizontal, viewProfile.resultsHorizontalPadding)
                    .padding(.bottom, viewProfile.resultsBottomPadding)
                }
                #if !os(watchOS)
                .scrollBounceBehavior(.basedOnSize)
                #endif
            case .watchCards:
                ScrollView {
                    VStack(spacing: viewProfile.resultsSpacing) {
                        if results.isEmpty {
                            compactResultsPlaceholder
                        } else {
                            ForEach(results) { result in
                                compactResultCard(result)
                            }
                        }
                    }
                    .padding(.horizontal, viewProfile.resultsHorizontalPadding)
                    .padding(.bottom, viewProfile.resultsBottomPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private var framedResultsContent: some View {
        if viewProfile.resultsContentFillsHeight {
            resultsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .layoutPriority(1)
        } else {
            resultsContent
        }
    }

    private func resultRow(_ result: BenchmarkResult) -> some View {
        HStack(spacing: 0) {
            tableCell(result.name, width: 260, alignment: .leading)
            tableCell(formatBenchmarkMs(result.pretextMs), width: 100, color: .green)
            tableCell(formatBenchmarkMs(result.coreTextMs), width: 100)
            tableCell(result.swiftUIMs.map(formatBenchmarkMs) ?? "—", width: 100)
            tableCell(formatBenchmarkSpeedup(result.speedupVsCoreText), width: 80, color: benchmarkSpeedupTone(result.speedupVsCoreText).color)
            tableCell(
                result.speedupVsSwiftUI.map(formatBenchmarkSpeedup) ?? "—",
                width: 80,
                color: result.speedupVsSwiftUI.map { benchmarkSpeedupTone($0).color } ?? BenchmarkMetricTone.muted.color
            )
        }
        .padding(.vertical, 6)
    }

    private var compactResultsPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.white.opacity(0.03))
            .overlay {
                VStack(spacing: 8) {
                    Text("Benchmark results will appear here.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(layoutStyle == .watchCards
                        ? "Apple Watch uses a simplified card stack."
                        : "Compact iPhone uses cards so every metric stays visible.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
    }

    private func compactResultCard(_ result: BenchmarkResult) -> some View {
        let metrics = compactBenchmarkMetrics(for: result, platform: presentationPlatform)

        return VStack(alignment: .leading, spacing: viewProfile.resultsSpacing) {
            Text(benchmarkDisplayName(result.name, platform: presentationPlatform))
                .font(.system(size: viewProfile.cardTitleFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(layoutStyle == .watchCards ? 2 : nil)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewProfile.metricLayoutStyle == .stackedRows {
                VStack(spacing: 0) {
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                        compactMetricRow(metric)

                        if index < metrics.count - 1 {
                            Divider()
                                .overlay(.white.opacity(0.06))
                        }
                    }
                }
                .background(.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVGrid(
                    columns: compactGridColumns,
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(metrics) { metric in
                        compactMetricTile(metric)
                    }
                }
            }
        }
        .padding(viewProfile.cardPadding)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func compactMetricTile(_ metric: BenchmarkMetricDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.35))

            Text(metric.value)
                .font(.system(size: viewProfile.metricValueFontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(metric.tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func compactMetricRow(_ metric: BenchmarkMetricDisplay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(metric.label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.35))

            Spacer(minLength: 8)

            Text(metric.value)
                .font(.system(size: viewProfile.metricValueFontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(metric.tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var compactGridColumns: [GridItem] {
        switch layoutStyle {
        case .watchCards:
            [GridItem(.flexible(minimum: 0), spacing: 10)]
        case .table, .cards:
            [
                GridItem(.flexible(minimum: 0), spacing: 10),
                GridItem(.flexible(minimum: 0), spacing: 10),
            ]
        }
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
        Group {
            if viewProfile.showsBottomBar {
                HStack {
                    Text(bottomBarText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer()
                    if !results.isEmpty, layoutStyle != .watchCards {
                        Text("Lower is better (ms)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
                .padding(.horizontal, viewProfile.bottomBarHorizontalPadding)
                .padding(.vertical, viewProfile.bottomBarVerticalPadding)
                .background(.black.opacity(0.3))
            }
        }
    }

    private var emptyStateDetailText: String {
        switch layoutStyle {
        case .watchCards:
            "Batch \u{00B7} Reflow \u{00B7} Line-by-Line"
        case .table, .cards:
            "Batch \u{00B7} Reflow \u{00B7} Line-by-Line \u{00B7} Thrashing \u{00B7} Masonry"
        }
    }

    private var bottomBarText: String {
        switch layoutStyle {
        case .watchCards:
            "Median of 5 runs"
        case .table, .cards:
            "Median of 5 runs \u{00B7} 1 warmup \u{00B7} ContinuousClock timing"
        }
    }

    private func runAllBenchmarks() {
        guard !isCLI else {
            return
        }

        results = []
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
                state = .running("Test 5/5: Masonry Heights...")
            }

            let r5 = runMasonryHeights()
            await MainActor.run {
                results.append(r5)
                state = .done
            }
        }
    }
}

private struct BenchmarkNavigationTitleModifier: ViewModifier {
    let title: String?

    func body(content: Content) -> some View {
        if let title {
            content.navigationTitle(title)
        } else {
            content
        }
    }
}

private extension View {
    func applyBenchmarkNavigationTitle(_ title: String?) -> some View {
        modifier(BenchmarkNavigationTitleModifier(title: title))
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
