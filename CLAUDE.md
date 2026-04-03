## Pretext Swift

Native Swift port of [Pretext](https://github.com/chenglou/pretext) — a text layout engine that measures and lays out multiline text without touching the view hierarchy.

### Project structure

Four targets:
- **Pretext** — reusable library (core engine)
- **PretextUI** — optional SwiftUI bridge for `FontDescriptor.makeDisplayFont()`
- **Demo** — SwiftUI demo app for iOS + macOS
- **Benchmark** — macOS benchmark app (GUI + CLI)

### Commands

- `swift build` — debug build (all targets)
- `swift build -c release` — release build (10x faster, use for benchmarks)
- `swift test` — run all tests (PretextTests + DemoTests)
- `xcodebuild -scheme Pretext -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` — validate the `Pretext` library on iOS Simulator
- `xcodebuild build -scheme Demo -destination 'platform=iOS Simulator,id=…' CODE_SIGNING_ALLOWED=NO` — build the demo app on iOS Simulator
- `xcodebuild test -scheme PretextSwift-Package -destination 'platform=iOS Simulator,id=…' -only-testing:DemoTests CODE_SIGNING_ALLOWED=NO` — run `DemoTests` on iOS Simulator
- `swift run Demo` — launch the demo app
- `swift run Benchmark` — launch the benchmark GUI
- `.build/release/Benchmark --cli` — CLI benchmark (Pretext vs Core Text vs SwiftUI)

### Architecture

The engine has a clean two-phase split:

1. **`prepare(text, font)`** — one-time: segments text, measures via Core Text glyph advances, caches widths
2. **`layout(prepared, maxWidth, lineHeight)`** — hot path: pure arithmetic over cached widths, zero CT calls

### Important files

**Pretext library** (`Sources/Pretext/`):
- `API/LayoutAPI.swift` — public API: `prepare()`, `layout()`, `layoutNextLine()`, `walkLineRanges()`
- `Engine/TextAnalysis.swift` — UTF-8 byte scanner, whitespace normalization, punctuation merging
- `Engine/TextMeasurement.swift` — Core Text glyph advance measurement, segment cache
- `Engine/LineBreaker.swift` — pure arithmetic line-breaking engine (~1100 lines)
- `Model/PreparedText.swift` — all data types

**PretextUI bridge** (`Sources/PretextUI/`):
- `Extensions/FontDescriptor+SwiftUI.swift` — SwiftUI helper kept out of the core target

**Demo app** (`Sources/Demo/`):
- `App/DemoApp.swift` — app entry point
- `Features/SituationalAwareness/EditorialView.swift` — "Situational Awareness" demo (light theme, logo obstacles)
- `Features/EditorialEngine/OrbEditorialView.swift` — "Editorial Engine" demo (dark theme, floating orbs)

**Benchmark support** (`Sources/BenchmarkSupport/`):
- `Core/BenchmarkCorpus.swift` — benchmark corpus and shared typography constants
- `Core/BenchmarkScenarios.swift` — the five benchmark scenarios
- `UI/BenchmarkView.swift` — benchmark UI shared by the app and demo

**Benchmark app** (`Sources/Benchmark/`):
- `App/BenchmarkApp.swift` — app entry point, `--cli` mode

**Tests:**
- `Tests/PretextTests/` — core engine tests (CoreEngineTests, LineBreakerTests, TextAnalysisTests)
- `Tests/DemoTests/` — demo tests (EditorialLayoutTests, LogoHullTests, OrbEditorialLayoutTests, WrapGeometryTests)

### Performance (release mode, Apple Silicon)

```
Pretext:    ~4.5ms  (500 texts, prepare + layout)
Core Text: ~29.8ms  (CTFramesetterSuggestFrameSizeWithConstraints)
SwiftUI:   ~88ms    (NSHostingView + fittingSize)
```

Pretext is **6.5x faster** than Core Text, **20x faster** than SwiftUI. The hot-path `layout()` takes 0.1ms for 500 texts.

### Platform support

- `Pretext` supports `iOS 18+` and `macOS 15+`
- `PretextUI` is optional and only provides the SwiftUI display-font helper
- `Demo` is maintained as an iOS + macOS repo app
- `Benchmark` remains macOS-only

### Key design decisions

- **Always benchmark in release mode** (`-c release`). Debug mode inflates numbers by 10x due to no inlining, full bounds checking, uneliminated ARC.
- `prepare()` uses lazy grapheme measurement: `breakableWidths` are nil during prepare, resolved by `prepareForWidth()` only when a word overflows `maxWidth`. The `maxBreakableWidth` field enables O(1) early exit.
- The text analysis scanner uses raw UTF-8 bytes (`withContiguousStorageIfAvailable` / `withUnsafeBufferPointer`) to avoid String.Index overhead. It handles smart quotes (3-byte E2 80 xx sequences) inline.
- Punctuation stickiness checks use `Set<UInt32>` (scalar values), not `Set<Character>`, to avoid expensive grapheme cluster construction.
- The measurement cache uses `FontCacheKey` (CTFont pointer identity via `Unmanaged.toOpaque()`) instead of string-based font keys.
- Reference-type cache wrappers (`WidthTable`, `MetricsTable`) avoid Dictionary COW copies in the batch measurement loop — though in release mode the compiler optimizes value-type COW nearly as well.
- The glyph-advance fast path (`CTFontGetGlyphsForCharacters` + `CTFontGetAdvancesForGlyphs`) bypasses CTLine creation for Latin text. Falls back to CTTypesetter for complex scripts.

### Current test status

- `swift test --filter PretextTests` currently passes
- `Demo` and `Benchmark` still compile on macOS after the `PretextUI` split

### Optimization history

The `prepare()` function went through 5 rounds of optimization:
1. **Fast glyph advances** — replaced CTLine with CTFontGetAdvancesForGlyphs (minor win)
2. **Batch CTTypesetter** — one typesetter per text instead of one CTLine per segment (2x win on measurement)
3. **Lightweight word scanner** — replaced NLTokenizer with Unicode scalar scanner (eliminated ML overhead)
4. **Lazy grapheme measurement** — defer grapheme widths to layout time (eliminated 23ms)
5. **Raw UTF-8 byte scanner** — replaced scalar iteration with byte-level scanning (1.5x win on analysis)

The theoretical floor is ~1.5ms. Current 4.5ms is 3x the floor. The gap is Swift runtime tax (String ARC, Dictionary hashing). Further optimization requires abandoning Swift's String type.
