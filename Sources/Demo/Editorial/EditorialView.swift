import Pretext
import PretextUI
import SwiftUI

private enum LogoKind {
    case openai
    case claude
}

struct SpinState: Equatable {
    var from: Double
    var to: Double
    var start: TimeInterval
    var duration: TimeInterval
}

private struct LogoAnimationState {
    var angle: Double = 0
    var spin: SpinState?
}

private struct AnimationSnapshot {
    var openaiAngle: Double
    var claudeAngle: Double
    var animating: Bool
    var needsCommit: Bool
}

private enum EditorialPalette {
    static let paper = SituationalAwarenessPalette.paper
    static let ink = SituationalAwarenessPalette.ink
    static let accent = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
    static let mutedInk = ink.opacity(0.58)
    static let hintBackground = ink.opacity(0.94)
    static let hintText = paper.opacity(0.96)
    static let leftAtmospherePrimary = Color(red: 45 / 255, green: 88 / 255, blue: 128 / 255)
    static let leftAtmosphereSecondary = Color(red: 57 / 255, green: 78 / 255, blue: 124 / 255)
}

struct EditorialHintStyle: Equatable {
    var fontSize: Double
    var weightValue: Double
    var horizontalPadding: Double
    var verticalPadding: Double
    var maxWidth: Double?
}

func editorialInteractionHintText(isNarrow: Bool) -> String {
    if isNarrow {
        return "The logos spin in. Tap either one to spin it again."
    }
    return "Everything laid out in Swift. Click the logos."
}

func editorialShouldAutoSpinOnAppear(
    platform: DemoNavigationPlatform = .current
) -> Bool {
    switch platform {
    case .ios, .macOS, .watchOS:
        true
    }
}

func editorialHintTopPadding(
    safeAreaTop: Double,
    platform: DemoNavigationPlatform = .current
) -> Double {
    switch platform {
    case .macOS:
        max(safeAreaTop + 24, 52)
    case .ios, .watchOS:
        16
    }
}

func editorialHintStyle(
    isNarrow: Bool,
    platform: DemoNavigationPlatform = .current
) -> EditorialHintStyle {
    if platform == .macOS, !isNarrow {
        return EditorialHintStyle(
            fontSize: 15,
            weightValue: 0.34,
            horizontalPadding: 22,
            verticalPadding: 13,
            maxWidth: nil
        )
    }

    return EditorialHintStyle(
        fontSize: 12,
        weightValue: 0.23,
        horizontalPadding: 16,
        verticalPadding: 10,
        maxWidth: isNarrow ? 320 : nil
    )
}

func editorialIntroSpinPlan(startTime: TimeInterval) -> (openai: SpinState, claude: SpinState) {
    (
        openai: SpinState(from: 0, to: -.pi, start: startTime, duration: 0.9),
        claude: SpinState(from: 0, to: .pi, start: startTime, duration: 0.9)
    )
}

private struct HintPillView: View {
    let isNarrow: Bool
    let platform: DemoNavigationPlatform

    private var style: EditorialHintStyle {
        editorialHintStyle(isNarrow: isNarrow, platform: platform)
    }

    private var hintFont: Font {
        FontDescriptor(
            familyName: "Helvetica Neue",
            size: style.fontSize,
            weightValue: style.weightValue
        )
        .makeDisplayFont()
    }

    var body: some View {
        Text(editorialInteractionHintText(isNarrow: isNarrow))
            .lineLimit(isNarrow ? 2 : 1)
            .multilineTextAlignment(.center)
            .foregroundStyle(EditorialPalette.hintText)
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .frame(maxWidth: style.maxWidth.map { CGFloat($0) })
            .fixedSize(horizontal: !isNarrow, vertical: false)
            .environment(\.font, hintFont)
            .background(EditorialPalette.hintBackground)
            .clipShape(Capsule())
            .shadow(color: EditorialPalette.ink.opacity(0.16), radius: 32, x: 0, y: 14)
            .allowsHitTesting(false)
    }
}

private struct EditorialBackgroundView: View {
    var size: CGSize

