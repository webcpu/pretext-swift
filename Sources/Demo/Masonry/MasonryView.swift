import CoreText
import Pretext
import PretextUI
import SwiftUI

private enum MasonryData {
    static let texts: [String] = {
        guard let url = Bundle.module.url(forResource: "shower-thoughts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }()

    static let prepared: [PreparedText] = {
        let font = MasonryMetrics.cardCTFont()
        return texts.map { prepare($0, font: font) }
    }()
}

enum MasonryEngine: String, CaseIterable {
    case pretext = "Pretext"
    case coreText = "Core Text"
}

func masonryUsesCompactStatsBar(
    platform: DemoNavigationPlatform = .current
) -> Bool {
    platform == .watchOS
}

func masonryStatsBarHeight(
    platform: DemoNavigationPlatform = .current
) -> Double {
    masonryUsesCompactStatsBar(platform: platform) ? 56 : 36
}

func masonryStatsBarHorizontalPadding(
    platform: DemoNavigationPlatform = .current
) -> Double {
    masonryUsesCompactStatsBar(platform: platform) ? 12 : 18
}

func masonryUsesSplitWatchControlRows(
    platform: DemoNavigationPlatform = .current
) -> Bool {
    masonryUsesCompactStatsBar(platform: platform)
}

func masonryContentBottomInset(
    platform: DemoNavigationPlatform = .current
) -> Double {
    masonryUsesCompactStatsBar(platform: platform) ? masonryStatsBarHeight(platform: platform) : 0
}

func masonryStatsMetricLabels(
    platform: DemoNavigationPlatform = .current
) -> [String] {
    switch platform {
    case .watchOS:
        ["Cards", "Cols", "Layout", "Budget"]
    case .ios, .macOS:
        ["Cards", "Columns", "Engine", "Layout", "Budget"]
    }
}

struct MasonryWatchEngineOption: Equatable, Sendable {
    let engine: MasonryEngine
    let title: String
    let isActive: Bool
}

func masonryWatchEngineOptions(current: MasonryEngine) -> [MasonryWatchEngineOption] {
    MasonryEngine.allCases.map { engine in
        MasonryWatchEngineOption(
            engine: engine,
            title: engine == .coreText ? "CoreText" : engine.rawValue,
            isActive: engine == current
        )
    }
}

func masonryRenderedCardIndices(
    from positionedCards: [PositionedCard],
    scrollOffset: Double,
    viewportHeight: Double
) -> [Int] {
    visibleCardIndices(
        from: positionedCards,
        scrollOffset: scrollOffset,
        viewportHeight: viewportHeight
    )
}

struct MasonryView: View {
    @State private var engine: MasonryEngine = .pretext
    @State private var passes: Int = 1
    @State private var scrollOffset: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let platform = DemoNavigationPlatform.current
            let viewportWidth = Double(proxy.size.width)
            let viewportHeight = Double(proxy.size.height)
            let columns = computeMasonryColumns(
                viewportWidth: viewportWidth,
                platform: platform
            )

            // Recompute heights every time scrollOffset or engine changes.
            // Pretext handles this in <1ms; Core Text takes ~26ms and will stutter.
            let timed = timedCardHeights(
                engine: engine,
                colWidth: columns.colWidth,
                passes: passes,
                scrollTick: scrollOffset
            )
            let layoutResult = computeMasonryLayout(
                viewportWidth: viewportWidth,
                cardHeights: timed.heights,
                platform: platform
            )
            let renderedCardIndices = masonryRenderedCardIndices(
                from: layoutResult.positionedCards,
                scrollOffset: scrollOffset,
                viewportHeight: viewportHeight
            )

            ZStack(alignment: .bottom) {
                masonryScrollView(
                    layoutResult: layoutResult,
                    renderedCardIndices: renderedCardIndices,
                    bottomInset: masonryContentBottomInset(platform: platform)
                )
                statsBar(
                    platform: platform,
                    columnCount: layoutResult.colCount,
                    layoutMs: timed.ms
                )
            }
        }
        .background(MasonryPalette.background)
        .preferredColorScheme(.light)
    }

    private func masonryScrollView(
        layoutResult: MasonryLayoutResult,
        renderedCardIndices: [Int],
        bottomInset: Double
    ) -> some View {
        ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(height: layoutResult.contentHeight + bottomInset)
                    .background(
                        GeometryReader { scrollProxy in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: -scrollProxy.frame(in: .named("masonry")).minY
                            )
                        }
                    )

