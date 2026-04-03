import CoreGraphics
import CoreText
import Foundation

enum FluidFallbackFont: Equatable {
    case helveticaNeue
}

enum FluidFontMode: Equatable {
    case exact
    case fallback(FluidFallbackFont)
}

enum FluidFontLoadFailure: Error, Equatable {
    case missingResource
    case unreadableData
    case invalidGraphicsFont
}

private enum FluidFontCache {
    enum ExactFontResult {
        case success(CGFont)
        case failure(any Error)
    }

    static let lock = NSLock()
    nonisolated(unsafe) static var exactFontResults: [String: ExactFontResult] = [:]
    nonisolated(unsafe) static var resolvedModes: [String: FluidFontMode] = [:]
    nonisolated(unsafe) static var bodyFonts: [String: CTFont] = [:]
}

struct FluidFontAssets: @unchecked Sendable {
    private let cacheIdentifier: String
    private let resolvePackagedFontURL: () -> URL?
    var loadExactGraphicsFont: () throws -> CGFont

    init(
        cacheIdentifier: String,
        resolvePackagedFontURL: @escaping () -> URL?,
        loadExactGraphicsFont: @escaping () throws -> CGFont
    ) {
        self.cacheIdentifier = cacheIdentifier
        self.resolvePackagedFontURL = resolvePackagedFontURL
        self.loadExactGraphicsFont = loadExactGraphicsFont
    }

    func packagedFontURL() -> URL? {
        resolvePackagedFontURL()
    }

    func resolvedFontMode(size _: Double) -> FluidFontMode {
        FluidFontCache.lock.lock()
        let cachedMode = FluidFontCache.resolvedModes[cacheIdentifier]
        FluidFontCache.lock.unlock()
        if let cachedMode {
            return cachedMode
        }

        let resolvedMode: FluidFontMode
        do {
            _ = try exactGraphicsFont()
            resolvedMode = .exact
        } catch let explicitFailure as FluidFontLoadFailure {
            resolvedMode = .fallback(.helveticaNeue)
            FluidFontCache.lock.lock()
            FluidFontCache.resolvedModes[cacheIdentifier] = resolvedMode
            FluidFontCache.lock.unlock()
            _ = explicitFailure
            return resolvedMode
        } catch {
            preconditionFailure("Unexpected fluid exact font loader error: \(error)")
        }

        FluidFontCache.lock.lock()
        FluidFontCache.resolvedModes[cacheIdentifier] = resolvedMode
        FluidFontCache.lock.unlock()
        return resolvedMode
    }

    func bodyFont(size: Double) -> CTFont {
        let sizeKey = Int(round(size * 10))
        let mode = resolvedFontMode(size: size)
        let cacheKey = "\(cacheIdentifier):\(sizeKey):\(mode)"
        FluidFontCache.lock.lock()
        let cachedFont = FluidFontCache.bodyFonts[cacheKey]
        FluidFontCache.lock.unlock()
        if let cachedFont {
            return cachedFont
        }

        let font: CTFont
        switch mode {
        case .exact:
            let exactFont = (try? exactGraphicsFont())
            if let exactFont {
                font = CTFontCreateWithGraphicsFont(exactFont, size, nil, nil)
            } else {
                font = CTFontCreateWithName("Helvetica Neue" as CFString, size, nil)
            }
        case .fallback:
            font = CTFontCreateWithName("Helvetica Neue" as CFString, size, nil)
        }

        FluidFontCache.lock.lock()
        FluidFontCache.bodyFonts[cacheKey] = font
        FluidFontCache.lock.unlock()
        return font
    }

    static let live = FluidFontAssets(
        cacheIdentifier: "fluid.live",
        resolvePackagedFontURL: {
            Bundle.module.url(
                forResource: "L10-Medium",
                withExtension: "woff"
            )
        },
        loadExactGraphicsFont: {
            guard let url = Bundle.module.url(
                forResource: "L10-Medium",
                withExtension: "woff"
            ) else {
                throw FluidFontLoadFailure.missingResource
            }
            guard let provider = CGDataProvider(url: url as CFURL) else {
                throw FluidFontLoadFailure.unreadableData
            }
            guard let font = CGFont(provider) else {
                throw FluidFontLoadFailure.invalidGraphicsFont
            }
            return font
        }
    )

    static func testValue(
        loadExactGraphicsFont: @escaping () throws -> CGFont
    ) -> FluidFontAssets {
        FluidFontAssets(
            cacheIdentifier: UUID().uuidString,
            resolvePackagedFontURL: { nil },
            loadExactGraphicsFont: loadExactGraphicsFont
        )
    }

    func exactGraphicsFont() throws -> CGFont {
        FluidFontCache.lock.lock()
        let cachedResult = FluidFontCache.exactFontResults[cacheIdentifier]
        FluidFontCache.lock.unlock()
        if let cachedResult {
            switch cachedResult {
            case let .success(font):
                return font
            case let .failure(error):
                throw error
            }
        }

        do {
            let font = try loadExactGraphicsFont()
            FluidFontCache.lock.lock()
            FluidFontCache.exactFontResults[cacheIdentifier] = .success(font)
            FluidFontCache.lock.unlock()
            return font
        } catch {
            FluidFontCache.lock.lock()
            FluidFontCache.exactFontResults[cacheIdentifier] = .failure(error)
            FluidFontCache.lock.unlock()
            throw error
        }
    }
}
