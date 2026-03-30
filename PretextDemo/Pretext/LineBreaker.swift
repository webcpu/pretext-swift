import Foundation

private func canBreakAfter(_ kind: SegmentBreakKind) -> Bool {
    switch kind {
    case .space, .preservedSpace, .tab, .zeroWidthBreak, .softHyphen:
        return true
    default:
        return false
    }
}

private func isSimpleCollapsibleSpace(_ kind: SegmentBreakKind) -> Bool {
    kind == .space
}

private func getTabAdvance(lineWidth: Double, tabStopAdvance: Double) -> Double {
    guard tabStopAdvance > 0 else {
        return 0
    }

    let remainder = lineWidth.truncatingRemainder(dividingBy: tabStopAdvance)
    if abs(remainder) <= 1e-6 {
        return tabStopAdvance
    }
    return tabStopAdvance - remainder
}

private func getBreakableAdvance(
    graphemeWidths: [Double],
    graphemePrefixWidths: [Double]?,
    graphemeIndex: Int,
    preferPrefixWidths: Bool
) -> Double {
    guard preferPrefixWidths, let graphemePrefixWidths else {
        return graphemeWidths[graphemeIndex]
    }

    let previous = graphemeIndex > 0 ? graphemePrefixWidths[graphemeIndex - 1] : 0
    return graphemePrefixWidths[graphemeIndex] - previous
}

private func fitSoftHyphenBreak(
    graphemeWidths: [Double],
    initialWidth: Double,
    maxWidth: Double,
    lineFitEpsilon: Double,
    discretionaryHyphenWidth: Double,
    cumulativeWidths: Bool
) -> (fitCount: Int, fittedWidth: Double) {
    var fitCount = 0
    var fittedWidth = initialWidth

    while fitCount < graphemeWidths.count {
        let nextWidth = cumulativeWidths
            ? initialWidth + graphemeWidths[fitCount]
            : fittedWidth + graphemeWidths[fitCount]
        let nextLineWidth = fitCount + 1 < graphemeWidths.count
            ? nextWidth + discretionaryHyphenWidth
            : nextWidth
        if nextLineWidth > maxWidth + lineFitEpsilon {
            break
        }
        fittedWidth = nextWidth
        fitCount += 1
    }

    return (fitCount, fittedWidth)
}

private func findChunkIndexForStart(_ prepared: PreparedText, segmentIndex: Int) -> Int? {
    for (index, chunk) in prepared.chunks.enumerated() {
        if segmentIndex < chunk.consumedEndSegmentIndex {
            return index
        }
    }
    return nil
}

func normalizeLineStart(_ prepared: PreparedText, start: LayoutCursor) -> LayoutCursor? {
    var segmentIndex = start.segmentIndex
    let graphemeIndex = start.graphemeIndex

    guard segmentIndex < prepared.widths.count else {
        return nil
    }

    if graphemeIndex > 0 {
        return start
    }

    guard let chunkIndex = findChunkIndexForStart(prepared, segmentIndex: segmentIndex) else {
        return nil
    }

    let chunk = prepared.chunks[chunkIndex]
    if chunk.startSegmentIndex == chunk.endSegmentIndex, segmentIndex == chunk.startSegmentIndex {
        return LayoutCursor(segmentIndex: segmentIndex, graphemeIndex: 0)
    }

    if segmentIndex < chunk.startSegmentIndex {
        segmentIndex = chunk.startSegmentIndex
    }

    while segmentIndex < chunk.endSegmentIndex {
        let kind = prepared.kinds[segmentIndex]
        if kind != .space, kind != .zeroWidthBreak, kind != .softHyphen {
            return LayoutCursor(segmentIndex: segmentIndex, graphemeIndex: 0)
        }
        segmentIndex += 1
    }

    guard chunk.consumedEndSegmentIndex < prepared.widths.count else {
        return nil
    }

    return LayoutCursor(segmentIndex: chunk.consumedEndSegmentIndex, graphemeIndex: 0)
}

func countPreparedLines(_ prepared: PreparedText, maxWidth: Double) -> Int {
    if prepared.simpleLineWalkFastPath {
        return countPreparedLinesSimple(prepared, maxWidth: maxWidth)
    }
    return walkPreparedLines(prepared, maxWidth: maxWidth, onLine: nil)
}

