# Fluid Web Parity Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the `Fluid` demo so the default scene and interaction match the pinned `2026-04-01` `fluid.felixmartinez.dev` reference on macOS, with the same scene model adapted for touch on iOS.

**Architecture:** Keep the existing demo-shell integration intact, but replace the current `Fluid` internals with a three-part system: deterministic `Pretext` rest layout plus font gate, a web-parity point-particle simulation over visible glyphs, and a thin SwiftUI `Canvas` view that handles per-glyph drawing and platform input lifecycle. Use the exact bundled `L10-Medium` font if it loads locally; otherwise fall back deterministically to `Helvetica Neue`. Do not add native-only glyph-rectangle collision, edge packing, or whole-glyph viewport clamping.

**Tech Stack:** Swift 6, SwiftUI `Canvas`, CoreText, CoreGraphics, Pretext, XCTest, Instruments, XcodeGen

---

## File Map

### Existing files to modify

- `Sources/Demo/Fluid/FluidLayout.swift`
  Replace the current padded line/run layout with an edge-to-edge, immutable `Pretext` rest-layout snapshot that emits visible glyph particles only.
- `Sources/Demo/Fluid/FluidSimulation.swift`
  Replace the coarse flow-field model and native rectangle correction layer with explicit particle state, web-parity solver passes, cursor state, pointer lifecycle handling, and dt policy.
- `Sources/Demo/Fluid/FluidView.swift`
  Replace word-run rendering with per-glyph drawing, thin orchestration, and platform-specific pointer/cursor teardown.
- `Tests/DemoTests/FluidLayoutTests.swift`
  Replace run-count-oriented tests with parity-contract tests for phrase assembly, clipping, font mode, and rest-layout determinism.
- `Tests/DemoTests/FluidSimulationTests.swift`
  Replace field-based tests with particle-state, pointer lifecycle, web-parity force-model, and dt-clamp tests.

### New source files

- `Sources/Demo/Fluid/FluidFontAssets.swift`
  Font-loading and font-mode gate: exact bundled `L10-Medium` if loadable, otherwise deterministic `Helvetica Neue` fallback.

### New resources

- `Sources/Demo/Resources/Fluid/L10-Medium.woff`
  Pinned font asset captured from the reference site.

### Existing tests to keep as integration guards

- `Tests/DemoTests/ContentViewTests.swift`
  Existing shell-order tests already pin `Fluid` after `Live Camera Silhouette` and before `Benchmark`.
- `Tests/DemoTests/DemoWatchCatalogTests.swift`
  Existing watch-catalog tests already pin `Fluid` as excluded from watchOS.

### Context files to read while executing

- `docs/superpowers/specs/2026-04-01-fluid-web-parity-design.md`
- `docs/superpowers/specs/2026-04-01-fluid-web-parity-reference.md`
- `Sources/Demo/IllustratedManuscript/IllustratedManuscriptAssets.swift`
- `Sources/Demo/ContentView.swift`
- `Tests/DemoTests/ContentViewTests.swift`
- `Tests/DemoTests/DemoWatchCatalogTests.swift`

### Working-tree constraints

- The repo may already be dirty. Do not revert unrelated changes.
- Existing demo-shell tests already encode the `Fluid` tab placement contract; no shell-file change is expected unless refactoring breaks that contract.
- This repo requires ask-first before commits. Commit steps below are conditional and must be skipped unless the user explicitly approves committing.

## Chunk 1: Font Gate and Rest Layout

### Task 1: Add the font gate and lock deterministic font behavior

**Files:**
- Modify: `Tests/DemoTests/FluidLayoutTests.swift`
- Create: `Sources/Demo/Fluid/FluidFontAssets.swift`
- Create: `Sources/Demo/Resources/Fluid/L10-Medium.woff`
- Modify: `Sources/Demo/Fluid/FluidLayout.swift`

- [ ] **Step 1: Write the failing tests for font mode and fallback behavior**

Add tests in `Tests/DemoTests/FluidLayoutTests.swift` for:

- resolved font mode is `.exact` when the bundled font loads
- fallback is `.fallback(.helveticaNeue)` when exact loading fails in a controlled test seam
- the font mode is deterministic and cached
- fallback is only considered valid for explicit load failures such as missing resource or invalid graphics font
- the packaged `L10-Medium.woff` resolves from `Bundle.module`

Example skeleton:

