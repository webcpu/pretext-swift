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

    func testNarrowLayoutLeavesRoomForTopHintPill() {
        let layout = buildLayout(pageWidth: 390, pageHeight: 844, lineHeight: EditorialMetrics.bodyLineHeight)

        XCTAssertGreaterThanOrEqual(layout.headlineRegion.y, EditorialMetrics.narrowHintPillSafeTop)
    }

    func testEditorialInteractionHintExplainsAutoSpinOnNarrowLayouts() {
        XCTAssertEqual(
            editorialInteractionHintText(isNarrow: true),
            "The logos spin in. Tap either one to spin it again."
        )
    }

    func testEditorialInteractionHintMatchesWebPhrasingOnDesktop() {
        XCTAssertEqual(
            editorialInteractionHintText(isNarrow: false),
            "Everything laid out in Swift. Click the logos."
        )
    }

    func testEditorialIntroSpinPlanStartsBothLogosFromRest() {
        let plan = editorialIntroSpinPlan(startTime: 123)

        XCTAssertEqual(plan.openai, SpinState(from: 0, to: -.pi, start: 123, duration: 0.9))
        XCTAssertEqual(plan.claude, SpinState(from: 0, to: .pi, start: 123, duration: 0.9))
    }

    func testEditorialAutoSpinRunsOnAllSupportedPlatforms() {
        XCTAssertTrue(editorialShouldAutoSpinOnAppear(platform: .ios))
        XCTAssertTrue(editorialShouldAutoSpinOnAppear(platform: .macOS))
    }

    func testEditorialHintTopPaddingAccountsForMacOSWindowChrome() {
        XCTAssertEqual(
            editorialHintTopPadding(safeAreaTop: 0, platform: .ios),
            16
        )
        XCTAssertEqual(
            editorialHintTopPadding(safeAreaTop: 0, platform: .macOS),
            52
        )
        XCTAssertEqual(
            editorialHintTopPadding(safeAreaTop: 28, platform: .macOS),
            52
        )
    }

    func testEditorialHintStyleUsesLargerDesktopPillForWebParity() {
        let desktop = editorialHintStyle(isNarrow: false, platform: .macOS)
        let narrow = editorialHintStyle(isNarrow: true, platform: .ios)

        XCTAssertEqual(desktop.fontSize, 15)
        XCTAssertEqual(desktop.horizontalPadding, 22)
        XCTAssertEqual(desktop.verticalPadding, 13)
        XCTAssertNil(desktop.maxWidth)

        XCTAssertEqual(narrow.fontSize, 12)
        XCTAssertEqual(narrow.horizontalPadding, 16)
        XCTAssertEqual(narrow.verticalPadding, 10)
        XCTAssertEqual(
            narrow.maxWidth,
            320
        )
    }

    func testDesktopRightColumnReflowsWhenLogosSpin() {
        let layout = buildLayout(pageWidth: 1120, pageHeight: 780, lineHeight: EditorialMetrics.bodyLineHeight)
        let resting = evaluateLayout(
            layout: layout,
            lineHeight: EditorialMetrics.bodyLineHeight,
            preparedBody: EditorialAssets.bodyPrepared,
            openaiLogo: EditorialAssets.openaiLogo,
            claudeLogo: EditorialAssets.claudeLogo,
            openaiAngle: 0,
            claudeAngle: 0
        )
        let spinning = evaluateLayout(
            layout: layout,
            lineHeight: EditorialMetrics.bodyLineHeight,
            preparedBody: EditorialAssets.bodyPrepared,
            openaiLogo: EditorialAssets.openaiLogo,
            claudeLogo: EditorialAssets.claudeLogo,
            openaiAngle: -.pi * 0.5,
            claudeAngle: .pi * 0.5
        )

        XCTAssertNotEqual(resting.rightLines, spinning.rightLines)
    }
}
