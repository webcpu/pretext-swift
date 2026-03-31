import Pretext
import PretextUI
import SwiftUI

private enum OrbEditorialPalette {
    static let backgroundInner = Color(red: 15 / 255, green: 15 / 255, blue: 20 / 255)
    static let backgroundOuter = Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255)
    static let bodyText = Color(red: 232 / 255, green: 228 / 255, blue: 220 / 255)
    static let headline = Color.white
    static let dropCap = Color(red: 196 / 255, green: 163 / 255, blue: 90 / 255)
    static let pullquoteText = Color(red: 184 / 255, green: 160 / 255, blue: 112 / 255)
    static let pullquoteBorder = Color(red: 107 / 255, green: 90 / 255, blue: 61 / 255)
    static let statsBarBackground = Color(red: 6 / 255, green: 6 / 255, blue: 10 / 255).opacity(0.88)
    static let statsLabel = Color.white.opacity(0.35)
    static let statsValue = Color.white.opacity(0.7)
    static let statsBorder = Color.white.opacity(0.06)
    static let hintBackground = Color.black.opacity(0.45)
    static let hintText = Color.white.opacity(0.22)
}

private enum OrbPointerCursor: Equatable {
    case none
    case grab
    case grabbing

    var demoCursor: DemoPointerCursor? {
        switch self {
        case .none:
            nil
        case .grab:
            .openHand
        case .grabbing:
            .closedHand
        }
    }
}

struct OrbEditorialDisplayMode: Equatable {
    var platform: DemoNavigationPlatform
    var presentation: OrbEditorialPresentation
    var isCompactLayout: Bool
    var showsHint: Bool
    var showsStatsBar: Bool
    var showsDropCap: Bool
    var showsPullquotes: Bool
    var hintPauseVerb: String
}

func resolveOrbEditorialDisplayMode(
    isCompactWidth: Bool?,
    platform: DemoNavigationPlatform = .current,
    forceWatchPresentation: Bool = false
) -> OrbEditorialDisplayMode {
    let resolvedPlatform: DemoNavigationPlatform = forceWatchPresentation ? .watchOS : platform
    let presentation: OrbEditorialPresentation = resolvedPlatform == .watchOS ? .watch : .standard
    let isCompactLayout = resolvedPlatform == .watchOS || isCompactWidth == true
    let hidesWatchChrome = presentation == .watch

    return OrbEditorialDisplayMode(
        platform: resolvedPlatform,
        presentation: presentation,
        isCompactLayout: isCompactLayout,
        showsHint: !hidesWatchChrome,
        showsStatsBar: !hidesWatchChrome,
        showsDropCap: !hidesWatchChrome,
        showsPullquotes: !hidesWatchChrome,
        hintPauseVerb: isCompactLayout ? "Tap" : "Click"
    )
}

func orbEditorialUsesCompactLayout(
    isCompactWidth: Bool?,
    platform: DemoNavigationPlatform = .current
) -> Bool {
    resolveOrbEditorialDisplayMode(
        isCompactWidth: isCompactWidth,
        platform: platform
    )
    .isCompactLayout
}

private func orbEditorialForceWatchPresentation() -> Bool {
    #if os(watchOS)
    true
    #else
    false
    #endif
}

private struct OrbSceneState {
    var orbs: [OrbState] = []
    var drag: OrbDragState?
    var pointerLocation: CGPoint?
    var lastFrameTime: TimeInterval = 0
    var fpsTimestamps: [TimeInterval] = []
    var fpsDisplay = 60

    mutating func ensureInitialized(pageSize: CGSize, platform: DemoNavigationPlatform) {
        guard orbs.isEmpty, pageSize.width > 0, pageSize.height > 0 else {
            return
        }
        orbs = makeInitialOrbStates(pageSize: pageSize, platform: platform)
    }

    mutating func advance(
        now: TimeInterval,
        pageSize: CGSize,
        bottomInset: Double,
        platform: DemoNavigationPlatform
    ) {
        ensureInitialized(pageSize: pageSize, platform: platform)
        guard !orbs.isEmpty else {
            return
        }

        if lastFrameTime == 0 {
            lastFrameTime = now
            updateFPS(now: now)
            return
        }

        let dt = min(max(0, now - lastFrameTime), 0.05)
        lastFrameTime = now
        stepOrbPhysics(
            &orbs,
            pageSize: pageSize,
            dt: dt,
            topInset: OrbEditorialMetrics.profile(
                for: pageSize.width,
                presentation: platform == .watchOS ? .watch : .standard
            )
            .gutter * 0.5,
            bottomInset: bottomInset
        )
        updateFPS(now: now)
    }

