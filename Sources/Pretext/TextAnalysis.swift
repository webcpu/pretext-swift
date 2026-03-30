import Foundation
import NaturalLanguage

private struct SegmentationPiece {
    var text: String
    var isWordLike: Bool
    var kind: SegmentBreakKind
    var start: Int
}

private struct WhiteSpaceProfile {
    var mode: WhiteSpaceMode
    var preserveOrdinarySpaces: Bool
    var preserveHardBreaks: Bool
}

private struct MergedSegmentation {
    var segments: [String]
    var wordLike: [Bool]
    var kinds: [SegmentBreakKind]
    var starts: [Int]

    var count: Int { segments.count }
}

let kinsokuStart: Set<String> = [
    "\u{FF0C}", "\u{FF0E}", "\u{FF01}", "\u{FF1A}", "\u{FF1B}", "\u{FF1F}",
    "\u{3001}", "\u{3002}", "\u{30FB}", "\u{FF09}", "\u{3015}", "\u{3009}",
    "\u{300B}", "\u{300D}", "\u{300F}", "\u{3011}", "\u{3017}", "\u{3019}",
    "\u{301B}", "\u{30FC}", "\u{3005}", "\u{303B}", "\u{309D}", "\u{309E}",
    "\u{30FD}", "\u{30FE}",
]

let kinsokuEnd: Set<String> = [
    "\"", "(", "[", "{", "“", "‘", "«", "‹", "\u{FF08}", "\u{3014}",
    "\u{3008}", "\u{300A}", "\u{300C}", "\u{300E}", "\u{3010}", "\u{3016}",
    "\u{3018}", "\u{301A}",
]

private let leftStickyScalars: Set<UInt32> = [
    0x002E, 0x002C, 0x0021, 0x003F, 0x003A, 0x003B, 0x0025, 0x0029, 0x005D, 0x007D, 0x0022,
    0x201D, 0x2019, 0x00BB, 0x203A, 0x2026,
]

private let rightStickyScalars: Set<UInt32> = [
    0x0028, 0x005B, 0x007B, 0x0022, 0x201C, 0x2018, 0x00AB, 0x2039,
]

private let fastPathNonASCIIScalars: Set<UInt32> = [
    0x00AD, 0x200B, 0x2013, 0x2014, 0x2018, 0x2019,
    0x201C, 0x201D, 0x2026, 0x2039, 0x203A,
    0x00AB, 0x00BB,
]

private let forwardStickyGlue: Set<String> = ["'", "’"]

let leftStickyPunctuation: Set<String> = [
    ".", ",", "!", "?", ":", ";",
    "\u{060C}", "\u{061B}", "\u{061F}",
    "\u{0964}", "\u{0965}",
    "\u{104A}", "\u{104B}", "\u{104C}", "\u{104D}", "\u{104F}",
    ")", "]", "}", "%", "\"", "”", "’", "»", "›", "…",
]

private let arabicNoSpaceTrailingPunctuation: Set<String> = [":", ".", "\u{060C}", "\u{061B}"]
private let myanmarMedialGlue: Set<String> = ["\u{104F}"]
private let closingQuoteChars: Set<String> = [
    "”", "’", "»", "›", "\u{300D}", "\u{300F}", "\u{3011}",
    "\u{300B}", "\u{3009}", "\u{3015}", "\u{FF09}",
]

private let numericJoinerChars: Set<String> = [":", "-", "/", "×", ",", ".", "+", "\u{2013}", "\u{2014}"]

nonisolated(unsafe) private var tokenizerLocale: Locale?

public func setAnalysisLocale(_ locale: Locale?) {
    tokenizerLocale = locale
}

private func getWhiteSpaceProfile(_ whiteSpace: WhiteSpaceMode) -> WhiteSpaceProfile {
    switch whiteSpace {
    case .normal:
        WhiteSpaceProfile(mode: .normal, preserveOrdinarySpaces: false, preserveHardBreaks: false)
    case .preWrap:
        WhiteSpaceProfile(mode: .preWrap, preserveOrdinarySpaces: true, preserveHardBreaks: true)
    }
}

public func normalizeWhitespaceNormal(_ text: String) -> String {
    if text.isEmpty || isAlreadyNormalizedWhitespaceNormal(text) {
        return text
    }

    var result: [UInt8] = []
    result.reserveCapacity(text.utf8.count)
    var pendingSpace = false

    for byte in text.utf8 {
        let isWS = byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
        if isWS {
            pendingSpace = true
            continue
        }
        if pendingSpace && !result.isEmpty {
            result.append(0x20)
        }
        pendingSpace = false
        result.append(byte)
    }

    return String(bytes: result, encoding: .utf8) ?? text
}

private func isAlreadyNormalizedWhitespaceNormal(_ text: String) -> Bool {
    var previousWasWhitespace = true

    for byte in text.utf8 {
        let isWhitespace = byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
        if isWhitespace {
            if byte != 0x20 || previousWasWhitespace {
                return false
            }
            previousWasWhitespace = true
        } else {
            previousWasWhitespace = false
        }
    }

    return !previousWasWhitespace
}

public func normalizeWhitespacePreWrap(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .replacingOccurrences(of: "\u{000C}", with: "\n")
}

public enum AnalysisSubProfile {
    nonisolated(unsafe) public static var normalizeMs: Double = 0
    nonisolated(unsafe) public static var splitMs: Double = 0
    nonisolated(unsafe) public static var mergeMs: Double = 0
    nonisolated(unsafe) public static var expandMs: Double = 0
    nonisolated(unsafe) public static var finalizeMs: Double = 0
    nonisolated(unsafe) public static var count: Int = 0

    public static func reset() { normalizeMs = 0; splitMs = 0; mergeMs = 0; expandMs = 0; finalizeMs = 0; count = 0 }
    public static func summary() -> String {
        "  analyzeText x\(count): norm=\(f(normalizeMs))ms split=\(f(splitMs))ms merge=\(f(mergeMs))ms expand=\(f(expandMs))ms finalize=\(f(finalizeMs))ms"
    }
    private static func f(_ v: Double) -> String { String(format: "%.1f", v) }
}

