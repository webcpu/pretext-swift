import CoreText
import Foundation

/// Accumulated profiling data for `prepare()`. Reset before each benchmark run.
enum PrepareProfile {
    nonisolated(unsafe) static var analysisMs: Double = 0
    nonisolated(unsafe) static var batchMeasureMs: Double = 0
    nonisolated(unsafe) static var graphemeMs: Double = 0
    nonisolated(unsafe) static var buildMs: Double = 0
    nonisolated(unsafe) static var callCount: Int = 0

    static func reset() { analysisMs = 0; batchMeasureMs = 0; graphemeMs = 0; buildMs = 0; callCount = 0 }
    static func summary() -> String {
        "prepare() x\(callCount): analysis=\(String(format:"%.1f",analysisMs))ms batch=\(String(format:"%.1f",batchMeasureMs))ms grapheme=\(String(format:"%.1f",graphemeMs))ms build=\(String(format:"%.1f",buildMs))ms"
    }
}

func prepare(_ text: String, font: CTFont, whiteSpace: WhiteSpaceMode = .normal) -> PreparedText {
    let t0 = CFAbsoluteTimeGetCurrent()
    let analysis = analyzeText(text, whiteSpace: whiteSpace)
    let t1 = CFAbsoluteTimeGetCurrent()
    guard !analysis.isEmpty else {
        return PreparedText(
            widths: [],
            lineEndFitAdvances: [],
            lineEndPaintAdvances: [],
            kinds: [],
            simpleLineWalkFastPath: true,
            breakableSegments: [],
            breakableWidths: [],
            breakablePrefixWidths: [],
            maxBreakableWidth: 0,
            discretionaryHyphenWidth: 0,
            tabStopAdvance: 0,
            chunks: [],
            segments: []
        )
    }

    let measurer = TextMeasurer.shared
    let discretionaryHyphenWidth = measurer.measureSegment("-", font: font)
    let spaceWidth = measurer.measureSegment(" ", font: font)
    let tabStopAdvance = spaceWidth * 8
    let measuredWidths = measurer.batchMeasureWidths(for: analysis.segments, in: analysis.normalized, font: font)
    let t2 = CFAbsoluteTimeGetCurrent()

    let segmentCount = analysis.segments.count
    let kinds = analysis.kinds
    var widths = [Double](repeating: 0, count: segmentCount)
    let simpleLineWalkFastPath = analysis.chunks.count <= 1 && !kinds.contains {
        $0 != .text && $0 != .space && $0 != .zeroWidthBreak
    }
    var lineEndFitAdvances = simpleLineWalkFastPath ? [] : [Double](repeating: 0, count: segmentCount)
    var lineEndPaintAdvances = simpleLineWalkFastPath ? [] : [Double](repeating: 0, count: segmentCount)

    var breakableSegments = [Bool](repeating: false, count: segmentCount)
    let breakableWidths = [[Double]?](repeating: nil, count: segmentCount)
    let breakablePrefixWidths = [[Double]?](repeating: nil, count: segmentCount)
    var maxBreakableWidth = 0.0

    if simpleLineWalkFastPath {
        for index in analysis.segments.indices {
            let width = measuredWidths[index]
            widths[index] = width
            if kinds[index] == .text, analysis.wordLike[index] {
                breakableSegments[index] = true
                maxBreakableWidth = max(maxBreakableWidth, width)
            }
        }
    } else {
        for index in analysis.segments.indices {
            let kind = kinds[index]
            let isWordLike = analysis.wordLike[index]

            switch kind {
            case .softHyphen:
                lineEndFitAdvances[index] = discretionaryHyphenWidth
                lineEndPaintAdvances[index] = discretionaryHyphenWidth

            case .hardBreak, .tab:
                break

            default:
                let width = measuredWidths[index]
                let fitAdvance: Double = (kind == .space || kind == .preservedSpace || kind == .zeroWidthBreak) ? 0 : width
                let paintAdvance: Double = (kind == .space || kind == .zeroWidthBreak) ? 0 : width

                widths[index] = width
                lineEndFitAdvances[index] = fitAdvance
                lineEndPaintAdvances[index] = paintAdvance

                if kind == .text, isWordLike {
                    breakableSegments[index] = true
                    maxBreakableWidth = max(maxBreakableWidth, width)
                }
            }
        }
    }

    let t3 = CFAbsoluteTimeGetCurrent()
    PrepareProfile.analysisMs += (t1 - t0) * 1000
    PrepareProfile.batchMeasureMs += (t2 - t1) * 1000
    PrepareProfile.buildMs += (t3 - t2) * 1000
    PrepareProfile.callCount += 1

    return PreparedText(
        widths: widths,
        lineEndFitAdvances: lineEndFitAdvances,
        lineEndPaintAdvances: lineEndPaintAdvances,
        kinds: kinds,
        simpleLineWalkFastPath: simpleLineWalkFastPath,
        breakableSegments: breakableSegments,
        breakableWidths: breakableWidths,
        breakablePrefixWidths: breakablePrefixWidths,
        maxBreakableWidth: maxBreakableWidth,
        discretionaryHyphenWidth: discretionaryHyphenWidth,
        tabStopAdvance: tabStopAdvance,
        chunks: analysis.chunks,
        segments: analysis.segments,
        font: font
    )
}