    mutating func setPointerLocation(_ location: CGPoint?) {
        pointerLocation = location
    }

    mutating func beginDrag(at point: CGPoint, pageSize: CGSize, platform: DemoNavigationPlatform) {
        ensureInitialized(pageSize: pageSize, platform: platform)
        guard drag == nil, let orbIndex = hitTestOrb(at: point, in: orbs) else {
            return
        }

        drag = OrbDragState(
            orbIndex: orbIndex,
            startPointer: point,
            startCenter: CGPoint(x: orbs[orbIndex].x, y: orbs[orbIndex].y)
        )
        orbs[orbIndex].dragging = true
    }

    mutating func updateDrag(at point: CGPoint) {
        pointerLocation = point
        guard let drag else {
            return
        }

        orbs[drag.orbIndex].x = drag.startCenter.x + Double(point.x - drag.startPointer.x)
        orbs[drag.orbIndex].y = drag.startCenter.y + Double(point.y - drag.startPointer.y)
    }

    mutating func endDrag(at point: CGPoint?) {
        if let point {
            pointerLocation = point
        }

        guard let drag else {
            return
        }

        let endPoint = point ?? drag.startPointer
        let dx = endPoint.x - drag.startPointer.x
        let dy = endPoint.y - drag.startPointer.y
        if dx * dx + dy * dy < 16 {
            orbs[drag.orbIndex].paused.toggle()
        }
        orbs[drag.orbIndex].dragging = false
        self.drag = nil
    }

    mutating func togglePause(at point: CGPoint, pageSize: CGSize, platform: DemoNavigationPlatform) {
        ensureInitialized(pageSize: pageSize, platform: platform)
        pointerLocation = point
        guard let orbIndex = hitTestOrb(at: point, in: orbs) else {
            return
        }
        orbs[orbIndex].paused.toggle()
    }

    func hoveredOrbIndex(in orbs: [OrbState]) -> Int? {
        guard let pointerLocation else {
            return nil
        }
        return hitTestOrb(at: pointerLocation, in: orbs)
    }

    private mutating func updateFPS(now: TimeInterval) {
        fpsTimestamps.append(now)
        while let first = fpsTimestamps.first, first < now - 1 {
            fpsTimestamps.removeFirst()
        }
        fpsDisplay = fpsTimestamps.count
    }
}

private struct OrbHintPillView: View {
    private static let font = FontDescriptor(
        familyName: "Helvetica Neue",
        size: 13,
        weightValue: 0
    )
    .makeDisplayFont()

    let pauseVerb: String

    var body: some View {
        Text("Drag the orbs · \(pauseVerb) to pause · Text reflows at 60fps · Zero DOM reads")
            .font(Self.font)
            .foregroundStyle(OrbEditorialPalette.hintText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(OrbEditorialPalette.hintBackground)
            .clipShape(Capsule())
            .allowsHitTesting(false)
    }
}

private struct OrbStatItemView: View {
    let label: String
    let value: String

    private static let labelFont = FontDescriptor(
        familyName: "Helvetica Neue",
        size: 10,
        weightValue: 0
    )
    .makeDisplayFont()
    private static let valueFont = FontDescriptor(
        familyName: "Helvetica Neue",
        size: 12,
        weightValue: 0.23
    )
    .makeDisplayFont()

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(Self.labelFont)
                .tracking(0.5)
                .foregroundStyle(OrbEditorialPalette.statsLabel)
            Text(value)
                .font(Self.valueFont)
                .foregroundStyle(OrbEditorialPalette.statsValue)
        }
    }
}

private struct OrbStatsBarView: View {
    let lineCount: Int
    let reflowMilliseconds: Double
    let fps: Int
    let columnCount: Int

    var body: some View {
        HStack(spacing: 18) {
            OrbStatItemView(label: "Lines", value: "\(lineCount)")
            OrbStatItemView(label: "Reflow", value: String(format: "%.1fms", reflowMilliseconds))
            OrbStatItemView(label: "Layout reads", value: "0")
            OrbStatItemView(label: "FPS", value: "\(fps)")
            OrbStatItemView(label: "Columns", value: "\(columnCount)")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: OrbEditorialMetrics.statsBarHeight)
        .background(.ultraThinMaterial)
        .background(OrbEditorialPalette.statsBarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OrbEditorialPalette.statsBorder)
                .frame(height: 1)
        }
    }
}

private struct OrbPullquoteStaticView: View {
    let pullquote: OrbEditorialPullquoteBlock
    let fontSize: Double
    let lineHeight: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(OrbEditorialPalette.pullquoteBorder)
                .frame(width: 3, height: pullquote.rect.height)
                .offset(x: pullquote.rect.x, y: pullquote.rect.y)

