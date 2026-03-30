import CoreText
import Foundation

struct SegmentMetrics {
    var width: Double
    var containsCJK: Bool
    var graphemeWidths: [Double]?
    var graphemePrefixWidths: [Double]?
}

private struct FontCacheKey: Hashable {
    private let rawValue: UnsafeMutableRawPointer

    init(_ font: CTFont) {
        rawValue = Unmanaged<CTFont>.passUnretained(font).toOpaque()
    }
}

/// Reference-type wrapper to avoid Dictionary COW on every lookup.
private final class WidthTable {
    var widths: [String: Double] = [:]
}

private final class MetricsTable {
    var metrics: [String: SegmentMetrics] = [:]
}

final class TextMeasurer: @unchecked Sendable {
    static let shared = TextMeasurer()
    static let engineProfile = EngineProfile(
        lineFitEpsilon: 0.005,
        preferPrefixWidthsForBreakableRuns: false,
        preferEarlySoftHyphenBreak: false
    )

    private var metricsCache: [FontCacheKey: MetricsTable] = [:]
    private var widthCache: [FontCacheKey: WidthTable] = [:]

    // Reusable buffers to avoid per-call allocations
    private var glyphBuffer: [CGGlyph] = []
    private var advanceBuffer: [CGSize] = []
    private var charBuffer: [UniChar] = []

    private init() {}

    func clearCache() {
        metricsCache.removeAll()
        widthCache.removeAll()
    }

