import CoreGraphics
import CoreText
import Pretext
import SwiftUI

struct IllustratedManuscriptView: View {
    @State private var dragonState: IllustratedDragonState?
    @State private var pointerLocation: CGPoint?
    @State private var isPressing = false

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                let platform = DemoNavigationPlatform.current
                let now = timeline.date.timeIntervalSinceReferenceDate * 1000
                let metrics = illustratedManuscriptPageMetrics(
                    viewportWidth: proxy.size.width,
                    viewportHeight: proxy.size.height,
                    platform: platform
                )
                let state = resolvedDragonState(metrics: metrics, platform: platform)
                let snapshot = evaluateIllustratedManuscriptSnapshot(
                    viewportWidth: proxy.size.width,
                    viewportHeight: proxy.size.height,
                    dragonState: state,
                    platform: platform
                )

                Canvas(opaque: true) { context, size in
                    context.withCGContext { cg in
                        drawIllustratedManuscript(
                            snapshot: snapshot,
                            viewportSize: size,
                            now: now,
                            platform: platform,
                            cg: cg
                        )
                    }
                }
                .contentShape(Rectangle())
                .background(Color(cgColor: IllustratedManuscriptPalette.paper))
                .simultaneousGesture(dragGesture)
                .demoContinuousHover { location in
                    pointerLocation = location
                }
                .task(id: sizeTaskID(metrics: metrics)) {
                    dragonState = makeIllustratedDragonState(
                        pageRect: metrics.pageRect,
                        scale: metrics.scale,
                        platform: platform
                    )
                }
                .task(id: Int(now / 80)) {
                    guard var state = dragonState else {
                        dragonState = makeIllustratedDragonState(
                            pageRect: metrics.pageRect,
                            scale: metrics.scale,
                            platform: platform
                        )
                        return
                    }

                    if state.pageRect != metrics.pageRect || abs(state.scale - metrics.scale) > 0.001 {
                        state = makeIllustratedDragonState(
                            pageRect: metrics.pageRect,
                            scale: metrics.scale,
                            platform: platform
                        )
                    }

                    advanceIllustratedDragonState(
                        &state,
                        time: now,
                        pointer: pointerLocation.map { WrapPoint(x: $0.x, y: $0.y) },
                        isPressing: isPressing
                    )
                    dragonState = state
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                pointerLocation = value.location
                isPressing = true
            }
            .onEnded { _ in
                pointerLocation = nil
                isPressing = false
            }
    }

    private func resolvedDragonState(
        metrics: IllustratedManuscriptPageMetrics,
        platform: DemoNavigationPlatform
    ) -> IllustratedDragonState {
        if let dragonState {
            return dragonState
        }

        return makeIllustratedDragonState(
            pageRect: metrics.pageRect,
            scale: metrics.scale,
            platform: platform
        )
    }

    private func sizeTaskID(metrics: IllustratedManuscriptPageMetrics) -> String {
        [
            Int(metrics.pageRect.x).description,
            Int(metrics.pageRect.y).description,
            Int(metrics.pageRect.width).description,
            Int(metrics.pageRect.height).description,
            Int(metrics.scale * 1000).description,
        ].joined(separator: ":")
    }
}

private func drawIllustratedManuscript(
    snapshot: IllustratedManuscriptSnapshot,
    viewportSize: CGSize,
    now: Double,
    platform: DemoNavigationPlatform,
    cg: CGContext
) {
    cg.setFillColor(IllustratedManuscriptPalette.paper)
    cg.fill(CGRect(origin: .zero, size: viewportSize))

    drawImage(
        IllustratedManuscriptAssets.dropCapImage,
        in: snapshot.dropCapDrawRect.cgRect,
        platform: platform,
        cg: cg
    )

    let bodyFont = IllustratedManuscriptAssets.bodyFont(size: snapshot.pageMetrics.fontSize)
    for line in snapshot.bodyLines {
        let drawY = line.y + snapshot.lineTextInset
        if snapshot.dragonState.fire.isEmpty {
            drawText(
                line.text,
                at: CGPoint(x: line.x, y: drawY),
                font: bodyFont,
                color: IllustratedManuscriptPalette.ink,
                platform: platform,
                cg: cg
            )
            continue
        }

        drawWarpedText(
            line.text,
            x: line.x,
            y: drawY,
            font: bodyFont,
            particles: snapshot.dragonState.fire,
            platform: platform,
            cg: cg
        )
    }

    drawDragon(state: snapshot.dragonState, now: now, platform: platform, cg: cg)
    drawFireParticles(snapshot.dragonState.fire, cg: cg)
    drawAttribution(viewportSize: viewportSize, platform: platform, cg: cg)
}