    var body: some View {
        ZStack {
            EditorialPalette.paper

            atmosphereBlob(
                color: EditorialPalette.leftAtmospherePrimary.opacity(0.16),
                widthFactor: 0.744,
                heightFactor: 0.648,
                centerX: 0.092,
                centerY: 0.884
            )

            atmosphereBlob(
                color: EditorialPalette.leftAtmosphereSecondary.opacity(0.07),
                widthFactor: 0.528,
                heightFactor: 0.408,
                centerX: 0.236,
                centerY: 0.668
            )

            atmosphereBlob(
                color: EditorialPalette.accent.opacity(0.18),
                widthFactor: 0.696,
                heightFactor: 0.576,
                centerX: 0.932,
                centerY: 0.092
            )

            LinearGradient(
                colors: [
                    EditorialPalette.accent.opacity(0.055),
                    EditorialPalette.accent.opacity(0.02),
                    .clear,
                    EditorialPalette.leftAtmospherePrimary.opacity(0.045),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: size.width * 1.2, height: size.height * 1.2)
            .offset(x: -size.width * 0.1, y: -size.height * 0.1)
        }
        .ignoresSafeArea()
    }

    private func atmosphereBlob(
        color: Color,
        widthFactor: Double,
        heightFactor: Double,
        centerX: Double,
        centerY: Double
    ) -> some View {
        RadialGradient(
            colors: [color, .clear],
            center: .center,
            startRadius: 0,
            endRadius: max(size.width * widthFactor, size.height * heightFactor) * 0.5
        )
        .frame(width: size.width * widthFactor, height: size.height * heightFactor)
        .position(x: size.width * centerX, y: size.height * centerY)
    }
}

private struct EditorialTextProjection: Equatable {
    var headlineLines: [PositionedLine]
    var headlineFontSize: Double
    var headlineLineHeight: Double
    var creditLeft: Double
    var creditTop: Double
    var isNarrow: Bool
    var bodyLines: [PositionedLine]
}

private struct HeadlineLineView: View {
    var line: PositionedLine
    var fontSize: Double
    var lineHeight: Double

    var body: some View {
        Text(line.text)
            .font(EditorialMetrics.headlineDisplayFont(size: fontSize))
            .tracking(EditorialMetrics.headlineLetterSpacing)
            .foregroundStyle(EditorialPalette.ink)
            .demoTextSelectionEnabled()
            .demoPointerCursor(.iBeam)
            .frame(height: lineHeight, alignment: .topLeading)
            .offset(x: line.x, y: line.y)
            .zIndex(1)
    }
}

private struct EditorialTextLayerView: View, Equatable {
    var projection: EditorialTextProjection

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(projection.headlineLines, id: \.self) { line in
                HeadlineLineView(
                    line: line,
                    fontSize: projection.headlineFontSize,
                    lineHeight: projection.headlineLineHeight
                )
            }

            CreditLineView(
                left: projection.creditLeft,
                top: projection.creditTop,
                isNarrow: projection.isNarrow
            )

            ForEach(projection.bodyLines, id: \.self) { line in
                BodyLineView(line: line)
            }
        }
    }
}

private struct CreditLineView: View {
    var left: Double
    var top: Double
    var isNarrow: Bool

    var body: some View {
        Text(EditorialAssets.creditDisplayText)
            .font(EditorialMetrics.creditDisplayFont(isNarrow: isNarrow))
            .tracking(isNarrow ? EditorialMetrics.creditNarrowLetterSpacing : EditorialMetrics.creditLetterSpacing)
            .foregroundStyle(EditorialPalette.mutedInk)
            .demoTextSelectionEnabled()
            .demoPointerCursor(.iBeam)
            .offset(x: left, y: top)
            .zIndex(1)
    }
}

private struct BodyLineView: View {
    var line: PositionedLine
    @State private var isHovered = false

