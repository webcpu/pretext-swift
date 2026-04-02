import XCTest
@testable import Demo

final class FluidLayoutTests: XCTestCase {
    func testFluidPortsExactSitePhraseCorpus() {
        XCTAssertEqual(fluidSitePhrases.count, 15)
        XCTAssertEqual(
            fluidSitePhrases.first,
            "GPU shaders are like tiny wizards, casting millions of pixel spells per second!"
        )
        XCTAssertEqual(
            fluidSitePhrases.last,
            "Shader permutations are like a choose-your-own-adventure book, but for your GPU."
        )
    }

    func testFluidFontAssetsResolveExactModeFromBundledResource() {
        let assets = FluidFontAssets.live

        XCTAssertEqual(
            assets.packagedFontURL()?.lastPathComponent,
            "L10-Medium.woff"
        )
        XCTAssertEqual(assets.resolvedFontMode(size: 16), .exact)
    }

    func testFluidFontAssetsFallbackWhenExactLoadingFails() {
        let assets = FluidFontAssets.testValue(
            loadExactGraphicsFont: { throw FluidFontLoadFailure.invalidGraphicsFont }
        )

        XCTAssertEqual(
            assets.resolvedFontMode(size: 16),
            .fallback(.helveticaNeue)
        )
    }

    func testFluidFontAssetsFallbackWhenResourceIsMissing() {
        let assets = FluidFontAssets.testValue(
            loadExactGraphicsFont: { throw FluidFontLoadFailure.missingResource }
        )

        XCTAssertEqual(
            assets.resolvedFontMode(size: 16),
            .fallback(.helveticaNeue)
        )
    }

    func testFluidFontAssetsUnexpectedErrorsDoNotSilentlyFallback() {
        enum TestError: Error, Equatable {
            case boom
        }

        let assets = FluidFontAssets.testValue(
            loadExactGraphicsFont: { throw TestError.boom }
        )

        XCTAssertThrowsError(try assets.exactGraphicsFont()) { error in
            XCTAssertEqual(error as? TestError, .boom)
        }
    }

    func testFluidFontAssetsCacheResolvedMode() {
        var loadCount = 0
        let assets = FluidFontAssets.testValue(
            loadExactGraphicsFont: {
                loadCount += 1
                throw FluidFontLoadFailure.invalidGraphicsFont
            }
        )

        XCTAssertEqual(assets.resolvedFontMode(size: 16), .fallback(.helveticaNeue))
        XCTAssertEqual(assets.resolvedFontMode(size: 24), .fallback(.helveticaNeue))
        XCTAssertEqual(assets.resolvedFontMode(size: 16), .fallback(.helveticaNeue))
        XCTAssertEqual(loadCount, 1)
    }

    func testFluidPhraseCountMatchesViewportScalingWithNativeClamp() {
        XCTAssertEqual(fluidPhraseCount(for: 0.2), 1)
        XCTAssertEqual(fluidPhraseCount(for: 390), 19)
        XCTAssertEqual(fluidPhraseCount(for: 512), 25)
        XCTAssertEqual(fluidPhraseCount(for: 1024), 50)
    }

    func testFluidDisplayTextUsesDeterministicSeededCorpusCycles() {
        let phrases = fluidPhraseSequence(phraseCount: fluidSitePhrases.count * 2)
        let repeatedPhrases = fluidPhraseSequence(phraseCount: fluidSitePhrases.count * 2)
        let text = fluidDisplayText(phraseCount: fluidSitePhrases.count * 2)
        let repeatedText = fluidDisplayText(phraseCount: fluidSitePhrases.count * 2)
        let uppercaseCorpus = fluidSitePhrases.map { $0.uppercased() }

        XCTAssertEqual(phrases, repeatedPhrases)
        XCTAssertEqual(text, repeatedText)
        XCTAssertTrue(text.hasSuffix(" "))
        XCTAssertEqual(
            text,
            phrases
                .map { $0.uppercased() + " " }
                .joined()
        )

        let firstCycle = Array(phrases.prefix(fluidSitePhrases.count))
        let secondCycle = Array(phrases.suffix(fluidSitePhrases.count))

        XCTAssertEqual(Set(firstCycle.map { $0.uppercased() }), Set(uppercaseCorpus))
        XCTAssertEqual(Set(secondCycle.map { $0.uppercased() }), Set(uppercaseCorpus))
        XCTAssertNotEqual(firstCycle.map { $0.uppercased() }, uppercaseCorpus)
        XCTAssertNotEqual(secondCycle, firstCycle)
    }

