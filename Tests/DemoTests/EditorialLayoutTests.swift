import Pretext
import XCTest
@testable import Demo

final class EditorialLayoutTests: XCTestCase {
    func testBuildLayoutSwitchesToNarrowUnderBreakpoint() {
        let narrow = buildLayout(pageWidth: 700, pageHeight: 900, lineHeight: EditorialMetrics.bodyLineHeight)
        let wide = buildLayout(pageWidth: 1000, pageHeight: 900, lineHeight: EditorialMetrics.bodyLineHeight)

        XCTAssertTrue(narrow.isNarrow)
        XCTAssertFalse(wide.isNarrow)
    }

    func testEvaluateLayoutProducesBodyLines() {
        let layout = buildLayout(pageWidth: 1000, pageHeight: 900, lineHeight: EditorialMetrics.bodyLineHeight)
        let evaluated = evaluateLayout(
            layout: layout,
            lineHeight: EditorialMetrics.bodyLineHeight,
            preparedBody: EditorialAssets.bodyPrepared,
            openaiLogo: EditorialAssets.openaiLogo,
            claudeLogo: EditorialAssets.claudeLogo,
            openaiAngle: 0,
            claudeAngle: 0
        )

        XCTAssertFalse(evaluated.headlineLines.isEmpty)
        XCTAssertFalse(evaluated.leftLines.isEmpty)
    }

    func testCreditWidthUsesUppercaseMeasurement() {
        let preparedUppercaseCredit = prepare(
            BodyText.credit.uppercased(),
            font: EditorialMetrics.creditFont()
        )

        var measuredWidth = 0.0
        walkLineRanges(preparedUppercaseCredit, maxWidth: 100_000) { lineWidth, _, _ in
            measuredWidth = lineWidth
        }

        XCTAssertEqual(EditorialAssets.creditWidth, measuredWidth, accuracy: 0.001)
    }

    func testNarrowLayoutUsesLargerPhoneLogoSizes() {
        let layout = buildLayout(pageWidth: 390, pageHeight: 844, lineHeight: EditorialMetrics.bodyLineHeight)

        XCTAssertGreaterThan(layout.openaiRect.width, 140)
        XCTAssertGreaterThan(layout.claudeRect.width, 100)
    }

    func testEvaluateNarrowLayoutPlacesClaudeLogoBelowHeadline() {
        let layout = buildLayout(pageWidth: 390, pageHeight: 844, lineHeight: EditorialMetrics.bodyLineHeight)
        let evaluated = evaluateLayout(
            layout: layout,
            lineHeight: EditorialMetrics.bodyLineHeight,
            preparedBody: EditorialAssets.bodyPrepared,
            openaiLogo: EditorialAssets.openaiLogo,
            claudeLogo: EditorialAssets.claudeLogo,
            openaiAngle: 0,
            claudeAngle: 0
        )

        let headlineBottom = evaluated.headlineLines.map { $0.y + layout.headlineLineHeight }.max() ?? layout.headlineRegion.y

        XCTAssertGreaterThanOrEqual(evaluated.claudeRect.y, headlineBottom + 8)
    }

    func testEditorialInteractionHintUsesTapLanguageOnNarrowLayouts() {
        XCTAssertEqual(editorialInteractionHintText(isNarrow: true), "Tap the logos to spin them.")
        XCTAssertTrue(editorialInteractionHintText(isNarrow: false).contains("click the logos"))
    }
}
