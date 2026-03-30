import CoreGraphics
import XCTest
@testable import PretextDemo

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
}
