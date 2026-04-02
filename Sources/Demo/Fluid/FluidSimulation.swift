import Foundation
import simd
#if canImport(Metal)
import Metal
#endif

let fluidMaximumGlyphDisplacement = 240.0

private enum FluidSimulationConstants {
    static let substepCount = 3
    static let range = 15.0
    static let densityTarget = -1.5
    static let nearPressureMultiplier = 0.0
    static let pressureMultiplier = 15.0
    static let viscosityFactor = 600.1
    static let dampingFactor = 0.999
    static let idleDampingFactor = 0.999
    static let forceToCenterFactor = 0.0
    static let originalPositionFactor = 0.0
    static let maxVelocity = 1200.0
    static let idleRestReturnFactor = 0.0
    static let activeRestReturnFactor = 0.0
    static let pointerActivationThreshold = 0.0015
    static let pointerForceThreshold = 35.0
    static let pointerForceScale = 2_400_000.0
    static let pointerForceRamp = 7.0
    static let pointerForceMinimum = 0.1
    static let pointerForceMaximum = 1.1
    static let cursorTailMultiplier = 4.0
    static let collisionPasses = 3
    static let collisionGap = 12.0
    static let collisionPadding = 2.5
    static let collisionVelocityDamping = 1.0
    static let collisionCellSize = 20.0
    static let edgeIntersectionPasses = 10
    static let nativeCorrectionPasses = 6

    static let poly6ScalingFactor = 4.0 / (Double.pi * pow(range, 8))
    static let spikyPow2ScalingFactor = 6.0 / (Double.pi * pow(range, 4))
    static let spikyPow3ScalingFactor = 10.0 / (Double.pi * pow(range, 5))
    static let spikyPow3DerivativeScalingFactor = 30.0 / (Double.pi * pow(range, 5))
    static let spikyPow2DerivativeScalingFactor = 12.0 / (Double.pi * pow(range, 4))
}

func fluidPressureForDensity(_ density: Double) -> Double {
    FluidSimulationConstants.pressureMultiplier * (
        density - FluidSimulationConstants.densityTarget
    )
}

private struct FluidSpatialCell: Hashable {
    var x: Int
    var y: Int
}

private struct FluidSpatialGrid {
    let cellSize: Double
    let cells: [FluidSpatialCell: [Int]]

    init(points: [WrapPoint], cellSize: Double) {
        self.cellSize = cellSize
        var nextCells: [FluidSpatialCell: [Int]] = [:]
        for (index, point) in points.enumerated() {
            let cell = FluidSpatialCell(
                x: Int(floor(point.x / cellSize)),
                y: Int(floor(point.y / cellSize))
            )
            nextCells[cell, default: []].append(index)
        }
        cells = nextCells
    }

    func neighbors(around point: WrapPoint) -> [Int] {
        let origin = FluidSpatialCell(
            x: Int(floor(point.x / cellSize)),
            y: Int(floor(point.y / cellSize))
        )
        var indices: [Int] = []
        indices.reserveCapacity(32)

        for y in (origin.y - 1)...(origin.y + 1) {
            for x in (origin.x - 1)...(origin.x + 1) {
                indices.append(contentsOf: cells[FluidSpatialCell(x: x, y: y)] ?? [])
            }
        }

        return indices
    }
}

struct FluidParticleState: Equatable {
    var id: Int
    var center: WrapPoint
    var velocity: SIMD2<Double>
}

struct FluidPointerInput: Equatable {
    var center: WrapPoint
    var direction: SIMD2<Double> = .zero
    var strength: Double = 0
    var isInitialContact: Bool = false

    init(
        center: WrapPoint,
        direction: SIMD2<Double> = .zero,
        strength: Double = 0,
        isInitialContact: Bool = false
    ) {
        self.center = center
        self.direction = direction
        self.strength = strength
        self.isInitialContact = isInitialContact
    }
}

struct FluidPointerState: Equatable {
    var targetCenter: WrapPoint?
    var current: FluidPointerInput?
}

struct FluidCursorState: Equatable {
    var isVisible: Bool
    var center: WrapPoint
    var angle: Double
    var ballRadius: Double
    var tailLength: Double
}

typealias FluidCursorSnapshot = FluidCursorState

struct FluidFrameStepResult: Equatable {
    var appliedDeltaTime: Double
    var clearedPointerForLargeGap: Bool
}

struct FluidSimulationState: Equatable {
    var particles: [FluidParticleState] = []
    var glyphLayouts: [FluidGlyphLayout] = []
    var restCenters: [WrapPoint] = []
    var pointer = FluidPointerState()
    var cursor: FluidCursorState?
    var elapsedTime = 0.0
    var idleElapsedTime = 0.0
    var hasActivatedPointer = false
    var restVisibleOverlapPairs = 0
    var visibleOverlapPairs = 0

    static let empty = FluidSimulationState()

    mutating func reset(from layout: FluidLayoutSnapshot) {
        glyphLayouts = layout.glyphs
        particles = layout.glyphs.map { glyph in
            FluidParticleState(
                id: glyph.id,
                center: glyph.restCenter,
                velocity: .zero
            )
        }
        restCenters = layout.glyphs.map(\.restCenter)
        elapsedTime = 0
        idleElapsedTime = 0
        hasActivatedPointer = false
        restVisibleOverlapPairs = fluidVisibleOverlapPairCount(
            particles: particles,
            glyphLayouts: glyphLayouts
        )
        visibleOverlapPairs = restVisibleOverlapPairs

        if let pointerCenter = pointer.targetCenter,
           fluidPointIsInsideViewport(pointerCenter, viewport: layout.pageMetrics.viewportRect)
        {
            pointer.targetCenter = pointerCenter
        } else {
            clearPointer()
        }
    }

    @discardableResult
    mutating func step(
        dt: Double,
        pointer pointerInput: FluidPointerInput?,
        layout: FluidLayoutSnapshot
    ) -> FluidFrameStepResult {
        if particles.map(\.id) != layout.glyphs.map(\.id) {
            reset(from: layout)
        }

        var clearedPointerForLargeGap = false
        let appliedDeltaTime: Double
        if dt > 0.1 {
            clearPointer()
            clearedPointerForLargeGap = true
            appliedDeltaTime = 1.0 / 60.0
        } else {
            appliedDeltaTime = min(max(dt, 1.0 / 240.0), 1.0 / 20.0)
            if let pointerInput {
                hasActivatedPointer = true
                updatePointer(pointerInput)
            }
        }

        guard hasActivatedPointer || pointerInput != nil || !fluidSimulationIsPristineRestState(self) else {
            return FluidFrameStepResult(
                appliedDeltaTime: appliedDeltaTime,
                clearedPointerForLargeGap: clearedPointerForLargeGap
            )
        }

        elapsedTime += appliedDeltaTime
        idleElapsedTime = pointerInput == nil ? idleElapsedTime + appliedDeltaTime : 0

        guard particles.count == layout.glyphs.count else {
            return FluidFrameStepResult(
                appliedDeltaTime: appliedDeltaTime,
                clearedPointerForLargeGap: clearedPointerForLargeGap
            )
        }

        fluidAdvancePointer(
            &pointer,
            dt: appliedDeltaTime,
            viewport: layout.pageMetrics.viewportRect
        )
        cursor = fluidCursorState(
            from: pointer.current,
            metrics: layout.pageMetrics
        )

        let substep = appliedDeltaTime / Double(FluidSimulationConstants.substepCount)
        for _ in 0..<FluidSimulationConstants.substepCount {
            fluidAdvanceParticles(
                &particles,
                restCenters: restCenters,
                pointer: pointer.current,
                substep: substep,
                viewport: layout.pageMetrics.viewportRect
            )
        }

        fluidResolveGlyphCollisionsWithMomentum(
            &particles,
            glyphLayouts: glyphLayouts,
            viewport: layout.pageMetrics.viewportRect
        )

        visibleOverlapPairs = fluidVisibleOverlapPairCount(
            particles: particles,
            glyphLayouts: glyphLayouts
        )

        return FluidFrameStepResult(
            appliedDeltaTime: appliedDeltaTime,
            clearedPointerForLargeGap: clearedPointerForLargeGap
        )
    }

    mutating func updatePointer(_ input: FluidPointerInput?) {
        guard let input else {
            clearPointer()
            return
        }

        if pointer.current == nil || input.isInitialContact {
            pointer.current = FluidPointerInput(center: input.center)
        }
        pointer.targetCenter = input.center
    }

    mutating func clearPointer() {
        pointer.targetCenter = nil
        pointer.current = nil
        cursor = nil
    }
}

func fluidEmptySimulationState(metrics _: FluidPageMetrics) -> FluidSimulationState {
    .empty
}

func advanceFluidSimulation(
    _ state: inout FluidSimulationState,
    pointerTarget: WrapPoint?,
    dt: Double,
    metrics: FluidPageMetrics
) {
    let pointer = pointerTarget.map { target in
        FluidPointerInput(
            center: target,
            direction: .zero,
            strength: 0
        )
    }

    _ = state.step(
        dt: dt,
        pointer: pointer,
        layout: FluidLayoutSnapshot(
            pageMetrics: metrics,
            text: "",
            glyphs: state.particles.enumerated().map { index, particle in
                FluidGlyphLayout(
                    id: particle.id,
                    character: "",
                    fontGlyph: 0,
                    restCenter: state.restCenters.indices.contains(index) ? state.restCenters[index] : particle.center,
                    drawOrigin: particle.center,
                    baselineY: particle.center.y,
                    width: 0,
                    bounds: WrapRect(x: particle.center.x, y: particle.center.y, width: 0, height: 0)
                )
            }
        )
    )
}

func fluidGlyphOffset(
    at point: WrapPoint,
    state: FluidSimulationState,
    metrics _: FluidPageMetrics
) -> WrapPoint {
    guard
        !state.particles.isEmpty,
        state.particles.count == state.restCenters.count
    else {
        return WrapPoint(x: 0, y: 0)
    }

    let nearestIndex = state.restCenters.indices.min { lhs, rhs in
        fluidDistanceSquared(from: state.restCenters[lhs], to: point) <
            fluidDistanceSquared(from: state.restCenters[rhs], to: point)
    }
    guard let nearestIndex else {
        return WrapPoint(x: 0, y: 0)
    }

    let particle = state.particles[nearestIndex]
    let rest = state.restCenters[nearestIndex]
    var offset = SIMD2<Double>(
        particle.center.x - rest.x,
        particle.center.y - rest.y
    )
    let magnitude = simd_length(offset)
    if magnitude > fluidMaximumGlyphDisplacement, magnitude > 0 {
        offset = offset / magnitude * fluidMaximumGlyphDisplacement
    }

    return WrapPoint(x: offset.x, y: offset.y)
}