```swift
func testFluidFontAssetsResolveDeterministicMode() {
    let assets = FluidFontAssets.testValue(
        loadExactGraphicsFont: { throw FluidFontLoadFailure.invalidGraphicsFont }
    )

    XCTAssertEqual(assets.resolvedFontMode(size: 16), .fallback(.helveticaNeue))
}
```

- [ ] **Step 2: Run the focused layout tests to verify failure**

Run: `swift test --filter FluidLayoutTests`
Expected: FAIL because `FluidFontAssets` and the font-mode API do not exist yet.

- [ ] **Step 3: Add the exact-font resource and minimal font gate**

Create `Sources/Demo/Resources/Fluid/L10-Medium.woff` from the pinned reference asset.

Create `Sources/Demo/Fluid/FluidFontAssets.swift` with:

- `enum FluidFontMode { case exact, fallback(FluidFallbackFont) }`
- `enum FluidFallbackFont { case helveticaNeue }`
- `enum FluidFontLoadFailure: Error { case missingResource, unreadableData, invalidGraphicsFont }`
- a test seam that allows forcing exact-load failure deterministically
- exact font loading from `Bundle.module`
- deterministic fallback to `Helvetica Neue`
- explicit decision rule:
  - if the bundled resource exists and `CGFont(provider)` succeeds, mode must resolve to `.exact`
  - fallback is allowed only when the exact loader throws one of the explicit `FluidFontLoadFailure` cases or the resource is intentionally removed by a user/legal decision outside the plan
- wire `Sources/Demo/Fluid/FluidLayout.swift` to use `FluidFontAssets.bodyFont(size:)` so the exact-font path is consumed by real layout code immediately rather than staying dead code

Suggested API surface:

```swift
struct FluidFontAssets {
    var loadExactGraphicsFont: () throws -> CGFont
    func resolvedFontMode(size: Double) -> FluidFontMode
    func bodyFont(size: Double) -> CTFont
    static let live: FluidFontAssets
    static func testValue(
        loadExactGraphicsFont: @escaping () throws -> CGFont
    ) -> FluidFontAssets
}
```

- [ ] **Step 4: Re-run the focused layout tests**

Run: `swift test --filter FluidLayoutTests`
Expected: PASS for the new font-mode tests.

- [ ] **Step 5: If the user has approved commits in this repo, commit this task**

```bash
git add Tests/DemoTests/FluidLayoutTests.swift Sources/Demo/Fluid/FluidFontAssets.swift Sources/Demo/Fluid/FluidLayout.swift Sources/Demo/Resources/Fluid/L10-Medium.woff
git commit -m "feat: add fluid font asset gate"
```

### Task 2: Rewrite `FluidLayout` around immutable visible glyphs

**Files:**
- Modify: `Tests/DemoTests/FluidLayoutTests.swift`
- Modify: `Sources/Demo/Fluid/FluidLayout.swift`
- Modify: `Sources/Demo/Fluid/FluidView.swift` only for a temporary compile-safe bridge until Chunk 3 replaces the renderer

- [ ] **Step 1: Add failing tests for the parity layout contract**

Extend `Tests/DemoTests/FluidLayoutTests.swift` with tests for:

- zero or negative viewport dimensions -> empty layout snapshot
- tiny positive widths use the intentional native clamp: `max(1, round(width / 512 * 25))`
- deterministic phrase shuffling via the fixed native seed
- the fixed seed is exposed as a named constant or helper seam so corpus-cycle behavior is asserted without duplicating shuffle internals in the test file
- phrase assembly shuffles before the first phrase, reshuffles at each full corpus cycle, and appends uppercase phrases with trailing spaces
- full-width horizontal layout contract on macOS and iOS
- full-width explicitly means no editorial side padding and glyph placement can reach the viewport edges
- visible-only vertical clipping
- partially visible top-edge glyphs are kept
- partially visible bottom-edge glyphs are kept
- spaces affect layout but are not emitted as visible glyph particles
- desktop/mobile font sizing remains `16` / `12`

Example skeleton:

```swift
func testFluidLayoutUsesFullViewportWidthOnMacOS() {
    let snapshot = evaluateFluidLayout(
        viewportWidth: 1280,
        viewportHeight: 800,
        platform: .macOS
    )

    XCTAssertEqual(snapshot.pageMetrics.layoutWidth, 1280, accuracy: 0.001)
}
```

- [ ] **Step 2: Run the layout tests to verify failure**

