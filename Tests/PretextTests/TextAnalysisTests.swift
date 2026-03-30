import CoreText
import XCTest
@testable import Pretext

final class TextAnalysisTests: XCTestCase {
    func testBatchMeasureWidthsProducesConsistentResults() {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let analysis = analyzeText("Hello   world!", whiteSpace: .normal)
        let measurer = TextMeasurer.shared

        let widths1 = measurer.batchMeasureWidths(
            for: analysis.segments, in: analysis.normalized, font: font)
        let widths2 = measurer.batchMeasureWidths(
            for: analysis.segments, in: analysis.normalized, font: font)

        XCTAssertEqual(widths1, widths2)
        XCTAssertEqual(widths1.count, analysis.segments.count)
        XCTAssertTrue(widths1.allSatisfy { $0 >= 0 })
    }

    func testPrepareCollapsesWhitespaceAndMergesTrailingPunctuation() {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        let prepared = prepare("Hello   world!", font: font)

        XCTAssertEqual(prepared.segments, ["Hello", " ", "world!"])
        XCTAssertEqual(prepared.kinds, [.text, .space, .text])
        XCTAssertEqual(prepared.breakableSegments, [true, false, true])
        XCTAssertEqual(prepared.breakableWidths, [nil, nil, nil])
    }

    func testPrepareClassifiesGlueRuns() {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        let prepared = prepare("Hello\u{00A0}world", font: font)

        XCTAssertEqual(prepared.segments, ["Hello", "\u{00A0}", "world"])
        XCTAssertEqual(prepared.kinds, [.text, .glue, .text])
    }

    func testPrepareSkipsLineEndAdvanceArraysForSimpleFastPath() {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        let prepared = prepare("Hello world!", font: font)
        let (_, lines) = layoutWithLines(prepared, maxWidth: 10_000, lineHeight: 14)

        XCTAssertTrue(prepared.simpleLineWalkFastPath)
        XCTAssertEqual(prepared.lineEndFitAdvances, [])
        XCTAssertEqual(prepared.lineEndPaintAdvances, [])
        XCTAssertEqual(lines.map(\.text), ["Hello world!"])
    }
}
