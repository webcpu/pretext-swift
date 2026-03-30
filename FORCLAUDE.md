# Pretext Swift — The Full Story

This document explains the entire project: what it is, how it was built, the technical decisions, the bugs we hit, and the lessons learned. Written to be engaging and useful for anyone picking up this codebase.

## What Is This?

Pretext is a text layout engine. The original is a TypeScript library by Cheng Lou that measures and lays out multiline text in the browser without touching the DOM — pure JavaScript arithmetic over cached canvas measurements.

This repo is a **native Swift port** of that engine, plus two editorial demos and a benchmark suite. It runs on macOS as a SwiftUI app.

The killer feature: **measure text height without triggering layout reflow**. On the web, this avoids DOM reflow. In Swift, this avoids the SwiftUI/AppKit layout system entirely. You call `prepare()` once (which uses Core Text under the hood), then `layout()` is pure arithmetic — no Core Text calls, no view hierarchy, no allocations.

## How It Was Built

The project was built in a single session, iteratively, using Claude Code + Codex as AI assistants. The entire journey from "can Pretext work in SwiftUI?" to "6.5x faster than Core Text" happened in one conversation.

### Phase 1: Feasibility Study

We started by analyzing the TypeScript source to understand which parts are platform-dependent (canvas.measureText, Intl.Segmenter) and which are pure logic (line breaking, geometry). The conclusion: ~80% ports directly to Swift, and only ~200 lines of platform glue need replacing.

### Phase 2: Initial Port (via Codex)

Codex implemented the full 10-step plan:
1. Data types (PreparedText, LayoutCursor, etc.)
2. Core Text measurement backend
3. Text analysis with NLTokenizer
4. Line-breaking engine (1100 lines, direct transliteration)
5. Public API (prepare, layout, layoutNextLine)
6. Wrap geometry (polygon/circle obstacle avoidance)
7. Logo hull extraction (SVG → NSImage → alpha channel → hull polygon)
8. Editorial layout (two-column, responsive, obstacle-aware)
9. SwiftUI Canvas rendering
10. App shell

### Phase 3: Visual Iteration (5 rounds)

We compared screenshots of the web demo vs the Swift app and fixed differences:
1. **Color scheme was wrong** — web uses light paper theme, not dark
2. **Atmosphere gradients** — radial gradient overlays were missing
3. **Sidebar eating content** — NavigationSplitView replaced with floating picker
4. **Logo SVGs** — placeholder polygons replaced with real logos from the repo
5. **Orb rendering** — CSS box-shadow simulated with multi-stop radial gradients

The orb iteration was particularly tricky. CSS `box-shadow` renders *outside* the element only, but our initial gradient filled color from center outward, making orbs look like bright bokeh blobs instead of dark glass spheres.

### Phase 4: The Editorial Engine (Second Demo)

The web page at somnai-dreams.github.io showed a completely different demo than what's in the pretext repo. It has floating glowing orbs, 3-column layout, drop caps, pullquotes, and a stats bar. We fetched the full JS source (494 lines), wrote a detailed spec, and Codex implemented it.

### Phase 5: Benchmarking & Optimization

This was the deepest phase. We built a benchmark suite comparing Pretext vs Core Text vs SwiftUI, then spent 5 optimization rounds making Pretext faster.

## The Performance Journey

This is the most educational part of the project. Here's what we learned about Swift performance:

### The Initial Shock

First benchmark: **Pretext 127ms vs Core Text 28ms**. Pretext was 4.5x *slower*. We expected the opposite.

### Root Cause: `prepare()` Was Doing Too Much Work

Profiling revealed `prepare()` called `CTLineCreateWithAttributedString` + `CTLineGetTypographicBounds` once per segment (~35,000 calls for 500 texts). Core Text's `CTFramesetterSuggestFrameSizeWithConstraints` does everything in one optimized call per text (~500 calls).

### Optimization 1: Fast Glyph Advances

Replaced CTLine with `CTFontGetGlyphsForCharacters` + `CTFontGetAdvancesForGlyphs`. This bypasses NSAttributedString + CTLine object creation entirely for Latin text.

**Result**: Barely moved the needle (~3ms savings). The overhead was elsewhere.

### Optimization 2: Batch CTTypesetter

Instead of one CTLine per segment, create ONE CTTypesetter for the entire text and extract per-segment widths using `CTTypesetterCreateLine` with ranges.

**Result**: Measurement dropped from 15ms to 6.5ms. Good, but analysis (76ms!) was the real problem.