    func testFluidPageMetricsUsePlatformTypographyAndFullWidth() {
        let mobile = fluidPageMetrics(
            viewportWidth: 390,
            viewportHeight: 844,
            platform: .ios
        )
        let desktop = fluidPageMetrics(
            viewportWidth: 1280,
            viewportHeight: 900,
            platform: .macOS
        )

        XCTAssertEqual(mobile.fontSize, 12, accuracy: 0.001)
        XCTAssertEqual(mobile.lineHeight, 14.4, accuracy: 0.01)
        XCTAssertEqual(mobile.layoutWidth, 390, accuracy: 0.001)
        XCTAssertEqual(mobile.contentRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(mobile.contentRect.maxX, 390, accuracy: 0.001)

        XCTAssertEqual(desktop.fontSize, 16, accuracy: 0.001)
        XCTAssertEqual(desktop.lineHeight, 19.2, accuracy: 0.01)
        XCTAssertEqual(desktop.layoutWidth, 1280, accuracy: 0.001)
        XCTAssertEqual(desktop.contentRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(desktop.contentRect.maxX, 1280, accuracy: 0.001)
    }

    func testFluidLayoutReturnsEmptySnapshotForNonPositiveViewport() {
        let zeroWidth = evaluateFluidLayout(
            viewportWidth: 0,
            viewportHeight: 400,
            platform: .macOS
        )
        let zeroHeight = evaluateFluidLayout(
            viewportWidth: 800,
            viewportHeight: 0,
            platform: .macOS
        )
        let negativeViewport = evaluateFluidLayout(
            viewportWidth: -10,
            viewportHeight: 400,
            platform: .macOS
        )

        XCTAssertTrue(zeroWidth.text.isEmpty)
        XCTAssertTrue(zeroWidth.glyphs.isEmpty)
        XCTAssertTrue(zeroHeight.glyphs.isEmpty)
        XCTAssertTrue(negativeViewport.text.isEmpty)
        XCTAssertTrue(negativeViewport.glyphs.isEmpty)
    }

    func testFluidLayoutUsesVisibleNonWhitespaceGlyphsForWebParity() {
        let snapshot = evaluateFluidLayout(
            viewportWidth: 390,
            viewportHeight: 844,
            platform: .ios
        )

        XCTAssertFalse(snapshot.text.isEmpty)
        XCTAssertFalse(snapshot.glyphs.isEmpty)
        XCTAssertTrue(snapshot.text.contains(" "))
        XCTAssertFalse(snapshot.glyphs.contains { $0.character == " " })

        XCTAssertTrue(snapshot.glyphs.allSatisfy { glyph in
            !glyph.character.allSatisfy(\.isWhitespace) &&
            glyph.bounds.maxX > snapshot.pageMetrics.viewportRect.minX &&
                glyph.bounds.minX < snapshot.pageMetrics.viewportRect.maxX &&
                glyph.bounds.maxY > snapshot.pageMetrics.viewportRect.minY &&
                glyph.bounds.minY < snapshot.pageMetrics.viewportRect.maxY
        })
    }

    func testFluidLayoutResolvesVisibleGlyphsToConcreteFontGlyphs() {
        let snapshot = evaluateFluidLayout(
            viewportWidth: 1280,
            viewportHeight: 900,
            platform: .macOS
        )

        XCTAssertFalse(snapshot.glyphs.isEmpty)
        XCTAssertFalse(
            snapshot.glyphs.contains { $0.fontGlyph == 0 },
            "unresolved glyphs: \(snapshot.glyphs.filter { $0.fontGlyph == 0 }.map { $0.character })"
        )
    }

    func testFluidLayoutKeepsPartiallyVisibleTopAndBottomGlyphs() {
        let snapshot = evaluateFluidLayout(
            viewportWidth: 390,
            viewportHeight: 44,
            platform: .ios
        )

        XCTAssertTrue(
            snapshot.glyphs.contains {
                $0.bounds.minY <= snapshot.pageMetrics.fontSize * 0.25
            }
        )
        XCTAssertTrue(
            snapshot.glyphs.contains {
                $0.bounds.maxY >= snapshot.pageMetrics.viewportRect.maxY - snapshot.pageMetrics.fontSize * 0.25
            }
        )
        XCTAssertTrue(snapshot.glyphs.allSatisfy { glyph in
            glyph.bounds.maxY > snapshot.pageMetrics.viewportRect.minY &&
                glyph.bounds.minY < snapshot.pageMetrics.viewportRect.maxY
        })
    }

    func testFluidLayoutCanReachViewportEdges() {
        let snapshot = evaluateFluidLayout(
            viewportWidth: 1280,
            viewportHeight: 900,
            platform: .macOS
        )

        XCTAssertTrue(snapshot.glyphs.contains { $0.bounds.minX <= 0.5 })
        XCTAssertTrue(
            snapshot.glyphs.contains {
                $0.bounds.maxX >= snapshot.pageMetrics.layoutWidth - snapshot.pageMetrics.fontSize * 1.5
            }
        )
    }

    func testFluidLayoutCentersVisibleGlyphBlockVertically() {
        let snapshot = evaluateFluidLayout(
            viewportWidth: 1280,
            viewportHeight: 900,
            platform: .macOS
        )

        let minY = snapshot.glyphs.map(\.bounds.minY).min() ?? 0
        let maxY = snapshot.glyphs.map(\.bounds.maxY).max() ?? 0

        XCTAssertEqual(
            (minY + maxY) * 0.5,
            snapshot.pageMetrics.viewportRect.midY,
            accuracy: snapshot.pageMetrics.fontSize
        )
    }

    func testFluidLayoutIsDeterministicForSameViewport() {
        let first = evaluateFluidLayout(
            viewportWidth: 1280,
            viewportHeight: 900,
            platform: .macOS
        )
        let second = evaluateFluidLayout(
            viewportWidth: 1280,
            viewportHeight: 900,
            platform: .macOS
        )

        XCTAssertEqual(first, second)
    }
}
