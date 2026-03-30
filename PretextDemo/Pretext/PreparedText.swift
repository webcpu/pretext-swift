import CoreText
import Foundation
import SwiftUI

enum SegmentBreakKind: Equatable {
    case text
    case space
    case preservedSpace
    case tab
    case glue
    case zeroWidthBreak
    case softHyphen
    case hardBreak
}

enum WhiteSpaceMode: Equatable {
    case normal
    case preWrap
}

struct LayoutCursor: Equatable {
    var segmentIndex: Int
    var graphemeIndex: Int

    static let start = LayoutCursor(segmentIndex: 0, graphemeIndex: 0)
}

struct PreparedLineChunk: Equatable {
    var startSegmentIndex: Int
    var endSegmentIndex: Int
    var consumedEndSegmentIndex: Int
}

struct PreparedText {
    var widths: [Double]
    var lineEndFitAdvances: [Double]
    var lineEndPaintAdvances: [Double]
    var kinds: [SegmentBreakKind]
    var simpleLineWalkFastPath: Bool
    var breakableSegments: [Bool]
    var breakableWidths: [[Double]?]
    var breakablePrefixWidths: [[Double]?]
    var maxBreakableWidth: Double
    var discretionaryHyphenWidth: Double
    var tabStopAdvance: Double
    var chunks: [PreparedLineChunk]
    var segments: [String]
    nonisolated(unsafe) var font: CTFont?

    var isEmpty: Bool {
        widths.isEmpty
    }
}

struct LayoutLine {
    var text: String
    var width: Double
    var start: LayoutCursor
    var end: LayoutCursor
}

struct LayoutLineRange: Equatable {
    var width: Double
    var start: LayoutCursor
    var end: LayoutCursor
}

struct LayoutResult: Equatable {
    var height: Double
    var lineCount: Int
}

struct InternalLayoutLine: Equatable {
    var startSegmentIndex: Int
    var startGraphemeIndex: Int
    var endSegmentIndex: Int
    var endGraphemeIndex: Int
    var width: Double
}

struct EngineProfile: Equatable {
    var lineFitEpsilon: Double
    var preferPrefixWidthsForBreakableRuns: Bool
    var preferEarlySoftHyphenBreak: Bool
}

struct TextAnalysisResult {
    var normalized: String
    var segments: [String]
    var kinds: [SegmentBreakKind]
    var wordLike: [Bool]
    var chunks: [PreparedLineChunk]

    var isEmpty: Bool {
        segments.isEmpty
    }
}

struct FontDescriptor: Equatable {
    var familyName: String
    var size: Double
    var symbolicTraits: CTFontSymbolicTraits = []
    var weightValue: Double?

    func makeCTFont() -> CTFont {
        var attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: familyName,
            kCTFontSizeAttribute: size,
        ]
        var traits: [CFString: Any] = [:]

        if symbolicTraits != [] {
            traits[kCTFontSymbolicTrait] = symbolicTraits.rawValue
        }

        if let weightValue {
            traits[kCTFontWeightTrait] = weightValue
        }

        if !traits.isEmpty {
            attributes[kCTFontTraitsAttribute] = traits
        }

        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    func makeDisplayFont() -> Font {
        Font(makeCTFont())
    }
}
