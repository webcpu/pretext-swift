import Foundation

struct IllustratedDragonSegment: Equatable {
    var x: Double
    var y: Double
    var angle: Double
    var width: Double
}

struct IllustratedFireParticle: Equatable {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var size: Double
    var life: Double
    var maxLife: Int
    var frame: Int
    var colorIndex: Int
}

struct IllustratedDragonState: Equatable {
    var pageRect: WrapRect
    var scale: Double
    var dragonScaleMultiplier: Double
    var segments: [IllustratedDragonSegment]
    var restSegments: [IllustratedDragonSegment]
    var fire: [IllustratedFireParticle] = []
    var lastStepTime: Double = 0
    var fireLastStep: Double = 0
    var lastInteractionTime: Double = -.infinity
    var lastPointer: WrapPoint?
    var jitterSeed: Double = 0
}

private enum IllustratedDragonPhysics {
    static let segmentSpacing = 30.0
    static let headToMouthFactor = IllustratedManuscriptConstants.dragonSpriteScale * 477.0 * 0.55
    static let stepInterval = 80.0
    static let fireInterval = 80.0
    static let idleTimeout = 2_000.0
    static let maxTurnDelta = 0.25
    static let dragonWrapHorizontalPadding = 10.0
    static let dragonWrapVerticalPadding = 10.0
    static let fireWrapPadding = 6.0
}

func makeIllustratedDragonState(
    pageRect: WrapRect,
    scale: Double,
    platform: DemoNavigationPlatform = .current
) -> IllustratedDragonState {
    let margin = round(IllustratedManuscriptConstants.baseMargin * scale)
    let lineHeightScale = 0.4 + 0.6 * scale
    let lineHeight = max(22.0, round(IllustratedManuscriptConstants.baseLineHeight * lineHeightScale))
    let dropCap = IllustratedManuscriptAssets.dropCapGeometry(
        pageRect: WrapRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height),
        margin: margin,
        lineHeight: lineHeight,
        scale: illustratedManuscriptDropCapScale(for: platform)
    )
    let headX: Double
    let headY: Double
    let dragonScaleMultiplier = illustratedDragonScaleMultiplier(platform: platform)

    switch platform {
    case .watchOS:
        headX = pageRect.x + margin + dropCap.obstacleRect.width * 1.05 + illustratedDragonHeadXOffset(platform: platform)
        headY = pageRect.y + margin - 82 * scale
    case .ios, .macOS:
        headX = pageRect.x + margin + dropCap.obstacleRect.width * 0.8
        headY = pageRect.y + margin - 70 * scale
    }

    let restSegments = illustratedDragonRestSegments(
        headX: headX,
        headY: headY,
        scale: scale,
        dragonScaleMultiplier: dragonScaleMultiplier,
        platform: platform
    )

    return IllustratedDragonState(
        pageRect: pageRect,
        scale: scale,
        dragonScaleMultiplier: dragonScaleMultiplier,
        segments: restSegments,
        restSegments: restSegments,
        jitterSeed: Double.random(in: 0...1_000)
    )
}

func advanceIllustratedDragonState(
    _ state: inout IllustratedDragonState,
    time: Double,
    pointer: WrapPoint?,
    isPressing: Bool
) {
    guard time - state.lastStepTime >= IllustratedDragonPhysics.stepInterval else {
        return
    }

    state.lastStepTime = time
    state.jitterSeed = Double.random(in: 0...1_000)

    if let pointer {
        state.lastPointer = pointer
        state.lastInteractionTime = time
    }

    let activePointer: WrapPoint?
    if let pointer {
        activePointer = pointer
    } else if time - state.lastInteractionTime <= IllustratedDragonPhysics.idleTimeout {
        activePointer = state.lastPointer
    } else {
        activePointer = nil
    }

    if let target = activePointer {
        illustratedDragonFollowPointer(&state, target: target)
    } else {
        illustratedDragonRelaxToRest(&state)
    }

    if isPressing {
        illustratedDragonEmitFire(&state)
    }

    illustratedDragonAdvanceFire(&state, time: time)
}

