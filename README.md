# Pretext Swift

A native Swift port of the [Pretext](https://github.com/chenglou/pretext) text layout engine. It measures and lays out multiline text without touching the view hierarchy, so repeated layout stays pure arithmetic over cached Core Text measurements.

The package currently ships four targets:

- `Pretext`: core layout engine
- `PretextUI`: optional SwiftUI bridge for `FontDescriptor`
- `Demo`: interactive sample app
- `Benchmark`: standalone benchmark app backed by shared benchmark support code

## Performance

On the current release benchmark table, Pretext is about **5.8x faster than Core Text** and **17.9x faster than SwiftUI** for `Batch Prepare + Layout (500 texts)`.

| Test | Pretext | Core Text | SwiftUI | Vs CT | Vs SwiftUI |
|---|---:|---:|---:|---:|---:|
| Batch Prepare + Layout (500 texts) | 4.9ms | 28.5ms | 87.8ms | 5.8x | 17.9x |
| Reflow 100 Widths (50k calls) | 7.0ms | 1895ms | 11703ms | 272x | 1680x |
| Variable-Width Line-by-Line | 0.08ms | 1.6ms | — | 19.1x | — |
| Interleaved Measure-Mutate (500x) | 4.8ms | 28.8ms | 91.4ms | 6.0x | 19.0x |
| Masonry Heights (1904 texts) | 8.4ms | 25.9ms | 307ms | 3.1x | 36.7x |

The hot `layout()` path is pure arithmetic. Measurement happens once in `prepare(...)`; repeated layout reuses cached widths.

## Platform Support

- `Pretext` supports `iOS 18+`, `macOS 15+`, and `watchOS 11+`
- `PretextUI` provides the optional `SwiftUI.Font` bridge on those same platforms
- `Demo` supports `iPhone`, `iPad`, `macOS`, and a curated Apple Watch catalog in this repository
- the standalone `Benchmark` executable remains macOS-first, while the shared benchmark presentation is also used inside the demo app

## Build & Run

```bash
# Launch the macOS demo app
rake demo

# Run the full SwiftPM test suite
rake test

# Run the CLI benchmark
rake bench
```

Requires Xcode with iOS 18 / macOS 15 / watchOS 11 SDK support and Swift 6.0+.

## Demo

<video src="https://github.com/user-attachments/assets/1921d5dc-9cc2-440e-850a-09a4677ccbd5" autoplay loop muted playsinline width="100%"></video>
**Editorial Engine** — dark multi-column editorial layout with animated orb obstacles



<video src="https://github.com/user-attachments/assets/55311c47-9f07-4c02-a6e9-8bba69317c0e" autoplay loop muted playsinline width="100%"></video>
**Chika Dance** — animated text reflow around live video silhouettes

<video src="https://github.com/user-attachments/assets/24734a37-bbd3-4ac5-9281-e8f9258fb6e8" autoplay loop muted playsinline width="100%"></video>

**Fluid** — particle-style text field reflow

The demo app also includes:

- `Situational Awareness`: light editorial layout with obstacle-aware text flow
- `Masonry`: waterfall card layout driven by cached text measurement
- `Illustrated Manuscript`: decorated long-form layout with physics-driven page composition
- `Live Camera Silhouette`: camera-driven text routing around a live subject silhouette
- `Benchmark`: in-app performance comparison against Core Text and SwiftUI

On Apple Watch, the catalog is intentionally narrower and currently includes:

- `Situational Awareness`
- `Editorial Engine`
- `Masonry`
- `Illustrated Manuscript`
- `Fluid`
- `Benchmark`

## API

### Fast path: measure a paragraph without touching SwiftUI layout

```swift
import CoreText
import Pretext

let font = CTFontCreateWithName("Helvetica Neue" as CFString, 16, nil)
let prepared = prepare("AGI 春天到了. بدأت الرحلة 🚀", font: font)
let result = layout(prepared, maxWidth: 320, lineHeight: 20)

print(result.lineCount)
print(result.height)
```

If you want textarea-style preserved spaces, tabs, and hard breaks, use `whiteSpace: .preWrap` during `prepare(...)`.

### Rich path: inspect lines or stream them one line at a time

```swift
import CoreText
import Pretext

let font = CTFontCreateWithName("Helvetica Neue" as CFString, 18, nil)
let prepared = prepareWithSegments("AGI 春天到了. بدأت الرحلة 🚀", font: font)

let (result, lines) = layoutWithLines(prepared, maxWidth: 320, lineHeight: 26)
let naturalWidth = measureNaturalWidth(prepared)

walkLineRanges(prepared, maxWidth: 320) { width, start, end in
    print(width, start, end)
}

var cursor = LayoutCursor.start
while let line = layoutNextLine(prepared, start: cursor, maxWidth: 320) {
    print(line.text)
    cursor = line.end
}
```

Useful helpers:

- `prepareForWidth(...)`: lazily resolves breakable grapheme widths for a specific width
- `measureNaturalWidth(...)`: returns the widest forced line when width itself is not causing wraps
- `setLocale(...)`: retargets text analysis for future `prepare(...)` calls
- `clearCache()`: clears shared analysis and measurement caches

### SwiftUI bridge

```swift
import PretextUI

let descriptor = FontDescriptor(familyName: "Helvetica Neue", size: 16)
let displayFont = descriptor.makeDisplayFont()
```

## How It Works

1. `prepare(text, font)` or `prepareWithSegments(text, font)` segments text, measures runs with Core Text, and caches widths.
2. `layout(prepared, maxWidth, lineHeight)` computes multiline layout from cached widths.
3. `layoutWithLines(...)`, `walkLineRanges(...)`, and `layoutNextLine(...)` expose the richer manual-layout path.
4. `measureNaturalWidth(prepared)` returns the widest forced line for rich/manual layout work.

The key idea is separating measurement from layout so resize and animated obstacle reflow stay cheap. Measurement happens once up front; repeated layout is pure arithmetic over cached widths.

## Credits

Based on [Pretext](https://github.com/chenglou/pretext) by Cheng Lou. The Swift port reimplements the text analysis pipeline, line-breaking engine, and editorial demos using Core Text for measurement and SwiftUI Canvas for rendering.

Demo-specific credits:

- `Chika Dance` uses a bundled sample clip sourced via [Matteflow](https://github.com/summerKK/Matteflow) by `summerKK`; Matteflow credits the underlying `Chika Dance Green Screen` footage to [Conics](https://www.youtube.com/@LConics).
- `Illustrated Manuscript` adapts the `Dragon` demo from [Pretext Playground](https://pretext-playground.builderz.dev) by Builderz.
- `Fluid` adapts [fluid.felixmartinez.dev](https://fluid.felixmartinez.dev) by Felix Martinez.