public func analyzeText(_ text: String, whiteSpace: WhiteSpaceMode = .normal) -> TextAnalysisResult {
    let t0 = CFAbsoluteTimeGetCurrent()
    let whiteSpaceProfile = getWhiteSpaceProfile(whiteSpace)
    let normalized = whiteSpaceProfile.mode == .preWrap
        ? normalizeWhitespacePreWrap(text)
        : normalizeWhitespaceNormal(text)
    let t1 = CFAbsoluteTimeGetCurrent()

    guard !normalized.isEmpty else {
        return TextAnalysisResult(
            normalized: normalized,
            segments: [],
            kinds: [],
            wordLike: [],
            chunks: [],
            starts: [],
            directPreparedLayout: false
        )
    }

    let t2 = CFAbsoluteTimeGetCurrent()
    if let result = analyzeSimpleScalarTextIfPossible(normalized, whiteSpaceProfile: whiteSpaceProfile) {
        let t3 = CFAbsoluteTimeGetCurrent()

        AnalysisSubProfile.normalizeMs += (t1 - t0) * 1000
        AnalysisSubProfile.splitMs += (t3 - t2) * 1000
        AnalysisSubProfile.mergeMs += 0
        AnalysisSubProfile.expandMs += 0
        AnalysisSubProfile.finalizeMs += 0
        AnalysisSubProfile.count += 1

        return result
    }

    let merged = buildMergedSegmentation(normalized, whiteSpaceProfile: whiteSpaceProfile)
    let t3 = CFAbsoluteTimeGetCurrent()
    let chunks = compileAnalysisChunks(merged, whiteSpaceProfile: whiteSpaceProfile)
    let t4 = CFAbsoluteTimeGetCurrent()

    AnalysisSubProfile.normalizeMs += (t1 - t0) * 1000
    AnalysisSubProfile.splitMs += (t2 - t1) * 1000
    AnalysisSubProfile.mergeMs += (t3 - t2) * 1000
    AnalysisSubProfile.expandMs += 0
    AnalysisSubProfile.finalizeMs += (t4 - t3) * 1000
    AnalysisSubProfile.count += 1

    return TextAnalysisResult(
        normalized: normalized,
        segments: merged.segments,
        kinds: merged.kinds,
        wordLike: merged.wordLike,
        chunks: chunks,
        starts: merged.starts,
        directPreparedLayout: false
    )
}

private func isDisallowedASCIINumericJoiner(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x3A, 0x2D, 0x2F, 0x2C, 0x2B:
        return true
    default:
        return false
    }
}

private func isDisallowedUnicodeNumericJoiner(_ value: UInt32) -> Bool {
    value == 0x2013 || value == 0x2014
}

private func analyzeSimpleScalarTextIfPossible(
    _ text: String,
    whiteSpaceProfile: WhiteSpaceProfile
) -> TextAnalysisResult? {
    guard !text.isEmpty else {
        return TextAnalysisResult(
            normalized: text,
            segments: [],
            kinds: [],
            wordLike: [],
            chunks: [],
            starts: [],
            directPreparedLayout: true
        )
    }

    if let result = text.utf8.withContiguousStorageIfAvailable({ buffer in
        analyzeSimpleUTF8BufferIfPossible(buffer, text: text, whiteSpaceProfile: whiteSpaceProfile)
    }) {
        return result
    }

    let utf8Bytes = Array(text.utf8)
    return utf8Bytes.withUnsafeBufferPointer { buffer in
        analyzeSimpleUTF8BufferIfPossible(buffer, text: text, whiteSpaceProfile: whiteSpaceProfile)
    }
}

private func analyzeSimpleUTF8BufferIfPossible(
    _ buffer: UnsafeBufferPointer<UInt8>,
    text: String,
    whiteSpaceProfile: WhiteSpaceProfile
) -> TextAnalysisResult? {
    let count = buffer.count
    guard count > 0 else {
        return TextAnalysisResult(
            normalized: text,
            segments: [],
            kinds: [],
            wordLike: [],
            chunks: [],
            starts: [],
            directPreparedLayout: true
        )
    }

    return withExtendedLifetime(text) {
        var segments: [String] = []
        var kinds: [SegmentBreakKind] = []
        var wordLike: [Bool] = []
        var starts: [Int] = []

        var rightStickyStart = -1
        var rightStickyEnd = -1
        var previousEndedWithDigit = false

        func slice(_ start: Int, _ end: Int) -> String {
            String(unsafeUninitializedCapacity: end - start) { bytes in
                _ = bytes.initialize(from: UnsafeBufferPointer(start: buffer.baseAddress! + start, count: end - start))
                return end - start
            }
        }

        func appendSegment(_ start: Int, _ end: Int, _ kind: SegmentBreakKind, _ isWord: Bool) {
            guard start < end else { return }
            segments.append(slice(start, end))
            kinds.append(kind)
            wordLike.append(isWord)
            starts.append(start)
        }

        func flushRightSticky() {
            guard rightStickyStart >= 0 else { return }
            appendSegment(rightStickyStart, rightStickyEnd, .text, false)
            rightStickyStart = -1
            rightStickyEnd = -1
        }

        func emitWord(_ start: Int, _ end: Int) {
            if rightStickyStart >= 0 {
                appendSegment(rightStickyStart, end, .text, true)
                rightStickyStart = -1
                rightStickyEnd = -1
                return
            }

            if
                let last = kinds.indices.last,
                kinds[last] == .text,
                wordLike[last],
                endsWithBridgePunctuation(segments[last])
            {
                segments[last] += slice(start, end)
                return
            }

            appendSegment(start, end, .text, true)
        }

        func emitNonWordText(_ start: Int, _ end: Int) {
            guard start < end else { return }

            if isAllLeftSticky(buffer, start, end), let last = kinds.indices.last, kinds[last] == .text {
                segments[last] += slice(start, end)
                return
            }

            if isForwardBridgePunctuation(buffer, start, end), let last = kinds.indices.last, kinds[last] == .text {
                segments[last] += slice(start, end)
                return
            }

            if isAllRightSticky(buffer, start, end) {
                if rightStickyStart >= 0 {
                    rightStickyEnd = end
                } else {
                    rightStickyStart = start
                    rightStickyEnd = end
                }
                return
            }

            flushRightSticky()
            appendSegment(start, end, .text, false)
        }

        var index = 0
        while index < count {
            let byte = buffer[index]

            if byte < 0x80 {
                if (whiteSpaceProfile.preserveOrdinarySpaces || whiteSpaceProfile.preserveHardBreaks) && (byte == 0x09 || byte == 0x0A) {
                    return nil
                }
                if byte == 0x5C || byte == 0x22 { return nil }
                if byte == 0x77, index + 3 < count, buffer[index + 1] == 0x77, buffer[index + 2] == 0x77, buffer[index + 3] == 0x2E {
                    return nil
                }
                if byte == 0x3A, index + 2 < count, buffer[index + 1] == 0x2F, buffer[index + 2] == 0x2F {
                    return nil
                }
                if previousEndedWithDigit, isDisallowedASCIINumericJoiner(byte), index + 1 < count {
                    let next = buffer[index + 1]
                    if next >= 0x30 && next <= 0x39 {
                        return nil
                    }
                }

                if isASCIIWordByte(byte) {
                    let start = index
                    index += 1
                    while index < count, buffer[index] < 0x80, isASCIIWordByte(buffer[index]) {
                        index += 1
                    }
                    emitWord(start, index)
                    previousEndedWithDigit = buffer[index - 1] >= 0x30 && buffer[index - 1] <= 0x39
                } else {
                    let kind = classifyASCIIBreakKind(byte, whiteSpaceProfile: whiteSpaceProfile)
                    let start = index
                    index += 1
                    while
                        index < count,
                        buffer[index] < 0x80,
                        !isASCIIWordByte(buffer[index]),
                        classifyASCIIBreakKind(buffer[index], whiteSpaceProfile: whiteSpaceProfile) == kind
                    {
                        index += 1
                    }

                    if kind == .text {
                        emitNonWordText(start, index)
                    } else {
                        flushRightSticky()
                        appendSegment(start, index, kind, false)
                    }
                    previousEndedWithDigit = false
                }
                continue
            }

            let (scalarValue, sequenceLength) = decodeUTF8Scalar(buffer, at: index, count: count)
            guard fastPathNonASCIIScalars.contains(scalarValue) else { return nil }
            if previousEndedWithDigit, isDisallowedUnicodeNumericJoiner(scalarValue), index + sequenceLength < count {
                let next = buffer[index + sequenceLength]
                if next >= 0x30 && next <= 0x39 {
                    return nil
                }
            }

            if isWordScalar(scalarValue) {
                let start = index
                index += sequenceLength
                while index < count {
                    if buffer[index] < 0x80 {
                        guard isASCIIWordByte(buffer[index]) else { break }
                        index += 1
                        continue
                    }

                    let (nextScalar, nextLength) = decodeUTF8Scalar(buffer, at: index, count: count)
                    guard isWordScalar(nextScalar) else { break }
                    index += nextLength
                }
                emitWord(start, index)
                previousEndedWithDigit = false
            } else {
                let kind = classifyScalarValueBreakKind(scalarValue, whiteSpaceProfile: whiteSpaceProfile)
                let start = index
                index += sequenceLength

                while index < count {
                    if buffer[index] < 0x80 {
                        if isASCIIWordByte(buffer[index]) { break }
                        guard classifyASCIIBreakKind(buffer[index], whiteSpaceProfile: whiteSpaceProfile) == kind else { break }
                        index += 1
                        continue
                    }

                    let (nextScalar, nextLength) = decodeUTF8Scalar(buffer, at: index, count: count)
                    if isWordScalar(nextScalar) { break }
                    guard classifyScalarValueBreakKind(nextScalar, whiteSpaceProfile: whiteSpaceProfile) == kind else { break }
                    index += nextLength
                }

                if kind == .text {
                    emitNonWordText(start, index)
                } else {
                    flushRightSticky()
                    appendSegment(start, index, kind, false)
                }
                previousEndedWithDigit = false
            }
        }

        flushRightSticky()

        let merged = MergedSegmentation(segments: segments, wordLike: wordLike, kinds: kinds, starts: starts)
        let chunks = compileAnalysisChunks(merged, whiteSpaceProfile: whiteSpaceProfile)

        return TextAnalysisResult(
            normalized: text,
            segments: segments,
            kinds: kinds,
            wordLike: wordLike,
            chunks: chunks,
            starts: starts,
            directPreparedLayout: true
        )
    }
}

