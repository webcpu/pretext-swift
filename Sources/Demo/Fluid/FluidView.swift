#if !os(watchOS)
import CoreText
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

private enum FluidPalette {
    static let background = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let text = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let cursor = CGColor(red: 1, green: 216 / 255, blue: 49 / 255, alpha: 1)
}

struct FluidInteractionState: Equatable {
    var pointerLocation: CGPoint?
    var isDragActive = false
}

enum FluidInteractionEvent: Equatable {
    case hoverChanged(CGPoint?)
    case dragChanged(CGPoint)
    case dragEnded
}

func fluidInteractionState(
    _ state: FluidInteractionState,
    applying event: FluidInteractionEvent,
    platform: DemoNavigationPlatform = .current
) -> FluidInteractionState {
    var nextState = state

    switch event {
    case let .hoverChanged(location):
        if platform == .macOS, state.isDragActive {
            return state
        }
        nextState.pointerLocation = location
    case let .dragChanged(location):
        nextState.isDragActive = true
        nextState.pointerLocation = location
    case .dragEnded:
        nextState.isDragActive = false
        nextState.pointerLocation = nil
    }

    return nextState
}

struct FluidView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var layoutSnapshot = FluidLayoutSnapshot(
        pageMetrics: fluidPageMetrics(viewportWidth: 0, viewportHeight: 0),
        text: ""
    )
    @State private var simulationDriver = FluidSimulationDriver()
    @State private var simulationState = FluidSimulationState.empty
    @State private var interactionState = FluidInteractionState()
    @State private var lastFrameTime: Double?
    #if os(macOS)
    @State private var isSystemCursorHidden = false
    #endif

    var body: some View {
        GeometryReader { proxy in
            let pointerLocation = interactionState.pointerLocation
            let timelineMinimumInterval = fluidTimelineMinimumInterval(
                isInteracting: pointerLocation != nil
            )
            TimelineView(.animation(minimumInterval: timelineMinimumInterval, paused: false)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let tick = Int(now / timelineMinimumInterval)

                Canvas(opaque: true, rendersAsynchronously: true) { context, size in
                    context.withCGContext { cg in
                        drawFluidScene(
                            in: CGRect(origin: .zero, size: size),
                            layout: layoutSnapshot,
                            simulation: simulationState,
                            cursor: fluidCursorSnapshot(
                                for: simulationState,
                                isActive: pointerLocation != nil,
                                metrics: layoutSnapshot.pageMetrics
                            ),
                            cg: cg
                        )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(Color.black)
                .contentShape(Rectangle())
                .simultaneousGesture(dragGesture)
                .demoContinuousHover { location in
                    applyInteraction(.hoverChanged(location))
                }
                .task(id: fluidLayoutTaskID(for: proxy.size, platform: .current)) {
                    let snapshot = evaluateFluidLayout(
                        viewportWidth: proxy.size.width,
                        viewportHeight: proxy.size.height,
                        platform: .current
                    )
                    layoutSnapshot = snapshot

                    simulationDriver.reset(from: snapshot)
                    simulationState = simulationDriver.snapshot
                    lastFrameTime = nil

                    if let pointerLocation,
                       !fluidViewportContains(
                           WrapPoint(x: pointerLocation.x, y: pointerLocation.y),
                           viewport: snapshot.pageMetrics.viewportRect
                       )
                    {
                        clearInteractionState()
                    }
                }
                .task(id: tick) {
                    advanceFrame(now: now)
                }
                .onChange(of: scenePhase) { _, newValue in
                    if newValue != .active {
                        clearInteractionState()
                    }
                }
                .onDisappear {
                    clearInteractionState()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                applyInteraction(.dragChanged(value.location))
            }
            .onEnded { _ in
                applyInteraction(.dragEnded)
            }
    }

    private func advanceFrame(now: Double) {
        guard layoutSnapshot.pageMetrics.viewportRect.width > 0,
              layoutSnapshot.pageMetrics.viewportRect.height > 0
        else {
            return
        }

        let rawDelta: Double
        if let lastFrameTime {
            rawDelta = now - lastFrameTime
        } else {
            rawDelta = 1.0 / 60.0
        }
        lastFrameTime = now

        let pointerInput = interactionState.pointerLocation.map(makePointerInput)
        let result = simulationDriver.step(
            dt: rawDelta,
            pointer: pointerInput,
            layout: layoutSnapshot
        )
        simulationState = simulationDriver.snapshot

        if result.clearedPointerForLargeGap {
            clearInteractionState()
        }
    }

    private func fluidLayoutTaskID(
        for size: CGSize,
        platform: DemoNavigationPlatform
    ) -> String {
        [
            platform == .macOS ? "macOS" : "ios",
            Int(size.width.rounded()).description,
            Int(size.height.rounded()).description,
        ].joined(separator: ":")
    }

    private func makePointerInput(from location: CGPoint) -> FluidPointerInput {
        return FluidPointerInput(
            center: WrapPoint(x: location.x, y: location.y),
            isInitialContact: simulationState.pointer.current == nil && DemoNavigationPlatform.current != .macOS
        )
    }

    private func applyInteraction(_ event: FluidInteractionEvent) {
        let previousLocation = interactionState.pointerLocation
        let nextState = fluidInteractionState(
            interactionState,
            applying: event,
            platform: .current
        )
        if previousLocation == nil, nextState.pointerLocation != nil {
            lastFrameTime = nil
        }
        interactionState = nextState
        syncSystemCursorVisibility(isActive: nextState.pointerLocation != nil)
    }

    private func clearInteractionState() {
        interactionState = FluidInteractionState()
        lastFrameTime = nil
        syncSystemCursorVisibility(isActive: false)
        clearSimulationPointer()
    }

    private func clearSimulationPointer() {
        simulationDriver.clearPointer()
        simulationState = simulationDriver.snapshot
    }

    private func syncSystemCursorVisibility(isActive: Bool) {
        #if os(macOS)
        guard isActive != isSystemCursorHidden else {
            return
        }

        if isActive {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
        }
        isSystemCursorHidden = isActive
        #endif
    }
}

func fluidTimelineMinimumInterval(isInteracting: Bool) -> Double {
    _ = isInteracting
    return 1.0 / 60.0
}

private func drawFluidScene(
    in rect: CGRect,
    layout: FluidLayoutSnapshot,
    simulation: FluidSimulationState,
    cursor: FluidCursorSnapshot?,
    cg: CGContext
) {
    cg.setFillColor(FluidPalette.background)
    cg.fill(rect)

    let font = fluidBodyFont(size: layout.pageMetrics.fontSize)
    drawFluidGlyphs(
        layout.glyphs,
        particles: alignedFluidParticles(for: layout, in: simulation),
        font: font,
        viewportHeight: rect.height,
        cg: cg
    )

    if let cursor {
        drawFluidCursor(cursor, cg: cg)
    }
}

private func alignedFluidParticles(
    for layout: FluidLayoutSnapshot,
    in simulation: FluidSimulationState
) -> [FluidParticleState]? {
    guard layout.glyphs.count == simulation.particles.count else {
        return nil
    }

    let isAligned = zip(layout.glyphs, simulation.particles).allSatisfy { glyph, particle in
        glyph.id == particle.id
    }
    return isAligned ? simulation.particles : nil
}

private func drawFluidGlyphs(
    _ glyphLayouts: [FluidGlyphLayout],
    particles: [FluidParticleState]?,
    font: CTFont,
    viewportHeight: Double,
    cg: CGContext
) {
    guard !glyphLayouts.isEmpty else {
        return
    }

    var glyphs: [CGGlyph] = []
    glyphs.reserveCapacity(glyphLayouts.count)

    var positions: [CGPoint] = []
    positions.reserveCapacity(glyphLayouts.count)

    for (index, glyphLayout) in glyphLayouts.enumerated() {
        if glyphLayout.character.allSatisfy(\.isWhitespace) || glyphLayout.bounds.height <= 0 {
            continue
        }

        let center = particles?[index].center ?? glyphLayout.restCenter
        let offsetX = center.x - glyphLayout.restCenter.x
        let offsetY = center.y - glyphLayout.restCenter.y

        glyphs.append(glyphLayout.fontGlyph)
        positions.append(
            CGPoint(
                x: glyphLayout.drawOrigin.x + offsetX,
                y: viewportHeight - (glyphLayout.baselineY + offsetY)
            )
        )
    }

    cg.saveGState()
    cg.setFillColor(FluidPalette.text)
    cg.translateBy(x: 0, y: viewportHeight)
    cg.scaleBy(x: 1, y: -1)
    glyphs.withUnsafeBufferPointer { glyphBuffer in
        positions.withUnsafeBufferPointer { positionBuffer in
            guard let glyphBase = glyphBuffer.baseAddress,
                  let positionBase = positionBuffer.baseAddress
            else {
                return
            }

            CTFontDrawGlyphs(font, glyphBase, positionBase, glyphs.count, cg)
        }
    }
    cg.restoreGState()
}

private func drawFluidCursor(
    _ cursor: FluidCursorSnapshot,
    cg: CGContext
) {
    guard cursor.isVisible else {
        return
    }

    cg.saveGState()
    cg.translateBy(x: cursor.center.x, y: cursor.center.y)
    cg.rotate(by: cursor.angle)
    cg.addPath(
        fluidMachConePath(
            ballRadius: cursor.ballRadius,
            tailLength: cursor.tailLength
        )
    )
    cg.setFillColor(FluidPalette.cursor)
    cg.fillPath()
    cg.restoreGState()
}

/// Mach cone cursor: a circle head with a V-shaped wake trailing behind.
/// In local coordinates, positive Y is the movement direction (front).
private func fluidMachConePath(
    ballRadius r: Double,
    tailLength: Double
) -> CGPath {
    let path = CGMutablePath()

    guard tailLength > 0.5 else {
        // No tail — just a circle
        path.addEllipse(in: CGRect(
            x: -r, y: -r, width: 2 * r, height: 2 * r
        ))
        return path
    }

    // Tip of the cone behind the ball
    let d = r + tailLength
    // Tangent points on the circle where the cone lines touch
    // sin(α) = -r/d  →  tangent points at angle α from positive X axis
    let sinA = r / d
    let cosA = sqrt(1 - sinA * sinA)
    let tangentX = r * cosA
    let tangentY = -(r * sinA)

    // Arc from right tangent point over the front to left tangent point
    let startAngle = atan2(tangentY, tangentX)
    let endAngle = atan2(tangentY, -tangentX)

    path.move(to: CGPoint(x: 0, y: -d))
    path.addLine(to: CGPoint(x: tangentX, y: tangentY))
    path.addArc(
        center: .zero,
        radius: r,
        startAngle: startAngle,
        endAngle: endAngle,
        clockwise: false
    )
    path.addLine(to: CGPoint(x: 0, y: -d))
    path.closeSubpath()

    return path
}

private func fluidViewportContains(
    _ point: WrapPoint,
    viewport: WrapRect
) -> Bool {
    point.x >= viewport.minX &&
        point.x <= viewport.maxX &&
        point.y >= viewport.minY &&
        point.y <= viewport.maxY
}
#endif
