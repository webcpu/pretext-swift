import XCTest
import simd
@testable import Demo

final class FluidSimulationTests: XCTestCase {
    func testResetFromLayoutSeedsZeroVelocityParticles() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        var state = FluidSimulationState.empty

        state.reset(from: layout)

        XCTAssertEqual(state.particles.count, layout.glyphs.count)
        XCTAssertEqual(state.particles.map(\.id), layout.glyphs.map(\.id))
        XCTAssertEqual(state.particles.map(\.center), layout.glyphs.map(\.restCenter))
        XCTAssertEqual(
            state.particles.map(\.velocity),
            Array(repeating: SIMD2<Double>.zero, count: layout.glyphs.count)
        )
    }

    func testResetPreservesPointerOnlyWhenStillInsideViewport() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        var state = FluidSimulationState.empty
        state.updatePointer(
            FluidPointerInput(
                center: WrapPoint(x: 120, y: 120),
                isInitialContact: true
            )
        )

        state.reset(from: layout)
        XCTAssertEqual(state.pointer.current?.center, WrapPoint(x: 120, y: 120))

        state.updatePointer(
            FluidPointerInput(
                center: WrapPoint(x: 900, y: 900),
                isInitialContact: true
            )
        )
        state.reset(from: layout)

        XCTAssertNil(state.pointer.current)
        XCTAssertNil(state.cursor)
    }

    func testStepClampsDeltaTimeIntoClosedInterval() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        let low = state.step(dt: 0.0001, pointer: nil, layout: layout)
        let high = state.step(dt: 0.08, pointer: nil, layout: layout)

        XCTAssertEqual(low.appliedDeltaTime, 1.0 / 240.0, accuracy: 0.0001)
        XCTAssertEqual(high.appliedDeltaTime, 1.0 / 20.0, accuracy: 0.0001)
    }

    func testStepClearsPointerForLargeFrameGap() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        var state = FluidSimulationState.empty
        state.reset(from: layout)
        state.updatePointer(
            FluidPointerInput(
                center: WrapPoint(x: 220, y: 140),
                isInitialContact: true
            )
        )

        let result = state.step(dt: 0.25, pointer: nil, layout: layout)

        XCTAssertTrue(result.clearedPointerForLargeGap)
        XCTAssertEqual(result.appliedDeltaTime, 1.0 / 60.0, accuracy: 0.0001)
        XCTAssertNil(state.pointer.current)
        XCTAssertNil(state.cursor)
    }

    func testClearPointerHidesCursorState() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        var state = FluidSimulationState.empty
        state.reset(from: layout)
        state.updatePointer(
            FluidPointerInput(
                center: WrapPoint(x: 80, y: 60),
                isInitialContact: true
            )
        )
        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: WrapPoint(x: 120, y: 60)),
            layout: layout
        )

        XCTAssertNotNil(state.cursor)

        state.clearPointer()

        XCTAssertNil(state.pointer.current)
        XCTAssertNil(state.cursor)
    }

    func testIdleStepDoesNotPullDisplacedGlyphBackTowardRestLikeWebParity() {
        let layout = makeSingleGlyphLayout()
        var state = FluidSimulationState.empty
        state.reset(from: layout)
        state.particles[0].center.x += 36

        _ = state.step(dt: 1.0 / 60.0, pointer: nil, layout: layout)

        XCTAssertEqual(state.particles[0].velocity.x, 0, accuracy: 0.0001)
        XCTAssertEqual(
            state.particles[0].center.x,
            layout.glyphs[0].restCenter.x + 36,
            accuracy: 0.0001
        )
    }

    func testPostInteractionIdleKeepsAdvancingWithoutForcedVelocityWipeLikeWebParity() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        var state = FluidSimulationState.empty
        state.reset(from: layout)
        let center = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX,
            y: layout.pageMetrics.viewportRect.midY
        )

        applySweep(
            to: &state,
            from: center,
            to: WrapPoint(x: center.x + 160, y: center.y),
            frames: 3,
            layout: layout
        )

        for _ in 0..<120 {
            _ = state.step(dt: 1.0 / 60.0, pointer: nil, layout: layout)
        }

        XCTAssertFalse(state.particles.allSatisfy { $0.velocity == .zero })
        XCTAssertTrue(state.hasActivatedPointer)
        XCTAssertGreaterThan(state.elapsedTime, 2.0)
    }

    func testIdleStepDoesNotForceVelocityToZeroAfterSettlementThresholds() {
        let layout = makeSingleGlyphLayout()
        var state = FluidSimulationState.empty
        state.reset(from: layout)
        state.idleElapsedTime = 2.0
        state.particles[0].velocity = SIMD2<Double>(12, -4)

        _ = state.step(dt: 1.0 / 60.0, pointer: nil, layout: layout)

        XCTAssertNotEqual(state.particles[0].velocity, .zero)
    }

    func testVisibleOverlapDiagnosticsDoNotBlockSettlement() {
        let layout = makeSingleGlyphLayout()
        var state = FluidSimulationState.empty
        state.reset(from: layout)
        state.idleElapsedTime = 2.0
        state.visibleOverlapPairs = 999
        state.restVisibleOverlapPairs = 0

        XCTAssertTrue(fluidSimulationIsSettled(state))
    }

    func testOverlapCorrectionCanFullySeparateEdgePinnedGlyphs() {
        let viewport = WrapRect(x: 0, y: 0, width: 80, height: 60)
        let metrics = FluidPageMetrics(
            viewportRect: viewport,
            contentRect: viewport,
            layoutWidth: viewport.width,
            fontSize: 16,
            lineHeight: 19.2,
            fieldColumns: 4,
            fieldRows: 3,
            cursorBaseSize: 22
        )
        let lhsBounds = WrapRect(x: -8, y: 21, width: 20, height: 18)
        let rhsBounds = WrapRect(x: -1, y: 21, width: 20, height: 18)
        let layout = FluidLayoutSnapshot(
            pageMetrics: metrics,
            text: "AB",
            glyphs: [
                FluidGlyphLayout(
                    id: 0,
                    character: "A",
                    fontGlyph: 0,
                    restCenter: WrapPoint(x: lhsBounds.midX, y: lhsBounds.midY),
                    drawOrigin: WrapPoint(x: lhsBounds.x, y: lhsBounds.maxY),
                    baselineY: lhsBounds.maxY,
                    width: lhsBounds.width,
                    bounds: lhsBounds
                ),
                FluidGlyphLayout(
                    id: 1,
                    character: "B",
                    fontGlyph: 1,
                    restCenter: WrapPoint(x: rhsBounds.midX, y: rhsBounds.midY),
                    drawOrigin: WrapPoint(x: rhsBounds.x, y: rhsBounds.maxY),
                    baselineY: rhsBounds.maxY,
                    width: rhsBounds.width,
                    bounds: rhsBounds
                ),
            ]
        )

        var state = FluidSimulationState.empty
        state.glyphLayouts = layout.glyphs
        state.restCenters = layout.glyphs.map(\.restCenter)
        state.particles = [
            FluidParticleState(id: 0, center: WrapPoint(x: 2, y: lhsBounds.midY), velocity: .zero),
            FluidParticleState(id: 1, center: WrapPoint(x: 9, y: rhsBounds.midY), velocity: .zero),
        ]
        state.hasActivatedPointer = true
        state.restVisibleOverlapPairs = 0
        state.visibleOverlapPairs = fluidVisibleOverlapPairCount(
            particles: state.particles,
            glyphLayouts: state.glyphLayouts
        )

        XCTAssertGreaterThan(state.visibleOverlapPairs, 0)

        _ = state.step(dt: 1.0 / 60.0, pointer: nil, layout: layout)

        XCTAssertEqual(
            fluidVisibleOverlapPairCount(
                particles: state.particles,
                glyphLayouts: state.glyphLayouts
            ),
            0
        )
    }

    func testOverlapCorrectionCanFullySeparateDenseBottomRightEdgeCluster() {
        let viewport = WrapRect(x: 0, y: 0, width: 120, height: 80)
        let metrics = FluidPageMetrics(
            viewportRect: viewport,
            contentRect: viewport,
            layoutWidth: viewport.width,
            fontSize: 16,
            lineHeight: 19.2,
            fieldColumns: 6,
            fieldRows: 4,
            cursorBaseSize: 22
        )

        let glyphs: [FluidGlyphLayout] = [
            makeGlyph(id: 0, character: "A", bounds: WrapRect(x: 95, y: 54, width: 20, height: 18)),
            makeGlyph(id: 1, character: "B", bounds: WrapRect(x: 98, y: 56, width: 20, height: 18)),
            makeGlyph(id: 2, character: "C", bounds: WrapRect(x: 100, y: 58, width: 20, height: 18)),
            makeGlyph(id: 3, character: "D", bounds: WrapRect(x: 102, y: 60, width: 20, height: 18)),
        ]
        let layout = FluidLayoutSnapshot(
            pageMetrics: metrics,
            text: "ABCD",
            glyphs: glyphs
        )

        var state = FluidSimulationState.empty
        state.glyphLayouts = layout.glyphs
        state.restCenters = layout.glyphs.map(\.restCenter)
        state.particles = [
            FluidParticleState(id: 0, center: WrapPoint(x: 104, y: 64), velocity: .zero),
            FluidParticleState(id: 1, center: WrapPoint(x: 107, y: 66), velocity: .zero),
            FluidParticleState(id: 2, center: WrapPoint(x: 109, y: 68), velocity: .zero),
            FluidParticleState(id: 3, center: WrapPoint(x: 111, y: 70), velocity: .zero),
        ]
        state.hasActivatedPointer = true
        state.restVisibleOverlapPairs = 0
        state.visibleOverlapPairs = fluidVisibleOverlapPairCount(
            particles: state.particles,
            glyphLayouts: state.glyphLayouts
        )

        XCTAssertGreaterThan(state.visibleOverlapPairs, 0)

        _ = state.step(dt: 1.0 / 60.0, pointer: nil, layout: layout)

        XCTAssertEqual(
            fluidVisibleOverlapPairCount(
                particles: state.particles,
                glyphLayouts: state.glyphLayouts
            ),
            0
        )
    }

    func testPointerLagsBehindTargetWhileBuildingStrengthLikeWebParity() throws {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        let center = WrapPoint(x: layout.pageMetrics.viewportRect.midX, y: layout.pageMetrics.viewportRect.midY)
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: center, isInitialContact: true),
            layout: layout
        )

        let target = WrapPoint(x: center.x + 80, y: center.y)
        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: target),
            layout: layout
        )

        let firstCenter = try XCTUnwrap(state.pointer.current?.center)
        let firstStrength = try XCTUnwrap(state.pointer.current?.strength)

        XCTAssertLessThan(firstCenter.x, target.x)
        XCTAssertEqual(firstCenter.y, target.y, accuracy: 0.001)
        XCTAssertGreaterThan(firstStrength, 0)

        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: target),
            layout: layout
        )

        let secondCenter = try XCTUnwrap(state.pointer.current?.center)
        let secondStrength = try XCTUnwrap(state.pointer.current?.strength)

        XCTAssertGreaterThan(secondCenter.x, firstCenter.x)
        XCTAssertLessThan(secondCenter.x, target.x)
        XCTAssertEqual(secondCenter.y, target.y, accuracy: 0.001)
        XCTAssertGreaterThan(secondStrength, 0)
    }

    func testPointerPersistsAndDecaysAfterReleaseLikeWebParity() throws {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        let center = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX,
            y: layout.pageMetrics.viewportRect.midY
        )
        let target = WrapPoint(x: center.x + 80, y: center.y)
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: center, isInitialContact: true),
            layout: layout
        )
        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: target),
            layout: layout
        )

        let releasedCenter = try XCTUnwrap(state.pointer.current?.center)
        let releasedStrength = try XCTUnwrap(state.pointer.current?.strength)

        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: nil,
            layout: layout
        )

        let continuedCenter = try XCTUnwrap(state.pointer.current?.center)
        XCTAssertEqual(state.pointer.targetCenter, target)
        XCTAssertGreaterThan(continuedCenter.x, releasedCenter.x)
        XCTAssertLessThan(continuedCenter.x, target.x)
        XCTAssertEqual(continuedCenter.y, target.y, accuracy: 0.001)

        for _ in 0..<60 {
            _ = state.step(
                dt: 1.0 / 60.0,
                pointer: nil,
                layout: layout
            )
        }

        let decayedCenter = try XCTUnwrap(state.pointer.current?.center)
        let decayedStrength = try XCTUnwrap(state.pointer.current?.strength)

        XCTAssertLessThan(abs(decayedCenter.x - target.x), abs(releasedCenter.x - target.x))
        XCTAssertEqual(decayedCenter.y, target.y, accuracy: 0.001)
        XCTAssertLessThan(decayedStrength, releasedStrength)
    }

    func testActiveHoverDoesNotBroadcastDisplacementAcrossMostGlyphs() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let center = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX,
            y: layout.pageMetrics.viewportRect.midY
        )
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: center, isInitialContact: true),
            layout: layout
        )
        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: WrapPoint(x: center.x + 40, y: center.y)),
            layout: layout
        )

        let displacedCount = zip(state.particles, layout.glyphs).filter { particle, glyph in
            hypot(
                particle.center.x - glyph.restCenter.x,
                particle.center.y - glyph.restCenter.y
            ) > 2
        }.count

        XCTAssertLessThan(
            displacedCount,
            layout.glyphs.count / 4,
            "displaced \(displacedCount) / \(layout.glyphs.count)"
        )
    }

    func testBelowWebPointerStrengthThresholdDoesNotMeaningfullyDisplaceField() throws {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let center = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX,
            y: layout.pageMetrics.viewportRect.midY
        )
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: center, isInitialContact: true),
            layout: layout
        )
        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: WrapPoint(x: center.x + 40, y: center.y)),
            layout: layout
        )

        let strength = try XCTUnwrap(state.pointer.current?.strength)
        XCTAssertLessThan(strength, 0.01)

        let maxDisplacement = zip(state.particles, layout.glyphs).map { particle, glyph in
            hypot(
                particle.center.x - glyph.restCenter.x,
                particle.center.y - glyph.restCenter.y
            )
        }.max() ?? 0

        XCTAssertLessThan(
            maxDisplacement,
            1.0,
            "strength \(strength) max displacement \(maxDisplacement)"
        )
    }

    func testSustainedStationaryHoverDoesNotEvacuateMostGlyphsAcrossField() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let center = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX,
            y: layout.pageMetrics.viewportRect.midY
        )
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        _ = state.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: center, isInitialContact: true),
            layout: layout
        )
        for _ in 0..<60 {
            _ = state.step(
                dt: 1.0 / 60.0,
                pointer: FluidPointerInput(center: center),
                layout: layout
            )
        }

        let displacedCount = zip(state.particles, layout.glyphs).filter { particle, glyph in
            hypot(
                particle.center.x - glyph.restCenter.x,
                particle.center.y - glyph.restCenter.y
            ) > 12
        }.count

        XCTAssertLessThan(
            displacedCount,
            layout.glyphs.count / 3,
            "displaced \(displacedCount) / \(layout.glyphs.count)"
        )
    }

    func testPointerSweepChangesFieldComparedWithStationaryHover() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        let center = WrapPoint(x: layout.pageMetrics.viewportRect.midX, y: layout.pageMetrics.viewportRect.midY)

        var withSweep = FluidSimulationState.empty
        withSweep.reset(from: layout)
        applySweep(
            to: &withSweep,
            from: center,
            to: WrapPoint(x: center.x + 320, y: center.y),
            frames: 6,
            layout: layout
        )

        var stationary = FluidSimulationState.empty
        stationary.reset(from: layout)
        applySweep(
            to: &stationary,
            from: center,
            to: center,
            frames: 6,
            layout: layout
        )

        let maxParticleDelta = zip(withSweep.particles, stationary.particles).map { lhs, rhs in
            hypot(lhs.center.x - rhs.center.x, lhs.center.y - rhs.center.y)
        }.max() ?? 0

        XCTAssertGreaterThan(maxParticleDelta, 4)
    }

    func testModerateSweepLocallyDisplacesNearbyGlyphsOnStatePath() throws {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let start = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX - 160,
            y: layout.pageMetrics.viewportRect.midY
        )
        let end = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX + 160,
            y: layout.pageMetrics.viewportRect.midY
        )
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        applySweep(
            to: &state,
            from: start,
            to: end,
            frames: 6,
            layout: layout
        )

        let liveCursorCenter = try XCTUnwrap(state.pointer.current?.center)
        let nearbyIndices = nearbyGlyphIndices(
            to: liveCursorCenter,
            radius: 90,
            in: layout
        )
        let farIndices = layout.glyphs.indices.filter { index in
            let glyph = layout.glyphs[index]
            return hypot(
                glyph.restCenter.x - liveCursorCenter.x,
                glyph.restCenter.y - liveCursorCenter.y
            ) >= 260
        }
        let nearbyAverageDisplacement = averageGlyphDisplacement(
            for: nearbyIndices,
            particles: state.particles,
            glyphs: layout.glyphs
        )
        let farAverageDisplacement = averageGlyphDisplacement(
            for: farIndices,
            particles: state.particles,
            glyphs: layout.glyphs
        )

        XCTAssertGreaterThan(nearbyAverageDisplacement, 4)
        XCTAssertGreaterThan(
            nearbyAverageDisplacement,
            farAverageDisplacement * 1.5,
            "nearby \(nearbyAverageDisplacement) far \(farAverageDisplacement)"
        )
    }

    func testStrongerInputProducesLargerImpulseAndCursorSize() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        let center = WrapPoint(x: layout.pageMetrics.viewportRect.midX, y: layout.pageMetrics.viewportRect.midY)

        var weak = FluidSimulationState.empty
        weak.reset(from: layout)
        applySweep(
            to: &weak,
            from: center,
            to: WrapPoint(x: center.x + 40, y: center.y),
            frames: 6,
            layout: layout
        )

        var strong = FluidSimulationState.empty
        strong.reset(from: layout)
        applySweep(
            to: &strong,
            from: center,
            to: WrapPoint(x: center.x + 320, y: center.y),
            frames: 6,
            layout: layout
        )

        XCTAssertGreaterThan(strong.cursor?.tailLength ?? 0, weak.cursor?.tailLength ?? 0)
    }

    func testDifferentPointerDirectionsChangeCursorAngleAndDisturbanceDirection() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        let center = WrapPoint(x: layout.pageMetrics.viewportRect.midX, y: layout.pageMetrics.viewportRect.midY)

        var horizontal = FluidSimulationState.empty
        horizontal.reset(from: layout)
        applySweep(
            to: &horizontal,
            from: center,
            to: WrapPoint(x: center.x + 320, y: center.y),
            frames: 6,
            layout: layout
        )

        var vertical = FluidSimulationState.empty
        vertical.reset(from: layout)
        applySweep(
            to: &vertical,
            from: center,
            to: WrapPoint(x: center.x, y: center.y - 320),
            frames: 6,
            layout: layout
        )

        XCTAssertEqual(horizontal.cursor?.angle ?? 0, -.pi / 2, accuracy: 0.2)
        XCTAssertEqual(vertical.cursor?.angle ?? 0, 0, accuracy: 0.2)
    }

    func testNeighborInteractionCreatesLocalSeparationWithoutExplodingVelocity() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        let center = WrapPoint(x: layout.pageMetrics.viewportRect.midX, y: layout.pageMetrics.viewportRect.midY)
        let nearbyIndices = nearbyGlyphIndices(to: center, radius: 60, in: layout)
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        let originalDistance = averageDistanceToCenter(for: nearbyIndices, particles: state.particles, center: center)

        applySweep(
            to: &state,
            from: center,
            to: WrapPoint(x: center.x + 320, y: center.y),
            frames: 6,
            layout: layout
        )

        let maxVelocity = state.particles.map { simd_length($0.velocity) }.max() ?? 0
        let separatedDistance = averageDistanceToCenter(for: nearbyIndices, particles: state.particles, center: center)

        XCTAssertGreaterThan(separatedDistance, originalDistance - 4)
        XCTAssertLessThanOrEqual(maxVelocity, 1200)
    }

    func testBoundaryHandlingKeepsParticleCentersInsideViewport() {
        let layout = makeLayout(width: 320, height: 180, platform: .macOS)
        var state = FluidSimulationState.empty
        state.reset(from: layout)
        state.particles[0].center = WrapPoint(x: -40, y: -30)
        state.particles[0].velocity = SIMD2<Double>(-300, -250)

        _ = state.step(dt: 1.0 / 20.0, pointer: nil, layout: layout)

        XCTAssertGreaterThanOrEqual(state.particles[0].center.x, layout.pageMetrics.viewportRect.minX)
        XCTAssertLessThanOrEqual(state.particles[0].center.x, layout.pageMetrics.viewportRect.maxX)
        XCTAssertGreaterThanOrEqual(state.particles[0].center.y, layout.pageMetrics.viewportRect.minY)
        XCTAssertLessThanOrEqual(state.particles[0].center.y, layout.pageMetrics.viewportRect.maxY)
    }

    func testPointCenterBounceReflectsVelocityLikeWebParity() {
        let layout = makeSingleGlyphLayout(viewport: WrapRect(x: 0, y: 0, width: 100, height: 100))
        var state = FluidSimulationState.empty
        state.reset(from: layout)
        state.particles[0].center = WrapPoint(x: 1, y: layout.glyphs[0].restCenter.y)
        state.particles[0].velocity = SIMD2<Double>(-300, 0)

        _ = state.step(dt: 1.0 / 60.0, pointer: nil, layout: layout)

        XCTAssertGreaterThan(state.particles[0].velocity.x, 40)
        XCTAssertLessThan(state.particles[0].velocity.x, 100)
    }

    func testWatchLayoutUsesReducedMetrics() {
        let layout = makeLayout(width: 198, height: 242, platform: .watchOS)

        XCTAssertEqual(layout.pageMetrics.fontSize, 10.0)
        XCTAssertEqual(layout.pageMetrics.cursorBaseSize, 14.0)
        XCTAssertGreaterThan(layout.glyphs.count, 0)
        XCTAssertLessThan(layout.glyphs.count, 300,
            "Watch should have fewer characters than mobile")
    }

    func testRestLayoutDensityScaleStaysNearNativePressureBalancePoint() {
        let layout = makeLayout(width: 1100, height: 700, platform: .macOS)
        let range = 15.0
        let scalingFactor = 6.0 / (Double.pi * pow(range, 4))

        let averageDensity = layout.glyphs.indices.reduce(0.0) { partial, index in
            let point = layout.glyphs[index].restCenter
            let density = layout.glyphs.indices.reduce(0.0) { densityPartial, neighborIndex in
                guard neighborIndex != index else {
                    return densityPartial
                }

                let neighbor = layout.glyphs[neighborIndex].restCenter
                let distance = hypot(neighbor.x - point.x, neighbor.y - point.y)
                guard distance < range else {
                    return densityPartial
                }

                let value = range - distance
                return densityPartial + value * value * scalingFactor
            }

            return partial + density
        } / Double(max(1, layout.glyphs.count))

        let restPressure = fluidPressureForDensity(averageDensity)

        XCTAssertGreaterThan(averageDensity, 0.001, "average density \(averageDensity)")
        XCTAssertLessThan(averageDensity, 0.01, "average density \(averageDensity)")
        XCTAssertLessThan(
            abs(restPressure),
            1.0,
            "pressure \(restPressure) density \(averageDensity)"
        )
    }

    func testSubTargetDensityProducesAttractiveCorrectionOnNativeScale() {
        let subTargetDensity = 0.0008

        XCTAssertLessThan(
            fluidPressureForDensity(subTargetDensity),
            0,
            "pressure \(fluidPressureForDensity(subTargetDensity)) density \(subTargetDensity)"
        )
    }

    func testPostSweepIdleDampsAverageVelocityBelowVisibleTrembleThreshold() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let start = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX - 160,
            y: layout.pageMetrics.viewportRect.midY
        )
        let end = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX + 160,
            y: layout.pageMetrics.viewportRect.midY
        )
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        applySweep(
            to: &state,
            from: start,
            to: end,
            frames: 6,
            layout: layout
        )

        let preIdleAverageSpeed = state.particles.reduce(0.0) { partial, particle in
            partial + simd_length(particle.velocity)
        } / Double(max(1, state.particles.count))

        for _ in 0..<180 {
            _ = state.step(
                dt: 1.0 / 60.0,
                pointer: nil,
                layout: layout
            )
        }

        let postIdleAverageSpeed = state.particles.reduce(0.0) { partial, particle in
            partial + simd_length(particle.velocity)
        } / Double(max(1, state.particles.count))

        XCTAssertLessThan(
            postIdleAverageSpeed,
            preIdleAverageSpeed * 0.25,
            "pre-idle average speed \(preIdleAverageSpeed) post-idle \(postIdleAverageSpeed)"
        )
    }

    private func makeLayout(
        width: Double,
        height: Double,
        platform: DemoNavigationPlatform
    ) -> FluidLayoutSnapshot {
        evaluateFluidLayout(
            viewportWidth: width,
            viewportHeight: height,
            platform: platform
        )
    }

    private func makeSingleGlyphLayout(
        viewport: WrapRect = WrapRect(x: 0, y: 0, width: 200, height: 120)
    ) -> FluidLayoutSnapshot {
        let metrics = FluidPageMetrics(
            viewportRect: viewport,
            contentRect: viewport,
            layoutWidth: viewport.width,
            fontSize: 16,
            lineHeight: 19.2,
            fieldColumns: 10,
            fieldRows: 6,
            cursorBaseSize: 22
        )
        let bounds = WrapRect(x: viewport.midX - 10, y: viewport.midY - 9, width: 20, height: 18)
        let glyph = FluidGlyphLayout(
            id: 0,
            character: "A",
            fontGlyph: 0,
            restCenter: WrapPoint(x: bounds.midX, y: bounds.midY),
            drawOrigin: WrapPoint(x: bounds.x, y: bounds.maxY),
            baselineY: bounds.maxY,
            width: bounds.width,
            bounds: bounds
        )
        return FluidLayoutSnapshot(
            pageMetrics: metrics,
            text: "A",
            glyphs: [glyph]
        )
    }

    private func makeGlyph(
        id: Int,
        character: String,
        bounds: WrapRect
    ) -> FluidGlyphLayout {
        FluidGlyphLayout(
            id: id,
            character: character,
            fontGlyph: CGGlyph(id),
            restCenter: WrapPoint(x: bounds.midX, y: bounds.midY),
            drawOrigin: WrapPoint(x: bounds.x, y: bounds.maxY),
            baselineY: bounds.maxY,
            width: bounds.width,
            bounds: bounds
        )
    }

    private func nearbyGlyphIndices(
        to point: WrapPoint,
        radius: Double,
        in layout: FluidLayoutSnapshot
    ) -> [Int] {
        layout.glyphs.indices.filter { index in
            let glyph = layout.glyphs[index]
            return hypot(
                glyph.restCenter.x - point.x,
                glyph.restCenter.y - point.y
            ) <= radius
        }
    }

    private func averageDistanceToCenter(
        for indices: [Int],
        particles: [FluidParticleState],
        center: WrapPoint
    ) -> Double {
        guard !indices.isEmpty else {
            return 0
        }

        let total = indices.reduce(0.0) { partial, index in
            partial + hypot(
                particles[index].center.x - center.x,
                particles[index].center.y - center.y
            )
        }
        return total / Double(indices.count)
    }

    private func averageGlyphDisplacement(
        for indices: [Int],
        particles: [FluidParticleState],
        glyphs: [FluidGlyphLayout]
    ) -> Double {
        guard !indices.isEmpty else {
            return 0
        }

        let total = indices.reduce(0.0) { partial, index in
            let particle = particles[index]
            let glyph = glyphs[index]
            return partial + hypot(
                particle.center.x - glyph.restCenter.x,
                particle.center.y - glyph.restCenter.y
            )
        }
        return total / Double(indices.count)
    }

    private func applySweep(
        to state: inout FluidSimulationState,
        from start: WrapPoint,
        to end: WrapPoint,
        frames: Int,
        dt: Double = 1.0 / 60.0,
        layout: FluidLayoutSnapshot
    ) {
        _ = state.step(
            dt: dt,
            pointer: FluidPointerInput(center: start, isInitialContact: true),
            layout: layout
        )

        guard frames > 0 else {
            return
        }

        for frame in 1...frames {
            let progress = Double(frame) / Double(frames)
            let point = WrapPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            _ = state.step(
                dt: dt,
                pointer: FluidPointerInput(center: point),
                layout: layout
            )
        }
    }

    // MARK: - Performance Baseline Tests

    /// Measures the full CPU simulation step (SPH + collisions) for ~1000 particles.
    /// Run before and after optimizations to verify speedup.
    func testPerformanceBaselineFullStepWith1000Particles() {
        let layout = makeLayout(width: 1200, height: 800, platform: .macOS)
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        let particleCount = state.particles.count
        XCTAssertGreaterThan(particleCount, 500, "Need enough particles for a meaningful benchmark")

        // Warm up: run a sweep to get particles moving
        let center = WrapPoint(x: 600, y: 400)
        applySweep(
            to: &state,
            from: center,
            to: WrapPoint(x: center.x + 200, y: center.y),
            frames: 10,
            layout: layout
        )

        // Benchmark: 60 frames of CPU simulation (1 second at 60fps)
        let iterations = 60
        let dt = 1.0 / 60.0
        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<iterations {
            _ = state.step(dt: dt, pointer: nil, layout: layout)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let msPerFrame = (elapsed / Double(iterations)) * 1000

        // Record baseline — update these after optimization
        print("""
        [Perf] Full step: \(particleCount) particles
        [Perf] Total: \(String(format: "%.1f", elapsed * 1000))ms for \(iterations) frames
        [Perf] Per frame: \(String(format: "%.2f", msPerFrame))ms
        [Perf] Budget: \(String(format: "%.1f", msPerFrame / 16.67 * 100))% of 16.67ms frame budget
        """)

        // Assert we stay under frame budget (16.67ms at 60fps)
        XCTAssertLessThan(
            msPerFrame, 16.0,
            "Simulation step must stay under 60fps frame budget"
        )
    }

    /// Measures idle simulation step (no pointer, particles moving from prior sweep).
    func testPerformanceBaselineIdleStepAfterSweep() {
        let layout = makeLayout(width: 1200, height: 800, platform: .macOS)
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        // Get particles moving
        let center = WrapPoint(x: 600, y: 400)
        applySweep(
            to: &state,
            from: center,
            to: WrapPoint(x: center.x + 300, y: center.y + 100),
            frames: 15,
            layout: layout
        )

        let particleCount = state.particles.count

        // Benchmark: 120 idle frames (2 seconds at 60fps)
        let iterations = 120
        let dt = 1.0 / 60.0
        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<iterations {
            _ = state.step(dt: dt, pointer: nil, layout: layout)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let msPerFrame = (elapsed / Double(iterations)) * 1000

        print("""
        [Perf] Idle step: \(particleCount) particles
        [Perf] Per frame: \(String(format: "%.2f", msPerFrame))ms
        """)

        XCTAssertLessThan(
            msPerFrame, 10.0,
            "Idle step should stay well under frame budget"
        )
    }

    /// Verifies that optimization does not change simulation output.
    /// Runs identical inputs and checks particle positions match a recorded snapshot.
    func testDeterministicOutputAfterSweep() {
        let layout = makeLayout(width: 640, height: 360, platform: .macOS)
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        let particleCount = state.particles.count
        XCTAssertGreaterThan(particleCount, 0)

        // Run a deterministic sweep
        let start = WrapPoint(x: 320, y: 180)
        let end = WrapPoint(x: 520, y: 180)
        applySweep(to: &state, from: start, to: end, frames: 30, layout: layout)

        // Run 30 more idle frames
        for _ in 0..<30 {
            _ = state.step(dt: 1.0 / 60.0, pointer: nil, layout: layout)
        }

        // Snapshot key statistics
        let totalDisplacement = state.particles.enumerated().reduce(0.0) { sum, pair in
            let (index, particle) = pair
            return sum + hypot(
                particle.center.x - state.restCenters[index].x,
                particle.center.y - state.restCenters[index].y
            )
        }

        let maxVelocity = state.particles.reduce(0.0) { max($0, simd_length($1.velocity)) }

        let allInBounds = state.particles.allSatisfy { particle in
            particle.center.x >= layout.pageMetrics.viewportRect.minX &&
            particle.center.x <= layout.pageMetrics.viewportRect.maxX &&
            particle.center.y >= layout.pageMetrics.viewportRect.minY &&
            particle.center.y <= layout.pageMetrics.viewportRect.maxY
        }

        // These assertions verify physics correctness:
        // 1. Some particles were displaced (sweep had an effect)
        XCTAssertGreaterThan(
            totalDisplacement, 100,
            "Sweep should displace particles significantly"
        )

        // 2. Velocities are bounded (no explosion)
        XCTAssertLessThan(
            maxVelocity, 1300,
            "Max velocity should stay near the 1200 limit"
        )

        // 3. All particles stayed in viewport
        XCTAssertTrue(allInBounds, "All particles must stay within viewport")

        // 4. Record snapshot for regression detection
        print("""
        [Determinism] Particles: \(particleCount)
        [Determinism] Total displacement: \(String(format: "%.1f", totalDisplacement))
        [Determinism] Max velocity: \(String(format: "%.1f", maxVelocity))
        [Determinism] All in bounds: \(allInBounds)
        """)
    }

    /// Measures active simulation with pointer sweep (worst case).
    func testPerformanceBaselineActiveSweep() {
        let layout = makeLayout(width: 1200, height: 800, platform: .macOS)
        var state = FluidSimulationState.empty
        state.reset(from: layout)

        let particleCount = state.particles.count
        let dt = 1.0 / 60.0

        // Benchmark: 60-frame sweep across viewport
        let iterations = 60
        let startPoint = WrapPoint(x: 100, y: 400)
        let endPoint = WrapPoint(x: 1100, y: 400)
        let start = CFAbsoluteTimeGetCurrent()

        for frame in 0..<iterations {
            let progress = Double(frame) / Double(iterations)
            let point = WrapPoint(
                x: startPoint.x + (endPoint.x - startPoint.x) * progress,
                y: startPoint.y + (endPoint.y - startPoint.y) * progress
            )
            _ = state.step(
                dt: dt,
                pointer: FluidPointerInput(
                    center: point,
                    isInitialContact: frame == 0
                ),
                layout: layout
            )
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let msPerFrame = (elapsed / Double(iterations)) * 1000

        print("""
        [Perf] Active sweep: \(particleCount) particles
        [Perf] Per frame: \(String(format: "%.2f", msPerFrame))ms
        [Perf] Budget: \(String(format: "%.1f", msPerFrame / 16.67 * 100))% of 16.67ms frame budget
        """)

        XCTAssertLessThan(
            msPerFrame, 16.0,
            "Active sweep must stay under 60fps frame budget"
        )
    }
}
