import CoreText
import Foundation
import SwiftUI

// MARK: - Test 1: Batch Prepare + Layout (500 texts x 1 width)

func runBatchPrepareAndLayout() -> BenchmarkResult {
    let texts = BenchmarkCorpus.texts
    let font = BenchmarkCorpus.font
    let width = BenchmarkCorpus.testWidth
    let lineHeight = BenchmarkCorpus.lineHeight
    let displayFont = OrbEditorialMetrics.bodyFontDescriptor.makeDisplayFont()

    // Pretext: prepare + layout for each text
    let pretextMs = measureMedian {
        PrepareProfile.reset()
        for text in texts {
            var prepared = prepare(text, font: font)
            _ = layout(&prepared, maxWidth: width, lineHeight: lineHeight)
        }
        let msg = PrepareProfile.summary() + "\n" + AnalysisSubProfile.summary() + "\n"
        AnalysisSubProfile.reset()
        if let data = msg.data(using: .utf8) {
            let handle = FileHandle(forWritingAtPath: "/tmp/pretext-profile.log")
                ?? { FileManager.default.createFile(atPath: "/tmp/pretext-profile.log", contents: nil); return FileHandle(forWritingAtPath: "/tmp/pretext-profile.log")! }()
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    // Core Text: CTFramesetter for each text
    let coreTextMs = measureMedian {
        for text in texts {
            _ = coreTextMeasureHeight(text: text, font: font, width: width)
        }
    }

    // SwiftUI: NSHostingView + fittingSize for each text
    let swiftUIMs = measureMedianMainActor {
        for text in texts {
            _ = swiftUIMeasureHeight(text: text, font: displayFont, width: width)
        }
    }

    return BenchmarkResult(
        name: "Batch Prepare + Layout (500 texts)",
        pretextMs: pretextMs,
        coreTextMs: coreTextMs,
        swiftUIMs: swiftUIMs,
        speedupVsCoreText: coreTextMs / max(pretextMs, 0.001),
        speedupVsSwiftUI: swiftUIMs / max(pretextMs, 0.001)
    )
}

// MARK: - Test 2: Reflow at 100 Different Widths (500 x 100 = 50,000 calls)

func runReflowAtDifferentWidths() -> BenchmarkResult {
    let texts = BenchmarkCorpus.texts
    let font = BenchmarkCorpus.font
    let lineHeight = BenchmarkCorpus.lineHeight
    let displayFont = OrbEditorialMetrics.bodyFontDescriptor.makeDisplayFont()
    let widths = (0..<100).map { 200.0 + Double($0) * 6.0 }

    // Prepare once (excluded from timing)
    var prepared = texts.map { prepare($0, font: font) }
    let framesetters = texts.map { coreTextCreateFramesetter(text: $0, font: font) }

    // Pretext: layout() is pure arithmetic
    let pretextMs = measureMedian {
        for width in widths {
            for index in prepared.indices {
                _ = layout(&prepared[index], maxWidth: width, lineHeight: lineHeight)
            }
        }
    }

    // Core Text: CTFramesetterSuggestFrameSizeWithConstraints at each width
    let coreTextMs = measureMedian {
        for width in widths {
            for fs in framesetters {
                _ = coreTextMeasureHeightWithFramesetter(fs, width: width)
            }
        }
    }

    // SwiftUI: create hosting views once, update width each time
    let swiftUIMs = measureMedianMainActor {
        // SwiftUI is so slow at this scale that we test 500 x 10 widths instead
        let sampleWidths = Array(widths.prefix(10))
        for width in sampleWidths {
            for text in texts {
                _ = swiftUIMeasureHeight(text: text, font: displayFont, width: width)
            }
        }
    }
    // Scale up to match 100 widths for fair comparison
    let swiftUIScaled = swiftUIMs * 10.0

    return BenchmarkResult(
        name: "Reflow 100 Widths (50k calls)",
        pretextMs: pretextMs,
        coreTextMs: coreTextMs,
        swiftUIMs: swiftUIScaled,
        speedupVsCoreText: coreTextMs / max(pretextMs, 0.001),
        speedupVsSwiftUI: swiftUIScaled / max(pretextMs, 0.001)
    )
}

// MARK: - Test 3: Variable-Width Line-by-Line (editorial engine scenario)

func runVariableWidthLineByLine() -> BenchmarkResult {
    let text = OrbEditorialText.body
    let font = BenchmarkCorpus.font

    // Generate 200 random widths between 150 and 500
    var widths: [Double] = []
    var seed: UInt64 = 42
    for _ in 0..<200 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let fraction = Double(seed >> 33) / Double(UInt32.max)
        widths.append(150.0 + fraction * 350.0)
    }

    // Pretext: prepareWithSegments + layoutNextLine in a loop
    var preparedSegments = prepareWithSegments(text, font: font)

    let pretextMs = measureMedian {
        var cursor = LayoutCursor.start
        var widthIndex = 0
        while true {
            let width = widths[widthIndex % widths.count]
            guard let line = layoutNextLine(&preparedSegments, start: cursor, maxWidth: width) else { break }
            if line.end == cursor { break }
            cursor = line.end
            widthIndex += 1
        }
    }

    // Core Text: CTTypesetter line-by-line
    let (typesetter, attrStr) = coreTextCreateTypesetter(text: text, font: font)
    let length = attrStr.length

    let coreTextMs = measureMedian {
        _ = coreTextLayoutLineByLine(typesetter: typesetter, length: length, widths: widths)
    }

    return BenchmarkResult(
        name: "Variable-Width Line-by-Line",
        pretextMs: pretextMs,
        coreTextMs: coreTextMs,
        swiftUIMs: nil,
        speedupVsCoreText: coreTextMs / max(pretextMs, 0.001),
        speedupVsSwiftUI: nil
    )
}

// MARK: - Test 4: Interleaved Measure-Mutate (layout thrashing)

func runInterleavedMeasureMutate() -> BenchmarkResult {
    let texts = BenchmarkCorpus.texts
    let font = BenchmarkCorpus.font
    let lineHeight = BenchmarkCorpus.lineHeight
    let width = BenchmarkCorpus.testWidth
    let displayFont = OrbEditorialMetrics.bodyFontDescriptor.makeDisplayFont()

    // Pretext: layout() interleaved with re-prepare (simulating mutation)
    // Even if the "source" changes, each prepare+layout pair is independent
    let pretextMs = measureMedian {
        for i in 0..<500 {
            let text = texts[i % texts.count]
            var prepared = prepare(text, font: font)
            _ = layout(&prepared, maxWidth: width, lineHeight: lineHeight)
        }
    }

    // Core Text: alternate between creating framesetter and measuring
    let coreTextMs = measureMedian {
        for i in 0..<500 {
            let text = texts[i % texts.count]
            let framesetter = coreTextCreateFramesetter(text: text, font: font)
            _ = coreTextMeasureHeightWithFramesetter(framesetter, width: width)
        }
    }

    // SwiftUI: create new hosting view each time (simulating content change + measure)
    let swiftUIMs = measureMedianMainActor {
        for i in 0..<500 {
            let text = texts[i % texts.count]
            _ = swiftUIMeasureHeight(text: text, font: displayFont, width: width)
        }
    }

    return BenchmarkResult(
        name: "Interleaved Measure-Mutate (500x)",
        pretextMs: pretextMs,
        coreTextMs: coreTextMs,
        swiftUIMs: swiftUIMs,
        speedupVsCoreText: coreTextMs / max(pretextMs, 0.001),
        speedupVsSwiftUI: swiftUIMs / max(pretextMs, 0.001)
    )
}

// MARK: - Test 5: Breakeven — at what reflow count does Pretext win?

struct BreakevenResult: Equatable {
    var prepareMs: Double
    var coreTextFirstMs: Double
    var pretextReflowPerCallMs: Double
    var coreTextReflowPerCallMs: Double
    var breakevenReflows: Int
}

func runBreakevenAnalysis() -> (BenchmarkResult, BreakevenResult) {
    let texts = BenchmarkCorpus.texts
    let font = BenchmarkCorpus.font
    let lineHeight = BenchmarkCorpus.lineHeight
    let width = BenchmarkCorpus.testWidth

    // Measure prepare() cost alone (500 texts)
    let prepareMs = measureMedian {
        for text in texts {
            _ = prepare(text, font: font)
        }
    }

    // Measure Core Text first-time cost (500 texts)
    let coreTextFirstMs = measureMedian {
        for text in texts {
            _ = coreTextMeasureHeight(text: text, font: font, width: width)
        }
    }

    // Prepare all texts once, then measure reflow cost per width-change
    var prepared = texts.map { prepare($0, font: font) }
    let framesetters = texts.map { coreTextCreateFramesetter(text: $0, font: font) }

    // Pretext reflow: 500 texts x 1 width
    let pretextReflowMs = measureMedian {
        for index in prepared.indices {
            _ = layout(&prepared[index], maxWidth: width * 0.75, lineHeight: lineHeight)
        }
    }

    // Core Text reflow: 500 texts x 1 width
    let coreTextReflowMs = measureMedian {
        for fs in framesetters {
            _ = coreTextMeasureHeightWithFramesetter(fs, width: width * 0.75)
        }
    }

    // Breakeven: prepare + N * pretextReflow = coreTextFirst + N * coreTextReflow
    // N = (prepare - coreTextFirst) / (coreTextReflow - pretextReflow)
    let reflowAdvantage = coreTextReflowMs - pretextReflowMs
    let prepareOverhead = prepareMs - coreTextFirstMs
    let breakevenN: Int
    if reflowAdvantage > 0.001 {
        breakevenN = max(1, Int(ceil(prepareOverhead / reflowAdvantage)))
    } else {
        breakevenN = 0 // Pretext is always faster or equal
    }

    let breakeven = BreakevenResult(
        prepareMs: prepareMs,
        coreTextFirstMs: coreTextFirstMs,
        pretextReflowPerCallMs: pretextReflowMs,
        coreTextReflowPerCallMs: coreTextReflowMs,
        breakevenReflows: breakevenN
    )

    let result = BenchmarkResult(
        name: "Breakeven: \(breakevenN) reflows",
        pretextMs: prepareMs + Double(breakevenN) * pretextReflowMs,
        coreTextMs: coreTextFirstMs + Double(breakevenN) * coreTextReflowMs,
        swiftUIMs: nil,
        speedupVsCoreText: 1.0,
        speedupVsSwiftUI: nil
    )

    return (result, breakeven)
}

// MARK: - Main actor helper

/// Runs a closure on the main actor and returns measured median time.
func measureMedianMainActor(warmup: Int = 1, iterations: Int = 5, _ body: @MainActor @Sendable () -> Void) -> Double {
    var times: [Double] = []

    // Warmup
    for _ in 0..<warmup {
        DispatchQueue.main.sync { body() }
    }

    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.sync { body() }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        times.append(elapsed)
    }

    times.sort()
    return times[times.count / 2]
}