    /// Fast path: sum glyph advances directly without creating CTLine.
    private func measureWithGlyphAdvances(_ text: String, font: CTFont) -> Double? {
        let utf16 = text.utf16
        let count = utf16.count
        guard count > 0 else { return 0 }

        if charBuffer.count < count {
            charBuffer = [UniChar](repeating: 0, count: count)
            glyphBuffer = [CGGlyph](repeating: 0, count: count)
            advanceBuffer = [CGSize](repeating: .zero, count: count)
        }

        var idx = 0
        for unit in utf16 {
            charBuffer[idx] = unit
            idx += 1
        }

        guard CTFontGetGlyphsForCharacters(font, &charBuffer, &glyphBuffer, count) else {
            return nil
        }

        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphBuffer, &advanceBuffer, count)
        var total = 0.0
        for j in 0..<count {
            total += advanceBuffer[j].width
        }
        return total
    }

    /// Slow path: full CTLine measurement.
    private func measureWithCTLine(_ text: String, font: CTFont) -> Double {
        let attrStr = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ])
        let line = CTLineCreateWithAttributedString(attrStr)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    func measureSegment(_ text: String, font: CTFont) -> Double {
        measureWithGlyphAdvances(text, font: font) ?? measureWithCTLine(text, font: font)
    }

    private func segmentMetrics(for text: String, font: CTFont, fontKey: FontCacheKey) -> SegmentMetrics {
        let table = metricsCache[fontKey] ?? {
            let t = MetricsTable()
            metricsCache[fontKey] = t
            return t
        }()
        if let existing = table.metrics[text] { return existing }

        let width: Double
        let wt = widthCache[fontKey]
        if let w = wt?.widths[text] {
            width = w
        } else {
            width = measureSegment(text, font: font)
            ensureWidthTable(fontKey).widths[text] = width
        }

        let metrics = SegmentMetrics(
            width: width,
            containsCJK: containsCJK(text),
            graphemeWidths: nil,
            graphemePrefixWidths: nil
        )
        table.metrics[text] = metrics
        return metrics
    }

    /// Batch measure all segment widths. Uses reference-type cache tables
    /// to avoid dictionary COW copies on every text.
    func batchMeasureWidths(for segments: [String], in text: String, font: CTFont) -> [Double] {
        guard !segments.isEmpty else { return [] }

        let fontKey = FontCacheKey(font)
        let table = ensureWidthTable(fontKey)
        var widths = [Double](repeating: 0, count: segments.count)
        var attrStr: NSAttributedString?
        var typesetter: CTTypesetter?

        var utf16Location = 0
        for index in segments.indices {
            let segment = segments[index]

            // Direct reference-type lookup — no COW copy
            if let existing = table.widths[segment] {
                widths[index] = existing
                utf16Location += segment.utf16.count
                continue
            }

            let utf16Length = segment.utf16.count
            let width: Double
            if let fast = measureWithGlyphAdvances(segment, font: font) {
                width = fast
            } else {
                if attrStr == nil {
                    attrStr = NSAttributedString(string: text, attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                    ])
                    typesetter = CTTypesetterCreateWithAttributedString(attrStr!)
                }
                let line = CTTypesetterCreateLine(
                    typesetter!,
                    CFRange(location: utf16Location, length: utf16Length)
                )
                width = CTLineGetTypographicBounds(line, nil, nil, nil)
            }
            table.widths[segment] = width
            widths[index] = width
            utf16Location += utf16Length
        }

        return widths
    }

    func graphemeWidths(for text: String, font: CTFont) -> [Double]? {
        let fontKey = FontCacheKey(font)
        let table = metricsCache[fontKey] ?? {
            let t = MetricsTable()
            metricsCache[fontKey] = t
            return t
        }()
        var metrics = table.metrics[text] ?? segmentMetrics(for: text, font: font, fontKey: fontKey)
        if let cached = metrics.graphemeWidths { return cached }

        let graphemes = text.graphemeStrings
        guard graphemes.count > 1 else {
            metrics.graphemeWidths = nil
            table.metrics[text] = metrics
            return nil
        }

        // Batch: if all graphemes are single UTF-16 units, one CTFont call
        if let batch = batchGraphemeAdvances(graphemes, font: font) {
            metrics.graphemeWidths = batch
        } else {
            metrics.graphemeWidths = graphemes.map { measureSegment($0, font: font) }
        }
        table.metrics[text] = metrics
        return metrics.graphemeWidths
    }

    private func batchGraphemeAdvances(_ graphemes: [String], font: CTFont) -> [Double]? {
        var allChars: [UniChar] = []
        allChars.reserveCapacity(graphemes.count)
        for g in graphemes {
            let utf16Count = g.utf16.count
            if utf16Count != 1 { return nil }
            allChars.append(g.utf16.first!)
        }
        var glyphs = [CGGlyph](repeating: 0, count: allChars.count)
        guard CTFontGetGlyphsForCharacters(font, &allChars, &glyphs, allChars.count) else {
            return nil
        }
        var advances = [CGSize](repeating: .zero, count: allChars.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, allChars.count)
        return advances.map { Double($0.width) }
    }

    func graphemePrefixWidths(for text: String, font: CTFont) -> [Double]? {
        let fontKey = FontCacheKey(font)
        let table = metricsCache[fontKey] ?? {
            let t = MetricsTable()
            metricsCache[fontKey] = t
            return t
        }()
        var metrics = table.metrics[text] ?? segmentMetrics(for: text, font: font, fontKey: fontKey)
        if let cached = metrics.graphemePrefixWidths { return cached }

        let graphemes = text.graphemeStrings
        guard graphemes.count > 1 else {
            metrics.graphemePrefixWidths = nil
            table.metrics[text] = metrics
            return nil
        }

        var prefix = ""
        var widths: [Double] = []
        widths.reserveCapacity(graphemes.count)
        for grapheme in graphemes {
            prefix += grapheme
            widths.append(measureSegment(prefix, font: font))
        }
        metrics.graphemePrefixWidths = widths
        table.metrics[text] = metrics
        return metrics.graphemePrefixWidths
    }

    private func ensureWidthTable(_ fontKey: FontCacheKey) -> WidthTable {
        if let existing = widthCache[fontKey] { return existing }
        let table = WidthTable()
        widthCache[fontKey] = table
        return table
    }
}

func engineProfile() -> EngineProfile {
    TextMeasurer.engineProfile
}

extension String {
    var graphemeStrings: [String] {
        map(String.init)
    }
}
