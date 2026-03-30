import XCTest
@testable import Pretext

final class LineBreakerTests: XCTestCase {
    func testLayoutNextLineBreaksAtSpaceBoundary() {
        var prepared = PreparedText(
            widths: [5, 1, 5],
            lineEndFitAdvances: [5, 0, 5],
            lineEndPaintAdvances: [5, 0, 5],
            kinds: [.text, .space, .text],
            simpleLineWalkFastPath: true,
            breakableSegments: [false, false, false],
            breakableWidths: [nil, nil, nil],
            breakablePrefixWidths: [nil, nil, nil],
            maxBreakableWidth: 0,
            discretionaryHyphenWidth: 0,
            tabStopAdvance: 8,
            chunks: [PreparedLineChunk(startSegmentIndex: 0, endSegmentIndex: 3, consumedEndSegmentIndex: 3)],
            segments: ["hello", " ", "world"],
        )

        let firstLine = layoutNextLine(&prepared, start: .start, maxWidth: 5)
        XCTAssertEqual(firstLine?.text, "hello ")
        XCTAssertEqual(firstLine?.end, LayoutCursor(segmentIndex: 2, graphemeIndex: 0))

        let secondLine = layoutNextLine(&prepared, start: firstLine!.end, maxWidth: 5)
        XCTAssertEqual(secondLine?.text, "world")
    }

    func testLayoutNextLineBreaksInsideLongWordByGrapheme() {
        var prepared = PreparedText(
            widths: [6],
            lineEndFitAdvances: [6],
            lineEndPaintAdvances: [6],
            kinds: [.text],
            simpleLineWalkFastPath: true,
            breakableSegments: [false],
            breakableWidths: [[1, 1, 1, 1, 1, 1]],
            breakablePrefixWidths: [[1, 2, 3, 4, 5, 6]],
            maxBreakableWidth: 0,
            discretionaryHyphenWidth: 0,
            tabStopAdvance: 8,
            chunks: [PreparedLineChunk(startSegmentIndex: 0, endSegmentIndex: 1, consumedEndSegmentIndex: 1)],
            segments: ["abcdef"],
        )

        let firstLine = layoutNextLine(&prepared, start: .start, maxWidth: 3)
        XCTAssertEqual(firstLine?.text, "abc")
        XCTAssertEqual(firstLine?.end, LayoutCursor(segmentIndex: 0, graphemeIndex: 3))

        let secondLine = layoutNextLine(&prepared, start: firstLine!.end, maxWidth: 3)
        XCTAssertEqual(secondLine?.text, "def")
    }
}