func fluidCursorAngle(for velocity: SIMD2<Double>) -> Double {
    guard simd_length_squared(velocity) > 0.000001 else {
        return 0
    }

    return -atan2(velocity.y, velocity.x) + (.pi * 0.5)
}

func fluidCursorSnapshot(
    for state: FluidSimulationState,
    isActive: Bool,
    metrics _: FluidPageMetrics
) -> FluidCursorSnapshot? {
    guard isActive else {
        return nil
    }
    return state.cursor
}

func fluidSimulationIsSettled(_ state: FluidSimulationState) -> Bool {
    guard state.pointer.current == nil, state.pointer.targetCenter == nil else {
        return false
    }
    guard !state.particles.isEmpty else {
        return true
    }
    guard state.idleElapsedTime >= 1.5 else {
        return false
    }

    let (sumVelocitySquared, maxVelocitySquared) = state.particles.reduce((0.0, 0.0)) { partial, particle in
        let velocitySquared = simd_length_squared(particle.velocity)
        return (
            partial.0 + velocitySquared,
            max(partial.1, velocitySquared)
        )
    }
    let averageVelocitySquared = sumVelocitySquared / Double(state.particles.count)
    return averageVelocitySquared < 256.0 && maxVelocitySquared < 4_096.0
}

private func fluidSimulationIsPristineRestState(_ state: FluidSimulationState) -> Bool {
    guard state.particles.count == state.restCenters.count else {
        return false
    }

    return zip(state.particles, state.restCenters).allSatisfy { particle, restCenter in
        particle.center == restCenter && particle.velocity == .zero
    }
}

private func fluidAdvancePointer(
    _ pointer: inout FluidPointerState,
    dt: Double,
    viewport: WrapRect
) {
    guard let targetCenter = pointer.targetCenter else {
        pointer.current = nil
        return
    }

    let targetMouse = fluidViewportPointToPointerSpace(targetCenter, viewport: viewport)
    let previousMouse = pointer.current.map { fluidViewportPointToPointerSpace($0.center, viewport: viewport) } ?? targetMouse
    // Match web: mouse lerp with rate 8*dt
    let currentMouse = previousMouse + (
        targetMouse - previousMouse
    ) * 8.0 * dt

    // Match web: direction & strength from smoothed position delta
    let mouseDirection = previousMouse - currentMouse
    let directionLength = simd_length(mouseDirection)
    let previousStrength = pointer.current?.strength ?? 0
    // Web formula: strength += (velocity * (1-25*dt) - strength) * 8 * dt
    let smoothedSpeed = directionLength
    let targetStrength = smoothedSpeed * max(0, 1 - 25.0 * dt)
    let nextStrength = previousStrength + (
        targetStrength - previousStrength
    ) * 8.0 * dt
    let nextDirection = directionLength > 0.000001
        ? mouseDirection
        : pointer.current?.direction ?? .zero

    pointer.current = FluidPointerInput(
        center: fluidPointerSpaceToViewportPoint(currentMouse, viewport: viewport),
        direction: nextDirection,
        strength: max(0, nextStrength)
    )
}

private func fluidCursorState(
    from pointer: FluidPointerInput?,
    metrics: FluidPageMetrics
) -> FluidCursorState? {
    guard let pointer else {
        return nil
    }

    let radius = metrics.cursorBaseSize / 2
    let tailLength = metrics.cursorBaseSize *
        FluidSimulationConstants.cursorTailMultiplier * max(0, pointer.strength)

    return FluidCursorState(
        isVisible: true,
        center: pointer.center,
        angle: fluidCursorAngle(for: pointer.direction),
        ballRadius: radius,
        tailLength: tailLength
    )
}

private func fluidAdvanceParticles(
    _ particles: inout [FluidParticleState],
    restCenters: [WrapPoint],
    pointer: FluidPointerInput?,
    substep: Double,
    viewport: WrapRect
) {
    guard
        !particles.isEmpty,
        particles.count == restCenters.count
    else {
        return
    }

    let predictedCenters = particles.map { particle in
        WrapPoint(
            x: particle.center.x + particle.velocity.x * substep,
            y: particle.center.y + particle.velocity.y * substep
        )
    }
    let grid = FluidSpatialGrid(
        points: predictedCenters,
        cellSize: FluidSimulationConstants.range
    )

    var densities = Array(repeating: 0.0, count: particles.count)
    var nearDensities = Array(repeating: 0.0, count: particles.count)
    var viscosityForces = Array(repeating: SIMD2<Double>.zero, count: particles.count)
    var pressureForces = Array(repeating: SIMD2<Double>.zero, count: particles.count)

    for index in particles.indices {
        let point = predictedCenters[index]
        var density = 0.0
        var nearDensity = 0.0
        var viscosity = SIMD2<Double>.zero

        for neighborIndex in grid.neighbors(around: point) where neighborIndex != index {
            let neighborPoint = predictedCenters[neighborIndex]
            let delta = SIMD2<Double>(
                neighborPoint.x - point.x,
                neighborPoint.y - point.y
            )
            let distance = simd_length(delta)
            guard distance < FluidSimulationConstants.range else {
                continue
            }

            density += fluidDensityKernel(distance: distance)
            nearDensity += fluidNearDensityKernel(distance: distance)
            viscosity += (particles[neighborIndex].velocity - particles[index].velocity) *
                fluidViscosityKernel(distance: distance)
        }

        densities[index] = max(0, density) + 1e-6
        nearDensities[index] = nearDensity + 1e-6
        viscosityForces[index] = viscosity
    }

    let pressures = densities.map { fluidPressureForDensity($0) }
    let nearPressures = nearDensities.map { fluidNearPressureForDensity($0) }

    for index in particles.indices {
        let point = predictedCenters[index]
        var force = SIMD2<Double>.zero

        for neighborIndex in grid.neighbors(around: point) where neighborIndex != index {
            let neighborPoint = predictedCenters[neighborIndex]
            let delta = SIMD2<Double>(
                neighborPoint.x - point.x,
                neighborPoint.y - point.y
            )
            let distance = simd_length(delta)
            guard distance > 0.0001, distance < FluidSimulationConstants.range else {
                continue
            }

            let direction = delta / distance
            let sharedPressure = (pressures[index] + pressures[neighborIndex]) * 0.5
            let sharedNearPressure = (nearPressures[index] + nearPressures[neighborIndex]) * 0.5
            force += direction *
                fluidSpikyPow2Derivative(distance: distance) *
                sharedPressure /
                max(densities[neighborIndex], 1e-6)
            force += direction *
                fluidSpikyPow3Derivative(distance: distance) *
                sharedNearPressure /
                max(nearDensities[neighborIndex], 1e-6)
        }

        pressureForces[index] = force
    }

    let springFactor = FluidSimulationConstants.originalPositionFactor
    let pointerActivity = min((pointer?.strength ?? 0) * 100, 1.0)
    let effectiveDamping = FluidSimulationConstants.idleDampingFactor +
        (FluidSimulationConstants.dampingFactor - FluidSimulationConstants.idleDampingFactor) * pointerActivity

    for index in particles.indices {
        var particle = particles[index]
        var velocity = particle.velocity * effectiveDamping
        velocity += pressureForces[index] * substep
        velocity += viscosityForces[index] * FluidSimulationConstants.viscosityFactor * substep

        if springFactor > 0 {
            let springForce = SIMD2<Double>(
                (restCenters[index].x - particle.center.x) * 20.0 * springFactor,
                (restCenters[index].y - particle.center.y) * 20.0 * springFactor
            )
            velocity += springForce * substep
        }

        if FluidSimulationConstants.forceToCenterFactor > 0 {
            let centerX = viewport.minX + viewport.width * 0.5
            let centerY = viewport.minY + viewport.height * 0.5
            let toCenter = SIMD2<Double>(
                centerX - particle.center.x,
                centerY - particle.center.y
            )
            let dist = simd_length(toCenter)
            if dist > 1.0 {
                velocity += (toCenter / dist) *
                    FluidSimulationConstants.forceToCenterFactor * substep
            }
        }

        if let pointer {
            velocity += fluidPointerVelocityDelta(
                particleCenter: particle.center,
                pointer: pointer,
                viewport: viewport
            )
        }

        velocity = fluidLimitedVelocity(velocity)
        let futureCenter = WrapPoint(
            x: particle.center.x + velocity.x * substep,
            y: particle.center.y + velocity.y * substep
        )
        fluidResolvePointBoundary(
            futureCenter: futureCenter,
            velocity: &velocity,
            viewport: viewport,
            substep: substep
        )

        particle.velocity = velocity
        particle.center.x += particle.velocity.x * substep
        particle.center.y += particle.velocity.y * substep
        fluidClampParticleCenter(&particle, viewport: viewport)
        particles[index] = particle
    }
}

private func fluidPointerVelocityDelta(
    particleCenter: WrapPoint,
    pointer: FluidPointerInput,
    viewport: WrapRect
) -> SIMD2<Double> {
    guard pointer.strength > FluidSimulationConstants.pointerActivationThreshold else {
        return .zero
    }

    let particleNDC = fluidViewportPointToSimulationNDC(particleCenter, viewport: viewport)
    var mouseNDC = fluidViewportPointToPointerSpace(pointer.center, viewport: viewport)
    mouseNDC.y *= -1
    let distance = simd_distance(particleNDC, mouseNDC)
    guard distance < pointer.strength * FluidSimulationConstants.pointerForceThreshold else {
        return .zero
    }

    let scaledStrength = max(
        FluidSimulationConstants.pointerForceMinimum,
        min(
            FluidSimulationConstants.pointerForceMaximum,
            pointer.strength * FluidSimulationConstants.pointerForceRamp
        )
    )
    let falloff = max(scaledStrength * 0.5 - distance, 0)
    guard falloff > 0 else {
        return .zero
    }

    let direction = -pointer.direction

    return direction * scaledStrength * FluidSimulationConstants.pointerForceScale * falloff
}

private func fluidPointIsInsideViewport(
    _ point: WrapPoint,
    viewport: WrapRect
) -> Bool {
    point.x >= viewport.minX &&
        point.x <= viewport.maxX &&
        point.y >= viewport.minY &&
        point.y <= viewport.maxY
}

private func fluidDistanceSquared(
    from lhs: WrapPoint,
    to rhs: WrapPoint
) -> Double {
    let dx = lhs.x - rhs.x
    let dy = lhs.y - rhs.y
    return dx * dx + dy * dy
}

private func fluidDensityKernel(distance: Double) -> Double {
    guard distance < FluidSimulationConstants.range else {
        return 0
    }

    let value = FluidSimulationConstants.range - distance
    return value * value * FluidSimulationConstants.spikyPow2ScalingFactor
}