Run: `swift test --filter FluidLayoutTests`
Expected: FAIL because the current layout still emits padded lines and run-based structures.

- [ ] **Step 3: Replace the old line/run model with immutable glyph layout types**

In `Sources/Demo/Fluid/FluidLayout.swift`:

- remove `drawRuns`
- introduce immutable layout types:

```swift
struct FluidGlyphLayout: Equatable {
    var id: Int
    var character: String
    var restCenter: WrapPoint
    var drawOrigin: WrapPoint
    var baselineY: Double
    var width: Double
    var bounds: WrapRect
}
```

```swift
struct FluidLayoutSnapshot: Equatable {
    var pageMetrics: FluidPageMetrics
    var text: String
    var glyphs: [FluidGlyphLayout]
}
```

- make phrase assembly deterministic using the fixed shuffle seed
- implement the full phrase-assembly contract:
  - shuffle before the first phrase
  - reshuffle at each full corpus cycle
  - append uppercase phrases with trailing spaces
- expose a named fixed shuffle seed or helper seam used by both implementation and tests
- use full scene width as justification width
- remove editorial side padding from the rest-layout path rather than hiding it behind a new metrics field
- emit only visible, non-space glyphs into `glyphs`
- add an explicit `layoutWidth` field or equivalent `FluidPageMetrics` contract so the full-width assertion is not inferred indirectly
- keep `FluidView.swift` compiling in this chunk by adding a temporary compatibility bridge or minimal compile-only adaptation to the new `glyphs` snapshot shape

- [ ] **Step 4: Re-run the layout tests**

Run: `swift test --filter FluidLayoutTests`
Expected: PASS for the new layout-contract tests.

- [ ] **Step 5: Remove obsolete run-oriented assertions and add explicit parity checks**

Delete or rewrite any test that assumes word-level draw runs or padded content rects.

Replace with parity-oriented checks:

- glyph count is stable for the same viewport
- glyph bounds intersect the viewport
- layout snapshot stays deterministic across repeated evaluation

- [ ] **Step 6: Re-run the layout tests again**

Run: `swift test --filter FluidLayoutTests`
Expected: PASS with the rewritten suite only asserting current parity requirements.

- [ ] **Step 7: If the user has approved commits in this repo, commit this task**

```bash
git add Tests/DemoTests/FluidLayoutTests.swift Sources/Demo/Fluid/FluidLayout.swift Sources/Demo/Fluid/FluidView.swift
git commit -m "feat: rewrite fluid rest layout for visible glyph particles"
```

## Chunk 2: Particle Simulation and Pointer Lifecycle

### Task 3: Add failing particle-simulation tests before replacing the old field model

**Files:**
- Modify: `Tests/DemoTests/FluidSimulationTests.swift`
- Modify: `Sources/Demo/Fluid/FluidSimulation.swift`

- [ ] **Step 1: Write failing tests for the new simulation state and lifecycle model**

Replace or extend `Tests/DemoTests/FluidSimulationTests.swift` with tests for:

- `reset(from:)` seeds particles at rest positions with zero velocity
- `reset(from:)` preserves pointer state only when the pointer remains inside the new layout bounds; otherwise it clears it
- `step(dt:pointer:layout:)` clamps `dt` to `[1/240, 1/20]`
- large frame gaps after deactivation clear pointer state and restart from nominal timing
- `clearPointer()` hides the cursor state

Example skeleton:

```swift
func testResetFromLayoutSeedsZeroVelocityParticles() {
    let layout = makeTestLayout()
    var state = FluidSimulationState.empty

    state.reset(from: layout)

    XCTAssertEqual(state.particles.map(\.velocity), Array(repeating: .zero, count: layout.glyphs.count))
}
```

- [ ] **Step 2: Run the simulation tests to verify failure**

Run: `swift test --filter FluidSimulationTests`
Expected: FAIL because the current implementation still exposes flow-field behavior and lacks the new API.

- [ ] **Step 3: Replace the old simulation model with explicit particle state**

In `Sources/Demo/Fluid/FluidSimulation.swift`, introduce:

```swift
struct FluidParticleState: Equatable {
    var id: Int
    var center: WrapPoint
    var velocity: SIMD2<Double>
}
```

```swift
struct FluidCursorState: Equatable {
    var isVisible: Bool
    var center: WrapPoint
    var angle: Double
    var size: Double
}
```