private func drawText(
    _ text: String,
    at point: CGPoint,
    font: CTFont,
    color: CGColor,
    platform: DemoNavigationPlatform,
    cg: CGContext
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    withIllustratedManuscriptLocalVerticalFlipIfNeeded(
        around: point,
        platform: platform,
        cg: cg
    ) {
        cg.textMatrix = .identity
        cg.textPosition = point
        CTLineDraw(line, cg)
    }
}

private func drawWarpedText(
    _ text: String,
    x: Double,
    y: Double,
    font: CTFont,
    particles: [IllustratedFireParticle],
    platform: DemoNavigationPlatform,
    cg: CGContext
) {
    var cursorX = x
    let graphemes = text.map(String.init)

    for grapheme in graphemes {
        let width = TextMeasurer.shared.measureSegment(grapheme, font: font)
        let centerX = cursorX + width / 2
        let centerY = y + (CTFontGetSize(font) * 0.43)
        let influence = particleInfluence(
            at: WrapPoint(x: centerX, y: centerY),
            particles: particles
        )

        if influence.strength < 0.01 {
            drawText(
                grapheme,
                at: CGPoint(x: cursorX, y: y),
                font: font,
                color: IllustratedManuscriptPalette.ink,
                platform: platform,
                cg: cg
            )
        } else {
            let red = min(1, 42.0 / 255.0 + influence.strength * 200.0 / 255.0)
            let green = min(1, 26.0 / 255.0 + influence.strength * 80.0 / 255.0)
            let emberColor = CGColor(red: red, green: green, blue: 10 / 255, alpha: max(0.25, 1 - influence.strength * 0.8))

            cg.saveGState()
            cg.translateBy(
                x: centerX + influence.dx * influence.strength * 45,
                y: centerY + influence.dy * influence.strength * 45
            )
            cg.rotate(by: influence.strength * (influence.dx >= 0 ? 1 : -1) * 1.2)
            drawText(
                grapheme,
                at: CGPoint(x: -width / 2, y: -(CTFontGetSize(font) * 0.43)),
                font: font,
                color: emberColor,
                platform: platform,
                cg: cg
            )
            cg.restoreGState()
        }

        cursorX += width
    }
}

private func particleInfluence(
    at point: WrapPoint,
    particles: [IllustratedFireParticle]
) -> (dx: Double, dy: Double, strength: Double) {
    var dxSum = 0.0
    var dySum = 0.0
    var weightSum = 0.0

    for particle in particles {
        let dx = point.x - particle.x
        let dy = point.y - particle.y
        let distance = hypot(dx, dy)
        if distance > 60 || distance < 0.1 {
            continue
        }

        let influence = 1 - distance / 60
        let weight = influence * influence * particle.life
        dxSum += (dx / distance) * weight
        dySum += (dy / distance) * weight
        weightSum += weight
    }

    if weightSum < 0.001 {
        return (0, 0, 0)
    }

    let length = hypot(dxSum, dySum)
    return (
        length > 0 ? dxSum / length : 0,
        length > 0 ? dySum / length : 0,
        min(weightSum, 1.5)
    )
}

private func drawDragon(
    state: IllustratedDragonState,
    now: Double,
    platform: DemoNavigationPlatform,
    cg: CGContext
) {
    let sprites = IllustratedManuscriptAssets.dragonSprites
    let spriteScale = IllustratedManuscriptConstants.dragonSpriteScale * illustratedDragonEffectiveScale(for: state)
    let seconds = now / 1000
    let wingIndex = 5

    if state.segments.indices.contains(wingIndex) {
        let wing = state.segments[wingIndex]
        cg.saveGState()
        cg.translateBy(x: wing.x, y: wing.y)
        cg.rotate(by: wing.angle + sin(seconds * 3) * 0.4)
        cg.scaleBy(x: spriteScale, y: spriteScale)
        drawCenteredImage(sprites.wingBack, platform: platform, cg: cg)
        cg.restoreGState()
    }

    for index in state.segments.indices.reversed() {
        let segment = state.segments[index]
        cg.saveGState()
        cg.translateBy(x: segment.x, y: segment.y)
        cg.rotate(by: segment.angle)
        cg.scaleBy(x: spriteScale, y: spriteScale)

        if index == 0 {
            drawImage(
                sprites.tongue,
                in: CGRect(
                    x: Double(sprites.head.width) * 0.3,
                    y: -Double(sprites.tongue.height) / 2,
                    width: Double(sprites.tongue.width),
                    height: Double(sprites.tongue.height)
                ),
                platform: platform,
                cg: cg
            )
            drawImage(
                sprites.head,
                in: CGRect(
                    x: -Double(sprites.head.width) * 0.45,
                    y: -Double(sprites.head.height) / 2,
                    width: Double(sprites.head.width),
                    height: Double(sprites.head.height)
                ),
                platform: platform,
                cg: cg
            )
        } else if sprites.body.indices.contains(index - 1) {
            drawCenteredImage(sprites.body[index - 1], platform: platform, cg: cg)
        }

        if index == wingIndex {
            cg.saveGState()
            cg.rotate(by: -sin(seconds * 3 + 0.5) * 0.4)
            drawCenteredImage(sprites.wingFront, platform: platform, cg: cg)
            cg.restoreGState()
        }

        cg.restoreGState()
    }
}