private func decodeUTF8Scalar(
    _ buffer: UnsafeBufferPointer<UInt8>,
    at index: Int,
    count: Int
) -> (UInt32, Int) {
    let first = buffer[index]
    if first < 0xC0 { return (UInt32(first), 1) }
    if first < 0xE0, index + 1 < count {
        return (UInt32(first & 0x1F) << 6 | UInt32(buffer[index + 1] & 0x3F), 2)
    }
    if first < 0xF0, index + 2 < count {
        return (
            UInt32(first & 0x0F) << 12 |
                UInt32(buffer[index + 1] & 0x3F) << 6 |
                UInt32(buffer[index + 2] & 0x3F),
            3
        )
    }
    if index + 3 < count {
        return (
            UInt32(first & 0x07) << 18 |
                UInt32(buffer[index + 1] & 0x3F) << 12 |
                UInt32(buffer[index + 2] & 0x3F) << 6 |
                UInt32(buffer[index + 3] & 0x3F),
            4
        )
    }
    return (0xFFFD, 1)
}

private func classifyScalarValueBreakKind(
    _ value: UInt32,
    whiteSpaceProfile: WhiteSpaceProfile
) -> SegmentBreakKind {
    if whiteSpaceProfile.preserveOrdinarySpaces || whiteSpaceProfile.preserveHardBreaks {
        if value == 0x20 { return .preservedSpace }
        if value == 0x09 { return .tab }
        if whiteSpaceProfile.preserveHardBreaks, value == 0x0A { return .hardBreak }
    }

    if value == 0x20 || value == 0x09 || value == 0x0A || value == 0x0D || value == 0x0C {
        return .space
    }
    if value == 0xA0 || value == 0x202F || value == 0x2060 || value == 0xFEFF { return .glue }
    if value == 0x200B { return .zeroWidthBreak }
    if value == 0xAD { return .softHyphen }
    return .text
}