private func fluidNearDensityKernel(distance: Double) -> Double {
    guard distance < FluidSimulationConstants.range else {
        return 0
    }

    let value = FluidSimulationConstants.range - distance
    return value * value * value * FluidSimulationConstants.spikyPow3ScalingFactor
}

private func fluidSpikyPow3Derivative(distance: Double) -> Double {
    guard distance <= FluidSimulationConstants.range else {
        return 0
    }

    let value = FluidSimulationConstants.range - distance
    return -value * value * FluidSimulationConstants.spikyPow3DerivativeScalingFactor
}

private func fluidNearPressureForDensity(_ nearDensity: Double) -> Double {
    FluidSimulationConstants.nearPressureMultiplier * nearDensity
}

private func fluidViscosityKernel(distance: Double) -> Double {
    guard distance < FluidSimulationConstants.range else {
        return 0
    }

    let value = FluidSimulationConstants.range * FluidSimulationConstants.range - distance * distance
    return value * value * value * FluidSimulationConstants.poly6ScalingFactor
}

private func fluidSpikyPow2Derivative(distance: Double) -> Double {
    guard distance <= FluidSimulationConstants.range else {
        return 0
    }

    let value = FluidSimulationConstants.range - distance
    return -value * FluidSimulationConstants.spikyPow2DerivativeScalingFactor
}

private func fluidViewportPointToPointerSpace(
    _ point: WrapPoint,
    viewport: WrapRect
) -> SIMD2<Double> {
    guard viewport.width > 0, viewport.height > 0 else {
        return .zero
    }

    return SIMD2<Double>(
        (point.x / viewport.width - 0.5) * 2,
        (point.y / viewport.height - 0.5) * 2
    )
}

private func fluidPointerSpaceToViewportPoint(
    _ point: SIMD2<Double>,
    viewport: WrapRect
) -> WrapPoint {
    WrapPoint(
        x: (point.x * 0.5 + 0.5) * viewport.width,
        y: (point.y * 0.5 + 0.5) * viewport.height
    )
}

private func fluidViewportPointToSimulationNDC(
    _ point: WrapPoint,
    viewport: WrapRect
) -> SIMD2<Double> {
    guard viewport.width > 0, viewport.height > 0 else {
        return .zero
    }

    return SIMD2<Double>(
        (point.x / viewport.width - 0.5) * 2,
        (0.5 - point.y / viewport.height) * 2
    )
}

private func fluidLimitedVelocity(_ velocity: SIMD2<Double>) -> SIMD2<Double> {
    let speed = simd_length(velocity)
    guard speed > FluidSimulationConstants.maxVelocity, speed > 0 else {
        return velocity
    }

    return velocity / speed * FluidSimulationConstants.maxVelocity
}

private func fluidResolvePointBoundary(
    futureCenter: WrapPoint,
    velocity: inout SIMD2<Double>,
    viewport: WrapRect,
    substep: Double
) {
    let minX = viewport.minX + fluidBoundaryMargin
    let maxX = viewport.maxX - fluidBoundaryMargin
    let minY = viewport.minY + fluidBoundaryMarginTop
    let maxY = viewport.maxY - fluidBoundaryMargin

    if futureCenter.x < minX || futureCenter.x > maxX {
        velocity.x *= -0.5
    }

    if futureCenter.y < minY || futureCenter.y > maxY {
        velocity.y *= -0.5
    }
}

private func fluidResolveBoundary(
    futureBounds: WrapRect,
    velocity: inout SIMD2<Double>,
    viewport: WrapRect
) {
    fluidResolvePointBoundary(
        futureCenter: WrapPoint(x: futureBounds.midX, y: futureBounds.midY),
        velocity: &velocity,
        viewport: viewport,
        substep: 1.0 / 60.0
    )
}

private let fluidBoundaryMargin = 10.0
private let fluidBoundaryMarginTop = 52.0

private func fluidClampParticleCenter(
    _ particle: inout FluidParticleState,
    viewport: WrapRect
) {
    let minX = viewport.minX + fluidBoundaryMargin
    let maxX = viewport.maxX - fluidBoundaryMargin
    let minY = viewport.minY + fluidBoundaryMarginTop
    let maxY = viewport.maxY - fluidBoundaryMargin

    if particle.center.x < minX {
        particle.center.x = minX
        if particle.velocity.x < 0 { particle.velocity.x = 0 }
    } else if particle.center.x > maxX {
        particle.center.x = maxX
        if particle.velocity.x > 0 { particle.velocity.x = 0 }
    }
    if particle.center.y < minY {
        particle.center.y = minY
        if particle.velocity.y < 0 { particle.velocity.y = 0 }
    } else if particle.center.y > maxY {
        particle.center.y = maxY
        if particle.velocity.y > 0 { particle.velocity.y = 0 }
    }
}

private func fluidClampParticle(
    _ particle: inout FluidParticleState,
    glyph _: FluidGlyphLayout,
    viewport: WrapRect
) {
    fluidClampParticleCenter(&particle, viewport: viewport)
}

private func fluidClampParticleForVisibleBounds(
    _ particle: inout FluidParticleState,
    glyph: FluidGlyphLayout,
    viewport: WrapRect
) {
    let halfWidth = glyph.bounds.width * 0.5
    let halfHeight = glyph.bounds.height * 0.5

    particle.center.x = min(
        max(particle.center.x, viewport.minX - halfWidth),
        viewport.maxX + halfWidth
    )
    particle.center.y = min(
        max(particle.center.y, viewport.minY - halfHeight),
        viewport.maxY + halfHeight
    )
}

private func fluidExpandedBounds(
    _ bounds: WrapRect,
    padding: Double
) -> WrapRect {
    WrapRect(
        x: bounds.x - padding,
        y: bounds.y - padding,
        width: bounds.width + padding * 2,
        height: bounds.height + padding * 2
    )
}

private func fluidResolveCurrentCursorClearance(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    pointer: FluidPointerInput,
    viewport: WrapRect
) {
    guard particles.count == glyphLayouts.count else {
        return
    }

    let clearanceRadius = fluidCursorClearanceRadius(
        pointer: pointer,
        viewport: viewport
    )
    guard clearanceRadius > 0 else {
        return
    }

    for index in particles.indices {
        let direction = SIMD2<Double>(
            particles[index].center.x - pointer.center.x,
            particles[index].center.y - pointer.center.y
        )
        let distance = simd_length(direction)
        guard distance < clearanceRadius else {
            continue
        }

        let normalizedDirection: SIMD2<Double>
        if distance > 0.0001 {
            normalizedDirection = direction / distance
        } else {
            let fallback = SIMD2<Double>(
                glyphLayouts[index].restCenter.x - pointer.center.x,
                glyphLayouts[index].restCenter.y - pointer.center.y
            )
            let fallbackLength = simd_length(fallback)
            normalizedDirection = fallbackLength > 0.0001
                ? fallback / fallbackLength
                : SIMD2<Double>(1, 0)
        }

        let shift = clearanceRadius +
            fluidGlyphClearanceInset(glyphLayouts[index]) -
            distance
        particles[index].center.x += normalizedDirection.x * shift
        particles[index].center.y += normalizedDirection.y * shift
        particles[index].velocity += normalizedDirection * (shift * 4.0)
        fluidClampParticle(
            &particles[index],
            glyph: glyphLayouts[index],
            viewport: viewport
        )
    }
}

private func fluidCursorClearanceRadius(
    pointer: FluidPointerInput,
    viewport: WrapRect
) -> Double {
    34.0 + pointer.strength * min(viewport.width, viewport.height) * 0.24
}

private func fluidResolveEdgeIntersections(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    viewport: WrapRect
) {
    guard particles.count == glyphLayouts.count else {
        return
    }

    let edgeInset = 48.0
    let candidateIndices = particles.indices.filter { index in
        let bounds = fluidTranslatedGlyphBounds(
            glyphLayouts[index],
            center: particles[index].center
        )
        return bounds.minX <= viewport.minX + edgeInset ||
            bounds.maxX >= viewport.maxX - edgeInset ||
            bounds.minY <= viewport.minY + edgeInset ||
            bounds.maxY >= viewport.maxY - edgeInset
    }

    guard candidateIndices.count > 1 else {
        return
    }

    fluidResolveExactGlyphIntersections(
        &particles,
        glyphLayouts: glyphLayouts,
        candidateIndices: candidateIndices,
        viewport: viewport
    )

    fluidResolveHorizontalEdgePacking(
        &particles,
        glyphLayouts: glyphLayouts,
        candidateIndices: candidateIndices,
        viewport: viewport
    )

    fluidResolveVerticalEdgePacking(
        &particles,
        glyphLayouts: glyphLayouts,
        candidateIndices: candidateIndices,
        viewport: viewport
    )

}

private func fluidResolveExactGlyphIntersections(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    candidateIndices: [Int],
    viewport: WrapRect
) {
    for _ in 0..<FluidSimulationConstants.edgeIntersectionPasses {
        var resolvedAnyOverlap = false

        for lhsOffset in 0..<candidateIndices.count {
            let lhsIndex = candidateIndices[lhsOffset]
            for rhsOffset in (lhsOffset + 1)..<candidateIndices.count {
                let rhsIndex = candidateIndices[rhsOffset]
                let lhsBounds = fluidTranslatedGlyphBounds(
                    glyphLayouts[lhsIndex],
                    center: particles[lhsIndex].center
                )
                let rhsBounds = fluidTranslatedGlyphBounds(
                    glyphLayouts[rhsIndex],
                    center: particles[rhsIndex].center
                )

                let overlapX = min(lhsBounds.maxX, rhsBounds.maxX) - max(lhsBounds.minX, rhsBounds.minX)
                let overlapY = min(lhsBounds.maxY, rhsBounds.maxY) - max(lhsBounds.minY, rhsBounds.minY)
                guard overlapX > 0, overlapY > 0 else {
                    continue
                }
                resolvedAnyOverlap = true

                let delta = SIMD2<Double>(
                    particles[lhsIndex].center.x - particles[rhsIndex].center.x,
                    particles[lhsIndex].center.y - particles[rhsIndex].center.y
                )

                if overlapX <= overlapY {
                    let direction = fluidSeparationDirection(
                        primary: delta.x,
                        fallback: glyphLayouts[lhsIndex].restCenter.x - glyphLayouts[rhsIndex].restCenter.x
                    )
                    let lhsPinned = lhsBounds.minX <= viewport.minX + 0.001 || lhsBounds.maxX >= viewport.maxX - 0.001
                    let rhsPinned = rhsBounds.minX <= viewport.minX + 0.001 || rhsBounds.maxX >= viewport.maxX - 0.001
                    let fullShift = overlapX + 1.0
                    if lhsPinned, !rhsPinned {
                        particles[rhsIndex].center.x -= direction * fullShift
                    } else if rhsPinned, !lhsPinned {
                        particles[lhsIndex].center.x += direction * fullShift
                    } else {
                        let shift = fullShift * 0.5
                        particles[lhsIndex].center.x += direction * shift
                        particles[rhsIndex].center.x -= direction * shift
                    }
                } else {
                    let direction = fluidSeparationDirection(
                        primary: delta.y,
                        fallback: glyphLayouts[lhsIndex].restCenter.y - glyphLayouts[rhsIndex].restCenter.y
                    )
                    let lhsPinned = lhsBounds.minY <= viewport.minY + 0.001 || lhsBounds.maxY >= viewport.maxY - 0.001
                    let rhsPinned = rhsBounds.minY <= viewport.minY + 0.001 || rhsBounds.maxY >= viewport.maxY - 0.001
                    let fullShift = overlapY + 1.0
                    if lhsPinned, !rhsPinned {
                        particles[rhsIndex].center.y -= direction * fullShift
                    } else if rhsPinned, !lhsPinned {
                        particles[lhsIndex].center.y += direction * fullShift
                    } else {
                        let shift = fullShift * 0.5
                        particles[lhsIndex].center.y += direction * shift
                        particles[rhsIndex].center.y -= direction * shift
                    }
                }

            }
        }

        for index in candidateIndices {
            fluidClampParticle(
                &particles[index],
                glyph: glyphLayouts[index],
                viewport: viewport
            )
        }

        if !resolvedAnyOverlap {
            break
        }
    }
}