private func countPreparedLinesSimple(_ prepared: PreparedText, maxWidth: Double) -> Int {
    let widths = prepared.widths
    let kinds = prepared.kinds
    let breakableWidths = prepared.breakableWidths
    let breakablePrefixWidths = prepared.breakablePrefixWidths

    guard !widths.isEmpty else {
        return 0
    }

    let profile = engineProfile()
    let epsilon = profile.lineFitEpsilon

    var lineCount = 0
    var lineWidth = 0.0
    var hasContent = false

    func placeOnFreshLine(segmentIndex: Int) {
        let width = widths[segmentIndex]
        if width > maxWidth, let graphemeWidths = breakableWidths[segmentIndex] {
            let graphemePrefixWidths = breakablePrefixWidths[segmentIndex]
            lineWidth = 0
            for graphemeIndex in graphemeWidths.indices {
                let advance = getBreakableAdvance(
                    graphemeWidths: graphemeWidths,
                    graphemePrefixWidths: graphemePrefixWidths,
                    graphemeIndex: graphemeIndex,
                    preferPrefixWidths: profile.preferPrefixWidthsForBreakableRuns
                )
                if lineWidth > 0, lineWidth + advance > maxWidth + epsilon {
                    lineCount += 1
                    lineWidth = advance
                } else {
                    if lineWidth == 0 {
                        lineCount += 1
                    }
                    lineWidth += advance
                }
            }
        } else {
            lineWidth = width
            lineCount += 1
        }
        hasContent = true
    }

    for index in widths.indices {
        let width = widths[index]
        let kind = kinds[index]

        if !hasContent {
            placeOnFreshLine(segmentIndex: index)
            continue
        }

        let newWidth = lineWidth + width
        if newWidth > maxWidth + epsilon {
            if isSimpleCollapsibleSpace(kind) {
                continue
            }
            lineWidth = 0
            hasContent = false
            placeOnFreshLine(segmentIndex: index)
            continue
        }

        lineWidth = newWidth
    }

    return hasContent ? lineCount : lineCount + 1
}

@discardableResult
private func walkPreparedLinesSimple(
    _ prepared: PreparedText,
    maxWidth: Double,
    onLine: ((InternalLayoutLine) -> Void)?
) -> Int {
    let widths = prepared.widths
    let kinds = prepared.kinds
    let breakableWidths = prepared.breakableWidths
    let breakablePrefixWidths = prepared.breakablePrefixWidths

    guard !widths.isEmpty else {
        return 0
    }

    let profile = engineProfile()
    let epsilon = profile.lineFitEpsilon

    var lineCount = 0
    var lineWidth = 0.0
    var hasContent = false
    var lineStartSegmentIndex = 0
    var lineStartGraphemeIndex = 0
    var lineEndSegmentIndex = 0
    var lineEndGraphemeIndex = 0
    var pendingBreakSegmentIndex = -1
    var pendingBreakPaintWidth = 0.0

    func clearPendingBreak() {
        pendingBreakSegmentIndex = -1
        pendingBreakPaintWidth = 0
    }

    func emitCurrentLine(
        endSegmentIndex: Int = lineEndSegmentIndex,
        endGraphemeIndex: Int = lineEndGraphemeIndex,
        width: Double = lineWidth
    ) {
        lineCount += 1
        onLine?(
            InternalLayoutLine(
                startSegmentIndex: lineStartSegmentIndex,
                startGraphemeIndex: lineStartGraphemeIndex,
                endSegmentIndex: endSegmentIndex,
                endGraphemeIndex: endGraphemeIndex,
                width: width
            )
        )
        lineWidth = 0
        hasContent = false
        clearPendingBreak()
    }

    func startLineAtSegment(_ segmentIndex: Int, width: Double) {
        hasContent = true
        lineStartSegmentIndex = segmentIndex
        lineStartGraphemeIndex = 0
        lineEndSegmentIndex = segmentIndex + 1
        lineEndGraphemeIndex = 0
        lineWidth = width
    }

    func startLineAtGrapheme(_ segmentIndex: Int, graphemeIndex: Int, width: Double) {
        hasContent = true
        lineStartSegmentIndex = segmentIndex
        lineStartGraphemeIndex = graphemeIndex
        lineEndSegmentIndex = segmentIndex
        lineEndGraphemeIndex = graphemeIndex + 1
        lineWidth = width
    }

    func appendWholeSegment(_ segmentIndex: Int, width: Double) {
        if !hasContent {
            startLineAtSegment(segmentIndex, width: width)
            return
        }
        lineWidth += width
        lineEndSegmentIndex = segmentIndex + 1
        lineEndGraphemeIndex = 0
    }

    func updatePendingBreak(_ segmentIndex: Int, segmentWidth: Double) {
        guard canBreakAfter(kinds[segmentIndex]) else {
            return
        }
        pendingBreakSegmentIndex = segmentIndex + 1
        pendingBreakPaintWidth = lineWidth - segmentWidth
    }

    func appendBreakableSegmentFrom(_ segmentIndex: Int, startGraphemeIndex: Int) {
        guard let graphemeWidths = breakableWidths[segmentIndex] else {
            return
        }
        let graphemePrefixWidths = breakablePrefixWidths[segmentIndex]

        for graphemeIndex in startGraphemeIndex..<graphemeWidths.count {
            let advance = getBreakableAdvance(
                graphemeWidths: graphemeWidths,
                graphemePrefixWidths: graphemePrefixWidths,
                graphemeIndex: graphemeIndex,
                preferPrefixWidths: profile.preferPrefixWidthsForBreakableRuns
            )

            if !hasContent {
                startLineAtGrapheme(segmentIndex, graphemeIndex: graphemeIndex, width: advance)
                continue
            }

            if lineWidth + advance > maxWidth + epsilon {
                emitCurrentLine()
                startLineAtGrapheme(segmentIndex, graphemeIndex: graphemeIndex, width: advance)
            } else {
                lineWidth += advance
                lineEndSegmentIndex = segmentIndex
                lineEndGraphemeIndex = graphemeIndex + 1
            }
        }

        if hasContent, lineEndSegmentIndex == segmentIndex, lineEndGraphemeIndex == graphemeWidths.count {
            lineEndSegmentIndex = segmentIndex + 1
            lineEndGraphemeIndex = 0
        }
    }

    var index = 0
    while index < widths.count {
        let width = widths[index]
        let kind = kinds[index]

        if !hasContent {
            if width > maxWidth, breakableWidths[index] != nil {
                appendBreakableSegmentFrom(index, startGraphemeIndex: 0)
            } else {
                startLineAtSegment(index, width: width)
            }
            updatePendingBreak(index, segmentWidth: width)
            index += 1
            continue
        }

        let newWidth = lineWidth + width
        if newWidth > maxWidth + epsilon {
            if canBreakAfter(kind) {
                appendWholeSegment(index, width: width)
                emitCurrentLine(endSegmentIndex: index + 1, endGraphemeIndex: 0, width: lineWidth - width)
                index += 1
                continue
            }

            if pendingBreakSegmentIndex >= 0 {
                emitCurrentLine(endSegmentIndex: pendingBreakSegmentIndex, endGraphemeIndex: 0, width: pendingBreakPaintWidth)
                continue
            }

            if width > maxWidth, breakableWidths[index] != nil {
                emitCurrentLine()
                appendBreakableSegmentFrom(index, startGraphemeIndex: 0)
                index += 1
                continue
            }

            emitCurrentLine()
            continue
        }

        appendWholeSegment(index, width: width)
        updatePendingBreak(index, segmentWidth: width)
        index += 1
    }

    if hasContent {
        emitCurrentLine()
    }

    return lineCount
}

