# Fluid watchOS Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable the Fluid tab on watchOS with touch-drag interaction and watch-optimized layout, without changing iOS/macOS behavior.

**Architecture:** The SPH physics engine (`FluidSimulationState`, `fluidAdvanceParticles`) already compiles on watchOS — only the view layer (`FluidView`) and driver (`FluidSimulationDriver`) are gated by `#if !os(watchOS)`. The plan lifts those guards, creates a watchOS-specific view using `Canvas` + `DragGesture` (no hover), and adds watch-optimized layout constants (smaller font, fewer characters, no toolbar margin).

**Tech Stack:** SwiftUI (Canvas), CoreText (CTFontDrawGlyphs), SPH physics (CPU-only on watchOS — no Metal compute)

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Sources/Demo/Fluid/FluidView.swift` | Modify | Remove `#if !os(watchOS)` guard, add watchOS-compatible view using existing `FluidView` with conditional compilation for hover/cursor hiding |
| `Sources/Demo/Fluid/FluidSimulation.swift` | Modify | Remove `#if !os(watchOS)` from `FluidSimulationDriver`, add watchOS CPU-only driver path |
| `Sources/Demo/Fluid/FluidLayout.swift` | Modify | Add watchOS layout constants (font size 10, cursor size 14, phrase multiplier 3) |
| `Sources/Demo/ContentView.swift` | Modify | Add `.fluid` to watchOS `availableCases`, replace `WatchUnsupportedDemoView` with `FluidView()` |
| `Tests/DemoTests/DemoWatchCatalogTests.swift` | Modify | Update test: fluid is now available on watchOS |
| `Tests/DemoTests/FluidSimulationTests.swift` | Modify | Add watchOS layout test to verify smaller metrics |

---

### Task 1: Add watchOS layout constants

**Files:**
- Modify: `Sources/Demo/Fluid/FluidLayout.swift:65-70` (FluidLayoutDefaults)
- Modify: `Sources/Demo/Fluid/FluidLayout.swift:160-183` (fluidPageMetrics)
- Modify: `Sources/Demo/Fluid/FluidLayout.swift:120-122` (fluidPhraseCount)
- Test: `Tests/DemoTests/FluidSimulationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testWatchLayoutUsesReducedMetrics() {
    let layout = makeLayout(width: 198, height: 242, platform: .watchOS)

    XCTAssertEqual(layout.pageMetrics.fontSize, 10.0)
    XCTAssertEqual(layout.pageMetrics.cursorBaseSize, 14.0)
    XCTAssertGreaterThan(layout.glyphs.count, 0)
    XCTAssertLessThan(layout.glyphs.count, 300,
        "Watch should have fewer characters than mobile")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FluidSimulationTests/testWatchLayoutUsesReducedMetrics`
Expected: FAIL — `fluidPageMetrics` doesn't handle `.watchOS` platform, returns mobile font size 12.0

- [ ] **Step 3: Add watch constants and update layout functions**

In `FluidLayout.swift`, add watch constants to `FluidLayoutDefaults`:

```swift
private enum FluidLayoutDefaults {
    static let desktopFontSize = 16.0
    static let mobileFontSize = 12.0
    static let watchFontSize = 10.0
    static let desktopCursorBaseSize = 22.0
    static let mobileCursorBaseSize = 18.0
    static let watchCursorBaseSize = 14.0
}
```

Update `fluidPhraseCount` to accept platform:

```swift
func fluidPhraseCount(for viewportWidth: Double, platform: DemoNavigationPlatform = .current) -> Int {
    let multiplier: Double = platform == .watchOS ? 3.0 : 7.0
    return max(1, Int((viewportWidth / 512.0 * multiplier).rounded()))
}
```

Update `fluidPageMetrics` to handle watchOS:

```swift
func fluidPageMetrics(
    viewportWidth: Double,
    viewportHeight: Double,
    platform: DemoNavigationPlatform = .current
) -> FluidPageMetrics {
    let width = max(0, viewportWidth)
    let height = max(0, viewportHeight)
    let usesDesktopSizing = platform == .macOS
    let usesWatchSizing = platform == .watchOS
    let viewportRect = WrapRect(x: 0, y: 0, width: width, height: height)
    let fontSize: Double
    let cursorBaseSize: Double
    if usesWatchSizing {
        fontSize = FluidLayoutDefaults.watchFontSize
        cursorBaseSize = FluidLayoutDefaults.watchCursorBaseSize
    } else if usesDesktopSizing {
        fontSize = FluidLayoutDefaults.desktopFontSize
        cursorBaseSize = FluidLayoutDefaults.desktopCursorBaseSize
    } else {
        fontSize = FluidLayoutDefaults.mobileFontSize
        cursorBaseSize = FluidLayoutDefaults.mobileCursorBaseSize
    }
    let font = fluidBodyFont(size: fontSize)
    let lineHeight = Double(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))

    return FluidPageMetrics(
        viewportRect: viewportRect,
        contentRect: viewportRect,
        layoutWidth: width,
        fontSize: fontSize,
        lineHeight: lineHeight,
        fieldColumns: max(18, Int(width / (usesWatchSizing ? 16 : usesDesktopSizing ? 28 : 22))),
        fieldRows: max(12, Int(height / (usesWatchSizing ? 18 : usesDesktopSizing ? 28 : 24))),
        cursorBaseSize: cursorBaseSize
    )
}
```

Update `evaluateFluidLayout` to pass platform to `fluidPhraseCount`:

```swift
let phraseCount = fluidPhraseCount(for: viewportWidth, platform: platform)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FluidSimulationTests/testWatchLayoutUsesReducedMetrics`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Demo/Fluid/FluidLayout.swift Tests/DemoTests/FluidSimulationTests.swift
git commit -m "feat: add watchOS-optimized fluid layout constants"
```

---

### Task 2: Remove watchOS guard from FluidSimulationDriver

**Files:**
- Modify: `Sources/Demo/Fluid/FluidSimulation.swift:1792` (remove `#if !os(watchOS)`)
- Test: `Tests/DemoTests/FluidSimulationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testWatchSimulationStepProducesMovement() {
    let layout = makeLayout(width: 198, height: 242, platform: .watchOS)
    var state = FluidSimulationState.empty
    state.reset(from: layout)

    let center = WrapPoint(x: 99, y: 121)
    applySweep(
        to: &state,
        from: center,
        to: WrapPoint(x: center.x + 50, y: center.y),
        frames: 10,
        layout: layout
    )

    let displaced = state.particles.filter { particle in
        let rest = state.restCenters[state.particles.firstIndex(where: { $0.id == particle.id })!]
        return hypot(particle.center.x - rest.x, particle.center.y - rest.y) > 5
    }

    XCTAssertGreaterThan(displaced.count, 0, "Watch sweep should displace particles")
}
```

- [ ] **Step 2: Run test to verify it passes** (this already works since FluidSimulationState is not gated)

Run: `swift test --filter FluidSimulationTests/testWatchSimulationStepProducesMovement`
Expected: PASS — the physics engine already compiles for all platforms

- [ ] **Step 3: Remove the watchOS guard from FluidSimulationDriver**

In `FluidSimulation.swift`, change line 1792:

```swift
// Before:
#if !os(watchOS)
final class FluidSimulationDriver {

// After (remove the #if and matching #endif):
final class FluidSimulationDriver {
```

Find the matching `#endif` (at the end of FluidSimulationDriver and the Metal engine) and remove it. Keep `#if canImport(Metal)` guards around Metal-specific code since watchOS doesn't have Metal compute.

- [ ] **Step 4: Build for watchOS to verify compilation**

Run: `swift build`
Expected: Build succeeds (FluidSimulationDriver now compiles on all platforms, Metal code is already guarded by `#if canImport(Metal)`)

- [ ] **Step 5: Commit**

```bash
git add Sources/Demo/Fluid/FluidSimulation.swift
git commit -m "refactor: remove watchOS exclusion from FluidSimulationDriver"
```

---

### Task 3: Remove watchOS guard from FluidView and add watchOS interaction

**Files:**
- Modify: `Sources/Demo/Fluid/FluidView.swift:1` (remove `#if !os(watchOS)` guard)
- Test: build verification

- [ ] **Step 1: Remove the `#if !os(watchOS)` guard from FluidView.swift**

Remove line 1 (`#if !os(watchOS)`) and the matching `#endif` at the end of the file.

- [ ] **Step 2: Guard macOS-only imports and cursor hiding**

The file imports `AppKit` (macOS) and `UIKit` (iOS) and uses `NSCursor.hide()`. These need platform guards. The existing `#if os(macOS)` / `#elseif os(iOS)` guards already handle this, but watchOS falls through. Add watchOS handling:

In `FluidView`, the `syncSystemCursorVisibility` method and `isSystemCursorHidden` state are macOS-only — they're already inside `#if os(macOS)`. No change needed.