                ForEach(renderedCardIndices, id: \.self) { i in
                    let card = layoutResult.positionedCards[i]
                    cardView(card, colWidth: layoutResult.colWidth)
                }
            }
        }
        .coordinateSpace(.named("masonry"))
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
        }
    }

    private func statsBar(
        platform: DemoNavigationPlatform,
        columnCount: Int,
        layoutMs: Double
    ) -> some View {
        MasonryStatsBar(
            cardCount: MasonryData.texts.count,
            columnCount: columnCount,
            engine: engine,
            passes: passes,
            layoutMs: layoutMs,
            platform: platform,
            onToggle: { engine = engine == .pretext ? .coreText : .pretext },
            onPassesChanged: { passes = $0 }
        )
    }

    private func cardView(_ card: PositionedCard, colWidth: Double) -> some View {
        Text(MasonryData.texts[card.cardIndex])
            .font(MasonryMetrics.cardDisplayFont())
            .foregroundStyle(MasonryPalette.cardText)
            .lineSpacing(MasonryMetrics.lineHeight - MasonryMetrics.fontSize)
            .padding(MasonryMetrics.cardPadding)
            .frame(width: colWidth, height: card.height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: MasonryMetrics.cardCornerRadius)
                    .fill(MasonryPalette.cardBackground)
                    .shadow(color: MasonryPalette.cardShadowColor, radius: 1.5, x: 0, y: 1)
            )
            .offset(x: card.x, y: card.y)
    }
}

// MARK: - Scroll offset tracking

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

// MARK: - Timed height computation

private struct TimedHeights: Equatable {
    var heights: [Double]
    var ms: Double
}

private func timedCardHeights(
    engine: MasonryEngine,
    colWidth: Double,
    passes: Int,
    scrollTick: Double  // unused value — its presence forces SwiftUI to recompute on scroll
) -> TimedHeights {
    let textWidth = colWidth - MasonryMetrics.cardPadding * 2
    let start = CFAbsoluteTimeGetCurrent()

    var heights: [Double] = []
    for _ in 0..<passes {
        switch engine {
        case .pretext:
            heights = MasonryData.prepared.map { p in
                layout(p, maxWidth: textWidth, lineHeight: MasonryMetrics.lineHeight).height
                    + MasonryMetrics.cardPadding * 2
            }
        case .coreText:
            let font = MasonryMetrics.cardCTFont()
            heights = MasonryData.texts.map { text in
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                let attrStr = NSAttributedString(string: text, attributes: attrs)
                let fs = CTFramesetterCreateWithAttributedString(attrStr)
                let constraint = CGSize(width: colWidth, height: .greatestFiniteMagnitude)
                let size = CTFramesetterSuggestFrameSizeWithConstraints(
                    fs, CFRange(location: 0, length: 0), nil, constraint, nil
                )
                return Double(size.height) + MasonryMetrics.cardPadding * 2
            }
        }
    }

    let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
    return TimedHeights(heights: heights, ms: ms)
}

// MARK: - Stats bar

private let passOptions = [1, 2, 5, 10]

private struct MasonryStatItemView: View {
    let label: String
    let value: String
    let stacked: Bool
    let compact: Bool

    private var labelFont: Font {
        FontDescriptor(
            familyName: "Helvetica Neue",
            size: compact ? 7 : 10
        ).makeDisplayFont()
    }