private func isAllLeftSticky(_ buffer: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> Bool {
    var index = start
    while index < end {
        let byte = buffer[index]
        if byte < 0x80 {
            switch byte {
            case 0x2E, 0x2C, 0x21, 0x3F, 0x3A, 0x3B, 0x25, 0x29, 0x5D, 0x7D, 0x22:
                index += 1
            default:
                return false
            }
            continue
        }

        let (value, length) = decodeUTF8Scalar(buffer, at: index, count: end)
        guard leftStickyScalars.contains(value) else { return false }
        index += length
    }
    return true
}

private func isAllRightSticky(_ buffer: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> Bool {
    var index = start
    while index < end {
        let byte = buffer[index]
        if byte < 0x80 {
            switch byte {
            case 0x28, 0x5B, 0x7B, 0x22:
                index += 1
            default:
                return false
            }
            continue
        }

        let (value, length) = decodeUTF8Scalar(buffer, at: index, count: end)
        guard rightStickyScalars.contains(value) else { return false }
        index += length
    }
    return true
}

private func isForwardBridgePunctuation(
    _ buffer: UnsafeBufferPointer<UInt8>,
    _ start: Int,
    _ end: Int
) -> Bool {
    guard start < end else { return false }
    var index = start

    while index < end {
        let byte = buffer[index]
        switch byte {
        case 0x2D, 0x2F:
            index += 1
        default:
            return false
        }
    }

    return true
}

private func endsWithBridgePunctuation(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }

    var sawBridge = false
    var sawWord = false

    for character in text.reversed() {
        let string = String(character)
        if [".", ",", ":", ";", "-", "/"].contains(string) {
            sawBridge = true
            continue
        }
        if character.wholeNumberValue != nil || character.unicodeScalars.allSatisfy({ isWordScalar($0.value) }) {
            sawWord = true
        }
        break
    }

    return sawBridge && sawWord
}

private func buildMergedSegmentation(
    _ normalized: String,
    whiteSpaceProfile: WhiteSpaceProfile
) -> MergedSegmentation {
    let pieces = splitIntoPieces(normalized, whiteSpaceProfile: whiteSpaceProfile)
    let profile = engineProfile()

    var mergedSegments: [String] = []
    var mergedWordLike: [Bool] = []
    var mergedKinds: [SegmentBreakKind] = []
    var mergedStarts: [Int] = []

    for piece in pieces {
        let isText = piece.kind == .text

        if
            profile.carryCJKAfterClosingQuote,
            isText,
            let lastKind = mergedKinds.last,
            lastKind == .text,
            containsCJK(piece.text),
            containsCJK(mergedSegments.last ?? ""),
            endsWithClosingQuote(mergedSegments.last ?? "")
        {
            mergedSegments[mergedSegments.count - 1] += piece.text
            mergedWordLike[mergedWordLike.count - 1] = mergedWordLike.last == true || piece.isWordLike
            continue
        }

        if
            isText,
            let lastKind = mergedKinds.last,
            lastKind == .text,
            isCJKLineStartProhibitedSegment(piece.text),
            containsCJK(mergedSegments.last ?? "")
        {
            mergedSegments[mergedSegments.count - 1] += piece.text
            mergedWordLike[mergedWordLike.count - 1] = mergedWordLike.last == true || piece.isWordLike
            continue
        }

        if
            isText,
            let lastKind = mergedKinds.last,
            lastKind == .text,
            endsWithMyanmarMedialGlue(mergedSegments.last ?? "")
        {
            mergedSegments[mergedSegments.count - 1] += piece.text
            mergedWordLike[mergedWordLike.count - 1] = mergedWordLike.last == true || piece.isWordLike
            continue
        }

        if
            isText,
            let lastKind = mergedKinds.last,
            lastKind == .text,
            piece.isWordLike,
            containsArabicScript(piece.text),
            endsWithArabicNoSpacePunctuation(mergedSegments.last ?? "")
        {
            mergedSegments[mergedSegments.count - 1] += piece.text
            mergedWordLike[mergedWordLike.count - 1] = true
            continue
        }

        if
            isText,
            !piece.isWordLike,
            let lastKind = mergedKinds.last,
            lastKind == .text,
            piece.text.count == 1,
            piece.text != "-",
            piece.text != "—",
            isRepeatedSingleCharRun(mergedSegments.last ?? "", character: piece.text)
        {
            mergedSegments[mergedSegments.count - 1] += piece.text
            continue
        }

        if
            isText,
            !piece.isWordLike,
            let lastKind = mergedKinds.last,
            lastKind == .text,
            (
                isLeftStickyPunctuationSegment(piece.text) ||
                (piece.text == "-" && mergedWordLike.last == true)
            )
        {
            mergedSegments[mergedSegments.count - 1] += piece.text
            continue
        }

        mergedSegments.append(piece.text)
        mergedWordLike.append(piece.isWordLike)
        mergedKinds.append(piece.kind)
        mergedStarts.append(piece.start)
    }

    if mergedSegments.count > 1 {
        for index in 1..<mergedSegments.count {
            if
                mergedKinds[index] == .text,
                !mergedWordLike[index],
                isEscapedQuoteClusterSegment(mergedSegments[index]),
                mergedKinds[index - 1] == .text
            {
                mergedSegments[index - 1] += mergedSegments[index]
                mergedWordLike[index - 1] = mergedWordLike[index - 1] || mergedWordLike[index]
                mergedSegments[index] = ""
            }
        }

        if mergedSegments.count > 1 {
            for index in stride(from: mergedSegments.count - 2, through: 0, by: -1) {
                if
                    mergedKinds[index] == .text,
                    !mergedWordLike[index],
                    isForwardStickyClusterSegment(mergedSegments[index])
                {
                    var next = index + 1
                    while next < mergedSegments.count && mergedSegments[next].isEmpty {
                        next += 1
                    }
                    if next < mergedSegments.count, mergedKinds[next] == .text {
                        mergedSegments[next] = mergedSegments[index] + mergedSegments[next]
                        mergedStarts[next] = mergedStarts[index]
                        mergedSegments[index] = ""
                    }
                }
            }
        }
    }

    var compactSegments: [String] = []
    var compactWordLike: [Bool] = []
    var compactKinds: [SegmentBreakKind] = []
    var compactStarts: [Int] = []

    for index in mergedSegments.indices where !mergedSegments[index].isEmpty {
        compactSegments.append(mergedSegments[index])
        compactWordLike.append(mergedWordLike[index])
        compactKinds.append(mergedKinds[index])
        compactStarts.append(mergedStarts[index])
    }

    var segmentation = MergedSegmentation(
        segments: compactSegments,
        wordLike: compactWordLike,
        kinds: compactKinds,
        starts: compactStarts
    )

    segmentation = mergeGlueConnectedTextRuns(segmentation)
    segmentation = mergeUrlLikeRuns(segmentation)
    segmentation = mergeUrlQueryRuns(segmentation)
    segmentation = mergeNumericRuns(segmentation)
    segmentation = splitHyphenatedNumericRuns(segmentation)
    segmentation = mergeASCIIPunctuationChains(segmentation)
    segmentation = mergeCJKStartProhibitedRuns(segmentation)
    segmentation = carryTrailingForwardStickyAcrossCJKBoundary(segmentation)
    segmentation = carryLeadingArabicMarks(segmentation, whiteSpaceProfile: whiteSpaceProfile)

    return segmentation
}

private func splitIntoPieces(_ text: String, whiteSpaceProfile: WhiteSpaceProfile) -> [SegmentationPiece] {
    if requiresDictionarySegmentation(text) {
        return splitByTokenizer(text, whiteSpaceProfile: whiteSpaceProfile)
    }
    return splitByScanner(text, whiteSpaceProfile: whiteSpaceProfile)
}

private func splitByScanner(_ text: String, whiteSpaceProfile: WhiteSpaceProfile) -> [SegmentationPiece] {
    if text.utf8.allSatisfy({ $0 < 0x80 }) {
        return splitByScannerASCII(text, whiteSpaceProfile: whiteSpaceProfile)
    }
    return splitByScannerGeneric(text, whiteSpaceProfile: whiteSpaceProfile)
}

private func splitByTokenizer(_ text: String, whiteSpaceProfile: WhiteSpaceProfile) -> [SegmentationPiece] {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    if let language = tokenizerLocale?.language.languageCode?.identifier {
        tokenizer.setLanguage(NLLanguage(rawValue: language))
    }

    var pieces: [SegmentationPiece] = []
    var cursor = text.startIndex

    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        if cursor < range.lowerBound {
            let gapStart = text.distance(from: text.startIndex, to: cursor)
            pieces.append(contentsOf: splitNonWordSegment(String(text[cursor..<range.lowerBound]), start: gapStart, whiteSpaceProfile: whiteSpaceProfile))
        }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        pieces.append(SegmentationPiece(text: String(text[range]), isWordLike: true, kind: .text, start: start))
        cursor = range.upperBound
        return true
    }

    if cursor < text.endIndex {
        let start = text.distance(from: text.startIndex, to: cursor)
        pieces.append(contentsOf: splitNonWordSegment(String(text[cursor..<text.endIndex]), start: start, whiteSpaceProfile: whiteSpaceProfile))
    }

    return pieces
}

