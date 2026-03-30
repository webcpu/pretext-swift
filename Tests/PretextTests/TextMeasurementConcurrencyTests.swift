@preconcurrency import CoreText
import Foundation
import XCTest
@testable import Pretext

final class TextMeasurementConcurrencyTests: XCTestCase {
    private final class WidthCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var widths: [Double] = []

        func reserveCapacity(_ capacity: Int) {
            lock.lock()
            defer { lock.unlock() }
            widths.reserveCapacity(capacity)
        }

        func append(_ width: Double) {
            lock.lock()
            defer { lock.unlock() }
            widths.append(width)
        }

        func snapshot() -> [Double] {
            lock.lock()
            defer { lock.unlock() }
            return widths
        }
    }

    func testSharedTextMeasurerStaysConsistentUnderConcurrentPrepareAndMeasure() {
        let fontName = "Helvetica" as CFString
        let fontSize: CGFloat = 16
        let font = CTFontCreateWithName(fontName, fontSize, nil)
        let reference = "Illustrated manuscript"
        let expectedWidth = TextMeasurer.shared.measureSegment(reference, font: font)
        let queue = DispatchQueue(label: "TextMeasurementConcurrencyTests", attributes: .concurrent)
        let group = DispatchGroup()
        let measuredWidths = WidthCollector()
        measuredWidths.reserveCapacity(4_800)

        let samples = [
            "Illustrated manuscript text wraps around dragons and illuminated initials.",
            "Benchmarks should not race background text measurement against animated views.",
            "The quick brown fox jumps over the lazy dog while scribes annotate the margins.",
            "Punctuation-heavy content: hello, world! “Quotes”, dashes, and soft\u{00AD}hyphens.",
        ]

        TextMeasurer.shared.clearCache()

        for worker in 0..<12 {
            group.enter()
            queue.async {
                let workerFont = CTFontCreateWithName(fontName, fontSize, nil)
                for iteration in 0..<400 {
                    let sample = samples[(worker + iteration) % samples.count]
                    let prepared = prepare(sample, font: workerFont)
                    _ = layout(prepared, maxWidth: 180 + Double(iteration % 3) * 12, lineHeight: 20)

                    let width = TextMeasurer.shared.measureSegment(reference, font: workerFont)
                    measuredWidths.append(width)
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 15), .success)
        let snapshot = measuredWidths.snapshot()
        XCTAssertEqual(snapshot.count, 4_800)
        XCTAssertTrue(snapshot.allSatisfy { abs($0 - expectedWidth) < 0.001 })
    }
}