    private var valueFont: Font {
        FontDescriptor(
            familyName: "Helvetica Neue",
            size: compact ? 9 : 12,
            weightValue: 0.23
        ).makeDisplayFont()
    }

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 1) {
                    statLabel
                    statValue
                }
            } else {
                HStack(spacing: 6) {
                    statLabel
                    statValue
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statLabel: some View {
        Text(label.uppercased())
            .font(labelFont)
            .tracking(0.5)
            .foregroundStyle(.black.opacity(0.35))
    }

    private var statValue: some View {
        Text(value)
            .font(valueFont)
            .foregroundStyle(.black.opacity(0.7))
    }
}

private struct MasonryStatsBar: View {
    let cardCount: Int
    let columnCount: Int
    let engine: MasonryEngine
    let passes: Int
    let layoutMs: Double
    let platform: DemoNavigationPlatform
    let onToggle: () -> Void
    let onPassesChanged: (Int) -> Void

    private static let frameBudgetMs = 16.67 // 60fps
    private static let barMaxMs = 40.0 // full bar width

    private var budgetFraction: Double {
        min(layoutMs / Self.barMaxMs, 1.0)
    }

    private var budgetColor: Color {
        if layoutMs < Self.frameBudgetMs * 0.5 { return .green }
        if layoutMs < Self.frameBudgetMs { return .yellow }
        return .red
    }

    var body: some View {
        VStack(spacing: 0) {
            // Frame budget bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.06))

                    Rectangle()
                        .fill(budgetColor)
                        .frame(width: max(2, geo.size.width * budgetFraction))

                    // 16.67ms budget line
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 1)
                        .offset(x: geo.size.width * (Self.frameBudgetMs / Self.barMaxMs))
                }
            }
            .frame(height: 4)

            if masonryUsesCompactStatsBar(platform: platform) {
                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        ForEach(Array(compactStats.enumerated()), id: \.offset) { _, stat in
                            MasonryStatItemView(
                                label: stat.label,
                                value: stat.value,
                                stacked: false,
                                compact: true
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if masonryUsesSplitWatchControlRows(platform: platform) {
                        HStack(spacing: 4) {
                            Spacer(minLength: 0)
                            ForEach(masonryWatchEngineOptions(current: engine), id: \.engine) { option in
                                watchEngineButton(option, compact: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    HStack(spacing: 3) {
                        Spacer(minLength: 0)
                        ForEach(passOptions, id: \.self) { n in
                            passButton(n, compact: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, masonryStatsBarHorizontalPadding(platform: platform))
                .padding(.vertical, 2)
                .frame(minHeight: masonryStatsBarHeight(platform: platform) - 4)
            } else {
                HStack(spacing: 18) {
                    ForEach(Array(standardStats.enumerated()), id: \.offset) { _, stat in
                        MasonryStatItemView(
                            label: stat.label,
                            value: stat.value,
                            stacked: false,
                            compact: false
                        )
                    }

                    Button(action: onToggle) {
                        Text("Switch to \(engine == .pretext ? "Core Text" : "Pretext")")
                            .font(controlFont(compact: false))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.black.opacity(0.6))
                            )
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 4) {
                        Text("PASSES")
                            .font(labelFont(compact: false))
                            .tracking(0.5)
                            .foregroundStyle(.black.opacity(0.35))
                        ForEach(passOptions, id: \.self) { n in
                            passButton(n, compact: false)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .frame(height: masonryStatsBarHeight(platform: platform))
            }
        }
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(height: 1)
        }
    }

    private var formattedLayoutMs: String {
        String(format: "%.1fms", layoutMs)
    }

    private var formattedBudget: String {
        String(format: "%.0f%%", layoutMs / Self.frameBudgetMs * 100)
    }

    private var compactStats: [(label: String, value: String)] {
        zip(
            masonryStatsMetricLabels(platform: platform),
            [
                "\(cardCount)",
                "\(columnCount)",
                formattedLayoutMs,
                formattedBudget,
            ]
        )
        .map { (label: $0.0, value: $0.1) }
    }

    private var standardStats: [(label: String, value: String)] {
        zip(
            masonryStatsMetricLabels(platform: platform),
            [
                "\(cardCount)",
                "\(columnCount)",
                engine.rawValue,
                formattedLayoutMs,
                formattedBudget,
            ]
        )
        .map { (label: $0.0, value: $0.1) }
    }

    private func passButton(_ passesOption: Int, compact: Bool) -> some View {
        Button(action: { onPassesChanged(passesOption) }) {
            Text("\(passesOption)x")
                .font(controlFont(compact: compact))
                .foregroundStyle(passes == passesOption ? .white : .black.opacity(0.5))
                .padding(.horizontal, compact ? 3 : 8)
                .padding(.vertical, compact ? 2 : 3)
                .background(
                    Capsule().fill(
                        passes == passesOption
                            ? Color.black.opacity(0.6)
                            : Color.black.opacity(0.08)
                    )
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func watchEngineButton(_ option: MasonryWatchEngineOption, compact: Bool) -> some View {
        if option.isActive {
            Text(option.title)
                .font(controlFont(compact: compact))
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 6 : 12)
                .padding(.vertical, compact ? 2 : 4)
                .background(
                    Capsule().fill(Color.black.opacity(0.6))
                )
        } else {
            Button(action: onToggle) {
                Text(option.title)
                    .font(controlFont(compact: compact))
                    .foregroundStyle(.black.opacity(0.65))
                    .padding(.horizontal, compact ? 6 : 12)
                    .padding(.vertical, compact ? 2 : 4)
                    .background(
                        Capsule().fill(Color.black.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func labelFont(compact: Bool) -> Font {
        FontDescriptor(
            familyName: "Helvetica Neue",
            size: compact ? 9 : 10
        ).makeDisplayFont()
    }

    private func controlFont(compact: Bool) -> Font {
        FontDescriptor(
            familyName: "Helvetica Neue",
            size: compact ? 8 : 12,
            weightValue: 0.23
        ).makeDisplayFont()
    }
}
