import CoreText
import Foundation

/// Accumulated profiling data for `prepare()`. Reset before each benchmark run.
public enum PrepareProfile {
    nonisolated(unsafe) public static var analysisMs: Double = 0
    nonisolated(unsafe) public static var batchMeasureMs: Double = 0
    nonisolated(unsafe) public static var graphemeMs: Double = 0
    nonisolated(unsafe) public static var buildMs: Double = 0
    nonisolated(unsafe) public static var callCount: Int = 0

    public static func reset() { analysisMs = 0; batchMeasureMs = 0; graphemeMs = 0; buildMs = 0; callCount = 0 }
    public static func summary() -> String {
        "prepare() x\(callCount): analysis=\(String(format:"%.1f",analysisMs))ms batch=\(String(format:"%.1f",batchMeasureMs))ms grapheme=\(String(format:"%.1f",graphemeMs))ms build=\(String(format:"%.1f",buildMs))ms"
    }
}

public func prepare(_ text: String, font: CTFont, whiteSpace: WhiteSpaceMode = .normal) -> PreparedText {
    prepareInternal(text, font: font, whiteSpace: whiteSpace, exposeRichSegments: false)
}

public func prepareWithSegments(_ text: String, font: CTFont, whiteSpace: WhiteSpaceMode = .normal) -> PreparedText {
    prepareInternal(text, font: font, whiteSpace: whiteSpace, exposeRichSegments: true)
}