private func splitByScannerASCII(_ text: String, whiteSpaceProfile: WhiteSpaceProfile) -> [SegmentationPiece] {
    let bytes = Array(text.utf8)
    var pieces: [SegmentationPiece] = []
    var index = 0

    while index < bytes.count {
        let byte = bytes[index]
        if isASCIIWordByte(byte) {
            let start = index
            index += 1
            while index < bytes.count, isASCIIWordByte(bytes[index]) {
                index += 1
            }
            let segment = String(bytes: bytes[start..<index], encoding: .utf8) ?? ""
            pieces.append(SegmentationPiece(text: segment, isWordLike: true, kind: .text, start: start))
            continue
        }

        let kind = classifyASCIIBreakKind(byte, whiteSpaceProfile: whiteSpaceProfile)
        let start = index
        index += 1
        if shouldCoalesce(kind) {
            while index < bytes.count, !isASCIIWordByte(bytes[index]), classifyASCIIBreakKind(bytes[index], whiteSpaceProfile: whiteSpaceProfile) == kind {
                index += 1
            }
        }
        let segment = String(bytes: bytes[start..<index], encoding: .utf8) ?? ""
        pieces.append(SegmentationPiece(text: segment, isWordLike: false, kind: kind, start: start))
    }

    return pieces
}

private func splitByScannerGeneric(_ text: String, whiteSpaceProfile: WhiteSpaceProfile) -> [SegmentationPiece] {
    var pieces: [SegmentationPiece] = []
    var currentWordLike: Bool?
    var segmentStart = text.startIndex

    func flush(to end: String.Index) {
        guard segmentStart < end, let currentWordLike else { return }
        let start = text.distance(from: text.startIndex, to: segmentStart)
        let segment = String(text[segmentStart..<end])
        if currentWordLike {
            pieces.append(SegmentationPiece(text: segment, isWordLike: true, kind: .text, start: start))
        } else {
            pieces.append(contentsOf: splitNonWordSegment(segment, start: start, whiteSpaceProfile: whiteSpaceProfile))
        }
    }

    for index in text.indices {
        let character = text[index]
        let wordLike = isSimpleWordCharacter(character)
        if currentWordLike == wordLike {
            continue
        }
        flush(to: index)
        currentWordLike = wordLike
        segmentStart = index
    }

    flush(to: text.endIndex)
    return pieces
}

private func splitNonWordSegment(
    _ text: String,
    start: Int,
    whiteSpaceProfile: WhiteSpaceProfile
) -> [SegmentationPiece] {
    var pieces: [SegmentationPiece] = []
    var currentKind: SegmentBreakKind?
    var currentText = ""
    var currentStart = start
    var offset = 0

    for character in text {
        let characterText = String(character)
        if let split = splitLeadingSpaceAndMarks(characterText) {
            if let existingKind = currentKind {
                pieces.append(SegmentationPiece(text: currentText, isWordLike: false, kind: existingKind, start: currentStart))
                currentKind = nil
                currentText = ""
            }

            let spaceKind: SegmentBreakKind = whiteSpaceProfile.preserveOrdinarySpaces || whiteSpaceProfile.preserveHardBreaks
                ? .preservedSpace
                : .space
            pieces.append(SegmentationPiece(text: split.space, isWordLike: false, kind: spaceKind, start: start + offset))
            pieces.append(SegmentationPiece(text: split.marks, isWordLike: false, kind: .text, start: start + offset + split.space.count))
            offset += characterText.count
            continue
        }

        let kind = classifyBreakKind(for: character, whiteSpaceProfile: whiteSpaceProfile)
        if
            let currentKind,
            currentKind == kind,
            shouldCoalesce(kind),
            (kind != .text || shouldCoalesceNonWordText(currentText: currentText, nextCharacter: character))
        {
            currentText.append(character)
            offset += 1
            continue
        }

        if let currentKind {
            pieces.append(SegmentationPiece(text: currentText, isWordLike: false, kind: currentKind, start: currentStart))
        }

        currentKind = kind
        currentText = String(character)
        currentStart = start + offset
        offset += 1
    }

    if let currentKind {
        pieces.append(SegmentationPiece(text: currentText, isWordLike: false, kind: currentKind, start: currentStart))
    }

    return pieces
}

private func classifyASCIIBreakKind(_ byte: UInt8, whiteSpaceProfile: WhiteSpaceProfile) -> SegmentBreakKind {
    if whiteSpaceProfile.preserveOrdinarySpaces || whiteSpaceProfile.preserveHardBreaks {
        if byte == 0x20 { return .preservedSpace }
        if byte == 0x09 { return .tab }
        if whiteSpaceProfile.preserveHardBreaks, byte == 0x0A { return .hardBreak }
    }
    if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C { return .space }
    return .text
}

private func classifyBreakKind(for character: Character, whiteSpaceProfile: WhiteSpaceProfile) -> SegmentBreakKind {
    if whiteSpaceProfile.preserveOrdinarySpaces || whiteSpaceProfile.preserveHardBreaks {
        if character == " " { return .preservedSpace }
        if character == "\t" { return .tab }
        if whiteSpaceProfile.preserveHardBreaks, character == "\n" { return .hardBreak }
    }

    if character == " " || character == "\t" || character == "\n" || character == "\r" || character == "\u{000C}" {
        return .space
    }

    let text = String(character)
    if text == "\u{00A0}" || text == "\u{202F}" || text == "\u{2060}" || text == "\u{FEFF}" {
        return .glue
    }
    if text == "\u{200B}" { return .zeroWidthBreak }
    if text == "\u{00AD}" { return .softHyphen }
    return .text
}

private func shouldCoalesce(_ kind: SegmentBreakKind) -> Bool {
    switch kind {
    case .text, .tab, .hardBreak, .zeroWidthBreak, .softHyphen:
        return false
    default:
        return true
    }
}

private func shouldCoalesceNonWordText(currentText: String, nextCharacter: Character) -> Bool {
    !currentText.isEmpty &&
        currentText.allSatisfy(isCombiningMark) &&
        isCombiningMark(nextCharacter)
}

