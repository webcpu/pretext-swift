import CoreText
import XCTest
@testable import Pretext

final class CoreEngineTests: XCTestCase {
    private let lineHeight = 20.0

    private var font: CTFont {
        CTFontCreateWithName("Helvetica" as CFString, 16, nil)
    }

    private func measure(_ text: String) -> Double {
        TextMeasurer.shared.measureSegment(text, font: font)
    }

    private func layoutLines(
        _ text: String,
        width: Double,
        whiteSpace: WhiteSpaceMode = .normal
    ) -> (LayoutResult, [LayoutLine]) {
        let prepared = prepare(text, font: font, whiteSpace: whiteSpace)
        return layoutWithLines(prepared, maxWidth: width, lineHeight: lineHeight)
    }

    func testWhitespaceOnlyInputStaysEmpty() {
        let prepared = prepare("  \t\n  ", font: font)

        let result = layout(prepared, maxWidth: 100, lineHeight: lineHeight)

        XCTAssertEqual(result.lineCount, 0)
        XCTAssertTrue(prepared.segments.isEmpty)
    }

    func testPrepareWithSegmentsCollapsesWhitespaceRuns() {
        let prepared = prepareWithSegments("  Hello\t \n  World  ", font: font)

        XCTAssertEqual(prepared.segments, ["Hello", " ", "World"])
        XCTAssertEqual(prepared.kinds, [.text, .space, .text])
    }

    func testPreWrapPrepareWithSegmentsKeepsSpaces() {
        let prepared = prepareWithSegments("  Hello   World  ", font: font, whiteSpace: .preWrap)

        XCTAssertEqual(prepared.segments, ["  ", "Hello", "   ", "World", "  "])
        XCTAssertEqual(
            prepared.kinds,
            [.preservedSpace, .text, .preservedSpace, .text, .preservedSpace]
        )
    }

    func testPreWrapPrepareWithSegmentsKeepsHardBreaks() {
        let prepared = prepareWithSegments("Hello\nWorld", font: font, whiteSpace: .preWrap)

        XCTAssertTrue(prepared.kinds.contains(.hardBreak))
    }

    func testPreWrapPrepareWithSegmentsKeepsTabs() {
        let prepared = prepareWithSegments("Hello\tWorld", font: font, whiteSpace: .preWrap)

        XCTAssertTrue(prepared.kinds.contains(.tab))
    }

    func testNBSPActsAsGlueWithinSingleSegment() {
        let prepared = prepareWithSegments("Hello\u{00A0}world", font: font)

        XCTAssertEqual(prepared.segments, ["Hello\u{00A0}world"])
    }

    func testStandaloneNBSPRemainsVisible() {
        let prepared = prepare("\u{00A0}", font: font)

        let result = layout(prepared, maxWidth: 100, lineHeight: lineHeight)

        XCTAssertEqual(result.lineCount, 1)
    }

    func testZWSPProducesZeroWidthBreakSegment() {
        let prepared = prepareWithSegments("alpha\u{200B}beta", font: font)

        XCTAssertTrue(prepared.kinds.contains(.zeroWidthBreak))
    }

    func testSoftHyphenProducesDiscretionaryBreakSegment() {
        let prepared = prepareWithSegments("trans\u{00AD}atlantic", font: font)

        XCTAssertTrue(prepared.kinds.contains(.softHyphen))
    }

    func testClosingPunctuationAttachesToPrecedingWord() {
        let prepared = prepareWithSegments("hello.", font: font)

        XCTAssertEqual(prepared.segments, ["hello."])
    }

    func testOpeningQuotesAttachToFollowingWord() {
        let prepared = prepareWithSegments("\u{201C}Whenever", font: font)

        XCTAssertEqual(prepared.segments, ["\u{201C}Whenever"])
    }

    func testEmDashesStayBreakableAsOwnSegments() {
        let prepared = prepareWithSegments("universe\u{2014}so", font: font)

        XCTAssertEqual(prepared.segments, ["universe", "\u{2014}", "so"])
    }

