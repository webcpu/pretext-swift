import CoreText
import Pretext
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

struct MasonryView: View {
    @State private var engine: MasonryEngine = .pretext
    @State private var passes: Int = 1
    @State private var scrollOffset: Double = 0
    @State private var layoutMs: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = Double(proxy.size.width)
            let columns = computeMasonryColumns(viewportWidth: viewportWidth)

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
                cardHeights: timed.heights
            )

            ZStack(alignment: .bottom) {
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(height: layoutResult.contentHeight)
                            .background(
                                GeometryReader { scrollProxy in
                                    Color.clear.preference(
                                        key: ScrollOffsetKey.self,
                                        value: -scrollProxy.frame(in: .named("masonry")).minY
                                    )
                                }
                            )

                        ForEach(0..<layoutResult.positionedCards.count, id: \.self) { i in
                            let card = layoutResult.positionedCards[i]
                            cardView(card, colWidth: layoutResult.colWidth)
                        }
                    }
                }
                .coordinateSpace(name: "masonry")
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    scrollOffset = value
                    layoutMs = timed.ms
                }

                MasonryStatsBar(
                    cardCount: MasonryData.texts.count,
                    columnCount: layoutResult.colCount,
                    engine: engine,
                    passes: passes,
                    layoutMs: layoutMs,
                    onToggle: { engine = engine == .pretext ? .coreText : .pretext },
                    onPassesChanged: { passes = $0 }
                )
            }
        }
        .background(MasonryPalette.background)
        .preferredColorScheme(.light)
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

private struct MasonryStatsBar: View {
    let cardCount: Int
    let columnCount: Int
    let engine: MasonryEngine
    let passes: Int
    let layoutMs: Double
    let onToggle: () -> Void
    let onPassesChanged: (Int) -> Void

    private static let frameBudgetMs = 16.67 // 60fps
    private static let barMaxMs = 40.0 // full bar width

    private static let labelFont = FontDescriptor(
        familyName: "Helvetica Neue", size: 10
    ).makeDisplayFont()

    private static let valueFont = FontDescriptor(
        familyName: "Helvetica Neue", size: 12, weightValue: 0.23
    ).makeDisplayFont()

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

            HStack(spacing: 18) {
                statItem("Cards", value: "\(cardCount)")
                statItem("Columns", value: "\(columnCount)")
                statItem("Engine", value: engine.rawValue)
                statItem("Layout", value: String(format: "%.1fms", layoutMs))
                statItem("Budget", value: String(
                    format: "%.0f%%",
                    layoutMs / Self.frameBudgetMs * 100
                ))

                Button(action: onToggle) {
                    Text("Switch to \(engine == .pretext ? "Core Text" : "Pretext")")
                        .font(Self.valueFont)
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
                        .font(Self.labelFont)
                        .tracking(0.5)
                        .foregroundStyle(.black.opacity(0.35))
                    ForEach(passOptions, id: \.self) { n in
                        Button(action: { onPassesChanged(n) }) {
                            Text("\(n)x")
                                .font(Self.valueFont)
                                .foregroundStyle(passes == n ? .white : .black.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(
                                        passes == n
                                            ? Color.black.opacity(0.6)
                                            : Color.black.opacity(0.08)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 36)
        }
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(height: 1)
        }
    }

    private func statItem(_ label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(Self.labelFont)
                .tracking(0.5)
                .foregroundStyle(.black.opacity(0.35))
            Text(value)
                .font(Self.valueFont)
                .foregroundStyle(.black.opacity(0.7))
        }
    }
}