private func fluidResolveHorizontalEdgePacking(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    candidateIndices: [Int],
    viewport: WrapRect
) {
    let rowKey: (Int) -> Int = { index in
        Int(round(glyphLayouts[index].baselineY * 2))
    }
    let gap = 1.0

    let leftRows = Set(candidateIndices.compactMap { index -> Int? in
        let bounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        return bounds.minX <= viewport.minX + 48.0 ? rowKey(index) : nil
    })
    let leftCandidates = particles.indices.filter { leftRows.contains(rowKey($0)) }
    let leftOrdered = leftCandidates.sorted { lhs, rhs in
        let lhsRow = rowKey(lhs)
        let rhsRow = rowKey(rhs)
        if lhsRow != rhsRow {
            return lhsRow < rhsRow
        }

        let lhsBounds = fluidTranslatedGlyphBounds(glyphLayouts[lhs], center: particles[lhs].center)
        let rhsBounds = fluidTranslatedGlyphBounds(glyphLayouts[rhs], center: particles[rhs].center)
        return lhsBounds.minX < rhsBounds.minX
    }

    var currentLeftRow: Int?
    var previousMaxX = viewport.minX
    for index in leftOrdered {
        let row = rowKey(index)
        if row != currentLeftRow {
            currentLeftRow = row
            previousMaxX = viewport.minX
        }

        let bounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        if bounds.minX < previousMaxX + gap {
            particles[index].center.x += previousMaxX + gap - bounds.minX
            fluidClampParticle(
                &particles[index],
                glyph: glyphLayouts[index],
                viewport: viewport
            )
        }
        let updatedBounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        previousMaxX = max(previousMaxX, updatedBounds.maxX)
    }

    let rightRows = Set(candidateIndices.compactMap { index -> Int? in
        let bounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        return bounds.maxX >= viewport.maxX - 48.0 ? rowKey(index) : nil
    })
    let rightCandidates = particles.indices.filter { rightRows.contains(rowKey($0)) }
    let rightOrdered = rightCandidates.sorted { lhs, rhs in
        let lhsRow = rowKey(lhs)
        let rhsRow = rowKey(rhs)
        if lhsRow != rhsRow {
            return lhsRow < rhsRow
        }

        let lhsBounds = fluidTranslatedGlyphBounds(glyphLayouts[lhs], center: particles[lhs].center)
        let rhsBounds = fluidTranslatedGlyphBounds(glyphLayouts[rhs], center: particles[rhs].center)
        return lhsBounds.maxX > rhsBounds.maxX
    }

    var currentRightRow: Int?
    var previousMinX = viewport.maxX
    for index in rightOrdered {
        let row = rowKey(index)
        if row != currentRightRow {
            currentRightRow = row
            previousMinX = viewport.maxX
        }

        let bounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        if bounds.maxX > previousMinX - gap {
            particles[index].center.x -= bounds.maxX - (previousMinX - gap)
            fluidClampParticle(
                &particles[index],
                glyph: glyphLayouts[index],
                viewport: viewport
            )
        }
        let updatedBounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        previousMinX = min(previousMinX, updatedBounds.minX)
    }
}

private func fluidResolveVerticalEdgePacking(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    candidateIndices: [Int],
    viewport: WrapRect
) {
    let columnKey: (Int) -> Int = { index in
        Int(round(glyphLayouts[index].restCenter.x / 12.0))
    }
    let gap = 1.0

    let topColumns = Set(candidateIndices.compactMap { index -> Int? in
        let bounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        return bounds.minY <= viewport.minY + 48.0 ? columnKey(index) : nil
    })
    let topCandidates = particles.indices.filter { topColumns.contains(columnKey($0)) }
    let topOrdered = topCandidates.sorted { lhs, rhs in
        let lhsColumn = columnKey(lhs)
        let rhsColumn = columnKey(rhs)
        if lhsColumn != rhsColumn {
            return lhsColumn < rhsColumn
        }

        let lhsBounds = fluidTranslatedGlyphBounds(glyphLayouts[lhs], center: particles[lhs].center)
        let rhsBounds = fluidTranslatedGlyphBounds(glyphLayouts[rhs], center: particles[rhs].center)
        return lhsBounds.minY < rhsBounds.minY
    }

    var currentTopColumn: Int?
    var previousMaxY = viewport.minY
    for index in topOrdered {
        let column = columnKey(index)
        if column != currentTopColumn {
            currentTopColumn = column
            previousMaxY = viewport.minY
        }

        let bounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        if bounds.minY < previousMaxY + gap {
            particles[index].center.y += previousMaxY + gap - bounds.minY
            fluidClampParticle(
                &particles[index],
                glyph: glyphLayouts[index],
                viewport: viewport
            )
        }
        let updatedBounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        previousMaxY = max(previousMaxY, updatedBounds.maxY)
    }

    let bottomColumns = Set(candidateIndices.compactMap { index -> Int? in
        let bounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        return bounds.maxY >= viewport.maxY - 48.0 ? columnKey(index) : nil
    })
    let bottomCandidates = particles.indices.filter { bottomColumns.contains(columnKey($0)) }
    let bottomOrdered = bottomCandidates.sorted { lhs, rhs in
        let lhsColumn = columnKey(lhs)
        let rhsColumn = columnKey(rhs)
        if lhsColumn != rhsColumn {
            return lhsColumn < rhsColumn
        }

        let lhsBounds = fluidTranslatedGlyphBounds(glyphLayouts[lhs], center: particles[lhs].center)
        let rhsBounds = fluidTranslatedGlyphBounds(glyphLayouts[rhs], center: particles[rhs].center)
        return lhsBounds.maxY > rhsBounds.maxY
    }

    var currentBottomColumn: Int?
    var previousMinY = viewport.maxY
    for index in bottomOrdered {
        let column = columnKey(index)
        if column != currentBottomColumn {
            currentBottomColumn = column
            previousMinY = viewport.maxY
        }

        let bounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        if bounds.maxY > previousMinY - gap {
            particles[index].center.y -= bounds.maxY - (previousMinY - gap)
            fluidClampParticle(
                &particles[index],
                glyph: glyphLayouts[index],
                viewport: viewport
            )
        }
        let updatedBounds = fluidTranslatedGlyphBounds(glyphLayouts[index], center: particles[index].center)
        previousMinY = min(previousMinY, updatedBounds.minY)
    }
}

private func fluidResolveGlyphOverlaps(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    pointer: FluidPointerInput?,
    viewport: WrapRect
) {
    guard particles.count == glyphLayouts.count else {
        return
    }

    fluidResolvePairwiseGlyphOverlaps(
        &particles,
        glyphLayouts: glyphLayouts,
        viewport: viewport,
        passCount: FluidSimulationConstants.collisionPasses
    )
}

private func fluidResolvePairwiseGlyphOverlaps(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    viewport: WrapRect,
    passCount: Int
) {
    let collisionCellSize = fluidCollisionCellSize(for: glyphLayouts)

    for _ in 0..<passCount {
        var resolvedAnyOverlap = false
        let grid = FluidSpatialGrid(
            points: particles.map(\.center),
            cellSize: collisionCellSize
        )

        for index in particles.indices {
            let neighborIndices = grid.neighbors(around: particles[index].center)
            for neighborIndex in neighborIndices where neighborIndex > index {
                let lhsBounds = fluidTranslatedGlyphBounds(
                    glyphLayouts[index],
                    center: particles[index].center
                )
                let rhsBounds = fluidTranslatedGlyphBounds(
                    glyphLayouts[neighborIndex],
                    center: particles[neighborIndex].center
                )
                let expandedLHSBounds = fluidExpandedBounds(
                    lhsBounds,
                    padding: FluidSimulationConstants.collisionPadding
                )
                let expandedRHSBounds = fluidExpandedBounds(
                    rhsBounds,
                    padding: FluidSimulationConstants.collisionPadding
                )

                let overlapX = min(expandedLHSBounds.maxX, expandedRHSBounds.maxX) - max(expandedLHSBounds.minX, expandedRHSBounds.minX)
                let overlapY = min(expandedLHSBounds.maxY, expandedRHSBounds.maxY) - max(expandedLHSBounds.minY, expandedRHSBounds.minY)
                guard overlapX > 0, overlapY > 0 else {
                    continue
                }
                resolvedAnyOverlap = true

                let delta = SIMD2<Double>(
                    particles[index].center.x - particles[neighborIndex].center.x,
                    particles[index].center.y - particles[neighborIndex].center.y
                )

                if overlapX <= overlapY {
                    let direction = fluidSeparationDirection(
                        primary: delta.x,
                        fallback: glyphLayouts[index].restCenter.x - glyphLayouts[neighborIndex].restCenter.x
                    )
                    let shift = (overlapX + FluidSimulationConstants.collisionGap) * 0.5
                    particles[index].center.x += direction * shift
                    particles[neighborIndex].center.x -= direction * shift
                    particles[index].velocity.x *= FluidSimulationConstants.collisionVelocityDamping
                    particles[neighborIndex].velocity.x *= FluidSimulationConstants.collisionVelocityDamping
                } else {
                    let direction = fluidSeparationDirection(
                        primary: delta.y,
                        fallback: glyphLayouts[index].restCenter.y - glyphLayouts[neighborIndex].restCenter.y
                    )
                    let shift = (overlapY + FluidSimulationConstants.collisionGap) * 0.5
                    particles[index].center.y += direction * shift
                    particles[neighborIndex].center.y -= direction * shift
                    particles[index].velocity.y *= FluidSimulationConstants.collisionVelocityDamping
                    particles[neighborIndex].velocity.y *= FluidSimulationConstants.collisionVelocityDamping
                }

                fluidClampParticleForVisibleBounds(
                    &particles[index],
                    glyph: glyphLayouts[index],
                    viewport: viewport
                )
                fluidClampParticleForVisibleBounds(
                    &particles[neighborIndex],
                    glyph: glyphLayouts[neighborIndex],
                    viewport: viewport
                )
            }
        }

        if !resolvedAnyOverlap {
            break
        }
    }
}