func illustratedDragonWrapHull(for state: IllustratedDragonState) -> [WrapPoint] {
    guard !state.segments.isEmpty else {
        return []
    }

    var left: [WrapPoint] = []
    var right: [WrapPoint] = []

    for segment in state.segments {
        let radius = segment.width / 2
        let normalX = -sin(segment.angle)
        let normalY = cos(segment.angle)
        left.append(WrapPoint(x: segment.x + normalX * radius, y: segment.y + normalY * radius))
        right.append(WrapPoint(x: segment.x - normalX * radius, y: segment.y - normalY * radius))
    }

    if let head = state.segments.first {
        let headRadius = head.width / 2
        left.insert(
            WrapPoint(
                x: head.x + cos(head.angle) * headRadius,
                y: head.y + sin(head.angle) * headRadius
            ),
            at: 0
        )
    }

    return left + right.reversed()
}

func illustratedDragonMouthPoint(for state: IllustratedDragonState) -> WrapPoint {
    guard let head = state.segments.first else {
        return WrapPoint(x: state.pageRect.midX, y: state.pageRect.minY)
    }

    let reach = IllustratedDragonPhysics.headToMouthFactor * illustratedDragonEffectiveScale(for: state)
    return WrapPoint(
        x: head.x + cos(head.angle) * reach,
        y: head.y + sin(head.angle) * reach
    )
}

func illustratedDragonWrapHorizontalPadding() -> Double {
    IllustratedDragonPhysics.dragonWrapHorizontalPadding
}

func illustratedDragonWrapVerticalPadding() -> Double {
    IllustratedDragonPhysics.dragonWrapVerticalPadding
}

func illustratedDragonFireWrapPadding() -> Double {
    IllustratedDragonPhysics.fireWrapPadding
}

func illustratedDragonScaleMultiplier(
    platform: DemoNavigationPlatform = .current
) -> Double {
    switch platform {
    case .watchOS:
        0.68
    case .ios, .macOS:
        1
    }
}

func illustratedDragonHeadXOffset(
    platform: DemoNavigationPlatform = .current
) -> Double {
    switch platform {
    case .watchOS:
        24
    case .ios, .macOS:
        0
    }
}

func illustratedDragonEffectiveScale(for state: IllustratedDragonState) -> Double {
    state.scale * state.dragonScaleMultiplier
}

private func illustratedDragonRestSegments(
    headX: Double,
    headY: Double,
    scale: Double,
    dragonScaleMultiplier: Double,
    platform: DemoNavigationPlatform
) -> [IllustratedDragonSegment] {
    let effectiveScale = scale * dragonScaleMultiplier
    var segments: [IllustratedDragonSegment] = [
        IllustratedDragonSegment(
            x: headX,
            y: headY - 2,
            angle: 0,
            width: illustratedDragonSegmentWidth(index: 0, scale: effectiveScale)
        )
    ]

    let spacingMultiplier: Double
    let maxAngle: Double
    let angleExponent: Double

    switch platform {
    case .watchOS:
        spacingMultiplier = 0.88
        maxAngle = (.pi / 2) * 0.92
        angleExponent = 1.65
    case .ios, .macOS:
        spacingMultiplier = 1
        maxAngle = (.pi / 2) * 1.4
        angleExponent = 1
    }

    let spacing = IllustratedDragonPhysics.segmentSpacing * spacingMultiplier * effectiveScale
    for index in 1..<IllustratedManuscriptConstants.dragonWidths.count {
        let progress = Double(index) / Double(IllustratedManuscriptConstants.dragonWidths.count - 1)
        let angle = -(pow(progress, angleExponent) * maxAngle)
        let previous = segments[index - 1]
        segments.append(
            IllustratedDragonSegment(
                x: previous.x - cos(angle) * spacing,
                y: previous.y - sin(angle) * spacing,
                angle: angle,
                width: illustratedDragonSegmentWidth(index: index, scale: effectiveScale)
            )
        )
    }

    return segments
}