    var body: some View {
        Text(line.text)
            .font(EditorialMetrics.bodyDisplayFont())
            .tracking(EditorialMetrics.bodyLetterSpacing)
            .foregroundStyle(isHovered ? EditorialPalette.accent : EditorialPalette.ink)
            .demoTextSelectionEnabled()
            .demoPointerCursor(.iBeam)
            .frame(height: EditorialMetrics.bodyLineHeight, alignment: .topLeading)
            .offset(x: line.x, y: line.y)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .demoHoverState { hovering in
                isHovered = hovering
            }
            .zIndex(1)
    }
}

private struct LogoImageView: View {
    var kind: LogoKind
    var image: DemoPlatformImage
    var rect: WrapRect
    var angle: Double

    var body: some View {
        logoImage
            .resizable()
            .interpolation(.high)
            .frame(width: rect.width, height: rect.height)
            .rotationEffect(.radians(angle))
            .shadow(
                color: kind == .openai
                    ? Color(red: 16 / 255, green: 16 / 255, blue: 12 / 255).opacity(0.14)
                    : Color(red: 140 / 255, green: 86 / 255, blue: 52 / 255).opacity(0.18),
                radius: kind == .openai ? 34 : 32,
                x: 0,
                y: kind == .openai ? 26 : 24
            )
            .offset(x: rect.x, y: rect.y)
            .allowsHitTesting(false)
            .zIndex(3)
    }

    private var logoImage: Image {
        let image = Image(platformImage: image)
        if kind == .openai {
            return image.renderingMode(.template)
        }
        return image
    }
}

private extension View {
    func editorialLogoPointer(active: Bool) -> some View {
        demoPointerCursor(active: active, cursor: .pointingHand)
    }
}

struct EditorialView: View {
    @State private var openaiAnimation = LogoAnimationState()
    @State private var claudeAnimation = LogoAnimationState()
    @State private var isAnimating = false
    @State private var hoverLocation: CGPoint?
    @State private var hasPlayedIntroSpin = false

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let snapshot = animationSnapshot(at: now)
                let pageWidth = max(Double(proxy.size.width), 320)
                let pageHeight = max(Double(proxy.size.height), 320)
                let layout = buildLayout(
                    pageWidth: pageWidth,
                    pageHeight: pageHeight,
                    lineHeight: EditorialMetrics.bodyLineHeight
                )
                let evaluated = evaluateLayout(
                    layout: layout,
                    lineHeight: EditorialMetrics.bodyLineHeight,
                    preparedBody: EditorialAssets.bodyPrepared,
                    openaiLogo: EditorialAssets.openaiLogo,
                    claudeLogo: EditorialAssets.claudeLogo,
                    openaiAngle: snapshot.openaiAngle,
                    claudeAngle: snapshot.claudeAngle
                )
                let hoveredLogo = hoveredLogoKind(at: hoverLocation, hits: evaluated.hits)
                let bodyLines = evaluated.leftLines + evaluated.rightLines
                let textProjection = EditorialTextProjection(
                    headlineLines: evaluated.headlineLines,
                    headlineFontSize: layout.headlineFontSize,
                    headlineLineHeight: layout.headlineLineHeight,
                    creditLeft: evaluated.creditLeft,
                    creditTop: evaluated.creditTop,
                    isNarrow: layout.isNarrow,
                    bodyLines: bodyLines
                )