@discardableResult
func walkPreparedLines(
    _ prepared: PreparedText,
    maxWidth: Double,
    onLine: ((InternalLayoutLine) -> Void)?
) -> Int {
    if prepared.simpleLineWalkFastPath {
        return walkPreparedLinesSimple(prepared, maxWidth: maxWidth, onLine: onLine)
    }

    let widths = prepared.widths
    let lineEndFitAdvances = prepared.lineEndFitAdvances
    let lineEndPaintAdvances = prepared.lineEndPaintAdvances
    let kinds = prepared.kinds
    let breakableWidths = prepared.breakableWidths
    let breakablePrefixWidths = prepared.breakablePrefixWidths
    let discretionaryHyphenWidth = prepared.discretionaryHyphenWidth
    let tabStopAdvance = prepared.tabStopAdvance
    let chunks = prepared.chunks

    guard !widths.isEmpty, !chunks.isEmpty else {
        return 0
    }

    let profile = engineProfile()
    let epsilon = profile.lineFitEpsilon

    var lineCount = 0
    var lineWidth = 0.0
    var hasContent = false
    var lineStartSegmentIndex = 0
    var lineStartGraphemeIndex = 0
    var lineEndSegmentIndex = 0
    var lineEndGraphemeIndex = 0
    var pendingBreakSegmentIndex = -1
    var pendingBreakFitWidth = 0.0
    var pendingBreakPaintWidth = 0.0
    var pendingBreakKind: SegmentBreakKind?

    func clearPendingBreak() {
        pendingBreakSegmentIndex = -1
        pendingBreakFitWidth = 0
        pendingBreakPaintWidth = 0
        pendingBreakKind = nil
    }

    func emitCurrentLine(
        endSegmentIndex: Int = lineEndSegmentIndex,
        endGraphemeIndex: Int = lineEndGraphemeIndex,
        width: Double = lineWidth
    ) {
        lineCount += 1
        onLine?(
            InternalLayoutLine(
                startSegmentIndex: lineStartSegmentIndex,
                startGraphemeIndex: lineStartGraphemeIndex,
                endSegmentIndex: endSegmentIndex,
                endGraphemeIndex: endGraphemeIndex,
                width: width
            )
        )
        lineWidth = 0
        hasContent = false
        clearPendingBreak()
    }

    func startLineAtSegment(_ segmentIndex: Int, width: Double) {
        hasContent = true
        lineStartSegmentIndex = segmentIndex
        lineStartGraphemeIndex = 0
        lineEndSegmentIndex = segmentIndex + 1
        lineEndGraphemeIndex = 0
        lineWidth = width
    }

    func startLineAtGrapheme(_ segmentIndex: Int, graphemeIndex: Int, width: Double) {
        hasContent = true
        lineStartSegmentIndex = segmentIndex
        lineStartGraphemeIndex = graphemeIndex
        lineEndSegmentIndex = segmentIndex
        lineEndGraphemeIndex = graphemeIndex + 1
        lineWidth = width
    }

    func appendWholeSegment(_ segmentIndex: Int, width: Double) {
        if !hasContent {
            startLineAtSegment(segmentIndex, width: width)
            return
        }
        lineWidth += width
        lineEndSegmentIndex = segmentIndex + 1
        lineEndGraphemeIndex = 0
    }

    func updatePendingBreakForWholeSegment(_ segmentIndex: Int, segmentWidth: Double) {
        guard canBreakAfter(kinds[segmentIndex]) else {
            return
        }

        let fitAdvance = kinds[segmentIndex] == .tab ? 0 : lineEndFitAdvances[segmentIndex]
        let paintAdvance = kinds[segmentIndex] == .tab ? segmentWidth : lineEndPaintAdvances[segmentIndex]
        pendingBreakSegmentIndex = segmentIndex + 1
        pendingBreakFitWidth = lineWidth - segmentWidth + fitAdvance
        pendingBreakPaintWidth = lineWidth - segmentWidth + paintAdvance
        pendingBreakKind = kinds[segmentIndex]
    }

    func appendBreakableSegmentFrom(_ segmentIndex: Int, startGraphemeIndex: Int) {
        guard let graphemeWidths = breakableWidths[segmentIndex] else {
            return
        }
        let graphemePrefixWidths = breakablePrefixWidths[segmentIndex]

        for graphemeIndex in startGraphemeIndex..<graphemeWidths.count {
            let advance = getBreakableAdvance(
                graphemeWidths: graphemeWidths,
                graphemePrefixWidths: graphemePrefixWidths,
                graphemeIndex: graphemeIndex,
                preferPrefixWidths: profile.preferPrefixWidthsForBreakableRuns
            )

            if !hasContent {
                startLineAtGrapheme(segmentIndex, graphemeIndex: graphemeIndex, width: advance)
                continue
            }

            if lineWidth + advance > maxWidth + epsilon {
                emitCurrentLine()
                startLineAtGrapheme(segmentIndex, graphemeIndex: graphemeIndex, width: advance)
            } else {
                lineWidth += advance
                lineEndSegmentIndex = segmentIndex
                lineEndGraphemeIndex = graphemeIndex + 1
            }
        }

        if hasContent, lineEndSegmentIndex == segmentIndex, lineEndGraphemeIndex == graphemeWidths.count {
            lineEndSegmentIndex = segmentIndex + 1
            lineEndGraphemeIndex = 0
        }
    }

    func continueSoftHyphenBreakableSegment(_ segmentIndex: Int) -> Bool {
        guard pendingBreakKind == .softHyphen, let graphemeWidths = breakableWidths[segmentIndex] else {
            return false
        }

        let fitWidths = profile.preferPrefixWidthsForBreakableRuns
            ? (breakablePrefixWidths[segmentIndex] ?? graphemeWidths)
            : graphemeWidths
        let usesPrefixWidths = fitWidths != graphemeWidths
        let fitted = fitSoftHyphenBreak(
            graphemeWidths: fitWidths,
            initialWidth: lineWidth,
            maxWidth: maxWidth,
            lineFitEpsilon: epsilon,
            discretionaryHyphenWidth: discretionaryHyphenWidth,
            cumulativeWidths: usesPrefixWidths
        )

        guard fitted.fitCount > 0 else {
            return false
        }

        lineWidth = fitted.fittedWidth
        lineEndSegmentIndex = segmentIndex
        lineEndGraphemeIndex = fitted.fitCount
        clearPendingBreak()

        if fitted.fitCount == graphemeWidths.count {
            lineEndSegmentIndex = segmentIndex + 1
            lineEndGraphemeIndex = 0
            return true
        }

        emitCurrentLine(
            endSegmentIndex: segmentIndex,
            endGraphemeIndex: fitted.fitCount,
            width: fitted.fittedWidth + discretionaryHyphenWidth
        )
        appendBreakableSegmentFrom(segmentIndex, startGraphemeIndex: fitted.fitCount)
        return true
    }

    func emitEmptyChunk(_ chunk: PreparedLineChunk) {
        lineCount += 1
        onLine?(
            InternalLayoutLine(
                startSegmentIndex: chunk.startSegmentIndex,
                startGraphemeIndex: 0,
                endSegmentIndex: chunk.consumedEndSegmentIndex,
                endGraphemeIndex: 0,
                width: 0
            )
        )
        clearPendingBreak()
    }

    for chunk in chunks {
        if chunk.startSegmentIndex == chunk.endSegmentIndex {
            emitEmptyChunk(chunk)
            continue
        }

        hasContent = false
        lineWidth = 0
        lineStartSegmentIndex = chunk.startSegmentIndex
        lineStartGraphemeIndex = 0
        lineEndSegmentIndex = chunk.startSegmentIndex
        lineEndGraphemeIndex = 0
        clearPendingBreak()

        var index = chunk.startSegmentIndex
        while index < chunk.endSegmentIndex {
            let kind = kinds[index]
            let width = kind == .tab ? getTabAdvance(lineWidth: lineWidth, tabStopAdvance: tabStopAdvance) : widths[index]

            if kind == .softHyphen {
                if hasContent {
                    lineEndSegmentIndex = index + 1
                    lineEndGraphemeIndex = 0
                    pendingBreakSegmentIndex = index + 1
                    pendingBreakFitWidth = lineWidth + discretionaryHyphenWidth
                    pendingBreakPaintWidth = lineWidth + discretionaryHyphenWidth
                    pendingBreakKind = kind
                }
                index += 1
                continue
            }

            if !hasContent {
                if width > maxWidth, breakableWidths[index] != nil {
                    appendBreakableSegmentFrom(index, startGraphemeIndex: 0)
                } else {
                    startLineAtSegment(index, width: width)
                }
                updatePendingBreakForWholeSegment(index, segmentWidth: width)
                index += 1
                continue
            }

            let newWidth = lineWidth + width
            if newWidth > maxWidth + epsilon {
                let currentBreakFitWidth = lineWidth + (kind == .tab ? 0 : lineEndFitAdvances[index])
                let currentBreakPaintWidth = lineWidth + (kind == .tab ? width : lineEndPaintAdvances[index])

                if
                    pendingBreakKind == .softHyphen,
                    profile.preferEarlySoftHyphenBreak,
                    pendingBreakFitWidth <= maxWidth + epsilon
                {
                    emitCurrentLine(
                        endSegmentIndex: pendingBreakSegmentIndex,
                        endGraphemeIndex: 0,
                        width: pendingBreakPaintWidth
                    )
                    continue
                }

                if pendingBreakKind == .softHyphen, continueSoftHyphenBreakableSegment(index) {
                    index += 1
                    continue
                }

                if canBreakAfter(kind), currentBreakFitWidth <= maxWidth + epsilon {
                    appendWholeSegment(index, width: width)
                    emitCurrentLine(endSegmentIndex: index + 1, endGraphemeIndex: 0, width: currentBreakPaintWidth)
                    index += 1
                    continue
                }

                if pendingBreakSegmentIndex >= 0, pendingBreakFitWidth <= maxWidth + epsilon {
                    emitCurrentLine(
                        endSegmentIndex: pendingBreakSegmentIndex,
                        endGraphemeIndex: 0,
                        width: pendingBreakPaintWidth
                    )
                    continue
                }

                if width > maxWidth, breakableWidths[index] != nil {
                    emitCurrentLine()
                    appendBreakableSegmentFrom(index, startGraphemeIndex: 0)
                    index += 1
                    continue
                }

                emitCurrentLine()
                continue
            }

            appendWholeSegment(index, width: width)
            updatePendingBreakForWholeSegment(index, segmentWidth: width)
            index += 1
        }

        if hasContent {
            let finalPaintWidth = pendingBreakSegmentIndex == chunk.consumedEndSegmentIndex
                ? pendingBreakPaintWidth
                : lineWidth
            emitCurrentLine(endSegmentIndex: chunk.consumedEndSegmentIndex, endGraphemeIndex: 0, width: finalPaintWidth)
        }
    }

    return lineCount
}