private func prepareInternal(
    _ text: String,
    font: CTFont,
    whiteSpace: WhiteSpaceMode,
    exposeRichSegments: Bool
) -> PreparedText {
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

    if !exposeRichSegments, analysis.directPreparedLayout {
        let (prepared, batchMs, buildMs) = prepareDirectLayout(analysis: analysis, font: font)
        PrepareProfile.analysisMs += (t1 - t0) * 1000
        PrepareProfile.batchMeasureMs += batchMs
        PrepareProfile.buildMs += buildMs
        PrepareProfile.callCount += 1
        return prepared
    }

    let measurer = TextMeasurer.shared
    let profile = engineProfile()
    let discretionaryHyphenWidth = measurer.measureSegment("-", font: font)
    let spaceWidth = measurer.measureSegment(" ", font: font)
    let tabStopAdvance = spaceWidth * 8
    var widths: [Double] = []
    var lineEndFitAdvances: [Double] = []
    var lineEndPaintAdvances: [Double] = []
    var engineKinds: [SegmentBreakKind] = []
    var engineSegments: [String] = []
    var breakableSegments: [Bool] = []
    var breakableWidths: [[Double]?] = []
    var breakablePrefixWidths: [[Double]?] = []
    var maxBreakableWidth = 0.0
    var simpleLineWalkFastPath = analysis.chunks.count <= 1
    var preparedStartByAnalysisIndex = Array(repeating: 0, count: analysis.segments.count + 1)
    let hasCJKSegments = analysis.segments.indices.contains {
        analysis.kinds[$0] == .text && containsCJK(analysis.segments[$0])
    }
    let measuredWidths = hasCJKSegments
        ? nil
        : measurer.batchMeasureWidths(for: analysis.segments, in: analysis.normalized, font: font)

    func pushMeasuredSegment(
        text: String,
        width: Double,
        lineEndFitAdvance: Double,
        lineEndPaintAdvance: Double,
        kind: SegmentBreakKind,
        isWordLike: Bool
    ) {
        if kind != .text, kind != .space, kind != .zeroWidthBreak {
            simpleLineWalkFastPath = false
        }
        widths.append(width)
        lineEndFitAdvances.append(lineEndFitAdvance)
        lineEndPaintAdvances.append(lineEndPaintAdvance)
        engineKinds.append(kind)
        engineSegments.append(text)

        let breakable = kind == .text && isWordLike && text.count > 1
        breakableSegments.append(breakable)
        breakableWidths.append(nil)
        breakablePrefixWidths.append(nil)
        if breakable {
            maxBreakableWidth = max(maxBreakableWidth, width)
        }
    }

    for analysisIndex in analysis.segments.indices {
        preparedStartByAnalysisIndex[analysisIndex] = engineSegments.count

        let segmentText = analysis.segments[analysisIndex]
        let segmentKind = analysis.kinds[analysisIndex]
        let segmentWordLike = analysis.wordLike[analysisIndex]

        if segmentKind == .softHyphen {
            pushMeasuredSegment(
                text: segmentText,
                width: 0,
                lineEndFitAdvance: discretionaryHyphenWidth,
                lineEndPaintAdvance: discretionaryHyphenWidth,
                kind: .softHyphen,
                isWordLike: false
            )
            continue
        }

        if segmentKind == .hardBreak || segmentKind == .tab {
            pushMeasuredSegment(
                text: segmentText,
                width: 0,
                lineEndFitAdvance: 0,
                lineEndPaintAdvance: 0,
                kind: segmentKind,
                isWordLike: false
            )
            continue
        }

        if segmentKind == .text, containsCJK(segmentText) {
            var currentUnit = ""

            for grapheme in segmentText.graphemeStrings {
                if currentUnit.isEmpty {
                    currentUnit = grapheme
                    continue
                }

                if
                    kinsokuEnd.contains(currentUnit) ||
                    kinsokuStart.contains(grapheme) ||
                    leftStickyPunctuation.contains(grapheme) ||
                    (profile.carryCJKAfterClosingQuote && containsCJK(grapheme) && endsWithClosingQuote(currentUnit))
                {
                    currentUnit += grapheme
                    continue
                }

                let width = measurer.measureSegment(currentUnit, font: font)
                pushMeasuredSegment(
                    text: currentUnit,
                    width: width,
                    lineEndFitAdvance: width,
                    lineEndPaintAdvance: width,
                    kind: .text,
                    isWordLike: segmentWordLike
                )
                currentUnit = grapheme
            }

            if !currentUnit.isEmpty {
                let width = measurer.measureSegment(currentUnit, font: font)
                pushMeasuredSegment(
                    text: currentUnit,
                    width: width,
                    lineEndFitAdvance: width,
                    lineEndPaintAdvance: width,
                    kind: .text,
                    isWordLike: segmentWordLike
                )
            }
            continue
        }

        let width = measuredWidths?[analysisIndex] ?? measurer.measureSegment(segmentText, font: font)
        let fitAdvance: Double = (segmentKind == .space || segmentKind == .preservedSpace || segmentKind == .zeroWidthBreak) ? 0 : width
        let paintAdvance: Double = (segmentKind == .space || segmentKind == .zeroWidthBreak) ? 0 : width
        pushMeasuredSegment(
            text: segmentText,
            width: width,
            lineEndFitAdvance: fitAdvance,
            lineEndPaintAdvance: paintAdvance,
            kind: segmentKind,
            isWordLike: segmentWordLike
        )
    }
    preparedStartByAnalysisIndex[analysis.segments.count] = engineSegments.count
    let t2 = CFAbsoluteTimeGetCurrent()

    if simpleLineWalkFastPath {
        lineEndFitAdvances = []
        lineEndPaintAdvances = []
    }

    let chunks = analysis.chunks.map { chunk in
        PreparedLineChunk(
            startSegmentIndex: preparedStartByAnalysisIndex[chunk.startSegmentIndex],
            endSegmentIndex: preparedStartByAnalysisIndex[chunk.endSegmentIndex],
            consumedEndSegmentIndex: preparedStartByAnalysisIndex[chunk.consumedEndSegmentIndex]
        )
    }

    let (displaySegments, displayKinds): ([String], [SegmentBreakKind]) = exposeRichSegments
        ? (engineSegments, engineKinds)
        : coarsenDisplaySegments(segments: engineSegments, kinds: engineKinds)

    let t3 = CFAbsoluteTimeGetCurrent()
    PrepareProfile.analysisMs += (t1 - t0) * 1000
    PrepareProfile.batchMeasureMs += (t2 - t1) * 1000
    PrepareProfile.buildMs += (t3 - t2) * 1000
    PrepareProfile.callCount += 1

    return PreparedText(
        widths: widths,
        lineEndFitAdvances: lineEndFitAdvances,
        lineEndPaintAdvances: lineEndPaintAdvances,
        kinds: displayKinds,
        simpleLineWalkFastPath: simpleLineWalkFastPath,
        breakableSegments: breakableSegments,
        breakableWidths: breakableWidths,
        breakablePrefixWidths: breakablePrefixWidths,
        maxBreakableWidth: maxBreakableWidth,
        discretionaryHyphenWidth: discretionaryHyphenWidth,
        tabStopAdvance: tabStopAdvance,
        chunks: chunks,
        segments: displaySegments,
        font: font,
        engineKinds: engineKinds,
        engineSegments: engineSegments
    )
}