The `demoContinuousHover` modifier needs guarding since watchOS has no hover. Wrap it:

```swift
#if !os(watchOS)
.demoContinuousHover { location in
    applyInteraction(.hoverChanged(location))
}
#endif
```

- [ ] **Step 3: Adjust boundary margins for watchOS**

In `FluidSimulation.swift`, the `fluidBoundaryMarginTop = 52.0` is for the macOS toolbar. watchOS has no toolbar. Add platform-aware margins:

```swift
func fluidBoundaryMargins(for platform: DemoNavigationPlatform) -> (top: Double, bottom: Double, side: Double) {
    switch platform {
    case .watchOS:
        return (top: 4.0, bottom: 4.0, side: 4.0)
    case .macOS:
        return (top: 52.0, bottom: 32.0, side: 10.0)
    case .ios:
        return (top: 10.0, bottom: 10.0, side: 10.0)
    }
}
```

Note: This requires passing margins through the simulation. The simplest approach is to store margins in `FluidPageMetrics` and use them in the boundary functions instead of the global constants.

- [ ] **Step 4: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/Demo/Fluid/FluidView.swift Sources/Demo/Fluid/FluidSimulation.swift
git commit -m "feat: enable FluidView on watchOS with drag-only interaction"
```

---

### Task 4: Add fluid to watchOS catalog and update ContentView

**Files:**
- Modify: `Sources/Demo/ContentView.swift:20-27` (availableCases)
- Modify: `Sources/Demo/ContentView.swift:304-309` (demoView switch case)
- Modify: `Tests/DemoTests/DemoWatchCatalogTests.swift:38-43`
- Test: `Tests/DemoTests/DemoWatchCatalogTests.swift`

- [ ] **Step 1: Update the watch catalog test**

Change the test from expecting `nil` (fluid unavailable) to expecting `.fluid`:

```swift
// Before:
XCTAssertNil(
    DemoScreen.launchSelection(
        arguments: ["Demo", "--demo-screen", DemoScreen.fluid.rawValue],
        platform: .watchOS
    )
)

// After:
XCTAssertEqual(
    DemoScreen.launchSelection(
        arguments: ["Demo", "--demo-screen", DemoScreen.fluid.rawValue],
        platform: .watchOS
    ),
    .fluid
)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DemoWatchCatalogTests`
Expected: FAIL — `.fluid` not in watchOS `availableCases`

- [ ] **Step 3: Add fluid to watchOS available cases**

In `ContentView.swift`, add `.fluid` to the watchOS case:

```swift
case .watchOS:
    [
        .situationalAwareness,
        .editorialEngine,
        .masonry,
        .illustratedManuscript,
        .fluid,
        .benchmark,
    ]
```

- [ ] **Step 4: Replace WatchUnsupportedDemoView with FluidView**

In the `demoView` switch case:

```swift
case .fluid:
    FluidView()
```

Remove the `#if os(watchOS)` / `WatchUnsupportedDemoView` / `#else` / `#endif` branching entirely since FluidView now compiles on all platforms.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter DemoWatchCatalogTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/Demo/ContentView.swift Tests/DemoTests/DemoWatchCatalogTests.swift
git commit -m "feat: enable Fluid tab on watchOS"
```

---

### Task 5: Build and deploy to Apple Watch

**Files:** None (verification only)

- [ ] **Step 1: Build for watchOS device**

```bash
xcodegen generate --spec Xcode/DemoWatchRunner/project.yml
xcodebuild -project Xcode/DemoWatchRunner/DemoWatchRunner.xcodeproj \
    -scheme DemoWatchRunner -configuration Release \
    -destination 'platform=watchOS,id=<watch-udid>' build
```

- [ ] **Step 2: Install and launch on watch**

```bash
xcrun devicectl device install app --device 'AW11' <app-path>
xcrun devicectl device process launch --device 'AW11' <bundle-id> --activate --terminate-existing
```

- [ ] **Step 3: Verify interaction**

Navigate to Fluid tab on the watch. Drag finger across the screen. Verify:
- Characters are visible and properly sized for the watch screen
- Drag gesture pushes characters apart
- Characters settle after releasing finger
- No characters escape viewport boundaries
- Performance is smooth (no visible stuttering)

- [ ] **Step 4: Run full test suite**

```bash
swift test
```

Expected: All existing tests pass, new watchOS tests pass.

- [ ] **Step 5: Commit any final adjustments**

```bash
git add -A
git commit -m "fix: watchOS fluid adjustments from device testing"
```
