# Pretext Swift

A native Swift port of the [Pretext](https://github.com/chenglou/pretext) text layout engine. Measures and lays out multiline text without touching the view hierarchy — pure arithmetic over cached Core Text measurements.

## Performance

In release mode, Pretext is **6.5x faster than Core Text** and **20x faster than SwiftUI** for batch text layout:

```
Pretext:     4.5ms   (500 texts, prepare + layout)
Core Text:  29.8ms   (CTFramesetterSuggestFrameSizeWithConstraints)
SwiftUI:    88.6ms   (NSHostingView + fittingSize)
```

The hot-path `layout()` is pure arithmetic — **0.1ms for 500 texts**. No Core Text calls, no view hierarchy, no allocations.

## Build & Run

```bash
# Build (debug)
swift build

# Build (release, for benchmarks)
swift build -c release

# Run the demo app (3 screens: editorial layouts + benchmarks)
swift run PretextDemo

# Run the CLI benchmark
.build/release/PretextDemo --benchmark

# Run tests
swift test
```

Requires macOS 14+ and Swift 6.0+.

## Architecture

```
PretextDemo/
  Pretext/            Core text engine (platform-independent logic)
    TextAnalysis        Whitespace normalization, word segmentation, punctuation merging
    TextMeasurement     Core Text glyph advance measurement + caching
    LineBreaker         Pure arithmetic line-breaking engine
    PreparedText        Data types (PreparedText, LayoutCursor, SegmentBreakKind)
    LayoutAPI           Public API: prepare(), layout(), layoutNextLine()
  Editorial/          Demo screens
    EditorialView       "Situational Awareness" — light editorial spread with logo obstacles
    OrbEditorialView    "The Editorial Engine" — dark theme with floating orbs + 3-column reflow
    WrapGeometry        Polygon/circle obstacle avoidance geometry
  Benchmark/          Performance comparison suite
    BenchmarkView       In-app benchmark UI (Pretext vs Core Text vs SwiftUI)
    BenchmarkTests      Test implementations for all 5 benchmarks
```

## How It Works

1. **`prepare(text, font)`** — Segments text, measures each segment via Core Text glyph advances, caches widths. One-time cost.
2. **`layout(prepared, maxWidth, lineHeight)`** — Walks cached widths with pure arithmetic. Returns `{ lineCount, height }`. No Core Text calls.
3. **`layoutNextLine(prepared, cursor, maxWidth)`** — Line-by-line iterator for variable-width layouts (text flowing around obstacles).

The key insight: separate measurement (expensive, done once) from layout (cheap, done every frame). This enables 60fps text reflow around animated obstacles.

## Credits

Based on [Pretext](https://github.com/chenglou/pretext) by Cheng Lou. The Swift port reimplements the text analysis pipeline, line-breaking engine, and editorial demos using Core Text for measurement and SwiftUI Canvas for rendering.