private func prepareDirectLayout(analysis: TextAnalysisResult, font: CTFont) -> (PreparedText, Double, Double) {
    let measurer = TextMeasurer.shared
    let t0 = CFAbsoluteTimeGetCurrent()
    let discretionaryHyphenWidth = measurer.measureSegment("-", font: font)
    let spaceWidth = measurer.measureSegment(" ", font: font)
    let tabStopAdvance = spaceWidth * 8
    let measuredWidths = measurer.batchMeasureWidths(for: analysis.segments, in: analysis.normalized, font: font)
    let t1 = CFAbsoluteTimeGetCurrent()

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
            if kinds[index] == .text, analysis.wordLike[index], analysis.segments[index].count > 1 {
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

                if kind == .text, isWordLike, analysis.segments[index].count > 1 {
                    breakableSegments[index] = true
                    maxBreakableWidth = max(maxBreakableWidth, width)
                }
            }
        }
    }

    let prepared = PreparedText(
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
    let t2 = CFAbsoluteTimeGetCurrent()
    return (prepared, (t1 - t0) * 1000, (t2 - t1) * 1000)
}

public func prepareForWidth(_ prepared: inout PreparedText, maxWidth: Double) {
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

        let segment = prepared.layoutSegments[index]
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

private func coarsenDisplaySegments(
    segments: [String],
    kinds: [SegmentBreakKind]
) -> ([String], [SegmentBreakKind]) {
    var displaySegments: [String] = []
    var displayKinds: [SegmentBreakKind] = []

    for (segment, kind) in zip(segments, kinds) {
        guard kind == .text else {
            displaySegments.append(segment)
            displayKinds.append(kind)
            continue
        }

        var currentText = ""
        for character in segment {
            let text = String(character)
            if text == "\u{00A0}" || text == "\u{202F}" || text == "\u{2060}" || text == "\u{FEFF}" {
                if !currentText.isEmpty {
                    displaySegments.append(currentText)
                    displayKinds.append(.text)
                    currentText = ""
                }
                displaySegments.append(text)
                displayKinds.append(.glue)
            } else {
                currentText += text
            }
        }

        if !currentText.isEmpty {
            displaySegments.append(currentText)
            displayKinds.append(.text)
        }
    }

    return (displaySegments, displayKinds)
}

public func layout(_ prepared: inout PreparedText, maxWidth: Double, lineHeight: Double) -> LayoutResult {
    prepareForWidth(&prepared, maxWidth: maxWidth)
    let lineCount = countPreparedLines(prepared, maxWidth: maxWidth)
    return LayoutResult(height: Double(lineCount) * lineHeight, lineCount: lineCount)
}

public func layout(_ prepared: PreparedText, maxWidth: Double, lineHeight: Double) -> LayoutResult {
    var prepared = prepared
    return layout(&prepared, maxWidth: maxWidth, lineHeight: lineHeight)
}

public func walkLineRanges(
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

public func walkLineRanges(
    _ prepared: PreparedText,
    maxWidth: Double,
    onLine: @escaping (Double, LayoutCursor, LayoutCursor) -> Void
) {
    var prepared = prepared
    walkLineRanges(&prepared, maxWidth: maxWidth, onLine: onLine)
}

public func layoutNextLine(_ prepared: inout PreparedText, start: LayoutCursor, maxWidth: Double) -> LayoutLine? {
    prepareForWidth(&prepared, maxWidth: maxWidth)
    guard let range = layoutNextLineRange(prepared, start: start, maxWidth: maxWidth) else {
        return nil
    }
    var cache: [Int: [String]] = [:]
    return materializeLayoutLine(prepared, range: range, cache: &cache)
}

public func layoutNextLine(_ prepared: PreparedText, start: LayoutCursor, maxWidth: Double) -> LayoutLine? {
    var prepared = prepared
    return layoutNextLine(&prepared, start: start, maxWidth: maxWidth)
}

public func layoutWithLines(_ prepared: inout PreparedText, maxWidth: Double, lineHeight: Double) -> (LayoutResult, [LayoutLine]) {
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

public func layoutWithLines(_ prepared: PreparedText, maxWidth: Double, lineHeight: Double) -> (LayoutResult, [LayoutLine]) {
    var prepared = prepared
    return layoutWithLines(&prepared, maxWidth: maxWidth, lineHeight: lineHeight)
}

public func clearCache() {
    TextMeasurer.shared.clearCache()
}

public func setLocale(_ locale: Locale?) {
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
        prepared.layoutKinds[endSegmentIndex - 1] == .softHyphen &&
        !(startSegmentIndex == endSegmentIndex && startGraphemeIndex > 0)
    )

    for index in startSegmentIndex..<endSegmentIndex {
        let kind = prepared.layoutKinds[index]
        if kind == .softHyphen || kind == .hardBreak {
            continue
        }

        if index == startSegmentIndex, startGraphemeIndex > 0 {
            text += graphemes(for: index, in: prepared, cache: &cache).dropFirst(startGraphemeIndex).joined()
        } else {
            text += prepared.layoutSegments[index]
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
    let value = prepared.layoutSegments[segmentIndex].graphemeStrings
    cache[segmentIndex] = value
    return value
}
