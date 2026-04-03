import CoreText
import Foundation

public enum SegmentBreakKind: Equatable, Sendable {
    case text
    case space
    case preservedSpace
    case tab
    case glue
    case zeroWidthBreak
    case softHyphen
    case hardBreak
}

public enum WhiteSpaceMode: Equatable, Sendable {
    case normal
    case preWrap
}

public struct LayoutCursor: Equatable, Sendable {
    public var segmentIndex: Int
    public var graphemeIndex: Int

    public init(segmentIndex: Int, graphemeIndex: Int) {
        self.segmentIndex = segmentIndex
        self.graphemeIndex = graphemeIndex
    }

    public static let start = LayoutCursor(segmentIndex: 0, graphemeIndex: 0)
}

public struct PreparedLineChunk: Equatable, Sendable {
    public var startSegmentIndex: Int
    public var endSegmentIndex: Int
    public var consumedEndSegmentIndex: Int
}

public struct PreparedText: @unchecked Sendable {
    public var widths: [Double]
    public var lineEndFitAdvances: [Double]
    public var lineEndPaintAdvances: [Double]
    public var kinds: [SegmentBreakKind]
    public var simpleLineWalkFastPath: Bool
    public var breakableSegments: [Bool]
    public var breakableWidths: [[Double]?]
    public var breakablePrefixWidths: [[Double]?]
    public var maxBreakableWidth: Double
    public var discretionaryHyphenWidth: Double
    public var tabStopAdvance: Double
    public var chunks: [PreparedLineChunk]
    public var segments: [String]
    public nonisolated(unsafe) var font: CTFont?
    var engineKinds: [SegmentBreakKind] = []
    var engineSegments: [String] = []

    public var isEmpty: Bool {
        widths.isEmpty
    }

    var layoutKinds: [SegmentBreakKind] {
        engineKinds.isEmpty ? kinds : engineKinds
    }

    var layoutSegments: [String] {
        engineSegments.isEmpty ? segments : engineSegments
    }
}

public struct LayoutLine: Sendable {
    public var text: String
    public var width: Double
    public var start: LayoutCursor
    public var end: LayoutCursor
}

public struct LayoutLineRange: Equatable, Sendable {
    public var width: Double
    public var start: LayoutCursor
    public var end: LayoutCursor
}

public struct LayoutResult: Equatable, Sendable {
    public var height: Double
    public var lineCount: Int
}

public struct InternalLayoutLine: Equatable, Sendable {
    public var startSegmentIndex: Int
    public var startGraphemeIndex: Int
    public var endSegmentIndex: Int
    public var endGraphemeIndex: Int
    public var width: Double
}

public struct EngineProfile: Equatable, Sendable {
    public var lineFitEpsilon: Double
    public var carryCJKAfterClosingQuote: Bool
    public var preferPrefixWidthsForBreakableRuns: Bool
    public var preferEarlySoftHyphenBreak: Bool
}

public struct TextAnalysisResult {
    public var normalized: String
    public var segments: [String]
    public var kinds: [SegmentBreakKind]
    public var wordLike: [Bool]
    public var chunks: [PreparedLineChunk]
    public var starts: [Int]
    var directPreparedLayout: Bool = false

    public var isEmpty: Bool {
        segments.isEmpty
    }
}

public struct FontDescriptor: Equatable, Sendable {
    public var familyName: String
    public var size: Double
    public var symbolicTraits: CTFontSymbolicTraits
    public var weightValue: Double?

    public init(
        familyName: String,
        size: Double,
        symbolicTraits: CTFontSymbolicTraits = [],
        weightValue: Double? = nil
    ) {
        self.familyName = familyName
        self.size = size
        self.symbolicTraits = symbolicTraits
        self.weightValue = weightValue
    }

    public func makeCTFont() -> CTFont {
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
}
