import XCTest
import simd
@testable import Demo

final class FluidSimulationDriverTests: XCTestCase {
    func testResetSeedsSnapshotAlignedToLayout() {
        let layout = evaluateFluidLayout(
            viewportWidth: 640,
            viewportHeight: 360,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()

        driver.reset(from: layout)

        let snapshot = driver.snapshot
        XCTAssertEqual(snapshot.particles.count, layout.glyphs.count)
        XCTAssertEqual(snapshot.particles.map(\.id), layout.glyphs.map(\.id))
        XCTAssertEqual(snapshot.particles.map(\.center), layout.glyphs.map(\.restCenter))
        XCTAssertEqual(
            snapshot.particles.map(\.velocity),
            Array(repeating: SIMD2<Double>.zero, count: layout.glyphs.count)
        )
    }

    func testStepPublishesCursorAndAlignedParticles() {
        let layout = evaluateFluidLayout(
            viewportWidth: 640,
            viewportHeight: 360,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()

        driver.reset(from: layout)
        _ = driver.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(
                center: WrapPoint(x: layout.pageMetrics.viewportRect.midX, y: layout.pageMetrics.viewportRect.midY),
                isInitialContact: true
            ),
            layout: layout
        )

        let snapshot = driver.snapshot
        XCTAssertEqual(snapshot.particles.count, layout.glyphs.count)
        XCTAssertEqual(snapshot.particles.map(\.id), layout.glyphs.map(\.id))
        XCTAssertNotNil(snapshot.cursor)
    }

    func testModerateSweepBuildsPastPointerForceGateAndLocallyDisplacesNearbyGlyphs() throws {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()
        let start = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX - 160,
            y: layout.pageMetrics.viewportRect.midY
        )
        let end = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX + 160,
            y: layout.pageMetrics.viewportRect.midY
        )
        driver.reset(from: layout)
        applySweep(
            to: driver,
            from: start,
            to: end,
            frames: 6,
            layout: layout
        )

        let strength = try XCTUnwrap(driver.snapshot.pointer.current?.strength)
        let liveCursorCenter = try XCTUnwrap(driver.snapshot.pointer.current?.center)
        let nearbyIndices = nearbyGlyphIndices(
            to: liveCursorCenter,
            radius: 90,
            in: layout
        )
        let farIndices = farGlyphIndices(
            from: liveCursorCenter,
            radius: 260,
            in: layout
        )
        let nearbyAverageDisplacement = averageDisplacement(
            for: nearbyIndices,
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs
        )
        let farAverageDisplacement = averageDisplacement(
            for: farIndices,
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs
        )