private func fluidResolveGlyphCollisionsWithMomentum(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    viewport: WrapRect
) {
    guard particles.count == glyphLayouts.count, !particles.isEmpty else { return }

    let collisionCellSize = fluidCollisionCellSize(for: glyphLayouts)
    let restitution = 1.0

    for _ in 0..<FluidSimulationConstants.collisionPasses {
        let grid = FluidSpatialGrid(
            points: particles.map(\.center),
            cellSize: collisionCellSize
        )
        var resolvedAny = false

        for index in particles.indices {
            for neighborIndex in grid.neighbors(around: particles[index].center)
                where neighborIndex > index
            {
                let bounds = fluidTranslatedGlyphBounds(
                    glyphLayouts[index],
                    center: particles[index].center
                )
                let neighborBounds = fluidTranslatedGlyphBounds(
                    glyphLayouts[neighborIndex],
                    center: particles[neighborIndex].center
                )
                let overlapX = min(bounds.maxX, neighborBounds.maxX) - max(bounds.minX, neighborBounds.minX)
                let overlapY = min(bounds.maxY, neighborBounds.maxY) - max(bounds.minY, neighborBounds.minY)
                guard overlapX > 0, overlapY > 0 else { continue }

                let maxSpeed = max(
                    simd_length(particles[index].velocity),
                    simd_length(particles[neighborIndex].velocity)
                )
                guard maxSpeed > 2.0 else { continue }

                resolvedAny = true

                let delta = SIMD2<Double>(
                    particles[index].center.x - particles[neighborIndex].center.x,
                    particles[index].center.y - particles[neighborIndex].center.y
                )

                if overlapX <= overlapY {
                    let direction = fluidSeparationDirection(
                        primary: delta.x,
                        fallback: glyphLayouts[index].restCenter.x - glyphLayouts[neighborIndex].restCenter.x
                    )
                    let shift = (overlapX + FluidSimulationConstants.collisionGap) * 0.5
                    particles[index].center.x += direction * shift
                    particles[neighborIndex].center.x -= direction * shift
                    let v1 = particles[index].velocity.x
                    let v2 = particles[neighborIndex].velocity.x
                    particles[index].velocity.x = (v1 + v2) * 0.5 + restitution * (v2 - v1) * 0.5
                    particles[neighborIndex].velocity.x = (v1 + v2) * 0.5 + restitution * (v1 - v2) * 0.5
                } else {
                    let direction = fluidSeparationDirection(
                        primary: delta.y,
                        fallback: glyphLayouts[index].restCenter.y - glyphLayouts[neighborIndex].restCenter.y
                    )
                    let shift = (overlapY + FluidSimulationConstants.collisionGap) * 0.5
                    particles[index].center.y += direction * shift
                    particles[neighborIndex].center.y -= direction * shift
                    let v1 = particles[index].velocity.y
                    let v2 = particles[neighborIndex].velocity.y
                    particles[index].velocity.y = (v1 + v2) * 0.5 + restitution * (v2 - v1) * 0.5
                    particles[neighborIndex].velocity.y = (v1 + v2) * 0.5 + restitution * (v1 - v2) * 0.5
                }

                fluidClampParticleCenter(&particles[index], viewport: viewport)
                fluidClampParticleCenter(&particles[neighborIndex], viewport: viewport)
            }
        }

        if !resolvedAny { break }
    }
}

private func fluidSeparateOverlappingGlyphs(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    viewport: WrapRect
) {
    guard particles.count == glyphLayouts.count, !particles.isEmpty else { return }

    let collisionCellSize = fluidCollisionCellSize(for: glyphLayouts)

    for _ in 0..<FluidSimulationConstants.collisionPasses {
        let grid = FluidSpatialGrid(
            points: particles.map(\.center),
            cellSize: collisionCellSize
        )
        var resolvedAny = false

        for index in particles.indices {
            for neighborIndex in grid.neighbors(around: particles[index].center)
                where neighborIndex > index
            {
                let bounds = fluidTranslatedGlyphBounds(
                    glyphLayouts[index],
                    center: particles[index].center
                )
                let neighborBounds = fluidTranslatedGlyphBounds(
                    glyphLayouts[neighborIndex],
                    center: particles[neighborIndex].center
                )
                let overlapX = min(bounds.maxX, neighborBounds.maxX) - max(bounds.minX, neighborBounds.minX)
                let overlapY = min(bounds.maxY, neighborBounds.maxY) - max(bounds.minY, neighborBounds.minY)
                guard overlapX > 0, overlapY > 0 else { continue }
                resolvedAny = true

                let delta = SIMD2<Double>(
                    particles[index].center.x - particles[neighborIndex].center.x,
                    particles[index].center.y - particles[neighborIndex].center.y
                )

                if overlapX <= overlapY {
                    let direction = fluidSeparationDirection(
                        primary: delta.x,
                        fallback: glyphLayouts[index].restCenter.x - glyphLayouts[neighborIndex].restCenter.x
                    )
                    let shift = (overlapX + FluidSimulationConstants.collisionGap) * 0.5
                    particles[index].center.x += direction * shift
                    particles[neighborIndex].center.x -= direction * shift
                } else {
                    let direction = fluidSeparationDirection(
                        primary: delta.y,
                        fallback: glyphLayouts[index].restCenter.y - glyphLayouts[neighborIndex].restCenter.y
                    )
                    let shift = (overlapY + FluidSimulationConstants.collisionGap) * 0.5
                    particles[index].center.y += direction * shift
                    particles[neighborIndex].center.y -= direction * shift
                }

                fluidClampParticleCenter(&particles[index], viewport: viewport)
                fluidClampParticleCenter(&particles[neighborIndex], viewport: viewport)
            }
        }

        if !resolvedAny { break }
    }
}

private func fluidCollisionCellSize(for glyphLayouts: [FluidGlyphLayout]) -> Double {
    glyphLayouts.reduce(FluidSimulationConstants.collisionCellSize) { partial, glyph in
        max(
            partial,
            max(glyph.bounds.width, glyph.bounds.height) +
                FluidSimulationConstants.collisionPadding * 2 +
                FluidSimulationConstants.collisionGap
        )
    }
}

private func fluidApplyDisplacedGlyphCollisionImpulses(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    restCenters: [WrapPoint],
    viewport: WrapRect
) {
    guard particles.count == glyphLayouts.count,
          particles.count == restCenters.count,
          !particles.isEmpty
    else { return }

    let displacementThreshold = 10.0
    let collisionCellSize = fluidCollisionCellSize(for: glyphLayouts)

    for _ in 0..<FluidSimulationConstants.collisionPasses {
        let grid = FluidSpatialGrid(
            points: particles.map(\.center),
            cellSize: collisionCellSize
        )
        var resolvedAny = false

        for index in particles.indices {
            for neighborIndex in grid.neighbors(around: particles[index].center)
                where neighborIndex > index
            {
                let displacementA = simd_length(SIMD2<Double>(
                    particles[index].center.x - restCenters[index].x,
                    particles[index].center.y - restCenters[index].y
                ))
                let displacementB = simd_length(SIMD2<Double>(
                    particles[neighborIndex].center.x - restCenters[neighborIndex].x,
                    particles[neighborIndex].center.y - restCenters[neighborIndex].y
                ))
                guard displacementA > displacementThreshold ||
                      displacementB > displacementThreshold
                else { continue }

                let bounds = fluidTranslatedGlyphBounds(
                    glyphLayouts[index],
                    center: particles[index].center
                )
                let neighborBounds = fluidTranslatedGlyphBounds(
                    glyphLayouts[neighborIndex],
                    center: particles[neighborIndex].center
                )
                let overlapX = min(bounds.maxX, neighborBounds.maxX) - max(bounds.minX, neighborBounds.minX)
                let overlapY = min(bounds.maxY, neighborBounds.maxY) - max(bounds.minY, neighborBounds.minY)
                guard overlapX > 0, overlapY > 0 else { continue }
                resolvedAny = true

                let delta = SIMD2<Double>(
                    particles[index].center.x - particles[neighborIndex].center.x,
                    particles[index].center.y - particles[neighborIndex].center.y
                )

                if overlapX <= overlapY {
                    let direction = fluidSeparationDirection(
                        primary: delta.x,
                        fallback: glyphLayouts[index].restCenter.x - glyphLayouts[neighborIndex].restCenter.x
                    )
                    let shift = (overlapX + FluidSimulationConstants.collisionGap) * 0.5
                    particles[index].center.x += direction * shift
                    particles[neighborIndex].center.x -= direction * shift
                } else {
                    let direction = fluidSeparationDirection(
                        primary: delta.y,
                        fallback: glyphLayouts[index].restCenter.y - glyphLayouts[neighborIndex].restCenter.y
                    )
                    let shift = (overlapY + FluidSimulationConstants.collisionGap) * 0.5
                    particles[index].center.y += direction * shift
                    particles[neighborIndex].center.y -= direction * shift
                }

                fluidClampParticleCenter(&particles[index], viewport: viewport)
                fluidClampParticleCenter(&particles[neighborIndex], viewport: viewport)
            }
        }

        if !resolvedAny { break }
    }
}

private func fluidGlyphClearanceInset(_ glyph: FluidGlyphLayout) -> Double {
    max(glyph.bounds.width, glyph.bounds.height) * 0.5 +
        FluidSimulationConstants.collisionPadding
}

private func fluidSeparationDirection(
    primary: Double,
    fallback: Double
) -> Double {
    if abs(primary) > 0.0001 {
        return primary < 0 ? -1 : 1
    }

    if abs(fallback) > 0.0001 {
        return fallback < 0 ? -1 : 1
    }

    return 1
}