private func mergeGlueConnectedTextRuns(_ segmentation: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLike: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    var read = 0
    while read < segmentation.count {
        var text = segmentation.segments[read]
        var isWordLike = segmentation.wordLike[read]
        var kind = segmentation.kinds[read]
        var start = segmentation.starts[read]

        if kind == .glue {
            var glueText = text
            let glueStart = start
            read += 1
            while read < segmentation.count, segmentation.kinds[read] == .glue {
                glueText += segmentation.segments[read]
                read += 1
            }

            if read < segmentation.count, segmentation.kinds[read] == .text {
                text = glueText + segmentation.segments[read]
                isWordLike = segmentation.wordLike[read]
                kind = .text
                start = glueStart
                read += 1
            } else {
                texts.append(glueText)
                wordLike.append(false)
                kinds.append(.glue)
                starts.append(glueStart)
                continue
            }
        } else {
            read += 1
        }

        if kind == .text {
            while read < segmentation.count, segmentation.kinds[read] == .glue {
                var glueText = ""
                while read < segmentation.count, segmentation.kinds[read] == .glue {
                    glueText += segmentation.segments[read]
                    read += 1
                }

                if read < segmentation.count, segmentation.kinds[read] == .text {
                    text += glueText + segmentation.segments[read]
                    isWordLike = isWordLike || segmentation.wordLike[read]
                    read += 1
                    continue
                }

                text += glueText
            }
        }

        texts.append(text)
        wordLike.append(isWordLike)
        kinds.append(kind)
        starts.append(start)
    }

    return MergedSegmentation(segments: texts, wordLike: wordLike, kinds: kinds, starts: starts)
}

private func mergeUrlLikeRuns(_ segmentation: MergedSegmentation) -> MergedSegmentation {
    var texts = segmentation.segments
    var wordLike = segmentation.wordLike
    var kinds = segmentation.kinds
    let starts = segmentation.starts

    for index in texts.indices {
        guard kinds[index] == .text, isURLLikeRunStart(segmentation, index: index) else { continue }

        var next = index + 1
        while next < segmentation.count, !isTextRunBoundary(segmentation.kinds[next]) {
            texts[index] += texts[next]
            wordLike[index] = true
            let endsQueryPrefix = texts[next].contains("?")
            kinds[next] = .text
            texts[next] = ""
            next += 1
            if endsQueryPrefix {
                break
            }
        }
    }

    return compactMergedSegmentation(segments: texts, wordLike: wordLike, kinds: kinds, starts: starts)
}

private func mergeUrlQueryRuns(_ segmentation: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLike: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    var index = 0
    while index < segmentation.count {
        let text = segmentation.segments[index]
        texts.append(text)
        wordLike.append(segmentation.wordLike[index])
        kinds.append(segmentation.kinds[index])
        starts.append(segmentation.starts[index])

        if isURLQueryBoundarySegment(text) {
            let nextIndex = index + 1
            if nextIndex < segmentation.count, !isTextRunBoundary(segmentation.kinds[nextIndex]) {
                var queryText = ""
                let queryStart = segmentation.starts[nextIndex]
                var read = nextIndex
                while read < segmentation.count, !isTextRunBoundary(segmentation.kinds[read]) {
                    queryText += segmentation.segments[read]
                    read += 1
                }
                if !queryText.isEmpty {
                    texts.append(queryText)
                    wordLike.append(true)
                    kinds.append(.text)
                    starts.append(queryStart)
                    index = read - 1
                }
            }
        }

        index += 1
    }

    return MergedSegmentation(segments: texts, wordLike: wordLike, kinds: kinds, starts: starts)
}

private func mergeNumericRuns(_ segmentation: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLike: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    var index = 0
    while index < segmentation.count {
        let text = segmentation.segments[index]
        let kind = segmentation.kinds[index]

        if kind == .text, isNumericRunSegment(text), segmentContainsDecimalDigit(text) {
            var mergedText = text
            var next = index + 1
            while next < segmentation.count, segmentation.kinds[next] == .text, isNumericRunSegment(segmentation.segments[next]) {
                mergedText += segmentation.segments[next]
                next += 1
            }

            texts.append(mergedText)
            wordLike.append(true)
            kinds.append(.text)
            starts.append(segmentation.starts[index])
            index = next
            continue
        }

        texts.append(text)
        wordLike.append(segmentation.wordLike[index])
        kinds.append(kind)
        starts.append(segmentation.starts[index])
        index += 1
    }

    return MergedSegmentation(segments: texts, wordLike: wordLike, kinds: kinds, starts: starts)
}

private func splitHyphenatedNumericRuns(_ segmentation: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLike: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    for index in 0..<segmentation.count {
        let text = segmentation.segments[index]
        if segmentation.kinds[index] == .text, text.contains("-") {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            let shouldSplit = parts.count > 1 && parts.allSatisfy { !$0.isEmpty && segmentContainsDecimalDigit($0) && isNumericRunSegment($0) }

            if shouldSplit {
                var offset = 0
                for partIndex in parts.indices {
                    let splitText = partIndex < parts.count - 1 ? "\(parts[partIndex])-" : parts[partIndex]
                    texts.append(splitText)
                    wordLike.append(true)
                    kinds.append(.text)
                    starts.append(segmentation.starts[index] + offset)
                    offset += splitText.count
                }
                continue
            }
        }

        texts.append(text)
        wordLike.append(segmentation.wordLike[index])
        kinds.append(segmentation.kinds[index])
        starts.append(segmentation.starts[index])
    }

    return MergedSegmentation(segments: texts, wordLike: wordLike, kinds: kinds, starts: starts)
}

private func mergeASCIIPunctuationChains(_ segmentation: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLike: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    var index = 0
    while index < segmentation.count {
        let text = segmentation.segments[index]
        let kind = segmentation.kinds[index]
        let isWordLike = segmentation.wordLike[index]

        if kind == .text, isWordLike, isASCIIPunctuationChainSegment(text) {
            var mergedText = text
            var next = index + 1
            while trailingASCIIPunctuationJoiners(mergedText), next < segmentation.count, segmentation.kinds[next] == .text, segmentation.wordLike[next], isASCIIPunctuationChainSegment(segmentation.segments[next]) {
                mergedText += segmentation.segments[next]
                next += 1
            }

            texts.append(mergedText)
            wordLike.append(true)
            kinds.append(.text)
            starts.append(segmentation.starts[index])
            index = next
            continue
        }

        texts.append(text)
        wordLike.append(isWordLike)
        kinds.append(kind)
        starts.append(segmentation.starts[index])
        index += 1
    }

    return MergedSegmentation(segments: texts, wordLike: wordLike, kinds: kinds, starts: starts)
}

private func carryTrailingForwardStickyAcrossCJKBoundary(_ segmentation: MergedSegmentation) -> MergedSegmentation {
    var texts = segmentation.segments
    var starts = segmentation.starts

    for index in 0..<(texts.count - 1) {
        guard segmentation.kinds[index] == .text, segmentation.kinds[index + 1] == .text else { continue }
        guard containsCJK(texts[index]), containsCJK(texts[index + 1]) else { continue }
        guard let split = splitTrailingForwardStickyCluster(texts[index]) else { continue }
        texts[index] = split.head
        texts[index + 1] = split.tail + texts[index + 1]
        starts[index + 1] = starts[index] + split.head.count
    }

    return MergedSegmentation(segments: texts, wordLike: segmentation.wordLike, kinds: segmentation.kinds, starts: starts)
}