func prepareWithSegments(_ text: String, font: CTFont, whiteSpace: WhiteSpaceMode = .normal) -> PreparedText {
    prepare(text, font: font, whiteSpace: whiteSpace)
}

func prepareForWidth(_ prepared: inout PreparedText, maxWidth: Double) {
    guard prepared.maxBreakableWidth > maxWidth else {
        return
    }
    guard let font = prepared.font else {
        return
    }

    let measurer = TextMeasurer.shared
    let preferPrefixWidths = engineProfile().preferPrefixWidthsForBreakableRuns
    var resolvedAny = false

    for index in prepared.widths.indices {
        guard prepared.breakableSegments[index], prepared.widths[index] > maxWidth, prepared.breakableWidths[index] == nil else {
            continue
        }

        let segment = prepared.segments[index]
        prepared.breakableWidths[index] = measurer.graphemeWidths(for: segment, font: font)
        if preferPrefixWidths, prepared.breakableWidths[index] != nil {
            prepared.breakablePrefixWidths[index] = measurer.graphemePrefixWidths(for: segment, font: font)
        }
        prepared.breakableSegments[index] = false
        resolvedAny = true
    }

    guard resolvedAny else {
        return
    }

    var unresolvedMax = 0.0
    for index in prepared.widths.indices where prepared.breakableSegments[index] && prepared.breakableWidths[index] == nil {
        unresolvedMax = max(unresolvedMax, prepared.widths[index])
    }
    prepared.maxBreakableWidth = unresolvedMax
}

func layout(_ prepared: inout PreparedText, maxWidth: Double, lineHeight: Double) -> LayoutResult {
    prepareForWidth(&prepared, maxWidth: maxWidth)
    let lineCount = countPreparedLines(prepared, maxWidth: maxWidth)
    return LayoutResult(height: Double(lineCount) * lineHeight, lineCount: lineCount)
}

func layout(_ prepared: PreparedText, maxWidth: Double, lineHeight: Double) -> LayoutResult {
    var prepared = prepared
    return layout(&prepared, maxWidth: maxWidth, lineHeight: lineHeight)
}

func walkLineRanges(
    _ prepared: inout PreparedText,
    maxWidth: Double,
    onLine: @escaping (Double, LayoutCursor, LayoutCursor) -> Void
) {
    guard !prepared.isEmpty else {
        return
    }

    prepareForWidth(&prepared, maxWidth: maxWidth)
    _ = walkPreparedLines(prepared, maxWidth: maxWidth) { line in
        onLine(
            line.width,
            LayoutCursor(segmentIndex: line.startSegmentIndex, graphemeIndex: line.startGraphemeIndex),
            LayoutCursor(segmentIndex: line.endSegmentIndex, graphemeIndex: line.endGraphemeIndex)
        )
    }
}

func walkLineRanges(
    _ prepared: PreparedText,
    maxWidth: Double,
    onLine: @escaping (Double, LayoutCursor, LayoutCursor) -> Void
) {
    var prepared = prepared
    walkLineRanges(&prepared, maxWidth: maxWidth, onLine: onLine)
}

func layoutNextLine(_ prepared: inout PreparedText, start: LayoutCursor, maxWidth: Double) -> LayoutLine? {
    prepareForWidth(&prepared, maxWidth: maxWidth)
    guard let range = layoutNextLineRange(prepared, start: start, maxWidth: maxWidth) else {
        return nil
    }
    var cache: [Int: [String]] = [:]
    return materializeLayoutLine(prepared, range: range, cache: &cache)
}