func layoutNextLineRange(
    _ prepared: PreparedText,
    start: LayoutCursor,
    maxWidth: Double
) -> InternalLayoutLine? {
    guard let normalizedStart = normalizeLineStart(prepared, start: start) else {
        return nil
    }

    if prepared.simpleLineWalkFastPath {
        return layoutNextLineRangeSimple(prepared, normalizedStart: normalizedStart, maxWidth: maxWidth)
    }

    guard let chunkIndex = findChunkIndexForStart(prepared, segmentIndex: normalizedStart.segmentIndex) else {
        return nil
    }

    let chunk = prepared.chunks[chunkIndex]
    if chunk.startSegmentIndex == chunk.endSegmentIndex {
        return InternalLayoutLine(
            startSegmentIndex: chunk.startSegmentIndex,
            startGraphemeIndex: 0,
            endSegmentIndex: chunk.consumedEndSegmentIndex,
            endGraphemeIndex: 0,
            width: 0
        )
    }

    let widths = prepared.widths
    let lineEndFitAdvances = prepared.lineEndFitAdvances
    let lineEndPaintAdvances = prepared.lineEndPaintAdvances
    let kinds = prepared.kinds
    let breakableWidths = prepared.breakableWidths
    let breakablePrefixWidths = prepared.breakablePrefixWidths
    let discretionaryHyphenWidth = prepared.discretionaryHyphenWidth
    let tabStopAdvance = prepared.tabStopAdvance
    let profile = engineProfile()
    let epsilon = profile.lineFitEpsilon

    var lineWidth = 0.0
    var hasContent = false
    let lineStartSegmentIndex = normalizedStart.segmentIndex
    let lineStartGraphemeIndex = normalizedStart.graphemeIndex
    var lineEndSegmentIndex = lineStartSegmentIndex
    var lineEndGraphemeIndex = lineStartGraphemeIndex
    var pendingBreakSegmentIndex = -1
    var pendingBreakFitWidth = 0.0
    var pendingBreakPaintWidth = 0.0
    var pendingBreakKind: SegmentBreakKind?

    func clearPendingBreak() {
        pendingBreakSegmentIndex = -1
        pendingBreakFitWidth = 0
        pendingBreakPaintWidth = 0
        pendingBreakKind = nil
    }

    func finishLine(
        endSegmentIndex: Int = lineEndSegmentIndex,
        endGraphemeIndex: Int = lineEndGraphemeIndex,
        width: Double = lineWidth
    ) -> InternalLayoutLine? {
        guard hasContent else {
            return nil
        }
        return InternalLayoutLine(
            startSegmentIndex: lineStartSegmentIndex,
            startGraphemeIndex: lineStartGraphemeIndex,
            endSegmentIndex: endSegmentIndex,
            endGraphemeIndex: endGraphemeIndex,
            width: width
        )
    }

    func startLineAtSegment(_ segmentIndex: Int, width: Double) {
        hasContent = true
        lineEndSegmentIndex = segmentIndex + 1
        lineEndGraphemeIndex = 0
        lineWidth = width
    }

    func startLineAtGrapheme(_ segmentIndex: Int, graphemeIndex: Int, width: Double) {
        hasContent = true
        lineEndSegmentIndex = segmentIndex
        lineEndGraphemeIndex = graphemeIndex + 1
        lineWidth = width
    }

    func appendWholeSegment(_ segmentIndex: Int, width: Double) {
        if !hasContent {
            startLineAtSegment(segmentIndex, width: width)
            return
        }
        lineWidth += width
        lineEndSegmentIndex = segmentIndex + 1
        lineEndGraphemeIndex = 0
    }

    func updatePendingBreakForWholeSegment(_ segmentIndex: Int, segmentWidth: Double) {
        guard canBreakAfter(kinds[segmentIndex]) else {
            return
        }

        let fitAdvance = kinds[segmentIndex] == .tab ? 0 : lineEndFitAdvances[segmentIndex]
        let paintAdvance = kinds[segmentIndex] == .tab ? segmentWidth : lineEndPaintAdvances[segmentIndex]
        pendingBreakSegmentIndex = segmentIndex + 1
        pendingBreakFitWidth = lineWidth - segmentWidth + fitAdvance
        pendingBreakPaintWidth = lineWidth - segmentWidth + paintAdvance
        pendingBreakKind = kinds[segmentIndex]
    }

    func appendBreakableSegmentFrom(_ segmentIndex: Int, startGraphemeIndex: Int) -> InternalLayoutLine? {
        guard let graphemeWidths = breakableWidths[segmentIndex] else {
            return nil
        }
        let graphemePrefixWidths = breakablePrefixWidths[segmentIndex]

        for graphemeIndex in startGraphemeIndex..<graphemeWidths.count {
            let advance = getBreakableAdvance(
                graphemeWidths: graphemeWidths,
                graphemePrefixWidths: graphemePrefixWidths,
                graphemeIndex: graphemeIndex,
                preferPrefixWidths: profile.preferPrefixWidthsForBreakableRuns
            )

            if !hasContent {
                startLineAtGrapheme(segmentIndex, graphemeIndex: graphemeIndex, width: advance)
                continue
            }

            if lineWidth + advance > maxWidth + epsilon {
                return finishLine()
            }

            lineWidth += advance
            lineEndSegmentIndex = segmentIndex
            lineEndGraphemeIndex = graphemeIndex + 1
        }

        if hasContent, lineEndSegmentIndex == segmentIndex, lineEndGraphemeIndex == graphemeWidths.count {
            lineEndSegmentIndex = segmentIndex + 1
            lineEndGraphemeIndex = 0
        }

        return nil
    }

    func maybeFinishAtSoftHyphen(_ segmentIndex: Int) -> InternalLayoutLine? {
        guard pendingBreakKind == .softHyphen, pendingBreakSegmentIndex >= 0 else {
            return nil
        }

        if let graphemeWidths = breakableWidths[segmentIndex] {
            let fitWidths = profile.preferPrefixWidthsForBreakableRuns
                ? (breakablePrefixWidths[segmentIndex] ?? graphemeWidths)
                : graphemeWidths
            let usesPrefixWidths = fitWidths != graphemeWidths
            let fitted = fitSoftHyphenBreak(
                graphemeWidths: fitWidths,
                initialWidth: lineWidth,
                maxWidth: maxWidth,
                lineFitEpsilon: epsilon,
                discretionaryHyphenWidth: discretionaryHyphenWidth,
                cumulativeWidths: usesPrefixWidths
            )

            if fitted.fitCount == graphemeWidths.count {
                lineWidth = fitted.fittedWidth
                lineEndSegmentIndex = segmentIndex + 1
                lineEndGraphemeIndex = 0
                clearPendingBreak()
                return nil
            }

            if fitted.fitCount > 0 {
                return finishLine(
                    endSegmentIndex: segmentIndex,
                    endGraphemeIndex: fitted.fitCount,
                    width: fitted.fittedWidth + discretionaryHyphenWidth
                )
            }
        }

        if pendingBreakFitWidth <= maxWidth + epsilon {
            return finishLine(endSegmentIndex: pendingBreakSegmentIndex, endGraphemeIndex: 0, width: pendingBreakPaintWidth)
        }

        return nil
    }

    for index in normalizedStart.segmentIndex..<chunk.endSegmentIndex {
        let kind = kinds[index]
        let startGraphemeIndex = index == normalizedStart.segmentIndex ? normalizedStart.graphemeIndex : 0
        let width = kind == .tab ? getTabAdvance(lineWidth: lineWidth, tabStopAdvance: tabStopAdvance) : widths[index]

        if kind == .softHyphen, startGraphemeIndex == 0 {
            if hasContent {
                lineEndSegmentIndex = index + 1
                lineEndGraphemeIndex = 0
                pendingBreakSegmentIndex = index + 1
                pendingBreakFitWidth = lineWidth + discretionaryHyphenWidth
                pendingBreakPaintWidth = lineWidth + discretionaryHyphenWidth
                pendingBreakKind = kind
            }
            continue
        }

        if !hasContent {
            if startGraphemeIndex > 0 {
                if let line = appendBreakableSegmentFrom(index, startGraphemeIndex: startGraphemeIndex) {
                    return line
                }
            } else if width > maxWidth, breakableWidths[index] != nil {
                if let line = appendBreakableSegmentFrom(index, startGraphemeIndex: 0) {
                    return line
                }
            } else {
                startLineAtSegment(index, width: width)
            }
            updatePendingBreakForWholeSegment(index, segmentWidth: width)
            continue
        }

        let newWidth = lineWidth + width
        if newWidth > maxWidth + epsilon {
            let currentBreakFitWidth = lineWidth + (kind == .tab ? 0 : lineEndFitAdvances[index])
            let currentBreakPaintWidth = lineWidth + (kind == .tab ? width : lineEndPaintAdvances[index])

            if
                pendingBreakKind == .softHyphen,
                profile.preferEarlySoftHyphenBreak,
                pendingBreakFitWidth <= maxWidth + epsilon
            {
                return finishLine(endSegmentIndex: pendingBreakSegmentIndex, endGraphemeIndex: 0, width: pendingBreakPaintWidth)
            }

            if let softBreakLine = maybeFinishAtSoftHyphen(index) {
                return softBreakLine
            }

            if canBreakAfter(kind), currentBreakFitWidth <= maxWidth + epsilon {
                appendWholeSegment(index, width: width)
                return finishLine(endSegmentIndex: index + 1, endGraphemeIndex: 0, width: currentBreakPaintWidth)
            }

            if pendingBreakSegmentIndex >= 0, pendingBreakFitWidth <= maxWidth + epsilon {
                return finishLine(endSegmentIndex: pendingBreakSegmentIndex, endGraphemeIndex: 0, width: pendingBreakPaintWidth)
            }

            if width > maxWidth, breakableWidths[index] != nil {
                if let currentLine = finishLine() {
                    return currentLine
                }
                if let line = appendBreakableSegmentFrom(index, startGraphemeIndex: 0) {
                    return line
                }
            }

            return finishLine()
        }

        appendWholeSegment(index, width: width)
        updatePendingBreakForWholeSegment(index, segmentWidth: width)
    }

    if pendingBreakSegmentIndex == chunk.consumedEndSegmentIndex, lineEndGraphemeIndex == 0 {
        return finishLine(endSegmentIndex: chunk.consumedEndSegmentIndex, endGraphemeIndex: 0, width: pendingBreakPaintWidth)
    }

    return finishLine(endSegmentIndex: chunk.consumedEndSegmentIndex, endGraphemeIndex: 0, width: lineWidth)
}

