# Pretext Swift

A native Swift port of the [Pretext](https://github.com/chenglou/pretext) text layout engine. Measures and lays out multiline text without touching the view hierarchy — pure arithmetic over cached Core Text measurements.

## Performance

On the bundled release benchmark, Pretext is about **6x faster than Core Text** and **16x faster than SwiftUI** for batch text layout:

```
Pretext:     4.6ms   (500 texts, prepare + layout)
Core Text:  28.6ms   (CTFramesetterSuggestFrameSizeWithConstraints)
SwiftUI:    76.5ms   (NSHostingView + fittingSize)
```

The hot `layout()` path is pure arithmetic. Measurement happens once in `prepare(...)`; repeated layout uses cached widths.

## Platform Support

- `Pretext` supports `iOS 18+` and `macOS 15+`
- `PretextUI` provides the optional `SwiftUI.Font` bridge on those same platforms
- `Demo` and `Benchmark` remain macOS-only showcase apps in this repository

## Build & Run

```bash
# Build debug binaries
rake build

# Validate the Pretext library for iOS Simulator
rake build_ios_pretext

# Launch the demo app
rake demo

# Run the CLI benchmark
rake bench

# Run tests
rake test
```

Requires Xcode with iOS 18 / macOS 15 SDK support and Swift 6.0+.

## Demo

The macOS demo app includes:

- `Situational Awareness`: light editorial layout with obstacle-aware text flow
- `Editorial Engine`: dark multi-column editorial layout with animated orb obstacles
- `Masonry`: waterfall card layout driven by cached text measurement
- `Chika Dance`: animated reflow around live video silhouettes
- `Benchmark`: in-app performance comparison against Core Text and SwiftUI

## How It Works

1. `prepare(text, font)` segments text, measures runs with Core Text, and caches widths.
2. `layout(prepared, maxWidth, lineHeight)` computes multiline layout from cached widths.
3. `layoutNextLine(prepared, cursor, maxWidth)` supports line-by-line flow for variable-width layouts.

The key idea is separating measurement from layout so animated obstacle reflow can stay cheap.

## Credits

Based on [Pretext](https://github.com/chenglou/pretext) by Cheng Lou. The Swift port reimplements the text analysis pipeline, line-breaking engine, and editorial demos using Core Text for measurement and SwiftUI Canvas for rendering.