```swift
struct FluidSimulationState: Equatable {
    var particles: [FluidParticleState]
    var pointer: FluidPointerState
    var cursor: FluidCursorState?
}
```

Add the required API:

- `mutating func reset(from layout: FluidLayoutSnapshot)`
- `mutating func step(dt: Double, pointer: FluidPointerInput?, layout: FluidLayoutSnapshot) -> FluidFrameStepResult`
- `mutating func updatePointer(_ input: FluidPointerInput?)`
- `mutating func clearPointer()`

Define the new pointer/frame types explicitly in this task so the implementer does not invent them ad hoc:

```swift
struct FluidPointerInput: Equatable {
    var center: WrapPoint
    var direction: SIMD2<Double>
    var strength: Double
}
```

```swift
struct FluidPointerState: Equatable {
    var current: FluidPointerInput?
}
```

```swift
struct FluidFrameStepResult: Equatable {
    var appliedDeltaTime: Double
    var clearedPointerForLargeGap: Bool
}
```

- [ ] **Step 4: Re-run the simulation tests**

Run: `swift test --filter FluidSimulationTests`
Expected: PASS for the state/lifecycle subset written in Step 1.

- [ ] **Step 5: Add the failing force-model regressions**

Extend `Tests/DemoTests/FluidSimulationTests.swift` with tests for:

- displaced particles do not spring back toward their rest positions when pointer input is absent
- idle simulation becomes still eventually without synthetic ambient drift
- pointer impulse changes nearby glyph velocity
- stronger input produces a larger impulse and larger cursor size
- different input directions change cursor angle and disturbance direction
- neighbor interaction creates local separation without exploding velocity
- point-particle boundary handling keeps centers in bounds
- no native glyph-rectangle overlap, edge-packing, or whole-glyph clamp pass is required for normal interaction

- [ ] **Step 6: Run the simulation tests again to verify the new force-model slice fails**

Run: `swift test --filter FluidSimulationTests`
Expected: FAIL on the newly added force-model assertions while the state/lifecycle subset remains green.

- [ ] **Step 7: Port the web pointer and timing model**

Inside `step(dt:pointer:layout:)`, add:

- the web pointer smoothing model
- the web mouse-strength growth/decay model
- the `3`-substep frame policy
- `dt` clamp and large-gap reset behavior from the design spec

- [ ] **Step 8: Port the web force passes and constants**

Mirror the deployed web solver behavior with:

- positions pass
- densities/forces pass
- velocities pass
- `range = 14`
- `pressureMultiplier = 10`
- `viscosityFactor = 600.1`
- `dampingFactor = 0.999`
- `originalPositionFactor = 0`

Verify this directly against the failing direction/strength/no-spring regressions from Step 5 before moving on.

- [ ] **Step 9: Remove native rectangle correction from the runtime path**

Delete or bypass:

- pairwise glyph-overlap correction
- edge packing near viewport borders
- whole-glyph viewport clamp/bounce

Keep only point-center viewport bounce/clamp, matching the web shader behavior.

- [ ] **Step 10: Add idle stillness without rest-springing**

Finish the frame step with damping and settle-zeroing so particles eventually become still without being pulled back into the original paragraph layout.

- [ ] **Step 11: Re-run the simulation tests with the full force model**

Run: `swift test --filter FluidSimulationTests`
Expected: PASS with stable particle behavior and bounded idle movement.

- [ ] **Step 12: If the user has approved commits in this repo, commit this task**

```bash
git add Tests/DemoTests/FluidSimulationTests.swift Sources/Demo/Fluid/FluidSimulation.swift
git commit -m "feat: replace fluid flow field with particle simulation"
```

## Chunk 3: View Rewrite, Integration Guards, and Runtime Verification

### Task 4: Replace `FluidView` with a thin per-glyph renderer

**Files:**
- Modify: `Sources/Demo/Fluid/FluidView.swift`
- Modify: `Sources/Demo/Fluid/FluidLayout.swift` only if compile-time integration changes are required
- Modify: `Sources/Demo/Fluid/FluidSimulation.swift` only if orchestration changes reveal a missing API

- [ ] **Step 1: Remove the word-run drawing path**

Delete the `drawRuns`-based rendering path and render each visible glyph independently from `FluidLayoutSnapshot.glyphs` + `FluidSimulationState.particles`.

- [ ] **Step 2: Implement the correct Core Graphics text transform**

Use a consistent text transform so glyphs are upright in `Canvas`.

Expected drawing shape:

```swift
cg.saveGState()
cg.textMatrix = .identity
cg.translateBy(x: glyphCenter.x, y: glyphCenter.y)
cg.rotate(by: rotation)
cg.translateBy(x: -glyphCenter.x, y: -glyphCenter.y)
cg.textPosition = CGPoint(x: drawOrigin.x, y: baselineY)
CTLineDraw(line, cg)
cg.restoreGState()
```

- [ ] **Step 3: Wire the pointer lifecycle policy into the view**

In `FluidView.swift`:

- macOS hover updates pointer continuously
- hover exit clears pointer and restores cursor
- app/window deactivation clears pointer and restores cursor
- iOS uses only the primary touch
- touch end/cancel clears pointer and hides the custom cursor
- relayout resets particle state from the new immutable layout snapshot

- [ ] **Step 4: Run focused tests to verify the rewrite still compiles**

Run:

```bash
swift test --filter FluidLayoutTests
swift test --filter FluidSimulationTests
```

Expected: both PASS

- [ ] **Step 5: If the user has approved commits in this repo, commit this task**

```bash
git add Sources/Demo/Fluid/FluidView.swift Sources/Demo/Fluid/FluidLayout.swift Sources/Demo/Fluid/FluidSimulation.swift
git commit -m "feat: render fluid scene as per-glyph particle canvas"
```

### Task 5: Re-verify shell contracts and run the parity runtime loop

**Files:**
- Modify: `Sources/Demo/ContentView.swift` only if refactoring accidentally breaks routing or tab placement
- Modify: `Tests/DemoTests/ContentViewTests.swift` only if preserved shell contract coverage unexpectedly needs repair
- Modify: `Tests/DemoTests/DemoWatchCatalogTests.swift` only if preserved watch-exclusion coverage unexpectedly needs repair

- [ ] **Step 1: Re-run the existing shell-contract tests**

Run:

```bash
swift test --filter ContentViewTests
swift test --filter DemoWatchCatalogTests
```

Expected: PASS, confirming:

- raw value remains `"fluid"`
- title remains `Fluid`
- compact title remains `Fluid`
- order remains after `Live Camera Silhouette` and before `Benchmark`
- watchOS still excludes `fluid`

- [ ] **Step 2: Launch the macOS app through the real workflow**

Run: `rake demo`
Expected: the current worktree’s `Demo.app` builds and launches.

- [ ] **Step 3: Run the explicit macOS runtime checklist**

After launch, verify all of the following end-to-end behaviors:

- custom cursor hides the system cursor while active
- hover exit restores the system cursor
- app/window deactivation restores the system cursor and clears pointer state
- app/window reactivation does not produce a giant simulation jump from a large `dt`
- resizing the window triggers relayout and particle reset without crashes

Expected: all checks succeed before parity-state comparison begins.

- [ ] **Step 4: Verify the three required parity states against the pinned reference note**

Compare the native scene against `docs/superpowers/specs/2026-04-01-fluid-web-parity-reference.md` for:

- `idle`
- `active-sweep`
- `post-settle`

Expected:

- full-viewport black stage is intact
- visible glyphs render as white uppercase text
- the custom cursor reads as the pinned yellow accent
- no debug/control panel or extra chrome appears inside the scene
- idle is alive but not a dense editorial block
- active sweep opens into a directional particle field
- post-settle remains sparse and eventually still, without snapping back into the original paragraph layout

- [ ] **Step 5: Build and smoke-test the iOS path**

First run the package-level build guard:

```bash
rake build_ios_demo
```

Expected: the package-level iPhone and iPad simulator builds succeed.

Then run one exact simulator launch path through the repo’s iOS runner project:

```bash
xcodegen generate --spec Xcode/DemoDeviceRunner/project.yml
IPHONE_UDID="$(ruby -rjson -e 'devices = JSON.parse(%x[xcrun simctl list devices available --json]).fetch(\"devices\").values.flatten; puts devices.find { |entry| entry[\"isAvailable\"] && entry[\"name\"].start_with?(\"iPhone\") }.fetch(\"udid\")')"
xcodebuild -project Xcode/DemoDeviceRunner/DemoDeviceRunner.xcodeproj -scheme DemoDeviceRunner -configuration Release -destination "platform=iOS Simulator,id=${IPHONE_UDID}" build CODE_SIGNING_ALLOWED=NO
APP_PATH="$(xcodebuild -project Xcode/DemoDeviceRunner/DemoDeviceRunner.xcodeproj -scheme DemoDeviceRunner -configuration Release -destination "platform=iOS Simulator,id=${IPHONE_UDID}" -showBuildSettings | ruby -e 'settings = STDIN.read; target = settings[/TARGET_BUILD_DIR = (.+)$/, 1]; product = settings[/FULL_PRODUCT_NAME = (.+)$/, 1]; abort \"missing build settings\" unless target && product; puts File.join(target.strip, product.strip)')"
xcrun simctl boot "${IPHONE_UDID}" || true
xcrun simctl bootstatus "${IPHONE_UDID}" -b
xcrun simctl install "${IPHONE_UDID}" "${APP_PATH}"
xcrun simctl launch "${IPHONE_UDID}" com.liang.pretextswift.demodevicerunner
```

Expected:

- the runner app installs from `~/Library/Developer/Xcode/DerivedData/DemoDeviceRunner-*/Build/Products/Release-iphonesimulator/Demo.app`
- launch succeeds for `com.liang.pretextswift.demodevicerunner`

Then run the touch smoke test on that same booted iPhone simulator and verify:

- only the primary touch drives the scene
- touch end/cancel clears pointer state
- the custom cursor hides on touch end/cancel
- resize or orientation change resets particles from the new layout without crashes

- [ ] **Step 6: Verify the font gate explicitly**

Confirm the active font mode with an explicit evidence source:

- inspect `FluidFontAssets.live.resolvedFontMode(size: 16)` once in the running process via LLDB, or temporarily log the same value and remove the diagnostic before final commit

Then confirm one of:

- exact bundled `L10-Medium` path is active
- deterministic `Helvetica Neue` fallback path is active because exact loading was proven impossible

If fallback is active, confirm the scene still satisfies motion and composition-class parity.

- [ ] **Step 7: Profile the named CPU scenario**

Measure with Instruments Core Animation FPS:

- hardware baseline: `MacBook Pro Mac16,5`
- chip: `Apple M4 Max`
- memory: `48 GB`
- window size: `1280x800`
- input pattern: continuous pointer sweep across the full canvas for `10` seconds

Expected:

- initial `>= 55 FPS`: accept
- initial `< 55 FPS`: perform exactly one bounded optimization pass in `Sources/Demo/Fluid/FluidView.swift`, `Sources/Demo/Fluid/FluidLayout.swift`, and/or `Sources/Demo/Fluid/FluidSimulation.swift`, then rerun the same measurement once
- rerun `>= 55 FPS`: accept
- rerun `50-54 FPS`: stop the execution thread and write a short CPU follow-up plan instead of continuing to tune indefinitely
- rerun `< 50 FPS`: stop and propose a Metal follow-up

Fallback rule if the named machine is unavailable:

- run the same Instruments method on any Apple Silicon Mac at `1280x800`
- treat that result as provisional local evidence only
- rerun the canonical `Mac16,5` measurement when that baseline machine becomes available

- [ ] **Step 8: Run the final targeted regression slice**

Run:

```bash
swift test --filter FluidLayoutTests
swift test --filter FluidSimulationTests
swift test --filter ContentViewTests
swift test --filter DemoWatchCatalogTests
```

Expected: all PASS

- [ ] **Step 9: If the user has approved commits in this repo, commit this task**

```bash
git add Sources/Demo/Fluid/FluidView.swift Sources/Demo/Fluid/FluidLayout.swift Sources/Demo/Fluid/FluidSimulation.swift Tests/DemoTests/FluidLayoutTests.swift Tests/DemoTests/FluidSimulationTests.swift Tests/DemoTests/ContentViewTests.swift Tests/DemoTests/DemoWatchCatalogTests.swift
git commit -m "feat: ship fluid web parity rewrite"
```

## Notes For Execution

- Do not preserve any `drawRuns` optimization that keeps words together; that is a parity regression, not an optimization.
- Do not add native glyph-rectangle collision, edge packing, or whole-glyph viewport clamping; those are parity regressions too.
- The exact-font path is the default shipping target. Fallback is allowed only after explicit failure to load or redistribute the pinned font asset.
- The shell integration is already present. Resist scope creep into unrelated demo navigation refactors.
- If the native path meets the behavior bar but misses the `55 FPS` target, finish the documented optimization pass before escalating renderer technology.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-01-fluid-web-parity.md`. Ready to execute?
