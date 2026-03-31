import CoreText
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Timing

struct BenchmarkResult: Equatable, Identifiable {
    let id = UUID()
    var name: String
    var pretextMs: Double
    var coreTextMs: Double
    var swiftUIMs: Double?
    var speedupVsCoreText: Double
    var speedupVsSwiftUI: Double?
}

func measureMedian(warmup: Int = 1, iterations: Int = 5, _ body: () -> Void) -> Double {
    for _ in 0..<warmup { body() }
    var times: [Double] = []
    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        body()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        times.append(elapsed)
    }
    times.sort()
    return times[times.count / 2]
}

// MARK: - Core Text helpers

func coreTextMeasureHeight(text: String, font: CTFont, width: Double) -> Double {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let attrStr = NSAttributedString(string: text, attributes: attributes)
    let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
    let constraint = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraint, nil)
    return size.height
}

func coreTextCreateFramesetter(text: String, font: CTFont) -> CTFramesetter {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let attrStr = NSAttributedString(string: text, attributes: attributes)
    return CTFramesetterCreateWithAttributedString(attrStr)
}

func coreTextMeasureHeightWithFramesetter(_ framesetter: CTFramesetter, width: Double) -> Double {
    let constraint = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraint, nil)
    return size.height
}

func coreTextCreateTypesetter(text: String, font: CTFont) -> (CTTypesetter, NSAttributedString) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let attrStr = NSAttributedString(string: text, attributes: attributes)
    let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
    return (typesetter, attrStr)
}

func coreTextLayoutLineByLine(typesetter: CTTypesetter, length: Int, widths: [Double]) -> Int {
    var offset = 0
    var lineCount = 0
    var widthIndex = 0
    while offset < length {
        let width = widths[widthIndex % widths.count]
        let count = CTTypesetterSuggestLineBreak(typesetter, offset, width)
        if count == 0 { break }
        _ = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: count))
        offset += count
        lineCount += 1
        widthIndex += 1
    }
    return lineCount
}

// MARK: - SwiftUI helpers

@MainActor
func swiftUIMeasureHeight(text: String, font: Font, width: Double) -> Double {
    let view = Text(text).font(font).frame(width: width, alignment: .leading)

    #if os(macOS)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 10000)
    hostingView.layout()
    return hostingView.fittingSize.height
    #elseif os(iOS)
    let hostingController = UIHostingController(rootView: view)
    let bounds = CGRect(x: 0, y: 0, width: width, height: 10000)
    hostingController.view.bounds = bounds
    return hostingController.sizeThatFits(in: bounds.size).height
    #else
    return 0
    #endif
}

func measureSwiftUIBenchmark(
    warmup: Int = 1,
    iterations: Int = 5,
    _ body: @MainActor @Sendable () -> Void
) -> Double? {
    #if os(watchOS)
    nil
    #else
    measureMedianMainActor(warmup: warmup, iterations: iterations, body)
    #endif
}
