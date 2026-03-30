import Foundation
import NaturalLanguage

private struct SegmentationPiece {
    var text: String
    var isWordLike: Bool
    var kind: SegmentBreakKind
}

private struct ScalarSegmentRange {
    var start: String.Index
    var end: String.Index
    var kind: SegmentBreakKind
    var isWordLike: Bool
}

private let leftStickyScalars: Set<UInt32> = [
    0x002E, 0x002C, 0x0021, 0x003F, 0x003A, 0x003B, 0x0025, 0x0029, 0x005D, 0x007D, 0x0022,
    0x201D, 0x2019, 0x00BB, 0x203A, 0x2026,
]

private let rightStickyScalars: Set<UInt32> = [
    0x0028, 0x005B, 0x007B, 0x0022, 0x201C, 0x2018, 0x00AB, 0x2039,
]

private let glueScalars: Set<UnicodeScalar> = [
    "\u{00A0}",
    "\u{202F}",
    "\u{2060}",
    "\u{FEFF}",
]

nonisolated(unsafe) private var tokenizerLocale: Locale?

func setAnalysisLocale(_ locale: Locale?) {
    tokenizerLocale = locale
}

func normalizeWhitespaceNormal(_ text: String) -> String {
    if text.isEmpty || isAlreadyNormalizedWhitespaceNormal(text) {
        return text
    }

    // Fast ASCII path
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

func normalizeWhitespacePreWrap(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .replacingOccurrences(of: "\u{000C}", with: "\n")
}

enum AnalysisSubProfile {
    nonisolated(unsafe) static var normalizeMs: Double = 0
    nonisolated(unsafe) static var splitMs: Double = 0
    nonisolated(unsafe) static var mergeMs: Double = 0
    nonisolated(unsafe) static var expandMs: Double = 0
    nonisolated(unsafe) static var finalizeMs: Double = 0
    nonisolated(unsafe) static var count: Int = 0

    static func reset() { normalizeMs = 0; splitMs = 0; mergeMs = 0; expandMs = 0; finalizeMs = 0; count = 0 }
    static func summary() -> String {
        "  analyzeText x\(count): norm=\(f(normalizeMs))ms split=\(f(splitMs))ms merge=\(f(mergeMs))ms expand=\(f(expandMs))ms finalize=\(f(finalizeMs))ms"
    }
    private static func f(_ v: Double) -> String { String(format: "%.1f", v) }
}

func analyzeText(_ text: String, whiteSpace: WhiteSpaceMode = .normal) -> TextAnalysisResult {
    let a0 = CFAbsoluteTimeGetCurrent()
    let normalized: String = switch whiteSpace {
    case .normal:
        normalizeWhitespaceNormal(text)
    case .preWrap:
        normalizeWhitespacePreWrap(text)
    }
    let a1 = CFAbsoluteTimeGetCurrent()

    guard !normalized.isEmpty else {
        return TextAnalysisResult(
            normalized: "",
            segments: [],
            kinds: [],
            wordLike: [],
            chunks: []
        )
    }

    if !requiresDictionarySegmentation(normalized) {
        let result = analyzeScalarText(normalized, whiteSpace: whiteSpace)
        let a5 = CFAbsoluteTimeGetCurrent()

        AnalysisSubProfile.normalizeMs += (a1 - a0) * 1000
        AnalysisSubProfile.splitMs += (a5 - a1) * 1000
        AnalysisSubProfile.mergeMs += 0
        AnalysisSubProfile.expandMs += 0
        AnalysisSubProfile.finalizeMs += 0
        AnalysisSubProfile.count += 1

        return result
    }

    let pieces = splitIntoPieces(normalized, whiteSpace: whiteSpace)
    let a2 = CFAbsoluteTimeGetCurrent()
    let merged = mergePunctuation(in: pieces)
    let a3 = CFAbsoluteTimeGetCurrent()
    let expanded = splitCJKSegments(in: merged)
    let compact = expanded.filter { !$0.text.isEmpty }
    let a4 = CFAbsoluteTimeGetCurrent()

    let result = TextAnalysisResult(
        normalized: normalized,
        segments: compact.map(\.text),
        kinds: compact.map(\.kind),
        wordLike: compact.map(\.isWordLike),
        chunks: compileChunks(from: compact.map(\.kind))
    )
    let a5 = CFAbsoluteTimeGetCurrent()

    AnalysisSubProfile.normalizeMs += (a1 - a0) * 1000
    AnalysisSubProfile.splitMs += (a2 - a1) * 1000
    AnalysisSubProfile.mergeMs += (a3 - a2) * 1000
    AnalysisSubProfile.expandMs += (a4 - a3) * 1000
    AnalysisSubProfile.finalizeMs += (a5 - a4) * 1000
    AnalysisSubProfile.count += 1

    return result
}

/// High-performance scanner using raw UTF-8 bytes with integer offsets.
/// Avoids all String.Index overhead. Handles ASCII + common Unicode punctuation
/// (smart quotes, em-dashes are 3-byte E2 80 xx sequences).
private func analyzeScalarText(_ text: String, whiteSpace: WhiteSpaceMode) -> TextAnalysisResult {
    guard !text.isEmpty else {
        return TextAnalysisResult(normalized: text, segments: [], kinds: [], wordLike: [], chunks: [])
    }
    // Try zero-copy access to the UTF-8 buffer; fall back to Array copy
    if let result = text.utf8.withContiguousStorageIfAvailable({ buffer in
        analyzeUTF8Buffer(buffer, text: text, whiteSpace: whiteSpace)
    }) {
        return result
    }
    let utf8Bytes = Array(text.utf8)
    return utf8Bytes.withUnsafeBufferPointer { buffer in
        analyzeUTF8Buffer(buffer, text: text, whiteSpace: whiteSpace)
    }
}

private func analyzeUTF8Buffer(
    _ buffer: UnsafeBufferPointer<UInt8>, text: String, whiteSpace: WhiteSpaceMode
) -> TextAnalysisResult {
    let count = buffer.count
    guard count > 0 else {
        return TextAnalysisResult(normalized: text, segments: [], kinds: [], wordLike: [], chunks: [])
    }
    return withExtendedLifetime(text) {

        // Output arrays built directly — no intermediate records
        var segments: [String] = []
        var kinds: [SegmentBreakKind] = []
        var wordLike: [Bool] = []
        var chunks: [PreparedLineChunk] = []
        var chunkStart = 0

        // Right-sticky buffer as byte offsets
        var rsStart = -1
        var rsEnd = -1

        func appendSeg(_ start: Int, _ end: Int, _ kind: SegmentBreakKind, _ isWord: Bool) {
            guard start < end else { return }
            let s = String(unsafeUninitializedCapacity: end - start) { buf in
                _ = buf.initialize(from: UnsafeBufferPointer(start: buffer.baseAddress! + start, count: end - start))
                return end - start
            }
            segments.append(s)
            kinds.append(kind)
            wordLike.append(isWord)
            if kind == .hardBreak {
                let idx = segments.count - 1
                chunks.append(PreparedLineChunk(startSegmentIndex: chunkStart, endSegmentIndex: idx, consumedEndSegmentIndex: idx + 1))
                chunkStart = idx + 1
            }
        }

        func emitWord(_ start: Int, _ end: Int) {
            if rsStart >= 0 {
                appendSeg(rsStart, end, .text, true)
                rsStart = -1; rsEnd = -1
            } else {
                appendSeg(start, end, .text, true)
            }
        }

        func emitNonWordText(_ start: Int, _ end: Int) {
            // Check left-sticky: all bytes in [start..<end] are left-sticky punct
            if isAllLeftSticky(buffer, start, end), let last = kinds.indices.last, kinds[last] == .text {
                // Extend previous segment (rebuild String)
                let prevStart = segments[last].utf8.count
                _ = prevStart // we need to rebuild from contiguous bytes
                // Actually: we can just append to the previous segment string
                let extra = String(unsafeUninitializedCapacity: end - start) { buf in
                    _ = buf.initialize(from: UnsafeBufferPointer(start: buffer.baseAddress! + start, count: end - start))
                    return end - start
                }
                segments[last] += extra
                return
            }

            // Check right-sticky
            if isAllRightSticky(buffer, start, end) {
                if rsStart >= 0 { rsEnd = end } else { rsStart = start; rsEnd = end }
                return
            }

            if rsStart >= 0 {
                appendSeg(rsStart, end, .text, false)
                rsStart = -1; rsEnd = -1
            } else {
                appendSeg(start, end, .text, false)
            }
        }

        var i = 0
        while i < count {
            let b = buffer[i]

            // ASCII fast path (covers >95% of English text)
            if b < 0x80 {
                if isASCIIWordByte(b) {
                    let start = i
                    i += 1
                    while i < count && buffer[i] < 0x80 && isASCIIWordByte(buffer[i]) { i += 1 }
                    emitWord(start, i)
                } else {
                    let kind = classifyASCIIBreakKind(b, whiteSpace: whiteSpace)
                    let start = i
                    i += 1
                    while i < count && buffer[i] < 0x80 && !isASCIIWordByte(buffer[i]) &&
                          classifyASCIIBreakKind(buffer[i], whiteSpace: whiteSpace) == kind { i += 1 }
                    if kind == .text {
                        emitNonWordText(start, i)
                    } else {
                        if rsStart >= 0 { appendSeg(rsStart, rsEnd, .text, false); rsStart = -1; rsEnd = -1 }
                        appendSeg(start, i, kind, false)
                    }
                }
                continue
            }

            // Multi-byte UTF-8: decode scalar value
            let (scalarValue, seqLen) = decodeUTF8Scalar(buffer, at: i, count: count)

            if isWordScalar(scalarValue) {
                let start = i
                i += seqLen
                // Continue scanning word
                while i < count {
                    if buffer[i] < 0x80 {
                        if isASCIIWordByte(buffer[i]) { i += 1; continue } else { break }
                    }
                    let (sv, sl) = decodeUTF8Scalar(buffer, at: i, count: count)
                    if isWordScalar(sv) { i += sl } else { break }
                }
                emitWord(start, i)
            } else {
                let kind = classifyScalarValueBreakKind(scalarValue, whiteSpace: whiteSpace)
                let start = i
                i += seqLen
                while i < count {
                    if buffer[i] < 0x80 {
                        if isASCIIWordByte(buffer[i]) { break }
                        if classifyASCIIBreakKind(buffer[i], whiteSpace: whiteSpace) != kind { break }
                        i += 1; continue
                    }
                    let (sv, sl) = decodeUTF8Scalar(buffer, at: i, count: count)
                    if isWordScalar(sv) { break }
                    if classifyScalarValueBreakKind(sv, whiteSpace: whiteSpace) != kind { break }
                    i += sl
                }
                if kind == .text {
                    emitNonWordText(start, i)
                } else {
                    if rsStart >= 0 { appendSeg(rsStart, rsEnd, .text, false); rsStart = -1; rsEnd = -1 }
                    appendSeg(start, i, kind, false)
                }
            }
        }

        if rsStart >= 0 { appendSeg(rsStart, rsEnd, .text, false) }
        if chunkStart < segments.count {
            chunks.append(PreparedLineChunk(startSegmentIndex: chunkStart, endSegmentIndex: segments.count, consumedEndSegmentIndex: segments.count))
        }

        return TextAnalysisResult(normalized: text, segments: segments, kinds: kinds, wordLike: wordLike, chunks: chunks)
    }
}

private func decodeUTF8Scalar(_ buf: UnsafeBufferPointer<UInt8>, at i: Int, count: Int) -> (UInt32, Int) {
    let b0 = buf[i]
    if b0 < 0xC0 { return (UInt32(b0), 1) } // unexpected continuation or ASCII
    if b0 < 0xE0 && i + 1 < count {
        return (UInt32(b0 & 0x1F) << 6 | UInt32(buf[i+1] & 0x3F), 2)
    }
    if b0 < 0xF0 && i + 2 < count {
        return (UInt32(b0 & 0x0F) << 12 | UInt32(buf[i+1] & 0x3F) << 6 | UInt32(buf[i+2] & 0x3F), 3)
    }
    if i + 3 < count {
        return (UInt32(b0 & 0x07) << 18 | UInt32(buf[i+1] & 0x3F) << 12 | UInt32(buf[i+2] & 0x3F) << 6 | UInt32(buf[i+3] & 0x3F), 4)
    }
    return (0xFFFD, 1)
}

private func classifyScalarValueBreakKind(_ v: UInt32, whiteSpace: WhiteSpaceMode) -> SegmentBreakKind {
    if v == 0x20 { return whiteSpace == .preWrap ? .preservedSpace : .space }
    if v == 0x09 { return whiteSpace == .preWrap ? .tab : .space }
    if v == 0x0A { return whiteSpace == .preWrap ? .hardBreak : .space }
    if v == 0x0D || v == 0x0C { return .space }
    if v == 0xA0 || v == 0x202F || v == 0x2060 || v == 0xFEFF { return .glue }
    if v == 0x200B { return .zeroWidthBreak }
    if v == 0xAD { return .softHyphen }
    return .text
}

private func isAllLeftSticky(_ buf: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> Bool {
    var i = start
    while i < end {
        let b = buf[i]
        if b < 0x80 {
            // ASCII left-sticky: . , ! ? : ; % ) ] } "
            switch b {
            case 0x2E, 0x2C, 0x21, 0x3F, 0x3A, 0x3B, 0x25, 0x29, 0x5D, 0x7D, 0x22: i += 1
            default: return false
            }
        } else {
            let (sv, sl) = decodeUTF8Scalar(buf, at: i, count: end)
            if !leftStickyScalars.contains(sv) { return false }
            i += sl
        }
    }
    return true
}

private func isAllRightSticky(_ buf: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> Bool {
    var i = start
    while i < end {
        let b = buf[i]
        if b < 0x80 {
            switch b {
            case 0x28, 0x5B, 0x7B, 0x22: i += 1
            default: return false
            }
        } else {
            let (sv, sl) = decodeUTF8Scalar(buf, at: i, count: end)
            if !rightStickyScalars.contains(sv) { return false }
            i += sl
        }
    }
    return true
}

private func classifyScalarBreakKind(_ scalar: UnicodeScalar, whiteSpace: WhiteSpaceMode) -> SegmentBreakKind {
    let v = scalar.value
    if v == 0x20 { return whiteSpace == .preWrap ? .preservedSpace : .space }
    if v == 0x09 { return whiteSpace == .preWrap ? .tab : .space }
    if v == 0x0A { return whiteSpace == .preWrap ? .hardBreak : .space }
    if v == 0x0D || v == 0x0C { return .space }
    if v == 0xA0 || v == 0x202F || v == 0x2060 || v == 0xFEFF { return .glue }
    if v == 0x200B { return .zeroWidthBreak }
    if v == 0xAD { return .softHyphen }
    return .text
}

private func splitIntoPieces(_ text: String, whiteSpace: WhiteSpaceMode) -> [SegmentationPiece] {
    if requiresDictionarySegmentation(text) {
        return splitByTokenizer(text, whiteSpace: whiteSpace)
    }
    return splitByScanner(text, whiteSpace: whiteSpace)
}

private func splitByTokenizer(_ text: String, whiteSpace: WhiteSpaceMode) -> [SegmentationPiece] {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    if let language = tokenizerLocale?.language.languageCode?.identifier {
        tokenizer.setLanguage(NLLanguage(rawValue: language))
    }

    var pieces: [SegmentationPiece] = []
    var cursor = text.startIndex

    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        if cursor < range.lowerBound {
            pieces.append(contentsOf: splitNonWordSegment(String(text[cursor..<range.lowerBound]), whiteSpace: whiteSpace))
        }
        pieces.append(SegmentationPiece(text: String(text[range]), isWordLike: true, kind: .text))
        cursor = range.upperBound
        return true
    }

    if cursor < text.endIndex {
        pieces.append(contentsOf: splitNonWordSegment(String(text[cursor..<text.endIndex]), whiteSpace: whiteSpace))
    }

    return pieces
}

private func splitByScanner(_ text: String, whiteSpace: WhiteSpaceMode) -> [SegmentationPiece] {
    let utf8 = text.utf8
    let isAllASCII = utf8.allSatisfy { $0 < 0x80 }

    if isAllASCII {
        return splitByScannerASCII(text, whiteSpace: whiteSpace)
    }
    return splitByScannerGeneric(text, whiteSpace: whiteSpace)
}

/// Fast ASCII path: operates on UTF-8 bytes, avoids grapheme cluster overhead.
private func splitByScannerASCII(_ text: String, whiteSpace: WhiteSpaceMode) -> [SegmentationPiece] {
    var pieces: [SegmentationPiece] = []
    let utf8 = Array(text.utf8)
    var i = 0

    while i < utf8.count {
        let byte = utf8[i]
        let isWord = isASCIIWordByte(byte)

        if isWord {
            // Scan word run
            let start = i
            while i < utf8.count && isASCIIWordByte(utf8[i]) { i += 1 }
            let segment = String(bytes: utf8[start..<i], encoding: .utf8)!
            pieces.append(SegmentationPiece(text: segment, isWordLike: true, kind: .text))
        } else {
            // Scan non-word run of same break kind
            let kind = classifyASCIIBreakKind(byte, whiteSpace: whiteSpace)
            let start = i
            i += 1
            while i < utf8.count && !isASCIIWordByte(utf8[i]) && classifyASCIIBreakKind(utf8[i], whiteSpace: whiteSpace) == kind {
                i += 1
            }
            let segment = String(bytes: utf8[start..<i], encoding: .utf8)!
            pieces.append(SegmentationPiece(text: segment, isWordLike: false, kind: kind))
        }
    }
    return pieces
}

private func isASCIIWordByte(_ byte: UInt8) -> Bool {
    (byte >= 0x41 && byte <= 0x5A) || // A-Z
    (byte >= 0x61 && byte <= 0x7A) || // a-z
    (byte >= 0x30 && byte <= 0x39) || // 0-9
    byte == 0x27                      // apostrophe
}

private func classifyASCIIBreakKind(_ byte: UInt8, whiteSpace: WhiteSpaceMode) -> SegmentBreakKind {
    if byte == 0x20 { // space
        return whiteSpace == .preWrap ? .preservedSpace : .space
    }
    if byte == 0x09 { // tab
        return whiteSpace == .preWrap ? .tab : .space
    }
    if byte == 0x0A { // newline
        return whiteSpace == .preWrap ? .hardBreak : .space
    }
    return .text
}

private func splitByScannerGeneric(_ text: String, whiteSpace: WhiteSpaceMode) -> [SegmentationPiece] {
    var pieces: [SegmentationPiece] = []
    var currentWordLike: Bool?
    var segStart = text.startIndex

    func flushTo(_ end: String.Index) {
        guard segStart < end, let isWordLike = currentWordLike else { return }
        let segment = String(text[segStart..<end])
        if isWordLike {
            pieces.append(SegmentationPiece(text: segment, isWordLike: true, kind: .text))
        } else {
            pieces.append(contentsOf: splitNonWordSegment(segment, whiteSpace: whiteSpace))
        }
    }

    for index in text.indices {
        let character = text[index]
        let isWordLike = isSimpleWordCharacter(character)
        if currentWordLike == isWordLike { continue }
        flushTo(index)
        currentWordLike = isWordLike
        segStart = index
    }
    flushTo(text.endIndex)
    return pieces
}

private func splitNonWordSegment(_ text: String, whiteSpace: WhiteSpaceMode) -> [SegmentationPiece] {
    var pieces: [SegmentationPiece] = []
    var currentKind: SegmentBreakKind?
    var currentText = ""

    for character in text {
        let kind = classifyBreakKind(for: character, whiteSpace: whiteSpace)
        if currentKind == kind {
            currentText.append(character)
            continue
        }

        if let currentKind {
            pieces.append(SegmentationPiece(text: currentText, isWordLike: false, kind: currentKind))
        }

        currentKind = kind
        currentText = String(character)
    }

    if let currentKind {
        pieces.append(SegmentationPiece(text: currentText, isWordLike: false, kind: currentKind))
    }

    return pieces
}

private func classifyBreakKind(for character: Character, whiteSpace: WhiteSpaceMode) -> SegmentBreakKind {
    if whiteSpace == .preWrap {
        if character == " " {
            return .preservedSpace
        }
        if character == "\t" {
            return .tab
        }
        if character == "\n" {
            return .hardBreak
        }
    }

    if character == " " {
        return .space
    }

    if let scalar = character.unicodeScalars.first, glueScalars.contains(scalar) {
        return .glue
    }

    if character == "\u{200B}" {
        return .zeroWidthBreak
    }

    if character == "\u{00AD}" {
        return .softHyphen
    }

    return .text
}

private func requiresDictionarySegmentation(_ text: String) -> Bool {
    // Fast check: if all bytes are ASCII, no dictionary segmentation needed
    if text.utf8.allSatisfy({ $0 < 0x80 }) { return false }
    return text.unicodeScalars.contains(where: isDictionarySegmentationScalar)
}

private func isDictionarySegmentationScalar(_ scalar: UnicodeScalar) -> Bool {
    let value = scalar.value
    return
        (0x0E00...0x0E7F).contains(value) || // Thai
        (0x0E80...0x0EFF).contains(value) || // Lao
        (0x1000...0x109F).contains(value) || // Myanmar
        (0xAA60...0xAA7F).contains(value) || // Myanmar Extended-A
        (0xA9E0...0xA9FF).contains(value) || // Myanmar Extended-B
        (0x1780...0x17FF).contains(value) || // Khmer
        (0x19E0...0x19FF).contains(value) // Khmer Symbols
}

private func isSimpleWordCharacter(_ character: Character) -> Bool {
    // Fast path: single-scalar BMP character (covers >99% of Latin text)
    let scalars = character.unicodeScalars
    if scalars.count == 1 {
        return isWordScalar(scalars.first!.value)
    }
    for scalar in scalars {
        if !isWordScalar(scalar.value) { return false }
    }
    return true
}

/// Check if a Unicode scalar is a letter, digit, or mark using range checks.
/// Much faster than `scalar.properties.generalCategory` which does a full ICU lookup.
private func isWordScalar(_ v: UInt32) -> Bool {
    // ASCII fast path
    if v <= 0x7A {
        return (v >= 0x41 && v <= 0x5A) || // A-Z
               (v >= 0x61 && v <= 0x7A) || // a-z
               (v >= 0x30 && v <= 0x39) || // 0-9
               v == 0x27                    // apostrophe (contractions)
    }
    // Latin-1 Supplement letters
    if v >= 0xC0 && v <= 0xFF && v != 0xD7 && v != 0xF7 { return true }
    // Latin Extended-A/B
    if v >= 0x100 && v <= 0x24F { return true }
    // Combining diacritical marks
    if v >= 0x300 && v <= 0x36F { return true }
    // Greek and Coptic
    if v >= 0x370 && v <= 0x3FF { return true }
    // Cyrillic
    if v >= 0x400 && v <= 0x4FF { return true }
    // Arabic
    if v >= 0x600 && v <= 0x6FF { return true }
    // Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada, Malayalam
    if v >= 0x900 && v <= 0xD7F { return true }
    // CJK (handled separately but mark as word-like)
    if v >= 0x4E00 && v <= 0x9FFF { return true }
    if v >= 0x3040 && v <= 0x30FF { return true } // Hiragana + Katakana
    if v >= 0xAC00 && v <= 0xD7AF { return true } // Hangul
    // General: digits in other scripts
    if v >= 0x660 && v <= 0x669 { return true } // Arabic-Indic digits
    if v >= 0x966 && v <= 0x96F { return true } // Devanagari digits
    // Fallback: use the slow property check for rare cases
    guard let scalar = Unicode.Scalar(v) else { return false }
    return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
}

private func mergePunctuation(in pieces: [SegmentationPiece]) -> [SegmentationPiece] {
    var leftMerged: [SegmentationPiece] = []
    leftMerged.reserveCapacity(pieces.count)

    for piece in pieces {
        if
            piece.kind == .text,
            !piece.isWordLike,
            piece.text.unicodeScalars.allSatisfy({ leftStickyScalars.contains($0.value) }),
            var last = leftMerged.last,
            last.kind == .text
        {
            leftMerged.removeLast()
            last.text += piece.text
            last.isWordLike = last.isWordLike || piece.isWordLike
            leftMerged.append(last)
            continue
        }

        leftMerged.append(piece)
    }

    var result: [SegmentationPiece] = []
    result.reserveCapacity(leftMerged.count)
    var pendingPrefix = ""

    for piece in leftMerged {
        if
            piece.kind == .text,
            !piece.isWordLike,
            piece.text.unicodeScalars.allSatisfy({ rightStickyScalars.contains($0.value) })
        {
            pendingPrefix += piece.text
            continue
        }

        if !pendingPrefix.isEmpty, piece.kind == .text {
            result.append(
                SegmentationPiece(
                    text: pendingPrefix + piece.text,
                    isWordLike: piece.isWordLike,
                    kind: .text
                )
            )
            pendingPrefix = ""
        } else {
            result.append(piece)
        }
    }

    if !pendingPrefix.isEmpty {
        result.append(SegmentationPiece(text: pendingPrefix, isWordLike: false, kind: .text))
    }

    return result
}

private func splitCJKSegments(in pieces: [SegmentationPiece]) -> [SegmentationPiece] {
    var result: [SegmentationPiece] = []
    result.reserveCapacity(pieces.count)

    for piece in pieces {
        guard piece.kind == .text, piece.isWordLike, containsCJK(piece.text), piece.text.count > 1 else {
            result.append(piece)
            continue
        }

        for character in piece.text {
            result.append(
                SegmentationPiece(
                    text: String(character),
                    isWordLike: true,
                    kind: .text
                )
            )
        }
    }

    return result
}

private func compileChunks(from kinds: [SegmentBreakKind]) -> [PreparedLineChunk] {
    guard !kinds.isEmpty else {
        return []
    }

    var chunks: [PreparedLineChunk] = []
    var startIndex = 0

    for (index, kind) in kinds.enumerated() where kind == .hardBreak {
        chunks.append(
            PreparedLineChunk(
                startSegmentIndex: startIndex,
                endSegmentIndex: index,
                consumedEndSegmentIndex: index + 1
            )
        )
        startIndex = index + 1
    }

    if startIndex < kinds.count {
        chunks.append(
            PreparedLineChunk(
                startSegmentIndex: startIndex,
                endSegmentIndex: kinds.count,
                consumedEndSegmentIndex: kinds.count
            )
        )
    }

    return chunks
}

func containsCJK(_ text: String) -> Bool {
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
    var isCollapsibleWhitespace: Bool {
        self == " " || self == "\t" || self == "\n" || self == "\r" || self == "\u{000C}"
    }
}