func fluidVisibleOverlapPairCount(
    particles: [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    inset: Double = 0
) -> Int {
    guard particles.count == glyphLayouts.count else {
        return .max
    }

    let collisionCellSize = fluidCollisionCellSize(for: glyphLayouts)
    let grid = FluidSpatialGrid(
        points: particles.map(\.center),
        cellSize: collisionCellSize
    )

    var overlaps = 0
    for lhs in glyphLayouts.indices {
        let lhsBounds = fluidInsetBounds(
            fluidTranslatedGlyphBounds(
                glyphLayouts[lhs],
                center: particles[lhs].center
            ),
            inset: inset
        )

        let neighborIndices = grid.neighbors(around: particles[lhs].center)
        for rhs in neighborIndices where rhs > lhs {
            let rhsBounds = fluidInsetBounds(
                fluidTranslatedGlyphBounds(
                    glyphLayouts[rhs],
                    center: particles[rhs].center
                ),
                inset: inset
            )

            let overlapX = min(lhsBounds.maxX, rhsBounds.maxX) - max(lhsBounds.minX, rhsBounds.minX)
            let overlapY = min(lhsBounds.maxY, rhsBounds.maxY) - max(lhsBounds.minY, rhsBounds.minY)
            if overlapX > 0, overlapY > 0 {
                overlaps += 1
            }
        }
    }

    return overlaps
}

private func fluidInsetBounds(
    _ bounds: WrapRect,
    inset: Double
) -> WrapRect {
    WrapRect(
        x: bounds.x + inset,
        y: bounds.y + inset,
        width: bounds.width - inset * 2,
        height: bounds.height - inset * 2
    )
}

private func fluidApplyNativeParticleCorrections(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    viewport: WrapRect
) {
    guard particles.count == glyphLayouts.count else {
        return
    }

    var previousOverlapCount = Int.max
    for _ in 0..<FluidSimulationConstants.nativeCorrectionPasses {
        fluidResolveGlyphOverlaps(
            &particles,
            glyphLayouts: glyphLayouts,
            pointer: nil,
            viewport: viewport
        )

        for index in particles.indices {
            var velocity = particles[index].velocity
            let bounds = fluidTranslatedGlyphBounds(
                glyphLayouts[index],
                center: particles[index].center
            )
            fluidResolveBoundary(
                futureBounds: bounds,
                velocity: &velocity,
                viewport: viewport
            )
            particles[index].velocity = velocity
            fluidClampParticle(
                &particles[index],
                glyph: glyphLayouts[index],
                viewport: viewport
            )
        }

        fluidResolveEdgeIntersections(
            &particles,
            glyphLayouts: glyphLayouts,
            viewport: viewport
        )

        let overlapCount = fluidVisibleOverlapPairCount(
            particles: particles,
            glyphLayouts: glyphLayouts
        )
        if overlapCount == 0 || overlapCount >= previousOverlapCount {
            break
        }
        previousOverlapCount = overlapCount
    }
}

private func fluidResolveVisibleOverlapBeyondRestBaseline(
    _ particles: inout [FluidParticleState],
    glyphLayouts: [FluidGlyphLayout],
    viewport: WrapRect,
    baselineCount: Int
) {
    guard particles.count == glyphLayouts.count else {
        return
    }

    var overlapCount = fluidVisibleOverlapPairCount(
        particles: particles,
        glyphLayouts: glyphLayouts
    )
    guard overlapCount > baselineCount else {
        return
    }

    for _ in 0..<FluidSimulationConstants.nativeCorrectionPasses {
        fluidResolvePairwiseGlyphOverlaps(
            &particles,
            glyphLayouts: glyphLayouts,
            viewport: viewport,
            passCount: FluidSimulationConstants.collisionPasses
        )

        overlapCount = fluidVisibleOverlapPairCount(
            particles: particles,
            glyphLayouts: glyphLayouts
        )
        if overlapCount <= baselineCount {
            break
        }
    }
}

@discardableResult
private func fluidZeroParticleVelocitiesIfSettled(
    _ state: inout FluidSimulationState
) -> Bool {
    guard fluidSimulationIsSettled(state) else {
        return false
    }

    var zeroedAnyVelocity = false
    for index in state.particles.indices {
        if state.particles[index].velocity != .zero {
            zeroedAnyVelocity = true
        }
        state.particles[index].velocity = .zero
    }

    return zeroedAnyVelocity
}

#if !os(watchOS)
final class FluidSimulationDriver {
    private var state = FluidSimulationState.empty
    #if canImport(Metal)
    private let metalEngine = FluidMetalSimulationEngine()
    #endif

    var snapshot: FluidSimulationState { state }

    func reset(from layout: FluidLayoutSnapshot) {
        state.reset(from: layout)
        #if canImport(Metal)
        metalEngine?.reset(from: layout)
        #endif
    }

    @discardableResult
    func step(
        dt: Double,
        pointer pointerInput: FluidPointerInput?,
        layout: FluidLayoutSnapshot
    ) -> FluidFrameStepResult {
        #if canImport(Metal)
        if let metalEngine {
            return stepWithMetal(
                using: metalEngine,
                dt: dt,
                pointer: pointerInput,
                layout: layout
            )
        }
        #endif

        return state.step(
            dt: dt,
            pointer: pointerInput,
            layout: layout
        )
    }

    func clearPointer() {
        state.clearPointer()
    }

    #if canImport(Metal)
    private func stepWithMetal(
        using metalEngine: FluidMetalSimulationEngine,
        dt: Double,
        pointer pointerInput: FluidPointerInput?,
        layout: FluidLayoutSnapshot
    ) -> FluidFrameStepResult {
        if state.particles.map(\.id) != layout.glyphs.map(\.id) {
            reset(from: layout)
        }

        var clearedPointerForLargeGap = false
        let appliedDeltaTime: Double
        if dt > 0.1 {
            state.clearPointer()
            clearedPointerForLargeGap = true
            appliedDeltaTime = 1.0 / 60.0
        } else {
            appliedDeltaTime = min(max(dt, 1.0 / 240.0), 1.0 / 20.0)
            if let pointerInput {
                state.hasActivatedPointer = true
                state.updatePointer(pointerInput)
            }
        }

        guard state.hasActivatedPointer || pointerInput != nil || !fluidSimulationIsPristineRestState(state) else {
            return FluidFrameStepResult(
                appliedDeltaTime: appliedDeltaTime,
                clearedPointerForLargeGap: clearedPointerForLargeGap
            )
        }

        state.elapsedTime += appliedDeltaTime
        state.idleElapsedTime = pointerInput == nil ? state.idleElapsedTime + appliedDeltaTime : 0

        guard state.particles.count == layout.glyphs.count else {
            return FluidFrameStepResult(
                appliedDeltaTime: appliedDeltaTime,
                clearedPointerForLargeGap: clearedPointerForLargeGap
            )
        }

        fluidAdvancePointer(
            &state.pointer,
            dt: appliedDeltaTime,
            viewport: layout.pageMetrics.viewportRect
        )
        state.cursor = fluidCursorState(
            from: state.pointer.current,
            metrics: layout.pageMetrics
        )

        metalEngine.advanceFrame(
            dt: appliedDeltaTime,
            substepCount: FluidSimulationConstants.substepCount,
            layout: layout,
            pointer: state.pointer.current,
            state: &state
        )

        fluidResolveGlyphCollisionsWithMomentum(
            &state.particles,
            glyphLayouts: state.glyphLayouts,
            viewport: layout.pageMetrics.viewportRect
        )

        state.visibleOverlapPairs = fluidVisibleOverlapPairCount(
            particles: state.particles,
            glyphLayouts: state.glyphLayouts
        )
        metalEngine.writeParticles(state.particles)

        return FluidFrameStepResult(
            appliedDeltaTime: appliedDeltaTime,
            clearedPointerForLargeGap: clearedPointerForLargeGap
        )
    }
    #endif
}
#endif

#if canImport(Metal) && !os(watchOS)
private struct FluidMetalPositionsUniforms {
    var values: SIMD4<Float>
}

private struct FluidMetalDensityUniforms {
    var params0: SIMD4<Float>
    var params1: SIMD4<Float>
    var params2: SIMD4<Float>
}

private struct FluidMetalVelocityUniforms {
    var params0: SIMD4<Float>
    var params1: SIMD4<Float>
    var pointerCenterAndStrength: SIMD4<Float>
    var pointerDirectionAndCount: SIMD4<Float>
}

private final class FluidMetalSimulationEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let positionsPipeline: MTLComputePipelineState
    private let densitiesPipeline: MTLComputePipelineState
    private let velocitiesPipeline: MTLComputePipelineState

    private var particleCount = 0
    private var restPositionsBuffer: MTLBuffer?
    private var currentPositionsBuffer: MTLBuffer?
    private var scratchPositionsBuffer: MTLBuffer?
    private var currentVelocitiesBuffer: MTLBuffer?
    private var scratchVelocitiesBuffer: MTLBuffer?
    private var currentDensitiesBuffer: MTLBuffer?
    private var scratchDensitiesBuffer: MTLBuffer?
    private var viscosityBuffer: MTLBuffer?
    private var pressureBuffer: MTLBuffer?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            return nil
        }

        do {
            let library = try device.makeLibrary(
                source: FluidMetalShaderSource.source,
                options: nil
            )
            guard let positionsFunction = library.makeFunction(name: "fluid_update_positions"),
                  let densitiesFunction = library.makeFunction(name: "fluid_update_densities"),
                  let velocitiesFunction = library.makeFunction(name: "fluid_update_velocities")
            else {
                return nil
            }

            self.device = device
            self.commandQueue = commandQueue
            positionsPipeline = try device.makeComputePipelineState(function: positionsFunction)
            densitiesPipeline = try device.makeComputePipelineState(function: densitiesFunction)
            velocitiesPipeline = try device.makeComputePipelineState(function: velocitiesFunction)
        } catch {
            return nil
        }
    }

    func reset(from layout: FluidLayoutSnapshot) {
        particleCount = layout.glyphs.count
        guard particleCount > 0 else {
            restPositionsBuffer = nil
            currentPositionsBuffer = nil
            scratchPositionsBuffer = nil
            currentVelocitiesBuffer = nil
            scratchVelocitiesBuffer = nil
            currentDensitiesBuffer = nil
            scratchDensitiesBuffer = nil
            viscosityBuffer = nil
            pressureBuffer = nil
            return
        }

        ensureBuffers()

        guard let restPositionsBuffer,
              let currentPositionsBuffer,
              let scratchPositionsBuffer,
              let currentVelocitiesBuffer,
              let scratchVelocitiesBuffer,
              let currentDensitiesBuffer,
              let scratchDensitiesBuffer,
              let viscosityBuffer,
              let pressureBuffer
        else {
            return
        }

        let restPositions = float2Pointer(from: restPositionsBuffer)
        let currentPositions = float2Pointer(from: currentPositionsBuffer)
        let scratchPositions = float2Pointer(from: scratchPositionsBuffer)
        let currentVelocities = float2Pointer(from: currentVelocitiesBuffer)
        let scratchVelocities = float2Pointer(from: scratchVelocitiesBuffer)
        let currentDensities = float2Pointer(from: currentDensitiesBuffer)
        let scratchDensities = float2Pointer(from: scratchDensitiesBuffer)
        let viscosity = float2Pointer(from: viscosityBuffer)
        let pressure = float2Pointer(from: pressureBuffer)

        for (index, glyph) in layout.glyphs.enumerated() {
            let position = SIMD2<Float>(
                Float(glyph.restCenter.x),
                Float(glyph.restCenter.y)
            )
            restPositions[index] = position
            currentPositions[index] = position
            scratchPositions[index] = position
            currentVelocities[index] = .zero
            scratchVelocities[index] = .zero
            currentDensities[index] = .zero
            scratchDensities[index] = .zero
            viscosity[index] = .zero
            pressure[index] = .zero
        }
    }

    func advanceFrame(
        dt: Double,
        substepCount: Int,
        layout: FluidLayoutSnapshot,
        pointer: FluidPointerInput?,
        state: inout FluidSimulationState
    ) {
        guard particleCount == layout.glyphs.count, particleCount > 0 else {
            return
        }
        let substep = Float(dt / Double(max(substepCount, 1)))
        var lastCommandBuffer: MTLCommandBuffer?

        for _ in 0..<substepCount {
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let currentPositionsBuffer,
                  let scratchPositionsBuffer,
                  let currentVelocitiesBuffer,
                  let scratchVelocitiesBuffer,
                  let currentDensitiesBuffer,
                  let scratchDensitiesBuffer,
                  let viscosityBuffer,
                  let pressureBuffer,
                  let restPositionsBuffer
            else {
                return
            }

            encodePositionsPass(
                into: commandBuffer,
                dt: substep,
                viewport: layout.pageMetrics.viewportRect,
                currentPositionsBuffer: currentPositionsBuffer,
                currentVelocitiesBuffer: currentVelocitiesBuffer,
                scratchPositionsBuffer: scratchPositionsBuffer
            )

            encodeDensitiesPass(
                into: commandBuffer,
                dt: substep,
                currentPositionsBuffer: scratchPositionsBuffer,
                currentVelocitiesBuffer: currentVelocitiesBuffer,
                currentDensitiesBuffer: currentDensitiesBuffer,
                scratchDensitiesBuffer: scratchDensitiesBuffer,
                viscosityBuffer: viscosityBuffer,
                pressureBuffer: pressureBuffer
            )

            encodeVelocitiesPass(
                into: commandBuffer,
                dt: substep,
                viewport: layout.pageMetrics.viewportRect,
                pointer: pointer,
                restPositionsBuffer: restPositionsBuffer,
                currentPositionsBuffer: scratchPositionsBuffer,
                currentVelocitiesBuffer: currentVelocitiesBuffer,
                viscosityBuffer: viscosityBuffer,
                pressureBuffer: pressureBuffer,
                scratchVelocitiesBuffer: scratchVelocitiesBuffer
            )

            commandBuffer.commit()
            lastCommandBuffer = commandBuffer

            swap(&self.currentPositionsBuffer, &self.scratchPositionsBuffer)
            swap(&self.currentVelocitiesBuffer, &self.scratchVelocitiesBuffer)
            swap(&self.currentDensitiesBuffer, &self.scratchDensitiesBuffer)
        }

        lastCommandBuffer?.waitUntilCompleted()

        readParticles(into: &state.particles)
    }

    func writeParticles(_ particles: [FluidParticleState]) {
        guard particles.count == particleCount,
              let currentPositionsBuffer,
              let currentVelocitiesBuffer
        else {
            return
        }

        let currentPositions = float2Pointer(from: currentPositionsBuffer)
        let currentVelocities = float2Pointer(from: currentVelocitiesBuffer)
        for (index, particle) in particles.enumerated() {
            currentPositions[index] = SIMD2<Float>(
                Float(particle.center.x),
                Float(particle.center.y)
            )
            currentVelocities[index] = SIMD2<Float>(
                Float(particle.velocity.x),
                Float(particle.velocity.y)
            )
        }
    }

    private func ensureBuffers() {
        let requiredLength = particleCount * MemoryLayout<SIMD2<Float>>.stride
        if restPositionsBuffer?.length == requiredLength {
            return
        }

        restPositionsBuffer = makeSharedBuffer(length: requiredLength)
        currentPositionsBuffer = makeSharedBuffer(length: requiredLength)
        scratchPositionsBuffer = makeSharedBuffer(length: requiredLength)
        currentVelocitiesBuffer = makeSharedBuffer(length: requiredLength)
        scratchVelocitiesBuffer = makeSharedBuffer(length: requiredLength)
        currentDensitiesBuffer = makeSharedBuffer(length: requiredLength)
        scratchDensitiesBuffer = makeSharedBuffer(length: requiredLength)
        viscosityBuffer = makeSharedBuffer(length: requiredLength)
        pressureBuffer = makeSharedBuffer(length: requiredLength)
    }

    private func makeSharedBuffer(length: Int) -> MTLBuffer? {
        device.makeBuffer(length: max(length, MemoryLayout<SIMD2<Float>>.stride), options: .storageModeShared)
    }

    private func float2Pointer(from buffer: MTLBuffer) -> UnsafeMutablePointer<SIMD2<Float>> {
        buffer.contents().bindMemory(
            to: SIMD2<Float>.self,
            capacity: max(particleCount, 1)
        )
    }

    private func readParticles(into particles: inout [FluidParticleState]) {
        guard particles.count == particleCount,
              let currentPositionsBuffer,
              let currentVelocitiesBuffer
        else {
            return
        }

        let currentPositions = float2Pointer(from: currentPositionsBuffer)
        let currentVelocities = float2Pointer(from: currentVelocitiesBuffer)
        for index in 0..<particleCount {
            particles[index].center = WrapPoint(
                x: Double(currentPositions[index].x),
                y: Double(currentPositions[index].y)
            )
            particles[index].velocity = SIMD2<Double>(
                Double(currentVelocities[index].x),
                Double(currentVelocities[index].y)
            )
        }
    }

    private func encodePositionsPass(
        into commandBuffer: MTLCommandBuffer,
        dt: Float,
        viewport: WrapRect,
        currentPositionsBuffer: MTLBuffer,
        currentVelocitiesBuffer: MTLBuffer,
        scratchPositionsBuffer: MTLBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        var uniforms = FluidMetalPositionsUniforms(
            values: SIMD4<Float>(
                dt,
                Float(viewport.width),
                Float(viewport.height),
                Float(particleCount)
            )
        )

        encoder.setComputePipelineState(positionsPipeline)
        encoder.setBuffer(currentPositionsBuffer, offset: 0, index: 0)
        encoder.setBuffer(currentVelocitiesBuffer, offset: 0, index: 1)
        encoder.setBuffer(scratchPositionsBuffer, offset: 0, index: 2)
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<FluidMetalPositionsUniforms>.stride,
            index: 3
        )
        dispatchAllParticles(encoder: encoder, pipeline: positionsPipeline)
        encoder.endEncoding()
    }

    private func encodeDensitiesPass(
        into commandBuffer: MTLCommandBuffer,
        dt: Float,
        currentPositionsBuffer: MTLBuffer,
        currentVelocitiesBuffer: MTLBuffer,
        currentDensitiesBuffer: MTLBuffer,
        scratchDensitiesBuffer: MTLBuffer,
        viscosityBuffer: MTLBuffer,
        pressureBuffer: MTLBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        var uniforms = FluidMetalDensityUniforms(
            params0: SIMD4<Float>(
                dt,
                Float(FluidSimulationConstants.range),
                Float(FluidSimulationConstants.poly6ScalingFactor),
                Float(FluidSimulationConstants.spikyPow2ScalingFactor)
            ),
            params1: SIMD4<Float>(
                Float(FluidSimulationConstants.spikyPow3ScalingFactor),
                Float(FluidSimulationConstants.spikyPow3DerivativeScalingFactor),
                Float(FluidSimulationConstants.spikyPow2DerivativeScalingFactor),
                Float(FluidSimulationConstants.densityTarget)
            ),
            params2: SIMD4<Float>(
                Float(FluidSimulationConstants.pressureMultiplier),
                Float(FluidSimulationConstants.nearPressureMultiplier),
                Float(particleCount),
                0
            )
        )

        encoder.setComputePipelineState(densitiesPipeline)
        encoder.setBuffer(currentPositionsBuffer, offset: 0, index: 0)
        encoder.setBuffer(currentVelocitiesBuffer, offset: 0, index: 1)
        encoder.setBuffer(currentDensitiesBuffer, offset: 0, index: 2)
        encoder.setBuffer(scratchDensitiesBuffer, offset: 0, index: 3)
        encoder.setBuffer(viscosityBuffer, offset: 0, index: 4)
        encoder.setBuffer(pressureBuffer, offset: 0, index: 5)
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<FluidMetalDensityUniforms>.stride,
            index: 6
        )
        dispatchAllParticles(encoder: encoder, pipeline: densitiesPipeline)
        encoder.endEncoding()
    }

    private func encodeVelocitiesPass(
        into commandBuffer: MTLCommandBuffer,
        dt: Float,
        viewport: WrapRect,
        pointer: FluidPointerInput?,
        restPositionsBuffer: MTLBuffer,
        currentPositionsBuffer: MTLBuffer,
        currentVelocitiesBuffer: MTLBuffer,
        viscosityBuffer: MTLBuffer,
        pressureBuffer: MTLBuffer,
        scratchVelocitiesBuffer: MTLBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        let pointerCenter = pointer.map {
            fluidViewportPointToPointerSpace($0.center, viewport: viewport)
        } ?? .zero
        let pointerDirection = pointer?.direction ?? .zero
        let pointerActivity = min(Float(pointer?.strength ?? 0) * 100, 1.0)
        let effectiveDamping = Float(FluidSimulationConstants.idleDampingFactor) +
            (Float(FluidSimulationConstants.dampingFactor) - Float(FluidSimulationConstants.idleDampingFactor)) * pointerActivity
        var uniforms = FluidMetalVelocityUniforms(
            params0: SIMD4<Float>(
                dt,
                effectiveDamping,
                Float(FluidSimulationConstants.viscosityFactor),
                Float(FluidSimulationConstants.originalPositionFactor)
            ),
            params1: SIMD4<Float>(
                Float(FluidSimulationConstants.forceToCenterFactor),
                Float(viewport.width),
                Float(viewport.height),
                Float(FluidSimulationConstants.maxVelocity)
            ),
            pointerCenterAndStrength: SIMD4<Float>(
                Float(pointerCenter.x),
                Float(pointerCenter.y),
                Float(pointer?.strength ?? 0),
                0
            ),
            pointerDirectionAndCount: SIMD4<Float>(
                Float(pointerDirection.x),
                Float(pointerDirection.y),
                Float(particleCount),
                0
            )
        )

        encoder.setComputePipelineState(velocitiesPipeline)
        encoder.setBuffer(currentPositionsBuffer, offset: 0, index: 0)
        encoder.setBuffer(restPositionsBuffer, offset: 0, index: 1)
        encoder.setBuffer(currentVelocitiesBuffer, offset: 0, index: 2)
        encoder.setBuffer(viscosityBuffer, offset: 0, index: 3)
        encoder.setBuffer(pressureBuffer, offset: 0, index: 4)
        encoder.setBuffer(scratchVelocitiesBuffer, offset: 0, index: 5)
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<FluidMetalVelocityUniforms>.stride,
            index: 6
        )
        dispatchAllParticles(encoder: encoder, pipeline: velocitiesPipeline)
        encoder.endEncoding()
    }

    private func dispatchAllParticles(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState
    ) {
        let threadWidth = max(1, min(pipeline.threadExecutionWidth, particleCount))
        let threadsPerThreadgroup = MTLSize(width: threadWidth, height: 1, depth: 1)
        let threadgroups = MTLSize(
            width: (particleCount + threadWidth - 1) / threadWidth,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreadgroups(
            threadgroups,
            threadsPerThreadgroup: threadsPerThreadgroup
        )
    }
}