private func mergeCJKStartProhibitedRuns(_ segmentation: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLike: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    for index in 0..<segmentation.count {
        let text = segmentation.segments[index]
        let kind = segmentation.kinds[index]

        if
            kind == .text,
            let lastKind = kinds.last,
            lastKind == .text,
            isCJKLineStartProhibitedSegment(text),
            let previous = texts.last,
            containsCJK(previous)
        {
            texts[texts.count - 1] += text
            wordLike[wordLike.count - 1] = wordLike.last == true || segmentation.wordLike[index]
            continue
        }

        texts.append(text)
        wordLike.append(segmentation.wordLike[index])
        kinds.append(kind)
        starts.append(segmentation.starts[index])
    }

    return MergedSegmentation(segments: texts, wordLike: wordLike, kinds: kinds, starts: starts)
}

private func carryLeadingArabicMarks(
    _ segmentation: MergedSegmentation,
    whiteSpaceProfile: WhiteSpaceProfile
) -> MergedSegmentation {
    var texts = segmentation.segments
    var wordLike = segmentation.wordLike
    var kinds = segmentation.kinds
    var starts = segmentation.starts

    guard texts.count > 1 else {
        return segmentation
    }

    for index in 0..<(texts.count - 1) {
        guard let split = splitLeadingSpaceAndMarks(texts[index]) else { continue }
        if
            kinds[index + 1] == .text,
            containsArabicScript(texts[index + 1])
        {
            texts[index] = split.space
            wordLike[index] = false
            kinds[index] = whiteSpaceProfile.preserveOrdinarySpaces ? .preservedSpace : .space
            texts[index + 1] = split.marks + texts[index + 1]
            starts[index + 1] = starts[index] + split.space.count
        }
    }

    return MergedSegmentation(segments: texts, wordLike: wordLike, kinds: kinds, starts: starts)
}

private func compactMergedSegmentation(
    segments: [String],
    wordLike: [Bool],
    kinds: [SegmentBreakKind],
    starts: [Int]
) -> MergedSegmentation {
    var compactSegments: [String] = []
    var compactWordLike: [Bool] = []
    var compactKinds: [SegmentBreakKind] = []
    var compactStarts: [Int] = []

    for index in segments.indices where !segments[index].isEmpty {
        compactSegments.append(segments[index])
        compactWordLike.append(wordLike[index])
        compactKinds.append(kinds[index])
        compactStarts.append(starts[index])
    }

    return MergedSegmentation(segments: compactSegments, wordLike: compactWordLike, kinds: compactKinds, starts: compactStarts)
}

private func compileAnalysisChunks(
    _ segmentation: MergedSegmentation,
    whiteSpaceProfile: WhiteSpaceProfile
) -> [PreparedLineChunk] {
    guard segmentation.count > 0 else {
        return []
    }

    guard whiteSpaceProfile.preserveHardBreaks else {
        return [PreparedLineChunk(startSegmentIndex: 0, endSegmentIndex: segmentation.count, consumedEndSegmentIndex: segmentation.count)]
    }

    var chunks: [PreparedLineChunk] = []
    var startSegmentIndex = 0

    for index in 0..<segmentation.count where segmentation.kinds[index] == .hardBreak {
        chunks.append(
            PreparedLineChunk(
                startSegmentIndex: startSegmentIndex,
                endSegmentIndex: index,
                consumedEndSegmentIndex: index + 1
            )
        )
        startSegmentIndex = index + 1
    }

    if startSegmentIndex < segmentation.count {
        chunks.append(
            PreparedLineChunk(
                startSegmentIndex: startSegmentIndex,
                endSegmentIndex: segmentation.count,
                consumedEndSegmentIndex: segmentation.count
            )
        )
    }

    return chunks
}

private func isASCIIWordByte(_ byte: UInt8) -> Bool {
    (byte >= 0x41 && byte <= 0x5A) ||
    (byte >= 0x61 && byte <= 0x7A) ||
    (byte >= 0x30 && byte <= 0x39) ||
    byte == 0x27
}

private func isSimpleWordCharacter(_ character: Character) -> Bool {
    let scalars = character.unicodeScalars
    if scalars.count == 1, let scalar = scalars.first {
        return isWordScalar(scalar.value)
    }
    return scalars.allSatisfy { isWordScalar($0.value) }
}

private func isWordScalar(_ value: UInt32) -> Bool {
    if value <= 0x7A {
        return (value >= 0x41 && value <= 0x5A) ||
            (value >= 0x61 && value <= 0x7A) ||
            (value >= 0x30 && value <= 0x39) ||
            value == 0x27
    }
    if value >= 0xC0 && value <= 0xFF && value != 0xD7 && value != 0xF7 { return true }
    if value >= 0x100 && value <= 0x24F { return true }
    if value >= 0x300 && value <= 0x36F { return true }
    if value >= 0x370 && value <= 0x3FF { return true }
    if value >= 0x400 && value <= 0x4FF { return true }
    if value >= 0x600 && value <= 0x8FF { return true }
    if value >= 0x900 && value <= 0xD7F { return true }
    if value >= 0x4E00 && value <= 0x9FFF { return true }
    if value >= 0x3400 && value <= 0x4DBF { return true }
    if value >= 0x20000 && value <= 0x3134F { return true }
    if value >= 0x3040 && value <= 0x30FF { return true }
    if value >= 0xAC00 && value <= 0xD7AF { return true }
    if value >= 0x660 && value <= 0x669 { return true }
    if value >= 0x966 && value <= 0x96F { return true }
    guard let scalar = Unicode.Scalar(value) else { return false }
    return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
}

private func requiresDictionarySegmentation(_ text: String) -> Bool {
    if text.utf8.allSatisfy({ $0 < 0x80 }) { return false }
    return text.unicodeScalars.contains(where: isDictionarySegmentationScalar)
}

private func isDictionarySegmentationScalar(_ scalar: UnicodeScalar) -> Bool {
    let value = scalar.value
    return
        (0x0E00...0x0E7F).contains(value) ||
        (0x0E80...0x0EFF).contains(value) ||
        (0x1000...0x109F).contains(value) ||
        (0xAA60...0xAA7F).contains(value) ||
        (0xA9E0...0xA9FF).contains(value) ||
        (0x1780...0x17FF).contains(value) ||
        (0x19E0...0x19FF).contains(value)
}

private func isTextRunBoundary(_ kind: SegmentBreakKind) -> Bool {
    kind == .space || kind == .preservedSpace || kind == .zeroWidthBreak || kind == .hardBreak
}

private func isURLLikeRunStart(_ segmentation: MergedSegmentation, index: Int) -> Bool {
    let text = segmentation.segments[index]
    if text.hasPrefix("www.") { return true }
    guard index + 1 < segmentation.count, segmentation.kinds[index + 1] == .text else {
        return false
    }

    let next = segmentation.segments[index + 1]
    if isURLSchemeSegment(text) {
        return next == "//" || next.hasPrefix("//")
    }

    return isURLSchemeCore(text) && next.hasPrefix("://")
}