private func layoutNextLineRangeSimple(
    _ prepared: PreparedText,
    normalizedStart: LayoutCursor,
    maxWidth: Double
) -> InternalLayoutLine? {
    let widths = prepared.widths
    let kinds = prepared.kinds
    let breakableWidths = prepared.breakableWidths
    let breakablePrefixWidths = prepared.breakablePrefixWidths
    let profile = engineProfile()
    let epsilon = profile.lineFitEpsilon

    var lineWidth = 0.0
    var hasContent = false
    let lineStartSegmentIndex = normalizedStart.segmentIndex
    let lineStartGraphemeIndex = normalizedStart.graphemeIndex
    var lineEndSegmentIndex = lineStartSegmentIndex
    var lineEndGraphemeIndex = lineStartGraphemeIndex
    var pendingBreakSegmentIndex = -1
    var pendingBreakPaintWidth = 0.0

    func finishLine(
        endSegmentIndex: Int = lineEndSegmentIndex,
        endGraphemeIndex: Int = lineEndGraphemeIndex,
        width: Double = lineWidth
    ) -> InternalLayoutLine? {
        guard hasContent else {
            return nil
        }
        return InternalLayoutLine(
            startSegmentIndex: lineStartSegmentIndex,
            startGraphemeIndex: lineStartGraphemeIndex,
            endSegmentIndex: endSegmentIndex,
            endGraphemeIndex: endGraphemeIndex,
            width: width
        )
    }

    func startLineAtSegment(_ segmentIndex: Int, width: Double) {
        hasContent = true
        lineEndSegmentIndex = segmentIndex + 1
        lineEndGraphemeIndex = 0
        lineWidth = width
    }

    func startLineAtGrapheme(_ segmentIndex: Int, graphemeIndex: Int, width: Double) {
        hasContent = true
        lineEndSegmentIndex = segmentIndex
        lineEndGraphemeIndex = graphemeIndex + 1
        lineWidth = width
    }

    func appendWholeSegment(_ segmentIndex: Int, width: Double) {
        if !hasContent {
            startLineAtSegment(segmentIndex, width: width)
            return
        }
        lineWidth += width
        lineEndSegmentIndex = segmentIndex + 1
        lineEndGraphemeIndex = 0
    }

    func updatePendingBreak(_ segmentIndex: Int, segmentWidth: Double) {
        guard canBreakAfter(kinds[segmentIndex]) else {
            return
        }
        pendingBreakSegmentIndex = segmentIndex + 1
        pendingBreakPaintWidth = lineWidth - segmentWidth
    }

    func appendBreakableSegmentFrom(_ segmentIndex: Int, startGraphemeIndex: Int) -> InternalLayoutLine? {
        guard let graphemeWidths = breakableWidths[segmentIndex] else {
            return nil
        }
        let graphemePrefixWidths = breakablePrefixWidths[segmentIndex]

        for graphemeIndex in startGraphemeIndex..<graphemeWidths.count {
            let advance = getBreakableAdvance(
                graphemeWidths: graphemeWidths,
                graphemePrefixWidths: graphemePrefixWidths,
                graphemeIndex: graphemeIndex,
                preferPrefixWidths: profile.preferPrefixWidthsForBreakableRuns
            )

            if !hasContent {
                startLineAtGrapheme(segmentIndex, graphemeIndex: graphemeIndex, width: advance)
                continue
            }

            if lineWidth + advance > maxWidth + epsilon {
                return finishLine()
            }

            lineWidth += advance
            lineEndSegmentIndex = segmentIndex
            lineEndGraphemeIndex = graphemeIndex + 1
        }

        if hasContent, lineEndSegmentIndex == segmentIndex, lineEndGraphemeIndex == graphemeWidths.count {
            lineEndSegmentIndex = segmentIndex + 1
            lineEndGraphemeIndex = 0
        }
        return nil
    }

    for index in normalizedStart.segmentIndex..<widths.count {
        let width = widths[index]
        let kind = kinds[index]
        let startGraphemeIndex = index == normalizedStart.segmentIndex ? normalizedStart.graphemeIndex : 0

        if !hasContent {
            if startGraphemeIndex > 0 {
                if let line = appendBreakableSegmentFrom(index, startGraphemeIndex: startGraphemeIndex) {
                    return line
                }
            } else if width > maxWidth, breakableWidths[index] != nil {
                if let line = appendBreakableSegmentFrom(index, startGraphemeIndex: 0) {
                    return line
                }
            } else {
                startLineAtSegment(index, width: width)
            }
            updatePendingBreak(index, segmentWidth: width)
            continue
        }

        let newWidth = lineWidth + width
        if newWidth > maxWidth + epsilon {
            if canBreakAfter(kind) {
                appendWholeSegment(index, width: width)
                return finishLine(endSegmentIndex: index + 1, endGraphemeIndex: 0, width: lineWidth - width)
            }

            if pendingBreakSegmentIndex >= 0 {
                return finishLine(endSegmentIndex: pendingBreakSegmentIndex, endGraphemeIndex: 0, width: pendingBreakPaintWidth)
            }

            if width > maxWidth, breakableWidths[index] != nil {
                if let currentLine = finishLine() {
                    return currentLine
                }
                if let line = appendBreakableSegmentFrom(index, startGraphemeIndex: 0) {
                    return line
                }
            }

            return finishLine()
        }

        appendWholeSegment(index, width: width)
        updatePendingBreak(index, segmentWidth: width)
    }

    return finishLine()
}