    func testPrepareAndPrepareWithSegmentsAgreeOnLayoutAcrossWidths() {
        let text = "“Whenever” the trans\u{00AD}atlantic universe\u{2014}so alpha\u{200B}beta arrives."
        let widths = [220.0, 140.0, 90.0, 55.0]
        let prepared = prepare(text, font: font)
        let preparedWithSegments = prepareWithSegments(text, font: font)

        for width in widths {
            let (preparedResult, preparedLines) = layoutWithLines(
                prepared,
                maxWidth: width,
                lineHeight: lineHeight
            )
            let (segmentedResult, segmentedLines) = layoutWithLines(
                preparedWithSegments,
                maxWidth: width,
                lineHeight: lineHeight
            )

            XCTAssertEqual(preparedResult, segmentedResult)
            XCTAssertEqual(preparedLines.map(\.text), segmentedLines.map(\.text))
            XCTAssertEqual(preparedLines.map(\.start), segmentedLines.map(\.start))
            XCTAssertEqual(preparedLines.map(\.end), segmentedLines.map(\.end))
        }
    }

    func testLineCountGrowsMonotonicallyAsWidthShrinks() {
        let text = "The quick brown fox jumps over the lazy dog tonight."
        let widths = [240.0, 180.0, 120.0, 70.0]

        let lineCounts = widths.map { width in
            layout(prepare(text, font: font), maxWidth: width, lineHeight: lineHeight).lineCount
        }

        XCTAssertEqual(lineCounts.count, 4)
        XCTAssertLessThanOrEqual(lineCounts[0], lineCounts[1])
        XCTAssertLessThanOrEqual(lineCounts[1], lineCounts[2])
        XCTAssertLessThanOrEqual(lineCounts[2], lineCounts[3])
    }

    func testTrailingWhitespaceHangsAtLineEnd() {
        let width = measure("Hello")
        let prepared = prepare("Hello ", font: font)

        let result = layout(prepared, maxWidth: width, lineHeight: lineHeight)

        XCTAssertEqual(result.lineCount, 1)
    }

    func testLongWordsBreakAtGraphemeBoundaries() {
        let (_, lines) = layoutLines("Superlongword", width: 25)

        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertEqual(lines.map(\.text).joined(), "Superlongword")
    }