private enum FluidMetalShaderSource {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct PositionsUniforms {
        float4 values;
    };

    struct DensityUniforms {
        float4 params0;
        float4 params1;
        float4 params2;
    };

    struct VelocityUniforms {
        float4 params0;
        float4 params1;
        float4 pointerCenterAndStrength;
        float4 pointerDirectionAndCount;
    };

    inline float viscosity_kernel(float radius, float dist, float scale) {
        if (dist < radius) {
            float v = radius * radius - dist * dist;
            return v * v * v * scale;
        }
        return 0.0;
    }

    inline float density_kernel(float radius, float dist, float scale) {
        if (dist < radius) {
            float v = radius - dist;
            return v * v * scale;
        }
        return 0.0;
    }

    inline float near_density_kernel(float radius, float dist, float scale) {
        if (dist < radius) {
            float v = radius - dist;
            return v * v * v * scale;
        }
        return 0.0;
    }

    inline float derivative_spiky_pow2(float radius, float dist, float scale) {
        if (dist <= radius) {
            float v = radius - dist;
            return -v * scale;
        }
        return 0.0;
    }

    inline float derivative_spiky_pow3(float radius, float dist, float scale) {
        if (dist <= radius) {
            float v = radius - dist;
            return -v * v * scale;
        }
        return 0.0;
    }

