import CoreText
import XCTest
@testable import PretextDemo

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

    func testCJKCharactersSplitIntoIndividualSegments() {
        let prepared = prepareWithSegments("中文测试", font: font)

        XCTAssertEqual(prepared.segments, ["中", "文", "测", "试"])
    }

    func testAstralCJKCharactersSplitIntoIndividualSegments() {
        let prepared = prepareWithSegments("\u{20000}\u{20001}", font: font)

        XCTAssertEqual(prepared.segments, ["\u{20000}", "\u{20001}"])
    }
}
