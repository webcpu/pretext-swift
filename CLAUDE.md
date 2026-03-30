## Pretext Swift

Native Swift port of [Pretext](https://github.com/chenglou/pretext) — a text layout engine that measures and lays out multiline text without touching the view hierarchy.

### Project structure

Three targets:
- **Pretext** — reusable library (core engine)
- **Demo** — macOS demo app (2 editorial screens)
- **Benchmark** — benchmark app (GUI + CLI)

### Commands

- `swift build` — debug build (all targets)
- `swift build -c release` — release build (10x faster, use for benchmarks)
- `swift test` — run all tests (PretextTests + DemoTests, 41 total)
- `swift run Demo` — launch the demo app (2 screens)
- `swift run Benchmark` — launch the benchmark GUI
- `.build/release/Benchmark --cli` — CLI benchmark (Pretext vs Core Text vs SwiftUI)

### Architecture

The engine has a clean two-phase split:

1. **`prepare(text, font)`** — one-time: segments text, measures via Core Text glyph advances, caches widths
2. **`layout(prepared, maxWidth, lineHeight)`** — hot path: pure arithmetic over cached widths, zero CT calls

### Important files

**Pretext library** (`Sources/Pretext/`):
- `LayoutAPI.swift` — public API: `prepare()`, `layout()`, `layoutNextLine()`, `walkLineRanges()`
- `TextAnalysis.swift` — UTF-8 byte scanner, whitespace normalization, punctuation merging
- `TextMeasurement.swift` — Core Text glyph advance measurement, segment cache
- `LineBreaker.swift` — pure arithmetic line-breaking engine (~1100 lines)
- `PreparedText.swift` — all data types

**Demo app** (`Sources/Demo/`):
- `DemoApp.swift` — app entry point
- `Editorial/EditorialView.swift` — "Situational Awareness" demo (light theme, logo obstacles)
- `Editorial/OrbEditorialView.swift` — "Editorial Engine" demo (dark theme, floating orbs)

**Benchmark app** (`Sources/Benchmark/`):
- `BenchmarkApp.swift` — app entry point, `--cli` mode
- `BenchmarkTests.swift` — 5 benchmark tests

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

### Key design decisions

- **Always benchmark in release mode** (`-c release`). Debug mode inflates numbers by 10x due to no inlining, full bounds checking, uneliminated ARC.
- `prepare()` uses lazy grapheme measurement: `breakableWidths` are nil during prepare, resolved by `prepareForWidth()` only when a word overflows `maxWidth`. The `maxBreakableWidth` field enables O(1) early exit.
- The text analysis scanner uses raw UTF-8 bytes (`withContiguousStorageIfAvailable` / `withUnsafeBufferPointer`) to avoid String.Index overhead. It handles smart quotes (3-byte E2 80 xx sequences) inline.
- Punctuation stickiness checks use `Set<UInt32>` (scalar values), not `Set<Character>`, to avoid expensive grapheme cluster construction.
- The measurement cache uses `FontCacheKey` (CTFont pointer identity via `Unmanaged.toOpaque()`) instead of string-based font keys.
- Reference-type cache wrappers (`WidthTable`, `MetricsTable`) avoid Dictionary COW copies in the batch measurement loop — though in release mode the compiler optimizes value-type COW nearly as well.
- The glyph-advance fast path (`CTFontGetGlyphsForCharacters` + `CTFontGetAdvancesForGlyphs`) bypasses CTLine creation for Latin text. Falls back to CTTypesetter for complex scripts.

### Known test failures

4 tests in `CoreEngineTests` fail due to known gaps in the scalar scanner:
- CJK character splitting (the UTF-8 scanner doesn't run `splitCJKSegments`)
- NBSP glue merging (the scanner treats NBSP as a separate segment, not merged)
- Pre-wrap consecutive hard breaks

These affect the scalar fast path only. The tokenizer fallback path (Thai/Khmer/Myanmar/Lao) still handles them. Fix by adding CJK splitting and NBSP merging to `analyzeUTF8Buffer()`.

### Optimization history

The `prepare()` function went through 5 rounds of optimization:
1. **Fast glyph advances** — replaced CTLine with CTFontGetAdvancesForGlyphs (minor win)
2. **Batch CTTypesetter** — one typesetter per text instead of one CTLine per segment (2x win on measurement)
3. **Lightweight word scanner** — replaced NLTokenizer with Unicode scalar scanner (eliminated ML overhead)
4. **Lazy grapheme measurement** — defer grapheme widths to layout time (eliminated 23ms)
5. **Raw UTF-8 byte scanner** — replaced scalar iteration with byte-level scanning (1.5x win on analysis)

The theoretical floor is ~1.5ms. Current 4.5ms is 3x the floor. The gap is Swift runtime tax (String ARC, Dictionary hashing). Further optimization requires abandoning Swift's String type.