    inline float convert_density_to_pressure(float density, float targetDensity, float multiplier) {
        return multiplier * (density - targetDensity);
    }

    inline float convert_near_density_to_pressure(float nearDensity, float multiplier) {
        return multiplier * nearDensity;
    }

    inline float2 limit_vector(float2 value, float maxValue) {
        float squaredLength = dot(value, value);
        if (squaredLength > maxValue * maxValue) {
            return normalize(value) * maxValue;
        }
        return value;
    }

    kernel void fluid_update_positions(
        const device float2 *positions [[buffer(0)]],
        const device float2 *velocities [[buffer(1)]],
        device float2 *nextPositions [[buffer(2)]],
        constant PositionsUniforms &uniforms [[buffer(3)]],
        uint id [[thread_position_in_grid]]
    ) {
        uint count = uint(uniforms.values.w);
        if (id >= count) {
            return;
        }

        float dt = uniforms.values.x;
        float width = uniforms.values.y;
        float height = uniforms.values.z;
        float m = \(fluidBoundaryMargin);
        float mt = \(fluidBoundaryMarginTop);
        float2 next = positions[id] + velocities[id] * dt;
        next.x = clamp(next.x, m, width - m);
        next.y = clamp(next.y, mt, height - m);
        nextPositions[id] = next;
    }

    kernel void fluid_update_densities(
        const device float2 *positions [[buffer(0)]],
        const device float2 *velocities [[buffer(1)]],
        const device float2 *densitiesIn [[buffer(2)]],
        device float2 *densitiesOut [[buffer(3)]],
        device float2 *viscosityOut [[buffer(4)]],
        device float2 *pressureOut [[buffer(5)]],
        constant DensityUniforms &uniforms [[buffer(6)]],
        uint id [[thread_position_in_grid]]
    ) {
        uint count = uint(uniforms.params2.z);
        if (id >= count) {
            return;
        }

        float dt = uniforms.params0.x;
        float range = uniforms.params0.y;
        float poly6Scale = uniforms.params0.z;
        float spikyPow2Scale = uniforms.params0.w;
        float spikyPow3Scale = uniforms.params1.x;
        float spikyPow3DerivativeScale = uniforms.params1.y;
        float spikyPow2DerivativeScale = uniforms.params1.z;
        float targetDensity = uniforms.params1.w;
        float pressureMultiplier = uniforms.params2.x;
        float nearPressureMultiplier = uniforms.params2.y;

        float2 mePosition = positions[id];
        float2 meVelocity = velocities[id];
        float2 meDensity = densitiesIn[id];
        float2 p = mePosition + meVelocity * dt;

        float density = 0.0;
        float nearDensity = 0.0;
        float2 viscosityForce = float2(0.0);
        float2 pressureForce = float2(0.0);

        float pressure = convert_density_to_pressure(meDensity.x, targetDensity, pressureMultiplier);
        float nearPressure = convert_near_density_to_pressure(meDensity.y, nearPressureMultiplier);

        for (uint otherIndex = 0; otherIndex < count; ++otherIndex) {
            if (otherIndex == id) {
                continue;
            }

            float2 otherPosition = positions[otherIndex];
            float2 otherVelocity = velocities[otherIndex];
            float2 otherDensity = densitiesIn[otherIndex];
            float2 otherProjected = otherPosition + otherVelocity * dt;
            float dist = distance(otherProjected, p);
            if (dist >= range) {
                continue;
            }

            density += density_kernel(range, dist, spikyPow2Scale);
            nearDensity += near_density_kernel(range, dist, spikyPow3Scale);
            viscosityForce += (otherVelocity - meVelocity) * viscosity_kernel(range, dist, poly6Scale);

            if (dist > 0.0001) {
                float2 dir = normalize(otherProjected - p);
                float neighbourDensity = max(otherDensity.x, 1e-6);
                float neighbourNearDensity = max(otherDensity.y, 1e-6);
                float neighbourPressure = convert_density_to_pressure(neighbourDensity, targetDensity, pressureMultiplier);
                float neighbourNearPressure = convert_near_density_to_pressure(neighbourNearDensity, nearPressureMultiplier);
                float sharedPressure = (pressure + neighbourPressure) * 0.5;
                float sharedNearPressure = (nearPressure + neighbourNearPressure) * 0.5;

                pressureForce += dir * derivative_spiky_pow2(range, dist, spikyPow2DerivativeScale) * sharedPressure / neighbourDensity;
                pressureForce += dir * derivative_spiky_pow3(range, dist, spikyPow3DerivativeScale) * sharedNearPressure / neighbourNearDensity;
            }
        }

        densitiesOut[id] = float2(max(0.0, density) + 1e-6, nearDensity + 1e-6);
        viscosityOut[id] = viscosityForce;
        pressureOut[id] = pressureForce;
    }

    kernel void fluid_update_velocities(
        const device float2 *positions [[buffer(0)]],
        const device float2 *restPositions [[buffer(1)]],
        const device float2 *velocities [[buffer(2)]],
        const device float2 *viscosity [[buffer(3)]],
        const device float2 *pressure [[buffer(4)]],
        device float2 *velocityOut [[buffer(5)]],
        constant VelocityUniforms &uniforms [[buffer(6)]],
        uint id [[thread_position_in_grid]]
    ) {
        uint count = uint(uniforms.pointerDirectionAndCount.z);
        if (id >= count) {
            return;
        }

        float dt = uniforms.params0.x;
        float dampingFactor = uniforms.params0.y;
        float viscosityFactor = uniforms.params0.z;
        float toOriginalPositionFactor = uniforms.params0.w;
        float forceToCenterFactor = uniforms.params1.x;
        float width = uniforms.params1.y;
        float height = uniforms.params1.z;
        float maxVelocity = uniforms.params1.w;
        float2 mousePointerSpace = uniforms.pointerCenterAndStrength.xy;
        float mouseStrengthInput = uniforms.pointerCenterAndStrength.z;
        float2 mouseDirection = uniforms.pointerDirectionAndCount.xy;

        float2 position = positions[id];
        float2 velocity = velocities[id] * dampingFactor;
        float2 pressureAcceleration = pressure[id];
        float2 originDirection = mix(
            (restPositions[id] - position) * 20.0,
            float2(0.0),
            1.0 - toOriginalPositionFactor
        );

        float2 particleNDC = float2(
            (position.x / width - 0.5) * 2.0,
            (0.5 - position.y / height) * 2.0
        );
        float2 mouseNDC = mousePointerSpace;
        mouseNDC.y *= -1.0;
        float distanceToMouse = distance(mouseNDC, particleNDC);

        if (distanceToMouse < mouseStrengthInput * \(FluidSimulationConstants.pointerForceThreshold) && mouseStrengthInput > \(FluidSimulationConstants.pointerActivationThreshold)) {
            float mouseStrength = clamp(mouseStrengthInput * \(FluidSimulationConstants.pointerForceRamp), \(FluidSimulationConstants.pointerForceMinimum), \(FluidSimulationConstants.pointerForceMaximum));
            float2 direction = -mouseDirection;
            velocity += direction * mouseStrength * \(FluidSimulationConstants.pointerForceScale) * max(mouseStrength * 0.5 - distanceToMouse, 0.0);
        }

        float2 viewportCenter = float2(width * 0.5, height * 0.5);
        float2 toCenter = viewportCenter - position;
        float distToCenter = length(toCenter);
        float2 centerForce = (distToCenter > 1.0)
            ? normalize(toCenter) * forceToCenterFactor
            : float2(0.0);

        velocity += pressureAcceleration * dt;
        velocity += viscosity[id] * viscosityFactor * dt;
        velocity += centerForce * dt;
        velocity += originDirection * dt;

        float margin = \(fluidBoundaryMargin);
        float marginTop = \(fluidBoundaryMarginTop);
        float2 futurePosition = position + velocity * dt;
        if (futurePosition.x < margin || futurePosition.x > width - margin) {
            velocity.x *= -0.5;
        }
        if (futurePosition.y < marginTop || futurePosition.y > height - margin) {
            velocity.y *= -0.5;
        }

        velocityOut[id] = limit_vector(velocity, maxVelocity);
    }
    """
}
#endif