private func isURLSchemeSegment(_ text: String) -> Bool {
    guard text.count >= 2, text.last == ":" else { return false }
    return isURLSchemeCore(String(text.dropLast()))
}

private func isURLSchemeCore(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    let chars = Array(text)
    guard chars.first?.unicodeScalars.allSatisfy({ ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A) }) == true else {
        return false
    }
    for character in chars {
        guard let scalar = character.unicodeScalars.first else { return false }
        let value = scalar.value
        let isASCIIAlphaNum = (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A) || (value >= 0x30 && value <= 0x39)
        if !isASCIIAlphaNum, character != "+", character != ".", character != "-" {
            return false
        }
    }
    return true
}

private func isURLQueryBoundarySegment(_ text: String) -> Bool {
    text.contains("?") && (text.contains("://") || text.hasPrefix("www."))
}

private func segmentContainsDecimalDigit(_ text: String) -> Bool {
    text.contains { character in
        character.wholeNumberValue != nil
    }
}

private func isNumericRunSegment(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    return text.allSatisfy { character in
        let value = String(character)
        return character.wholeNumberValue != nil || numericJoinerChars.contains(value)
    }
}

private func isASCIIPunctuationChainSegment(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    var sawCore = false
    var sawTrailing = false

    for character in text {
        if sawTrailing {
            if character == "," || character == ":" || character == ";" {
                continue
            }
            return false
        }

        if character.isASCIIAlphaNumeric || character == "_" {
            sawCore = true
            continue
        }

        if sawCore, character == "," || character == ":" || character == ";" {
            sawTrailing = true
            continue
        }

        return false
    }

    return sawCore
}

private func trailingASCIIPunctuationJoiners(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    var sawJoiner = false
    for character in text.reversed() {
        if character == "," || character == ":" || character == ";" {
            sawJoiner = true
            continue
        }
        break
    }
    return sawJoiner
}

private func isLeftStickyPunctuationSegment(_ segment: String) -> Bool {
    if isEscapedQuoteClusterSegment(segment) { return true }
    var sawPunctuation = false
    for character in segment {
        let text = String(character)
        if leftStickyPunctuation.contains(text) {
            sawPunctuation = true
            continue
        }
        if sawPunctuation, isCombiningMark(character) {
            continue
        }
        return false
    }
    return sawPunctuation
}

private func isCJKLineStartProhibitedSegment(_ segment: String) -> Bool {
    guard !segment.isEmpty else { return false }
    return segment.allSatisfy { character in
        let text = String(character)
        return kinsokuStart.contains(text) || leftStickyPunctuation.contains(text)
    }
}

private func isForwardStickyClusterSegment(_ segment: String) -> Bool {
    if isEscapedQuoteClusterSegment(segment) { return true }
    guard !segment.isEmpty else { return false }
    return segment.allSatisfy { character in
        let text = String(character)
        return kinsokuEnd.contains(text) || forwardStickyGlue.contains(text) || isCombiningMark(character)
    }
}

private func isEscapedQuoteClusterSegment(_ segment: String) -> Bool {
    var sawQuote = false
    for character in segment {
        let text = String(character)
        if text == "\\" || isCombiningMark(character) {
            continue
        }
        if kinsokuEnd.contains(text) || leftStickyPunctuation.contains(text) || forwardStickyGlue.contains(text) {
            sawQuote = true
            continue
        }
        return false
    }
    return sawQuote
}

private func splitTrailingForwardStickyCluster(_ text: String) -> (head: String, tail: String)? {
    let characters = Array(text)
    var splitIndex = characters.count

    while splitIndex > 0 {
        let character = characters[splitIndex - 1]
        let value = String(character)
        if isCombiningMark(character) {
            splitIndex -= 1
            continue
        }
        if kinsokuEnd.contains(value) || forwardStickyGlue.contains(value) {
            splitIndex -= 1
            continue
        }
        break
    }

    guard splitIndex > 0, splitIndex < characters.count else { return nil }
    return (String(characters[..<splitIndex]), String(characters[splitIndex...]))
}

private func isRepeatedSingleCharRun(_ segment: String, character: String) -> Bool {
    guard !segment.isEmpty else { return false }
    return segment.allSatisfy { String($0) == character }
}

private func endsWithArabicNoSpacePunctuation(_ segment: String) -> Bool {
    guard containsArabicScript(segment), let last = segment.last else { return false }
    return arabicNoSpaceTrailingPunctuation.contains(String(last))
}

private func endsWithMyanmarMedialGlue(_ segment: String) -> Bool {
    guard let last = segment.last else { return false }
    return myanmarMedialGlue.contains(String(last))
}

private func splitLeadingSpaceAndMarks(_ segment: String) -> (space: String, marks: String)? {
    let scalars = Array(segment.unicodeScalars)
    guard scalars.count >= 2, scalars.first == " " else { return nil }

    let markScalars = scalars.dropFirst()
    guard markScalars.allSatisfy({ scalar in
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }) else {
        return nil
    }

    let marks = String(String.UnicodeScalarView(markScalars))
    guard !marks.isEmpty else { return nil }
    return (" ", marks)
}

public func endsWithClosingQuote(_ text: String) -> Bool {
    for character in text.reversed() {
        let value = String(character)
        if closingQuoteChars.contains(value) {
            return true
        }
        if !leftStickyPunctuation.contains(value) {
            return false
        }
    }
    return false
}

private func containsArabicScript(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        let value = scalar.value
        return (0x0600...0x06FF).contains(value) ||
            (0x0750...0x077F).contains(value) ||
            (0x08A0...0x08FF).contains(value)
    }
}

private func isCombiningMark(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }
}

public func containsCJK(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        let value = scalar.value
        if
            (0x4E00...0x9FFF).contains(value) ||
            (0x3400...0x4DBF).contains(value) ||
            (0x20000...0x2A6DF).contains(value) ||
            (0x2A700...0x2B73F).contains(value) ||
            (0x2B740...0x2B81F).contains(value) ||
            (0x2B820...0x2CEAF).contains(value) ||
            (0x2CEB0...0x2EBEF).contains(value) ||
            (0x30000...0x3134F).contains(value) ||
            (0xF900...0xFAFF).contains(value) ||
            (0x2F800...0x2FA1F).contains(value) ||
            (0x3000...0x303F).contains(value) ||
            (0x3040...0x309F).contains(value) ||
            (0x30A0...0x30FF).contains(value) ||
            (0xAC00...0xD7AF).contains(value) ||
            (0xFF00...0xFFEF).contains(value)
        {
            return true
        }
    }
    return false
}

private extension Character {
    var isASCIIAlphaNumeric: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        let value = scalar.value
        return (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) || (0x30...0x39).contains(value)
    }
}