                ZStack(alignment: .topLeading) {
                    EditorialBackgroundView(size: proxy.size)
                        .allowsHitTesting(false)

                    EditorialTextLayerView(projection: textProjection)
                        .equatable()

                    LogoImageView(
                        kind: .openai,
                        image: EditorialAssets.openaiLogo.image,
                        rect: evaluated.openaiRect,
                        angle: snapshot.openaiAngle
                    )
                    .foregroundStyle(EditorialPalette.ink)

                    LogoImageView(
                        kind: .claude,
                        image: EditorialAssets.claudeLogo.image,
                        rect: evaluated.claudeRect,
                        angle: snapshot.claudeAngle
                    )

                    HintPillView(isNarrow: layout.isNarrow, platform: .current)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(
                            .top,
                            editorialHintTopPadding(
                                safeAreaTop: proxy.safeAreaInsets.top,
                                platform: .current
                            )
                        )
                        .padding(.horizontal, 16)
                        .zIndex(5)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .background(EditorialPalette.paper)
                .contentShape(Rectangle())
                .clipped()
                .editorialLogoPointer(active: hoveredLogo != nil)
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            handleTap(
                                at: value.location,
                                hits: evaluated.hits,
                                now: now
                            )
                        }
                )
                .demoContinuousHover { location in
                    hoverLocation = location
                }
                .background(EditorialPalette.paper)
                .task(id: snapshot.animating) {
                    if snapshot.needsCommit || isAnimating != snapshot.animating {
                        commitAnimations(at: now)
                    }
                }
            }
        }
        .onAppear {
            guard !hasPlayedIntroSpin, editorialShouldAutoSpinOnAppear() else {
                return
            }
            hasPlayedIntroSpin = true
            startIntroSpin(now: Date().timeIntervalSinceReferenceDate)
        }
        .preferredColorScheme(.light)
    }

    private func hoveredLogoKind(at location: CGPoint?, hits: LogoHits) -> LogoKind? {
        guard let location else {
            return nil
        }

        if isPointInPolygon(hits.openai, x: location.x, y: location.y) {
            return .openai
        }

        if isPointInPolygon(hits.claude, x: location.x, y: location.y) {
            return .claude
        }

        return nil
    }

    private func handleTap(at location: CGPoint, hits: LogoHits, now: TimeInterval) {
        if isPointInPolygon(hits.openai, x: location.x, y: location.y) {
            startLogoSpin(.openai, direction: -1, now: now)
        } else if isPointInPolygon(hits.claude, x: location.x, y: location.y) {
            startLogoSpin(.claude, direction: 1, now: now)
        }
    }

    private func startLogoSpin(_ kind: LogoKind, direction: Double, now: TimeInterval) {
        switch kind {
        case .openai:
            openaiAnimation.spin = SpinState(
                from: openaiAnimation.angle,
                to: openaiAnimation.angle + direction * .pi,
                start: now,
                duration: 0.9
            )
        case .claude:
            claudeAnimation.spin = SpinState(
                from: claudeAnimation.angle,
                to: claudeAnimation.angle + direction * .pi,
                start: now,
                duration: 0.9
            )
        }
        isAnimating = true
    }

    private func startIntroSpin(now: TimeInterval) {
        let plan = editorialIntroSpinPlan(startTime: now)
        openaiAnimation.spin = plan.openai
        claudeAnimation.spin = plan.claude
        isAnimating = true
    }

    private func animationSnapshot(at now: TimeInterval) -> AnimationSnapshot {
        let openai = resolveAnimation(openaiAnimation, at: now)
        let claude = resolveAnimation(claudeAnimation, at: now)
        return AnimationSnapshot(
            openaiAngle: openai.angle,
            claudeAngle: claude.angle,
            animating: openai.active || claude.active,
            needsCommit: openai.finished || claude.finished
        )
    }

    private func resolveAnimation(
        _ animation: LogoAnimationState,
        at now: TimeInterval
    ) -> (angle: Double, active: Bool, finished: Bool) {
        guard let spin = animation.spin else {
            return (animation.angle, false, false)
        }

        let progress = min(1, max(0, (now - spin.start) / spin.duration))
        let angle = spin.from + (spin.to - spin.from) * easeSpin(progress)
        return (progress >= 1 ? spin.to : angle, progress < 1, progress >= 1)
    }

    private func commitAnimations(at now: TimeInterval) {
        if let spin = openaiAnimation.spin, now >= spin.start + spin.duration {
            openaiAnimation.angle = spin.to
            openaiAnimation.spin = nil
        }
        if let spin = claudeAnimation.spin, now >= spin.start + spin.duration {
            claudeAnimation.angle = spin.to
            claudeAnimation.spin = nil
        }
        isAnimating = openaiAnimation.spin != nil || claudeAnimation.spin != nil
    }

    private func easeSpin(_ t: Double) -> Double {
        let oneMinusT = 1 - t
        return 1 - oneMinusT * oneMinusT * oneMinusT
    }
}