    func testLayoutNextLineReproducesLayoutWithLines() {
        let text = "The quick brown Superlongword jumps again."
        let width = 90.0
        let prepared = prepare(text, font: font)
        let (_, expectedLines) = layoutWithLines(prepared, maxWidth: width, lineHeight: lineHeight)
        var iterativePrepared = prepare(text, font: font)
        var cursor = LayoutCursor.start
        var actualLines: [LayoutLine] = []

        while let line = layoutNextLine(&iterativePrepared, start: cursor, maxWidth: width) {
            XCTAssertNotEqual(line.end, cursor)
            actualLines.append(line)
            cursor = line.end
        }

        XCTAssertEqual(actualLines.map(\.text), expectedLines.map(\.text))
        XCTAssertEqual(actualLines.map(\.start), expectedLines.map(\.start))
        XCTAssertEqual(actualLines.map(\.end), expectedLines.map(\.end))
        XCTAssertEqual(actualLines.count, expectedLines.count)
        for (actual, expected) in zip(actualLines, expectedLines) {
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.001)
        }
    }

    func testWalkLineRangesMatchesLayoutWithLinesGeometry() {
        let text = "Transatlantic voyages need narrower columns sometimes."
        let width = 110.0
        let prepared = prepare(text, font: font)
        let (_, lines) = layoutWithLines(prepared, maxWidth: width, lineHeight: lineHeight)
        var walkedRanges: [LayoutLineRange] = []

        walkLineRanges(prepared, maxWidth: width) { lineWidth, start, end in
            walkedRanges.append(LayoutLineRange(width: lineWidth, start: start, end: end))
        }

        XCTAssertEqual(walkedRanges.count, lines.count)
        XCTAssertEqual(walkedRanges.map(\.start), lines.map(\.start))
        XCTAssertEqual(walkedRanges.map(\.end), lines.map(\.end))
        for (walked, line) in zip(walkedRanges, lines) {
            XCTAssertEqual(walked.width, line.width, accuracy: 0.001)
        }
    }

    func testOverlongBreakableSegmentsWrapOntoFreshLine() {
        let width = measure("foo ")
        let (_, lines) = layoutLines("foo abcdefghijk", width: width)

        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertEqual(lines.first?.text, "foo ")
    }

    func testCountPreparedLinesMatchesWalkPreparedLinesAcrossTextsAndWidths() {
        let cases: [(String, WhiteSpaceMode, [Double])] = [
            ("Short words wrap cleanly across lines.", .normal, [240, 120, 70]),
            ("Superlongword", .normal, [80, 30]),
            ("a\nb\nc", .preWrap, [200, 20]),
        ]

        for (text, whiteSpace, widths) in cases {
            for width in widths {
                var prepared = prepare(text, font: font, whiteSpace: whiteSpace)
                prepareForWidth(&prepared, maxWidth: width)

                var walkedLineCount = 0
                let returnedWalkCount = walkPreparedLines(prepared, maxWidth: width) { _ in
                    walkedLineCount += 1
                }
                let countedLines = countPreparedLines(prepared, maxWidth: width)

                XCTAssertEqual(returnedWalkCount, walkedLineCount)
                XCTAssertEqual(countedLines, walkedLineCount)
            }
        }
    }

    func testPreWrapHardBreaksForceLineBoundaries() {
        let prepared = prepare("a\nb", font: font, whiteSpace: .preWrap)

        let result = layout(prepared, maxWidth: 100, lineHeight: lineHeight)

        XCTAssertEqual(result.lineCount, 2)
    }

    func testPreWrapKeepsEmptyLinesFromConsecutiveHardBreaks() {
        let prepared = prepare("\n\n", font: font, whiteSpace: .preWrap)

        let result = layout(prepared, maxWidth: 100, lineHeight: lineHeight)

        XCTAssertEqual(result.lineCount, 2)
    }

    func testPreWrapDoesNotInventTrailingEmptyLine() {
        let prepared = prepare("a\n", font: font, whiteSpace: .preWrap)

        let result = layout(prepared, maxWidth: 100, lineHeight: lineHeight)

        XCTAssertEqual(result.lineCount, 1)
    }

    func testPreWrapConsecutiveHardBreaksRemainDistinctSegments() {
        let prepared = prepareWithSegments("\n\n", font: font, whiteSpace: .preWrap)

        XCTAssertEqual(prepared.segments, ["\n", "\n"])
        XCTAssertEqual(prepared.kinds, [.hardBreak, .hardBreak])
    }

    // MARK: - Prepare invariants (parity with TypeScript suite)

    func testPreWrapNormalizesCRLF() {
        let prepared = prepareWithSegments("Hello\r\nWorld", font: font, whiteSpace: .preWrap)

        XCTAssertEqual(prepared.segments, ["Hello", "\n", "World"])
        XCTAssertEqual(prepared.kinds, [.text, .hardBreak, .text])
    }

    func testPreWrapKeepsWhitespaceOnlyInputVisible() {
        let prepared = prepare("   ", font: font, whiteSpace: .preWrap)

        let result = layout(prepared, maxWidth: 200, lineHeight: lineHeight)

        XCTAssertEqual(result.lineCount, 1)
        XCTAssertEqual(result.height, lineHeight)
    }

    func testNarrowNoBreakSpacesActAsGlue() {
        let prepared = prepareWithSegments("10\u{202F}000", font: font)

        XCTAssertEqual(prepared.segments, ["10\u{202F}000"])
        XCTAssertEqual(prepared.kinds, [.text])
    }

    func testPrepareAndPrepareWithSegmentsCanExposeDifferentGlueSegmentsButShareLayout() {
        let text = "Hello\u{00A0}world"
        let prepared = prepare(text, font: font)
        let segmented = prepareWithSegments(text, font: font)

        XCTAssertEqual(prepared.segments, ["Hello", "\u{00A0}", "world"])
        XCTAssertEqual(prepared.kinds, [.text, .glue, .text])
        XCTAssertEqual(segmented.segments, ["Hello\u{00A0}world"])
        XCTAssertEqual(segmented.kinds, [.text])

        let (preparedResult, preparedLines) = layoutWithLines(prepared, maxWidth: 40, lineHeight: lineHeight)
        let (segmentedResult, segmentedLines) = layoutWithLines(segmented, maxWidth: 40, lineHeight: lineHeight)

        XCTAssertEqual(preparedResult, segmentedResult)
        XCTAssertEqual(preparedLines.map(\.text), segmentedLines.map(\.text))
        XCTAssertEqual(preparedLines.map(\.start), segmentedLines.map(\.start))
        XCTAssertEqual(preparedLines.map(\.end), segmentedLines.map(\.end))
    }

    func testPreparePlainASCIIKeepsSimpleFastPath() {
        let prepared = prepare("Hello world!", font: font)

        XCTAssertTrue(prepared.simpleLineWalkFastPath)
        XCTAssertTrue(prepared.engineSegments.isEmpty)
        XCTAssertTrue(prepared.engineKinds.isEmpty)
    }

    func testPrepareDecimalTextKeepsSimpleFastPath() {
        let prepared = prepare("0.05 milliseconds", font: font)

        XCTAssertEqual(prepared.segments, ["0.05", " ", "milliseconds"])
        XCTAssertEqual(prepared.kinds, [.text, .space, .text])
        XCTAssertTrue(prepared.simpleLineWalkFastPath)
        XCTAssertTrue(prepared.engineSegments.isEmpty)
        XCTAssertTrue(prepared.engineKinds.isEmpty)
    }

    func testWordJoinersActAsGlue() {
        let prepared = prepareWithSegments("foo\u{2060}bar", font: font)

        XCTAssertEqual(prepared.segments, ["foo\u{2060}bar"])
        XCTAssertEqual(prepared.kinds, [.text])
    }

    func testZWSPWrapsAtNarrowWidths() {
        let prepared = prepareWithSegments("alpha\u{200B}beta", font: font)

        XCTAssertEqual(prepared.segments, ["alpha", "\u{200B}", "beta"])
        XCTAssertEqual(prepared.kinds, [.text, .zeroWidthBreak, .text])

        let alphaWidth = prepared.widths[0]
        XCTAssertEqual(layout(prepared, maxWidth: alphaWidth + 0.1, lineHeight: lineHeight).lineCount, 2)
    }

    func testSoftHyphenLayoutBehavior() {
        let prepared = prepareWithSegments("trans\u{00AD}atlantic", font: font)

        XCTAssertEqual(prepared.segments, ["trans", "\u{00AD}", "atlantic"])
        XCTAssertEqual(prepared.kinds, [.text, .softHyphen, .text])

        // Wide: single line, hyphen invisible
        let (wideResult, wideLines) = layoutWithLines(prepared, maxWidth: 200, lineHeight: lineHeight)
        XCTAssertEqual(wideResult.lineCount, 1)
        XCTAssertEqual(wideLines.map(\.text), ["transatlantic"])

        // Narrow: breaks at soft hyphen
        let prefixed = prepareWithSegments("foo trans\u{00AD}atlantic", font: font)
        let softBreakWidth = max(
            prefixed.widths[0] + prefixed.widths[1] + prefixed.widths[2] + prefixed.discretionaryHyphenWidth,
            prefixed.widths[4]
        ) + 0.1
        let (narrowResult, narrowLines) = layoutWithLines(prefixed, maxWidth: softBreakWidth, lineHeight: lineHeight)
        XCTAssertEqual(narrowResult.lineCount, 2)
        XCTAssertEqual(narrowLines.map(\.text), ["foo trans-", "atlantic"])
    }

    func testArabicPunctuationAttachesToPrecedingWord() {
        let prepared = prepareWithSegments("مرحبا، عالم؟", font: font)

        XCTAssertEqual(prepared.segments, ["مرحبا،", " ", "عالم؟"])
    }

    func testArabicPunctuationPlusMarkClustersAttach() {
        let prepared = prepareWithSegments("وحوارى بكشء،ٍ من قولهم", font: font)

        XCTAssertEqual(prepared.segments, ["وحوارى", " ", "بكشء،ٍ", " ", "من", " ", "قولهم"])
    }

    func testArabicNoSpacePunctuationStaysTogether() {
        let prepared = prepareWithSegments("فيقول:وعليك السلام", font: font)

        XCTAssertEqual(prepared.segments, ["فيقول:وعليك", " ", "السلام"])
    }

    func testArabicCommaFollowedTextStaysTogether() {
        let prepared = prepareWithSegments("همزةٌ،ما كان", font: font)

        XCTAssertEqual(prepared.segments, ["همزةٌ،ما", " ", "كان"])
    }

    func testLeadingArabicCombiningMarksAttachToFollowingWord() {
        let prepared = prepareWithSegments("كل ِّواحدةٍ", font: font)

        XCTAssertEqual(prepared.segments, ["كل", " ", "ِّواحدةٍ"])
    }

    func testDevanagariDandaPunctuationAttaches() {
        let prepared = prepareWithSegments("नमस्ते। दुनिया॥", font: font)

        XCTAssertEqual(prepared.segments, ["नमस्ते।", " ", "दुनिया॥"])
    }

    func testMyanmarPunctuationAttaches() {
        let prepared = prepareWithSegments(
            "ဖြစ်သည်။ နောက်တစ်ခု၊ ကိုက်ချီ၍ ယုံကြည်မိကြ၏။",
            font: font
        )

        XCTAssertEqual(
            Array(prepared.segments.prefix(7)),
            ["ဖြစ်သည်။", " ", "နောက်တစ်ခု၊", " ", "ကိုက်", "ချီ၍", " "]
        )
        XCTAssertEqual(prepared.segments.last, "ကြ၏။")
    }

    func testMyanmarPossessiveMarkerAttachesToFollowingWord() {
        let prepared = prepareWithSegments("ကျွန်ုပ်၏လက်မဖြင့်", font: font)

        XCTAssertEqual(prepared.segments, ["ကျွန်ုပ်၏လက်မ", "ဖြင့်"])
    }

    func testApostropheLedElisionsAttach() {
        let prepared = prepareWithSegments("\u{201C}Take \u{2018}em downstairs", font: font)

        XCTAssertEqual(
            prepared.segments,
            ["\u{201C}Take", " ", "\u{2018}em", " ", "downstairs"]
        )
    }

    func testStackedOpeningQuotesAttach() {
        let prepared = prepareWithSegments("invented, \u{201C}\u{2018}George B. Wilson", font: font)

        XCTAssertEqual(
            prepared.segments,
            ["invented,", " ", "\u{201C}\u{2018}George", " ", "B.", " ", "Wilson"]
        )
    }

    func testAsciiQuotesOpenCloseByContext() {
        let prepared = prepareWithSegments("said \"hello\" there", font: font)

        XCTAssertEqual(prepared.segments, ["said", " ", "\"hello\"", " ", "there"])
    }

    func testEscapedAsciiQuoteClusters() {
        let prepared = prepareWithSegments("say \\\"hello\\\" there", font: font)

        XCTAssertEqual(prepared.segments, ["say", " ", "\\\"hello\\\"", " ", "there"])
    }

    func testURLLikeRunsStayTogether() {
        let prepared = prepareWithSegments(
            "see https://example.com/reports/q3?lang=ar&mode=full now",
            font: font
        )

        XCTAssertEqual(prepared.segments, [
            "see", " ",
            "https://example.com/reports/q3?",
            "lang=ar&mode=full",
            " ", "now",
        ])
    }

    func testNoSpaceAsciiPunctuationChainsStayTogether() {
        let prepared = prepareWithSegments("foo;bar foo:bar foo,bar as;lkdfjals;k", font: font)

        XCTAssertEqual(prepared.segments, [
            "foo;bar", " ", "foo:bar", " ", "foo,bar", " ", "as;lkdfjals;k",
        ])
    }

    func testNumericTimeRangesStayTogether() {
        let prepared = prepareWithSegments("window 7:00-9:00 only", font: font)

        XCTAssertEqual(prepared.segments, ["window", " ", "7:00-", "9:00", " ", "only"])
    }

    func testHyphenatedNumericIdentifiersSplit() {
        let prepared = prepareWithSegments("SSN 420-69-8008 filed", font: font)

        XCTAssertEqual(prepared.segments, ["SSN", " ", "420-", "69-", "8008", " ", "filed"])
    }

    func testUnicodeDigitNumericExpressionsStayTogether() {
        let prepared = prepareWithSegments("यह २४×७ सपोर्ट है", font: font)

        XCTAssertEqual(prepared.segments, ["यह", " ", "२४×७", " ", "सपोर्ट", " ", "है"])
    }

    func testOpeningPunctuationDoesNotAttachToWhitespace() {
        let prepared = prepareWithSegments("\u{201C} hello", font: font)

        XCTAssertEqual(prepared.segments, ["\u{201C}", " ", "hello"])
    }

    func testJapaneseIterationMarksAttach() {
        let prepared = prepareWithSegments("棄てゝ行く", font: font)

        XCTAssertEqual(prepared.segments, ["棄", "てゝ", "行", "く"])
    }

    func testTrailingCJKOpeningPunctuationCarriesForward() {
        let prepared = prepareWithSegments("作者はさつき、「下人", font: font)

        XCTAssertEqual(prepared.segments, ["作", "者", "は", "さ", "つ", "き、", "「下", "人"])
    }

    func testCoalescesRepeatedPunctuationRuns() {
        let prepared = prepareWithSegments("=== heading ===", font: font)

        XCTAssertEqual(prepared.segments, ["===", " ", "heading", " ", "==="])
    }

    func testCJKAndHangulPunctuationRules() {
        XCTAssertEqual(
            prepareWithSegments("中文，测试。", font: font).segments,
            ["中", "文，", "测", "试。"]
        )
        XCTAssertEqual(
            prepareWithSegments("테스트입니다.", font: font).segments.last,
            "다."
        )
    }

    func testAstralCJKWithPunctuation() {
        XCTAssertEqual(
            prepareWithSegments("𠀀。", font: font).segments,
            ["𠀀。"]
        )
    }

    func testLocaleCanBeReset() {
        setLocale(Locale(identifier: "th"))
        let thai = prepare("ภาษาไทยภาษาไทย", font: font)
        XCTAssertGreaterThan(layout(thai, maxWidth: 80, lineHeight: lineHeight).lineCount, 0)

        setLocale(nil)
        let latin = prepare("hello world", font: font)
        XCTAssertEqual(layout(latin, maxWidth: 200, lineHeight: lineHeight).lineCount, 1)
    }

    // MARK: - Layout invariants (parity with TypeScript suite)

    func testMixedDirectionTextSmokeTest() {
        let text = "According to محمد الأحمد, the results improved."
        let prepared = prepareWithSegments(text, font: font)
        let (result, lines) = layoutWithLines(prepared, maxWidth: 120, lineHeight: lineHeight)

        XCTAssertGreaterThanOrEqual(result.lineCount, 1)
        XCTAssertEqual(result.height, Double(result.lineCount) * lineHeight)
        XCTAssertEqual(lines.map(\.text).joined(), text)
    }

    func testPreWrapHangingSpaces() {
        let prepared = prepareWithSegments("foo   bar", font: font, whiteSpace: .preWrap)
        let width = measure("foo") + 0.1
        let (result, lines) = layoutWithLines(prepared, maxWidth: width, lineHeight: lineHeight)

        XCTAssertEqual(result.lineCount, 2)
        XCTAssertEqual(lines.map(\.text), ["foo   ", "bar"])
    }

    func testPreWrapWalkLineRangesKeepsHangingWhitespaceBoundaries() {
        let prepared = prepareWithSegments("foo   bar", font: font, whiteSpace: .preWrap)
        let width = measure("foo") + 0.1
        let (_, expectedLines) = layoutWithLines(prepared, maxWidth: width, lineHeight: lineHeight)
        var walkedRanges: [LayoutLineRange] = []

        walkLineRanges(prepared, maxWidth: width) { lineWidth, start, end in
            walkedRanges.append(LayoutLineRange(width: lineWidth, start: start, end: end))
        }

        XCTAssertEqual(walkedRanges.map(\.start), expectedLines.map(\.start))
        XCTAssertEqual(walkedRanges.map(\.end), expectedLines.map(\.end))
        for (walked, expected) in zip(walkedRanges, expectedLines) {
            XCTAssertEqual(walked.width, expected.width, accuracy: 0.001)
        }
    }

    func testPreWrapTabsAsHangingWhitespace() {
        let prepared = prepareWithSegments("a\tb", font: font, whiteSpace: .preWrap)
        let spaceWidth = measure(" ")
        let prefixWidth = measure("a")
        let tabStopAdvance = spaceWidth * 8
        let remainder = prefixWidth.truncatingRemainder(dividingBy: tabStopAdvance)
        let tabAdvance = abs(remainder) <= 1e-6 ? tabStopAdvance : tabStopAdvance - remainder
        let totalWidth = prefixWidth + tabAdvance + measure("b")
        let width = totalWidth - 0.1

        let (result, lines) = layoutWithLines(prepared, maxWidth: width, lineHeight: lineHeight)

        XCTAssertEqual(result.lineCount, 2)
        XCTAssertEqual(lines.map(\.text), ["a\t", "b"])
    }

    func testPreWrapConsecutiveTabs() {
        let prepared = prepareWithSegments("a\t\tb", font: font, whiteSpace: .preWrap)
        let spaceWidth = measure(" ")
        let prefixWidth = measure("a")
        let tabStopAdvance = spaceWidth * 8

        let remainder1 = prefixWidth.truncatingRemainder(dividingBy: tabStopAdvance)
        let firstTabAdvance = abs(remainder1) <= 1e-6 ? tabStopAdvance : tabStopAdvance - remainder1
        let afterFirstTab = prefixWidth + firstTabAdvance
        let remainder2 = afterFirstTab.truncatingRemainder(dividingBy: tabStopAdvance)
        let secondTabAdvance = abs(remainder2) <= 1e-6 ? tabStopAdvance : tabStopAdvance - remainder2
        let width = prefixWidth + firstTabAdvance + secondTabAdvance - 0.1

        let (result, lines) = layoutWithLines(prepared, maxWidth: width, lineHeight: lineHeight)

        XCTAssertEqual(result.lineCount, 2)
        XCTAssertEqual(lines.map(\.text), ["a\t\t", "b"])
    }

    func testPreWrapWhitespaceOnlyMiddleLinesVisible() {
        let prepared = prepareWithSegments("foo\n  \nbar", font: font, whiteSpace: .preWrap)
        let (result, lines) = layoutWithLines(prepared, maxWidth: 200, lineHeight: lineHeight)

        XCTAssertEqual(lines.map(\.text), ["foo", "  ", "bar"])
        XCTAssertEqual(result.lineCount, 3)
        XCTAssertEqual(result.height, lineHeight * 3)
    }

    func testPreWrapTrailingSpacesBeforeHardBreak() {
        let prepared = prepareWithSegments("foo  \nbar", font: font, whiteSpace: .preWrap)
        let (result, lines) = layoutWithLines(prepared, maxWidth: 200, lineHeight: lineHeight)

        XCTAssertEqual(lines.map(\.text), ["foo  ", "bar"])
        XCTAssertEqual(result.lineCount, 2)
        XCTAssertEqual(result.height, lineHeight * 2)
    }

    func testPreWrapTrailingTabsBeforeHardBreak() {
        let prepared = prepareWithSegments("foo\t\nbar", font: font, whiteSpace: .preWrap)
        let (result, lines) = layoutWithLines(prepared, maxWidth: 200, lineHeight: lineHeight)

        XCTAssertEqual(lines.map(\.text), ["foo\t", "bar"])
        XCTAssertEqual(result.lineCount, 2)
        XCTAssertEqual(result.height, lineHeight * 2)
    }

    func testPreWrapTabStopsRestartAfterHardBreak() {
        let prepared = prepareWithSegments("foo\n\tbar", font: font, whiteSpace: .preWrap)
        let (_, lines) = layoutWithLines(prepared, maxWidth: 200, lineHeight: lineHeight)
        let spaceWidth = measure(" ")
        let tabStopAdvance = spaceWidth * 8
        let expectedSecondLineWidth = tabStopAdvance + measure("bar")

        XCTAssertEqual(lines.map(\.text), ["foo", "\tbar"])
        XCTAssertEqual(lines[1].width, expectedSecondLineWidth, accuracy: 0.001)
    }

    func testPreWrapLayoutNextLineStaysAligned() {
        let text = "foo\n  bar baz\nquux"
        let prepared = prepareWithSegments(text, font: font, whiteSpace: .preWrap)
        let width = measure("  bar") + 0.1
        let (_, expectedLines) = layoutWithLines(prepared, maxWidth: width, lineHeight: lineHeight)

        var cursor = LayoutCursor.start
        var actualLines: [LayoutLine] = []
        var iterPrepared = prepareWithSegments(text, font: font, whiteSpace: .preWrap)
        while let line = layoutNextLine(&iterPrepared, start: cursor, maxWidth: width) {
            actualLines.append(line)
            cursor = line.end
        }

        XCTAssertEqual(actualLines.map(\.text), expectedLines.map(\.text))
        XCTAssertEqual(actualLines.map(\.start), expectedLines.map(\.start))
        XCTAssertEqual(actualLines.map(\.end), expectedLines.map(\.end))
    }

    func testCJKCharactersSplitIntoIndividualSegments() {
        let prepared = prepareWithSegments("中文测试", font: font)

        XCTAssertEqual(prepared.segments, ["中", "文", "测", "试"])
    }

    func testAstralCJKCharactersSplitIntoIndividualSegments() {
        let prepared = prepareWithSegments("\u{20000}\u{20001}", font: font)

        XCTAssertEqual(prepared.segments, ["\u{20000}", "\u{20001}"])
    }
}