        XCTAssertGreaterThan(
            strength,
            0.01,
            "pointer strength \(strength)"
        )
        XCTAssertGreaterThan(
            nearbyAverageDisplacement,
            4,
            "nearby average displacement \(nearbyAverageDisplacement)"
        )
        XCTAssertGreaterThan(
            nearbyAverageDisplacement,
            farAverageDisplacement * 1.5,
            "nearby \(nearbyAverageDisplacement) far \(farAverageDisplacement)"
        )
    }

    func testPointerSweepMaintainsVisibleGlyphSpacingOnDriverPath() {
        let layout = evaluateFluidLayout(
            viewportWidth: 640,
            viewportHeight: 360,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()
        let start = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX,
            y: layout.pageMetrics.viewportRect.midY
        )
        let end = WrapPoint(x: start.x + 320, y: start.y)

        driver.reset(from: layout)
        let restOverlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: -1.5
        )

        applySweep(
            to: driver,
            from: start,
            to: end,
            frames: 6,
            layout: layout
        )

        let overlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: -1.5
        )

        XCTAssertLessThanOrEqual(
            overlapPairs,
            restOverlapPairs,
            "rest \(restOverlapPairs) after \(overlapPairs)"
        )
    }

    func testIdleDriverPathDoesNotIncreaseVisibleGlyphOverlapFromRest() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()

        driver.reset(from: layout)
        let restOverlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: -1.5
        )

        for _ in 0..<120 {
            _ = driver.step(
                dt: 1.0 / 60.0,
                pointer: nil,
                layout: layout
            )
        }

        let overlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: -1.5
        )

        XCTAssertLessThanOrEqual(
            overlapPairs,
            restOverlapPairs,
            "rest \(restOverlapPairs) after idle \(overlapPairs)"
        )
    }

    func testPostInteractionIdleDoesNotIncreaseVisibleGlyphOverlapBeyondRest() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()
        let start = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX,
            y: layout.pageMetrics.viewportRect.midY
        )
        let end = WrapPoint(x: start.x + 320, y: start.y)

        driver.reset(from: layout)
        let restOverlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: -1.5
        )

        applySweep(
            to: driver,
            from: start,
            to: end,
            frames: 6,
            layout: layout
        )

        for _ in 0..<120 {
            _ = driver.step(
                dt: 1.0 / 60.0,
                pointer: nil,
                layout: layout
            )
        }

        let overlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: -1.5
        )

        XCTAssertLessThanOrEqual(
            overlapPairs,
            restOverlapPairs,
            "rest \(restOverlapPairs) after sweep+idle \(overlapPairs)"
        )
    }

    func testSustainedStationaryHoverDoesNotIncreaseVisibleGlyphOverlapBeyondRestOnDriverPath() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()
        let center = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX,
            y: layout.pageMetrics.viewportRect.midY
        )

        driver.reset(from: layout)
        let restOverlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: -1.5
        )

        _ = driver.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: center, isInitialContact: true),
            layout: layout
        )
        for _ in 0..<60 {
            _ = driver.step(
                dt: 1.0 / 60.0,
                pointer: FluidPointerInput(center: center),
                layout: layout
            )
        }

        let overlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: -1.5
        )

        XCTAssertLessThanOrEqual(
            overlapPairs,
            restOverlapPairs,
            "rest \(restOverlapPairs) after sustained hover \(overlapPairs)"
        )
    }

    func testSweepThenHoldDoesNotIncreaseVisibleGlyphOverlapBeyondRestOnDriverPath() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()
        let start = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX - 160,
            y: layout.pageMetrics.viewportRect.midY
        )
        let hold = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX + 40,
            y: layout.pageMetrics.viewportRect.midY - 120
        )

        driver.reset(from: layout)
        let restOverlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: -1.5
        )

        applySweep(
            to: driver,
            from: start,
            to: hold,
            frames: 6,
            layout: layout
        )

        for _ in 0..<60 {
            _ = driver.step(
                dt: 1.0 / 60.0,
                pointer: FluidPointerInput(center: hold),
                layout: layout
            )
        }

        let overlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: -1.5
        )

        XCTAssertLessThanOrEqual(
            overlapPairs,
            restOverlapPairs,
            "rest \(restOverlapPairs) after sweep+hold \(overlapPairs)"
        )
    }

    func testSweepThenHoldDoesNotDisplaceMostGlyphsAcrossFieldOnDriverPath() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()
        let start = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX - 160,
            y: layout.pageMetrics.viewportRect.midY
        )
        let hold = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX + 40,
            y: layout.pageMetrics.viewportRect.midY - 120
        )

        driver.reset(from: layout)
        applySweep(
            to: driver,
            from: start,
            to: hold,
            frames: 6,
            layout: layout
        )

        for _ in 0..<60 {
            _ = driver.step(
                dt: 1.0 / 60.0,
                pointer: FluidPointerInput(center: hold),
                layout: layout
            )
        }

        let displacedCount = zip(driver.snapshot.particles, layout.glyphs).filter { particle, glyph in
            hypot(
                particle.center.x - glyph.restCenter.x,
                particle.center.y - glyph.restCenter.y
            ) > 24
        }.count

        XCTAssertLessThan(
            displacedCount,
            layout.glyphs.count / 2,
            "displaced \(displacedCount) / \(layout.glyphs.count)"
        )
    }

    func testSweepThenHoldDoesNotIncreaseRawGlyphOverlapBeyondRestOnDriverPath() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()
        let start = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX - 160,
            y: layout.pageMetrics.viewportRect.midY
        )
        let hold = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX + 40,
            y: layout.pageMetrics.viewportRect.midY - 120
        )

        driver.reset(from: layout)
        let restOverlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: 0
        )

        applySweep(
            to: driver,
            from: start,
            to: hold,
            frames: 6,
            layout: layout
        )

        for _ in 0..<60 {
            _ = driver.step(
                dt: 1.0 / 60.0,
                pointer: FluidPointerInput(center: hold),
                layout: layout
            )
        }

        let overlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: 0
        )

        XCTAssertLessThanOrEqual(
            overlapPairs,
            restOverlapPairs,
            "rest raw \(restOverlapPairs) after sweep+hold raw \(overlapPairs)"
        )
    }

    func testProlongedCenteredHoldDoesNotIncreaseRawGlyphOverlapBeyondRestOnDriverPath() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()
        let center = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX,
            y: layout.pageMetrics.viewportRect.midY
        )

        driver.reset(from: layout)
        let restOverlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: 0
        )

        _ = driver.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: center, isInitialContact: true),
            layout: layout
        )
        for _ in 0..<240 {
            _ = driver.step(
                dt: 1.0 / 60.0,
                pointer: FluidPointerInput(center: center),
                layout: layout
            )
        }

        let overlapPairs = countTranslatedGlyphOverlaps(
            particles: driver.snapshot.particles,
            glyphs: layout.glyphs,
            inset: 0
        )

        XCTAssertLessThanOrEqual(
            overlapPairs,
            restOverlapPairs,
            "rest raw \(restOverlapPairs) after prolonged hold raw \(overlapPairs)"
        )
    }

    func testProlongedCenteredHoldDoesNotEvacuateMostGlyphsFromInteriorOnDriverPath() {
        let layout = evaluateFluidLayout(
            viewportWidth: 1100,
            viewportHeight: 700,
            platform: .macOS
        )
        let driver = FluidSimulationDriver()
        let center = WrapPoint(
            x: layout.pageMetrics.viewportRect.midX,
            y: layout.pageMetrics.viewportRect.midY
        )
        let interior = WrapRect(
            x: layout.pageMetrics.viewportRect.width * 0.2,
            y: layout.pageMetrics.viewportRect.height * 0.2,
            width: layout.pageMetrics.viewportRect.width * 0.6,
            height: layout.pageMetrics.viewportRect.height * 0.6
        )

        driver.reset(from: layout)
        let restInteriorCount = driver.snapshot.particles.filter { particle in
            particle.center.x >= interior.minX &&
                particle.center.x <= interior.maxX &&
                particle.center.y >= interior.minY &&
                particle.center.y <= interior.maxY
        }.count

        _ = driver.step(
            dt: 1.0 / 60.0,
            pointer: FluidPointerInput(center: center, isInitialContact: true),
            layout: layout
        )
        for _ in 0..<240 {
            _ = driver.step(
                dt: 1.0 / 60.0,
                pointer: FluidPointerInput(center: center),
                layout: layout
            )
        }

        let interiorCount = driver.snapshot.particles.filter { particle in
            particle.center.x >= interior.minX &&
                particle.center.x <= interior.maxX &&
                particle.center.y >= interior.minY &&
                particle.center.y <= interior.maxY
        }.count

        XCTAssertGreaterThanOrEqual(
            interiorCount,
            restInteriorCount / 2,
            "rest interior \(restInteriorCount) after prolonged hold interior \(interiorCount)"
        )
    }

    private func applySweep(
        to driver: FluidSimulationDriver,
        from start: WrapPoint,
        to end: WrapPoint,
        frames: Int,
        dt: Double = 1.0 / 60.0,
        layout: FluidLayoutSnapshot
    ) {
        _ = driver.step(
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
            _ = driver.step(
                dt: dt,
                pointer: FluidPointerInput(center: point),
                layout: layout
            )
        }
    }

    private func countTranslatedGlyphOverlaps(
        particles: [FluidParticleState],
        glyphs: [FluidGlyphLayout],
        inset: Double = 0
    ) -> Int {
        guard particles.count == glyphs.count else {
            return .max
        }

        var overlaps = 0
        for lhs in glyphs.indices {
            let lhsBounds = fluidTranslatedGlyphBounds(
                glyphs[lhs],
                center: particles[lhs].center
            )
            let expandedLHSBounds = WrapRect(
                x: lhsBounds.x + inset,
                y: lhsBounds.y + inset,
                width: lhsBounds.width - inset * 2,
                height: lhsBounds.height - inset * 2
            )

            for rhs in glyphs.indices[(lhs + 1)...] {
                let rhsBounds = fluidTranslatedGlyphBounds(
                    glyphs[rhs],
                    center: particles[rhs].center
                )
                let expandedRHSBounds = WrapRect(
                    x: rhsBounds.x + inset,
                    y: rhsBounds.y + inset,
                    width: rhsBounds.width - inset * 2,
                    height: rhsBounds.height - inset * 2
                )

                let overlapX = min(expandedLHSBounds.maxX, expandedRHSBounds.maxX) - max(expandedLHSBounds.minX, expandedRHSBounds.minX)
                let overlapY = min(expandedLHSBounds.maxY, expandedRHSBounds.maxY) - max(expandedLHSBounds.minY, expandedRHSBounds.minY)
                if overlapX > 0, overlapY > 0 {
                    overlaps += 1
                }
            }
        }

        return overlaps
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

    private func farGlyphIndices(
        from point: WrapPoint,
        radius: Double,
        in layout: FluidLayoutSnapshot
    ) -> [Int] {
        layout.glyphs.indices.filter { index in
            let glyph = layout.glyphs[index]
            return hypot(
                glyph.restCenter.x - point.x,
                glyph.restCenter.y - point.y
            ) >= radius
        }
    }

    private func averageDisplacement(
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
}