func illustratedManuscriptUsesLocalVerticalFlipForRawCG(
    platform: DemoNavigationPlatform = .current
) -> Bool {
    platform == .watchOS
}

private func withIllustratedManuscriptLocalVerticalFlipIfNeeded(
    around anchor: CGPoint,
    platform: DemoNavigationPlatform,
    cg: CGContext,
    draw: () -> Void
) {
    guard illustratedManuscriptUsesLocalVerticalFlipForRawCG(platform: platform) else {
        draw()
        return
    }

    // watchOS Canvas uses a vertically flipped user space for raw CG image/text draws.
    // Flip around each element anchor so the page stays in top-left screen coordinates.
    cg.saveGState()
    cg.translateBy(x: anchor.x, y: anchor.y)
    cg.scaleBy(x: 1, y: -1)
    cg.translateBy(x: -anchor.x, y: -anchor.y)
    draw()
    cg.restoreGState()
}

private func drawImage(
    _ image: CGImage,
    in rect: CGRect,
    platform: DemoNavigationPlatform,
    cg: CGContext
) {
    withIllustratedManuscriptLocalVerticalFlipIfNeeded(
        around: CGPoint(x: rect.midX, y: rect.midY),
        platform: platform,
        cg: cg
    ) {
        cg.draw(image, in: rect)
    }
}

private func drawCenteredImage(
    _ image: CGImage,
    platform: DemoNavigationPlatform,
    cg: CGContext
) {
    drawImage(
        image,
        in: CGRect(
            x: -Double(image.width) / 2,
            y: -Double(image.height) / 2,
            width: Double(image.width),
            height: Double(image.height)
        ),
        platform: platform,
        cg: cg
    )
}

private func drawFireParticles(_ particles: [IllustratedFireParticle], cg: CGContext) {
    let colors = [
        IllustratedManuscriptPalette.ember,
        IllustratedManuscriptPalette.flame,
        IllustratedManuscriptPalette.glow,
    ]

    for particle in particles {
        let angle = atan2(particle.vy, particle.vx)
        let radius = particle.size / 2
        let wiggle = radius * 0.35
        let color = colors[min(max(particle.colorIndex, 0), colors.count - 1)]

        cg.saveGState()
        cg.translateBy(x: particle.x, y: particle.y)
        cg.rotate(by: angle)
        cg.setAlpha(min(1, particle.life * 1.5))
        cg.setFillColor(color)

        let points = [
            CGPoint(x: radius * 1.2 + randomOffset(seed: particle.frame + 1) * wiggle, y: randomOffset(seed: particle.frame + 2) * wiggle),
            CGPoint(x: randomOffset(seed: particle.frame + 3) * wiggle, y: -radius * 0.7 + randomOffset(seed: particle.frame + 4) * wiggle),
            CGPoint(x: -radius + randomOffset(seed: particle.frame + 5) * wiggle, y: randomOffset(seed: particle.frame + 6) * wiggle),
            CGPoint(x: randomOffset(seed: particle.frame + 7) * wiggle, y: radius * 0.7 + randomOffset(seed: particle.frame + 8) * wiggle),
        ]

        let path = CGMutablePath()
        path.move(to: points[0])
        path.addLines(between: Array(points.dropFirst()))
        path.closeSubpath()
        cg.addPath(path)
        cg.fillPath()
        cg.restoreGState()
    }
}

private func drawAttribution(
    viewportSize: CGSize,
    platform: DemoNavigationPlatform,
    cg: CGContext
) {
    let font = IllustratedManuscriptAssets.bodyFont(size: 14)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: IllustratedManuscriptPalette.ink,
    ]
    let attributed = NSAttributedString(string: IllustratedManuscriptAssets.attribution, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    let point = CGPoint(
        x: viewportSize.width / 2 - width / 2,
        y: viewportSize.height - 36
    )
    withIllustratedManuscriptLocalVerticalFlipIfNeeded(
        around: point,
        platform: platform,
        cg: cg
    ) {
        cg.textMatrix = .identity
        cg.textPosition = point
        CTLineDraw(line, cg)
    }
}

private func randomOffset(seed: Int) -> Double {
    let value = sin(Double(seed) * 12.9898 + 78.233) * 43758.5453
    return value - floor(value) - 0.5
}

private extension WrapRect {
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