### The NLTokenizer Red Herring

We replaced NLTokenizer with a "lightweight word scanner." But NLTokenizer wasn't the bottleneck. The scanner itself was fast — the overhead was in String operations.

### The Real Bottleneck: `scalar.properties.generalCategory`

The word boundary scanner used `scalar.properties.generalCategory` to classify each character. This does a full ICU lookup per scalar. We replaced it with range-based checks — but it barely helped because the text had smart quotes, so the ASCII fast path never fired.

### The Smart Quote Trap

The benchmark corpus used English text with typographic quotes (`"` `"` `'` `—`). These are 3-byte UTF-8 sequences, so `allSatisfy { $0 < 0x80 }` returned false, disabling every ASCII optimization.

**Lesson**: Always check what your actual corpus contains before optimizing for ASCII.

### The Analysis Breakdown Discovery

Adding sub-profiling to `analyzeText()` revealed where 76ms actually went:
- normalize: 5ms
- split: 28ms (String.Index iteration + String(scalars[...]) allocation)
- merge: 9ms (intermediate array copies)
- expand: 15ms (containsCJK on every piece + .filter)
- finalize: 18ms (4x .map creating separate arrays)

Seven intermediate arrays, each copying SegmentationPiece structs containing heap-allocated Strings.

### The Single-Pass Scanner

Rewrote `analyzeText()` to build output arrays directly — no intermediate `[SegmentationPiece]`. Used Unicode scalar iteration instead of Character iteration (avoids grapheme cluster overhead). Punctuation merging done inline via index range extension.

**Result**: Analysis dropped from 76ms to 21ms.

### The UTF-8 Byte Scanner

Replaced scalar iteration with raw `withUnsafeBufferPointer<UInt8>` byte scanning. Integer offsets instead of String.Index. Manual UTF-8 decoding for 3-byte smart quote sequences.

**Result**: Analysis dropped from 21ms to 13ms (debug), 1.5ms (release).

### Lazy Grapheme Measurement

The biggest single win. `prepare()` was eagerly measuring per-grapheme widths for every multi-character word (for `overflow-wrap: break-word`). But grapheme-level breaking only happens when a word overflows `maxWidth` — rare for normal text.

Added `breakableSegments: [Bool]` flag array and `maxBreakableWidth` for O(1) early exit. Graphemes measured lazily in `prepareForWidth()` only when overflow detected.

**Result**: Grapheme phase dropped from 23ms to 0ms in prepare (deferred to layout, almost never triggered).

### The Debug vs Release Revelation

After all optimizations, prepare() was still 52ms in debug. We tried release build:

**Debug: 52ms. Release: 4.5ms. A 10x difference.**

Swift's debug mode has no inlining, full bounds checking, uneliminated ARC retain/release, and no value-witness devirtualization. Every array subscript is a function call with bounds checking. In release mode, the compiler optimizes all of this away.

**Lesson**: NEVER benchmark Swift in debug mode. Always use `swift build -c release`.

### The Reference-Type Cache Experiment

Three analysis teams identified dictionary COW copies as a bottleneck. We wrapped the inner cache dictionaries in reference types (`final class WidthTable`). In debug mode it helped. In release mode it was **0.3ms slower** — the compiler was already optimizing value-type COW, and the reference-type indirection added overhead.

**Lesson**: The Swift compiler is smarter than you think in release mode. Profile before optimizing.

### Where We Landed

```
Original:  127ms  (0.2x Core Text)
Final:       4.5ms  (6.5x faster than Core Text)
Improvement: 28x faster
```

The theoretical floor is ~1.5ms. The remaining 3x gap is Swift runtime overhead (String ARC, Dictionary hashing, array bounds checks). Closing it would require abandoning Swift's String type entirely.

## Architecture Deep Dive

### The Two-Phase Split

This is the core insight. Separate **measurement** (expensive, uses Core Text) from **layout** (cheap, pure arithmetic):

```
prepare(text, font) → PreparedText   [~9μs per text, one-time]
layout(prepared, maxWidth, lineHeight) → {lineCount, height}   [~0.2μs per text, every frame]
```

`PreparedText` is a bag of parallel arrays: `widths`, `kinds`, `breakableWidths`, etc. The line breaker walks these arrays with index arithmetic. No string operations, no allocations, no Core Text calls.

### The Analysis Pipeline