            ForEach(Array(pullquote.lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(OrbEditorialMetrics.pullquoteFontDescriptor(size: fontSize).makeDisplayFont())
                    .foregroundStyle(OrbEditorialPalette.pullquoteText)
                    .frame(height: lineHeight, alignment: .topLeading)
                    .offset(x: line.x, y: line.y)
            }
        }
        .allowsHitTesting(false)
    }
}

struct OrbEditorialView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var scene = OrbSceneState()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: false)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let viewportSize = proxy.size
                let displayMode = resolveOrbEditorialDisplayMode(
                    isCompactWidth: horizontalSizeClass.map { $0 == .compact },
                    platform: .current,
                    forceWatchPresentation: orbEditorialForceWatchPresentation()
                )
                let platform = displayMode.platform
                let presentation = displayMode.presentation
                let displayOrbs = scene.orbs.isEmpty
                    ? makeInitialOrbStates(pageSize: viewportSize, platform: platform)
                    : scene.orbs
                let pageHeight = max(Double(viewportSize.height), 1)
                let snapshot = evaluateOrbEditorialLayout(
                    pageWidth: max(Double(viewportSize.width), 1),
                    pageHeight: pageHeight,
                    compositionHeight: displayMode.isCompactLayout ? max(Double(viewportSize.height), 1) : nil,
                    orbs: displayOrbs,
                    presentation: presentation
                )
                let cursor: OrbPointerCursor = if scene.drag != nil {
                    .grabbing
                } else if scene.hoveredOrbIndex(in: displayOrbs) != nil {
                    .grab
                } else {
                    .none
                }

                Group {
                    if displayMode.isCompactLayout {
                        phoneLayout(
                            viewportSize: viewportSize,
                            snapshot: snapshot,
                            displayOrbs: displayOrbs,
                            cursor: cursor,
                            platform: platform,
                            hintPauseVerb: displayMode.hintPauseVerb,
                            showsHint: displayMode.showsHint,
                            showsStatsBar: displayMode.showsStatsBar,
                            showsDropCap: displayMode.showsDropCap,
                            showsPullquotes: displayMode.showsPullquotes
                        )
                    } else {
                        desktopLayout(
                            pageSize: viewportSize,
                            snapshot: snapshot,
                            displayOrbs: displayOrbs,
                            cursor: cursor,
                            platform: platform,
                            hintPauseVerb: displayMode.hintPauseVerb
                        )
                    }
                }
                .background(OrbEditorialPalette.backgroundOuter)
                .onChange(of: now, initial: true) { _, newTime in
                    scene.advance(
                        now: newTime,
                        pageSize: viewportSize,
                        bottomInset: presentation.bottomChromeHeight,
                        platform: platform
                    )
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func desktopLayout(
        pageSize: CGSize,
        snapshot: OrbEditorialSnapshot,
        displayOrbs: [OrbState],
        cursor: OrbPointerCursor,
        platform: DemoNavigationPlatform,
        hintPauseVerb: String
    ) -> some View {
        ZStack(alignment: .topLeading) {
            orbCanvas(
                canvasSize: CGSize(width: pageSize.width, height: pageSize.height),
                snapshot: snapshot,
                displayOrbs: displayOrbs,
                includeStaticText: true
            )
            .frame(width: pageSize.width, height: pageSize.height)
            .contentShape(Rectangle())
            .gesture(orbDragGesture(in: pageSize, platform: platform))
            .demoContinuousHover { location in
                scene.setPointerLocation(location)
            }
            .demoPointerCursor(cursor.demoCursor)

            OrbHintPillView(pauseVerb: hintPauseVerb)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .zIndex(2)

            VStack {
                Spacer(minLength: 0)
                OrbStatsBarView(
                    lineCount: snapshot.bodyLines.count,
                    reflowMilliseconds: snapshot.reflowMilliseconds,
                    fps: scene.fpsDisplay,
                    columnCount: snapshot.columnCount
                )
            }
            .zIndex(2)
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipped()
    }

    @ViewBuilder
    private func phoneLayout(
        viewportSize: CGSize,
        snapshot: OrbEditorialSnapshot,
        displayOrbs: [OrbState],
        cursor: OrbPointerCursor,
        platform: DemoNavigationPlatform,
        hintPauseVerb: String,
        showsHint: Bool,
        showsStatsBar: Bool,
        showsDropCap: Bool,
        showsPullquotes: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            orbCanvas(
                canvasSize: viewportSize,
                snapshot: snapshot,
                displayOrbs: displayOrbs,
                includeStaticText: false
            )
            .frame(width: viewportSize.width, height: viewportSize.height)
            .contentShape(Rectangle())
            .simultaneousGesture(orbTapGesture(in: viewportSize, platform: platform))
            .simultaneousGesture(orbDragGesture(in: viewportSize, platform: platform))
            .demoContinuousHover { location in
                scene.setPointerLocation(location)
            }
            .demoPointerCursor(cursor.demoCursor)

            phoneStaticTextLayer(
                snapshot: snapshot,
                showsDropCap: showsDropCap,
                showsPullquotes: showsPullquotes
            )

            if showsHint {
                OrbHintPillView(pauseVerb: hintPauseVerb)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                    .zIndex(2)
            }

            if showsStatsBar {
                VStack {
                    Spacer(minLength: 0)
                    OrbStatsBarView(
                        lineCount: snapshot.bodyLines.count,
                        reflowMilliseconds: snapshot.reflowMilliseconds,
                        fps: scene.fpsDisplay,
                        columnCount: snapshot.columnCount
                    )
                }
                .zIndex(2)
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .clipped()
    }

    @ViewBuilder
    private func phoneStaticTextLayer(
        snapshot: OrbEditorialSnapshot,
        showsDropCap: Bool,
        showsPullquotes: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(snapshot.headlineLines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(Font(OrbEditorialMetrics.headlineFont(size: snapshot.headlineFontSize)))
                    .kerning(-0.5)
                    .foregroundStyle(OrbEditorialPalette.headline)
                    .frame(height: snapshot.headlineLineHeight, alignment: .topLeading)
                    .offset(x: line.x, y: line.y)
            }

            if showsDropCap {
                Text(String(OrbEditorialText.body.prefix(1)))
                    .font(Font(OrbEditorialMetrics.dropCapFont(size: snapshot.dropCapSize)))
                    .foregroundStyle(OrbEditorialPalette.dropCap)
                    .frame(width: snapshot.dropCapRect.width, height: snapshot.dropCapRect.height, alignment: .topLeading)
                    .offset(x: snapshot.dropCapPosition.x, y: snapshot.dropCapPosition.y)
            }

            if showsPullquotes {
                ForEach(Array(snapshot.pullquotes.enumerated()), id: \.offset) { _, pullquote in
                    OrbPullquoteStaticView(
                        pullquote: pullquote,
                        fontSize: snapshot.pullquoteFontSize,
                        lineHeight: snapshot.pullquoteLineHeight
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .zIndex(1)
    }

    @ViewBuilder
    private func orbCanvas(
        canvasSize: CGSize,
        snapshot: OrbEditorialSnapshot,
        displayOrbs: [OrbState],
        includeStaticText: Bool
    ) -> some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, size in
            drawBackground(in: &context, size: size)

            for orb in displayOrbs {
                drawOrb(orb, in: &context)
            }

            if includeStaticText {
                for line in snapshot.headlineLines {
                    drawTextLine(
                        line,
                        in: &context,
                        font: Font(OrbEditorialMetrics.headlineFont(size: snapshot.headlineFontSize)),
                        color: OrbEditorialPalette.headline,
                        tracking: -0.5
                    )
                }
            }

            for line in snapshot.bodyLines {
                drawTextLine(
                    line,
                    in: &context,
                    font: OrbEditorialMetrics.bodyFontDescriptor(size: snapshot.bodyFontSize).makeDisplayFont(),
                    color: OrbEditorialPalette.bodyText
                )
            }

            if includeStaticText {
                drawTextLine(
                    PositionedLine(
                        x: snapshot.dropCapPosition.x,
                        y: snapshot.dropCapPosition.y,
                        width: snapshot.dropCapRect.width,
                        text: String(OrbEditorialText.body.prefix(1))
                    ),
                    in: &context,
                    font: Font(OrbEditorialMetrics.dropCapFont(size: snapshot.dropCapSize)),
                    color: OrbEditorialPalette.dropCap
                )

                for pullquote in snapshot.pullquotes {
                    drawPullquote(
                        pullquote,
                        fontSize: snapshot.pullquoteFontSize,
                        in: &context
                    )
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private func orbTapGesture(
        in pageSize: CGSize,
        platform: DemoNavigationPlatform
    ) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .onEnded { value in
                scene.togglePause(at: value.location, pageSize: pageSize, platform: platform)
            }
    }

    private func orbDragGesture(
        in pageSize: CGSize,
        platform: DemoNavigationPlatform,
        minimumDistance: CGFloat = 0
    ) -> some Gesture {
        DragGesture(minimumDistance: minimumDistance, coordinateSpace: .local)
            .onChanged { value in
                if scene.drag == nil {
                    scene.beginDrag(at: value.startLocation, pageSize: pageSize, platform: platform)
                }
                guard scene.drag != nil else {
                    return
                }
                scene.updateDrag(at: value.location)
            }
            .onEnded { value in
                scene.endDrag(at: value.location)
            }
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(colors: [OrbEditorialPalette.backgroundInner, OrbEditorialPalette.backgroundOuter]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.4),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.85
            )
        )
    }

    private func drawOrb(_ orb: OrbState, in context: inout GraphicsContext) {
        let opacity = orb.paused ? 0.45 : 1.0
        let color = Color(
            red: orb.color.red,
            green: orb.color.green,
            blue: orb.color.blue
        )
        let center = CGPoint(x: orb.x, y: orb.y)
        let r = orb.radius

        // CSS box-shadow renders outside the element as a Gaussian-blurred glow.
        // We combine both shadows into a single smooth radial gradient ring.
        //   box-shadow: 0 0 60px 15px rgba(r,g,b,0.18),
        //               0 0 120px 40px rgba(r,g,b,0.07)
        // Peak intensity is at the orb edge; the glow fades smoothly outward.
        let glowEnd = r + 180
        let glowPath = Path(ellipseIn: CGRect(
            x: center.x - glowEnd, y: center.y - glowEnd,
            width: glowEnd * 2, height: glowEnd * 2
        ))
        context.fill(glowPath, with: .radialGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: max(0, (r - 4)) / glowEnd),
                .init(color: color.opacity(0.14 * opacity), location: r / glowEnd),
                .init(color: color.opacity(0.10 * opacity), location: (r + 20) / glowEnd),
                .init(color: color.opacity(0.06 * opacity), location: (r + 50) / glowEnd),
                .init(color: color.opacity(0.03 * opacity), location: (r + 90) / glowEnd),
                .init(color: color.opacity(0.01 * opacity), location: (r + 140) / glowEnd),
                .init(color: .clear, location: 1.0),
            ]),
            center: center, startRadius: 0, endRadius: glowEnd
        ))

        // CSS: background: radial-gradient(circle at 35% 35%,
        //        rgba(r,g,b,0.35), rgba(r,g,b,0.12) 55%, transparent 72%)
        //
        // "circle at 35% 35%" in a 2r x 2r div: gradient center at
        // (cx - 0.3r, cy - 0.3r). CSS "circle" resolves % stops against
        // the farthest-corner distance: sqrt(65² + 65²) ≈ 91.9% of 2r
        // → endRadius = 1.838r.
        let highlightCenter = CGPoint(x: orb.x - r * 0.3, y: orb.y - r * 0.3)
        let endR = r * 1.838
        let orbFillPath = Path(ellipseIn: CGRect(
            x: orb.x - r, y: orb.y - r, width: r * 2, height: r * 2
        ))
        context.fill(orbFillPath, with: .radialGradient(
            Gradient(stops: [
                .init(color: color.opacity(0.38 * opacity), location: 0),
                .init(color: color.opacity(0.25 * opacity), location: 0.25),
                .init(color: color.opacity(0.12 * opacity), location: 0.55),
                .init(color: color.opacity(0.03 * opacity), location: 0.68),
                .init(color: color.opacity(0), location: 0.72),
                .init(color: color.opacity(0), location: 1.0),
            ]),
            center: highlightCenter, startRadius: 0, endRadius: endR
        ))
    }

    private func drawPullquote(
        _ pullquote: OrbEditorialPullquoteBlock,
        fontSize: Double,
        in context: inout GraphicsContext
    ) {
        let borderRect = CGRect(
            x: pullquote.rect.x,
            y: pullquote.rect.y,
            width: 3,
            height: pullquote.rect.height
        )
        context.fill(Path(borderRect), with: .color(OrbEditorialPalette.pullquoteBorder))

        for line in pullquote.lines {
            drawTextLine(
                line,
                in: &context,
                font: OrbEditorialMetrics.pullquoteFontDescriptor(size: fontSize).makeDisplayFont(),
                color: OrbEditorialPalette.pullquoteText
            )
        }
    }

    private func drawTextLine(
        _ line: PositionedLine,
        in context: inout GraphicsContext,
        font: Font,
        color: Color,
        tracking: Double? = nil
    ) {
        var text = Text(line.text)
            .font(font)

        if let tracking {
            text = text.kerning(tracking)
        }

        var resolved = context.resolve(text)
        resolved.shading = .color(color)
        context.draw(
            resolved,
            at: CGPoint(x: line.x, y: line.y),
            anchor: .topLeading
        )
    }
}