private func illustratedDragonSegmentWidth(index: Int, scale: Double) -> Double {
    guard IllustratedManuscriptConstants.dragonWidths.indices.contains(index) else {
        return 10 * scale
    }

    return IllustratedManuscriptConstants.dragonWidths[index] * IllustratedManuscriptConstants.dragonSpriteScale * scale
}

private func illustratedDragonFollowPointer(_ state: inout IllustratedDragonState, target: WrapPoint) {
    guard !state.segments.isEmpty else {
        return
    }

    var head = state.segments[0]
    let dx = target.x - head.x
    let dy = target.y - head.y
    let distance = hypot(dx, dy)
    if distance > 4 {
        let step = min(distance, max(12, distance * 0.15))
        head.x += dx / distance * step
        head.y += dy / distance * step
        head.angle = atan2(dy, dx)
        state.segments[0] = head
    }

    let spacing = IllustratedDragonPhysics.segmentSpacing * illustratedDragonEffectiveScale(for: state)
    for index in 1..<state.segments.count {
        let previous = state.segments[index - 1]
        var segment = state.segments[index]
        var desiredAngle = atan2(previous.y - segment.y, previous.x - segment.x)
        var delta = normalizedAngle(desiredAngle - segment.angle)
        delta = max(-IllustratedDragonPhysics.maxTurnDelta, min(IllustratedDragonPhysics.maxTurnDelta, delta))
        desiredAngle = segment.angle + delta
        segment.angle = desiredAngle
        segment.x = previous.x - cos(segment.angle) * spacing
        segment.y = previous.y - sin(segment.angle) * spacing
        state.segments[index] = segment
    }
}

private func illustratedDragonRelaxToRest(_ state: inout IllustratedDragonState) {
    let easing = 0.12
    for index in state.segments.indices {
        let rest = state.restSegments[index]
        var segment = state.segments[index]
        segment.x += (rest.x - segment.x) * easing
        segment.y += (rest.y - segment.y) * easing
        segment.angle += normalizedAngle(rest.angle - segment.angle) * easing
        state.segments[index] = segment
    }
}

private func illustratedDragonEmitFire(_ state: inout IllustratedDragonState) {
    let mouth = illustratedDragonMouthPoint(for: state)
    let particleCount = 4

    for _ in 0..<particleCount {
        let angleJitter = Double.random(in: -0.125...0.125)
        let speed = (35 + Double.random(in: 0...20)) * illustratedDragonEffectiveScale(for: state)
        let angle = (state.segments.first?.angle ?? 0) + angleJitter
        state.fire.append(
            IllustratedFireParticle(
                x: mouth.x + Double.random(in: -2...2),
                y: mouth.y + Double.random(in: -2...2),
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                size: (8 + Double.random(in: 0...12)) * illustratedDragonEffectiveScale(for: state),
                life: 1,
                maxLife: Int.random(in: 12...17),
                frame: 0,
                colorIndex: Int.random(in: 0...2)
            )
        )
    }
}

private func illustratedDragonAdvanceFire(_ state: inout IllustratedDragonState, time: Double) {
    guard time - state.fireLastStep >= IllustratedDragonPhysics.fireInterval else {
        return
    }

    state.fireLastStep = time
    for index in state.fire.indices.reversed() {
        var particle = state.fire[index]
        particle.frame += 1
        particle.life = 1 - Double(particle.frame) / Double(particle.maxLife)
        particle.x += particle.vx
        particle.y += particle.vy
        particle.vx *= 0.95
        particle.vy *= 0.95
        let riseBoost = max(0, Double(particle.frame - 4) / Double(particle.maxLife))
        particle.vy -= riseBoost * 1.5

        if particle.life < 0.25 {
            particle.size *= 0.75
        } else if particle.frame < 3 {
            particle.size *= 1.15
        }

        if particle.life <= 0 || particle.size < 1.5 {
            state.fire.remove(at: index)
        } else {
            state.fire[index] = particle
        }
    }
}

private func normalizedAngle(_ angle: Double) -> Double {
    var result = angle
    while result > .pi {
        result -= .pi * 2
    }
    while result < -.pi {
        result += .pi * 2
    }
    return result
}