func layoutNextLine(_ prepared: PreparedText, start: LayoutCursor, maxWidth: Double) -> LayoutLine? {
    var prepared = prepared
    return layoutNextLine(&prepared, start: start, maxWidth: maxWidth)
}

func layoutWithLines(_ prepared: inout PreparedText, maxWidth: Double, lineHeight: Double) -> (LayoutResult, [LayoutLine]) {
    guard !prepared.isEmpty else {
        return (LayoutResult(height: 0, lineCount: 0), [])
    }

    prepareForWidth(&prepared, maxWidth: maxWidth)
    let preparedSnapshot = prepared
    var lines: [LayoutLine] = []
    var graphemeCache: [Int: [String]] = [:]
    let lineCount = walkPreparedLines(preparedSnapshot, maxWidth: maxWidth) { line in
        lines.append(materializeLayoutLine(preparedSnapshot, range: line, cache: &graphemeCache))
    }
    let result = LayoutResult(height: Double(lineCount) * lineHeight, lineCount: lineCount)
    return (result, lines)
}

func layoutWithLines(_ prepared: PreparedText, maxWidth: Double, lineHeight: Double) -> (LayoutResult, [LayoutLine]) {
    var prepared = prepared
    return layoutWithLines(&prepared, maxWidth: maxWidth, lineHeight: lineHeight)
}

func clearCache() {
    TextMeasurer.shared.clearCache()
}

func setLocale(_ locale: Locale?) {
    setAnalysisLocale(locale)
    clearCache()
}

private func materializeLayoutLine(
    _ prepared: PreparedText,
    range: InternalLayoutLine,
    cache: inout [Int: [String]]
) -> LayoutLine {
    return LayoutLine(
        text: buildLineText(
            prepared,
            startSegmentIndex: range.startSegmentIndex,
            startGraphemeIndex: range.startGraphemeIndex,
            endSegmentIndex: range.endSegmentIndex,
            endGraphemeIndex: range.endGraphemeIndex,
            cache: &cache
        ),
        width: range.width,
        start: LayoutCursor(segmentIndex: range.startSegmentIndex, graphemeIndex: range.startGraphemeIndex),
        end: LayoutCursor(segmentIndex: range.endSegmentIndex, graphemeIndex: range.endGraphemeIndex)
    )
}

private func buildLineText(
    _ prepared: PreparedText,
    startSegmentIndex: Int,
    startGraphemeIndex: Int,
    endSegmentIndex: Int,
    endGraphemeIndex: Int,
    cache: inout [Int: [String]]
) -> String {
    var text = ""
    let endsWithDiscretionaryHyphen = (
        endSegmentIndex > 0 &&
        prepared.kinds[endSegmentIndex - 1] == .softHyphen &&
        !(startSegmentIndex == endSegmentIndex && startGraphemeIndex > 0)
    )

    for index in startSegmentIndex..<endSegmentIndex {
        let kind = prepared.kinds[index]
        if kind == .softHyphen || kind == .hardBreak {
            continue
        }

        if index == startSegmentIndex, startGraphemeIndex > 0 {
            text += graphemes(for: index, in: prepared, cache: &cache).dropFirst(startGraphemeIndex).joined()
        } else {
            text += prepared.segments[index]
        }
    }

    if endGraphemeIndex > 0 {
        if endsWithDiscretionaryHyphen {
            text += "-"
        }
        let segmentIndex = endSegmentIndex
        let segmentGraphemes = graphemes(for: segmentIndex, in: prepared, cache: &cache)
        let lowerBound = startSegmentIndex == endSegmentIndex ? startGraphemeIndex : 0
        text += segmentGraphemes[lowerBound..<endGraphemeIndex].joined()
    } else if endsWithDiscretionaryHyphen {
        text += "-"
    }

    return text
}

private func graphemes(
    for segmentIndex: Int,
    in prepared: PreparedText,
    cache: inout [Int: [String]]
) -> [String] {
    if let existing = cache[segmentIndex] {
        return existing
    }
    let value = prepared.segments[segmentIndex].graphemeStrings
    cache[segmentIndex] = value
    return value
}