`analyzeText()` normalizes whitespace, segments into words/spaces/punctuation, merges sticky punctuation, and classifies break kinds. The fast path uses a raw UTF-8 byte scanner; the fallback uses NLTokenizer for Thai/Khmer/Myanmar/Lao.

Eight break kinds: text, space, preservedSpace, tab, glue (NBSP), zeroWidthBreak, softHyphen, hardBreak.

### The Line Breaker

~1100 lines of direct transliteration from the TypeScript original. Two code paths:
- **Simple fast path**: single chunk, no hard breaks/tabs/soft hyphens. Just walks widths and breaks on overflow.
- **Full chunked path**: handles hard breaks, tabs, soft hyphens, preserved spaces. Walks chunks, then segments within each chunk.

Key entry points:
- `countPreparedLines()` — hot path, just counts (used by `layout()`)
- `walkPreparedLines()` — emits line geometry (used by `layoutWithLines()`)
- `layoutNextLineRange()` — single-line iterator (used by `layoutNextLine()`)

### The Editorial Demos

Two demos showing the engine's capabilities:

1. **Situational Awareness** — light paper theme, two-column layout with text flowing around OpenAI and Claude logo polygon hulls. Logos spin on click with cubic ease-out. Text reflows at display refresh rate.

2. **The Editorial Engine** — dark theme, 3-column responsive layout with 5 floating glowing orbs. Orbs bounce, repel, and can be dragged. Text flows around circular obstacles. Drop cap, italic pullquotes, live stats bar.

Both use SwiftUI `Canvas` + `TimelineView` for rendering. Each frame: compute layout → draw text at absolute positions. No SwiftUI `Text` views in the layout loop.

### The Benchmark Suite

5 tests:
1. **Batch** (500 texts): prepare + layout vs CTFramesetter vs SwiftUI NSHostingView
2. **Reflow** (50k calls): layout at 100 different widths — Pretext's killer advantage
3. **Line-by-line**: layoutNextLine vs CTTypesetterSuggestLineBreak
4. **Thrashing**: interleaved measure-mutate cycles
5. **Breakeven**: at what reflow count does Pretext's total cost drop below Core Text's?

Answer: **1 reflow**. After a single width change, Pretext is already cheaper in total.

## Bugs & Gotchas

### The Lazy Sentinel Crash

First attempt at lazy grapheme measurement used a sentinel value `[-1]` in `breakableWidths`. The line breaker accesses `breakableWidths` in many places (15+ sites). The sentinel leaked into `appendBreakableSegmentFrom()` which tried to iterate it as actual widths → crash.

**Fix**: Use a separate `breakableSegments: [Bool]` array instead of overloading nil/sentinel semantics on `breakableWidths`.

### The `prepareForWidth` Regression

Adding `prepareForWidth(&prepared, maxWidth:)` at the start of every `layout()` call turned O(1) layout into O(N) where N is segment count. The reflow benchmark (50k calls) went from 640ms to 1940ms.

**Fix**: Added `maxBreakableWidth` field to PreparedText. `prepareForWidth` returns immediately when `maxWidth >= maxBreakableWidth`. This is O(1) for the common case.

### The `hiddenTitleBar` Window Bug

Using `.windowStyle(.hiddenTitleBar)` caused the app to launch without a visible window. The process ran but no window appeared. Reverted to `.windowStyle(.titleBar)` with `.windowToolbarStyle(.unified(showsTitle: false))`.

### The Segmented Picker Invisibility

A SwiftUI segmented picker with `.opacity(0.7)` on a dark background was virtually invisible. The native segmented control renders as small translucent pills that don't show text on dark backgrounds. Replaced with custom button-based tab bar.

### Core Text Thread Safety

`CTFont` objects are not `Sendable` in Swift 6 strict concurrency. We use `nonisolated(unsafe)` for the font stored in `PreparedText` and the segment cache globals. This is safe because our code is single-threaded in practice, but a proper fix would use actors or `@unchecked Sendable` wrappers.

## What I'd Do Differently

1. **Benchmark in release mode from the start**. We spent hours optimizing debug-mode overhead that evaporates with `-O`.
2. **Profile before optimizing**. The `PrepareProfile` + `AnalysisSubProfile` instrumentation was invaluable. Add it first.
3. **Check your corpus**. The smart quote trap wasted an entire optimization round.
4. **Don't use sentinels in shared data structures**. The `[-1]` crash was entirely avoidable with a proper boolean flag.
5. **Trust the compiler in release mode**. The reference-type cache wrapper was slower because the compiler already optimized value-type COW.
