import CoreGraphics
import Pretext
import XCTest
@testable import Demo

final class OrbEditorialLayoutTests: XCTestCase {
    func testOrbEditorialColumnCountUsesResponsiveBreakpoints() {
        XCTAssertEqual(orbEditorialColumnCount(for: 1200), 3)
        XCTAssertEqual(orbEditorialColumnCount(for: 900), 2)
        XCTAssertEqual(orbEditorialColumnCount(for: 640), 1)
    }

    func testEvaluateOrbEditorialLayoutProducesPullquotesAndSkipsDropCapCharacter() {
        let pageSize = CGSize(width: 1440, height: 960)
        let orbs = makeInitialOrbStates(pageSize: pageSize)
        let snapshot = evaluateOrbEditorialLayout(
            pageWidth: pageSize.width,
            pageHeight: pageSize.height,
            orbs: orbs
        )

        XCTAssertEqual(snapshot.columnCount, 3)
        XCTAssertEqual(snapshot.pullquotes.count, 2)
        XCTAssertFalse(snapshot.headlineLines.isEmpty)
        XCTAssertFalse(snapshot.bodyLines.isEmpty)
        XCTAssertFalse(snapshot.bodyLines[0].text.hasPrefix("The"))
        XCTAssertTrue(snapshot.bodyLines[0].text.hasPrefix("he"))
        XCTAssertGreaterThan(snapshot.dropCapRect.width, 0)
    }

    func testPhoneContentHeightExhaustsBodyText() {
        let viewportSize = CGSize(width: 390, height: 844)
        let orbs = makeInitialOrbStates(pageSize: viewportSize)
        let contentHeight = orbEditorialPhoneContentHeight(
            viewportWidth: viewportSize.width,
            viewportHeight: viewportSize.height,
            orbs: orbs
        )
        let snapshot = evaluateOrbEditorialLayout(
            pageWidth: viewportSize.width,
            pageHeight: contentHeight,
            compositionHeight: viewportSize.height,
            orbs: orbs
        )

        XCTAssertGreaterThan(contentHeight, viewportSize.height)
        XCTAssertTrue(snapshot.bodyExhausted)
        XCTAssertGreaterThan(snapshot.contentBottom, viewportSize.height)
    }

    func testPhoneScrollableLayoutKeepsOpeningCompositionAnchoredToViewport() {
        let viewportSize = CGSize(width: 390, height: 844)
        let orbs = makeInitialOrbStates(pageSize: viewportSize)
        let contentHeight = orbEditorialPhoneContentHeight(
            viewportWidth: viewportSize.width,
            viewportHeight: viewportSize.height,
            orbs: orbs
        )
        let viewportSnapshot = evaluateOrbEditorialLayout(
            pageWidth: viewportSize.width,
            pageHeight: viewportSize.height,
            compositionHeight: viewportSize.height,
            orbs: orbs
        )
        let scrollSnapshot = evaluateOrbEditorialLayout(
            pageWidth: viewportSize.width,
            pageHeight: contentHeight,
            compositionHeight: viewportSize.height,
            orbs: orbs
        )

        XCTAssertEqual(scrollSnapshot.headlineFontSize, viewportSnapshot.headlineFontSize)
        XCTAssertEqual(scrollSnapshot.headlineLineHeight, viewportSnapshot.headlineLineHeight)
        XCTAssertEqual(scrollSnapshot.dropCapPosition.y, viewportSnapshot.dropCapPosition.y)
        XCTAssertEqual(scrollSnapshot.pullquotes.map(\.rect.y), viewportSnapshot.pullquotes.map(\.rect.y))
    }

    func testPhoneLayoutUsesCompactTypographyProfile() {
        let viewportSize = CGSize(width: 390, height: 844)
        let orbs = makeInitialOrbStates(pageSize: viewportSize)
        let snapshot = evaluateOrbEditorialLayout(
            pageWidth: viewportSize.width,
            pageHeight: viewportSize.height,
            compositionHeight: viewportSize.height,
            orbs: orbs
        )
        let profile = OrbEditorialMetrics.compactProfile
        let headlineHeight = snapshot.headlineLineHeight * Double(snapshot.headlineLines.count)

        XCTAssertEqual(snapshot.bodyFontSize, profile.bodyFontSize)
        XCTAssertEqual(snapshot.bodyLineHeight, profile.bodyLineHeight)
        XCTAssertEqual(snapshot.pullquoteFontSize, profile.pullquoteFontSize)
        XCTAssertEqual(snapshot.pullquoteLineHeight, profile.pullquoteLineHeight)
        XCTAssertEqual(snapshot.dropCapSize, profile.dropCapSize)
        XCTAssertLessThanOrEqual(snapshot.headlineFontSize, Double(profile.headlineMaxSize))
        XCTAssertLessThanOrEqual(headlineHeight, viewportSize.height * profile.headlineMaxHeightFraction + 1)
    }

    func testInitialOrbStatesUseTwoThirdsRadiusOnCompactPhoneViewport() {
        let compactViewport = CGSize(width: 390, height: 844)
        let regularViewport = CGSize(width: 1024, height: 1366)
        let compactOrbs = makeInitialOrbStates(pageSize: compactViewport)
        let regularOrbs = makeInitialOrbStates(pageSize: regularViewport)

        XCTAssertEqual(compactOrbs.count, regularOrbs.count)

        for (compactOrb, regularOrb) in zip(compactOrbs, regularOrbs) {
            XCTAssertEqual(compactOrb.radius, regularOrb.radius * (2.0 / 3.0), accuracy: 0.001)
        }
    }
}
