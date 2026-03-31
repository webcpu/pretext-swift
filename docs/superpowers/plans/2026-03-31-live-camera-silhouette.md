# Live Camera Silhouette Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new iOS demo tab where bundled article text continuously wraps around a live front-camera silhouette produced by Apple's Vision person segmentation.

**Architecture:** Build an iOS-only camera + Vision pipeline that emits a normalized silhouette occupancy map, convert that map into per-line blocked spans inside a stable reading page, and reuse `Pretext` to lay out article text around those spans in real time. Keep the camera/Vision pipeline isolated from the pure layout engine so the wrap math is unit-testable without hardware.

**Tech Stack:** Swift 6, SwiftUI, Pretext, AVFoundation, Vision, CoreVideo, XCTest, XcodeGen

---

## File Map

### Existing files to modify

- `Sources/Demo/ContentView.swift`
  Add the new tab case, title, compact title, symbol, and view routing.
- `Xcode/DemoDeviceRunner/project.yml`
  Add the iOS camera usage description so the device runner app can request camera access.
- `Tests/DemoTests/ContentViewTests.swift`
  Extend demo-tab coverage to include the new screen.

### New source files

- `Sources/Demo/CameraSilhouette/CameraSilhouetteView.swift`
  Main SwiftUI screen that composes permission state, camera preview, and wrapped article rendering.
- `Sources/Demo/CameraSilhouette/CameraSilhouetteCapture.swift`
  Front-camera session owner and preview-frame publisher.
- `Sources/Demo/CameraSilhouette/CameraSilhouetteSegmentation.swift`
  Vision person-segmentation pipeline plus normalized silhouette data model.
- `Sources/Demo/CameraSilhouette/CameraSilhouetteLayout.swift`
  Pure layout engine that maps silhouette occupancy into blocked spans and evaluates a `Pretext` snapshot.
- `Sources/Demo/CameraSilhouette/CameraSilhouettePreviewView.swift`
  iOS preview bridge for the live camera feed.

### New resources

- `Sources/Demo/Resources/camera-silhouette/article.txt`
  Bundled sample article content for the new tab.

### New tests

- `Tests/DemoTests/CameraSilhouetteLayoutTests.swift`
  Pure tests for blocked-span derivation, fallback layout, and representative silhouette geometry.
- `Tests/DemoTests/CameraSilhouetteViewTests.swift`
  State-focused tests for permission/no-person fallback decisions if a pure state helper is introduced. Skip this file if view-state logic stays trivial and is covered by layout tests plus runtime verification.

### Context files to read while executing

- `docs/superpowers/specs/2026-03-31-live-camera-silhouette-design.md`
- `Sources/Demo/IllustratedManuscript/IllustratedManuscriptLayout.swift`
- `Sources/Demo/IllustratedManuscript/IllustratedManuscriptView.swift`
- `Sources/Demo/PlatformSupport.swift`
- `Package.swift`

### Working-tree constraints

- The repo may already be dirty. Do not revert unrelated changes.
- This repo requires ask-first before commits. Commit steps below are conditional and must be skipped unless the user explicitly approves committing.

## Chunk 1: Demo Shell, Permissions, and Resources

### Task 1: Add the demo tab entry

**Files:**
- Modify: `Tests/DemoTests/ContentViewTests.swift`
- Modify: `Sources/Demo/ContentView.swift`

- [ ] **Step 1: Write the failing test**

Add a new expectation in `Tests/DemoTests/ContentViewTests.swift` so `DemoScreen.allCases.map(\.title)` includes `"Live Camera Silhouette"` in the intended order.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ContentViewTests`
Expected: FAIL because `DemoScreen` does not yet include the new case.

- [ ] **Step 3: Add the minimal demo-shell implementation**

Update `Sources/Demo/ContentView.swift`:

- add `case liveCameraSilhouette`
- add title, compact title, and `systemImage`
- route the new case to `CameraSilhouetteView()`

Suggested labels:

```swift
case .liveCameraSilhouette:
    "Live Camera Silhouette"
```

```swift
case .liveCameraSilhouette:
    "Camera"
```

```swift
case .liveCameraSilhouette:
    "person.crop.rectangle"
```

- [ ] **Step 4: Re-run the test to verify it passes**

Run: `swift test --filter ContentViewTests`
Expected: PASS

- [ ] **Step 5: If the user has approved commits in this repo, commit this chunk**

```bash
git add Tests/DemoTests/ContentViewTests.swift Sources/Demo/ContentView.swift
git commit -m "feat: add live camera silhouette demo tab"
```

### Task 2: Wire camera permission metadata and bundled article resource

**Files:**
- Modify: `Xcode/DemoDeviceRunner/project.yml`
- Create: `Sources/Demo/Resources/camera-silhouette/article.txt`
- Modify: `Package.swift` only if resource processing needs adjustment (expected: no change because `Sources/Demo/Resources` is already processed)

- [ ] **Step 1: Add the camera usage description**

In `Xcode/DemoDeviceRunner/project.yml`, add:

```yaml
INFOPLIST_KEY_NSCameraUsageDescription: Read your silhouette live so article text can wrap around you.
```

- [ ] **Step 2: Add the bundled sample article**

Create `Sources/Demo/Resources/camera-silhouette/article.txt` with the chosen sample article content. Keep it plain UTF-8 text and sized for a sustained reading demo.

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate --spec Xcode/DemoDeviceRunner/project.yml`
Expected: `DemoDeviceRunner.xcodeproj` regenerates with the camera usage description baked into the iOS runner target.

- [ ] **Step 4: Verify the runner still builds generically**

Run: `xcodebuild -project Xcode/DemoDeviceRunner/DemoDeviceRunner.xcodeproj -scheme DemoDeviceRunner -destination 'generic/platform=iOS' -configuration Release build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: If the user has approved commits in this repo, commit this chunk**

```bash
git add Xcode/DemoDeviceRunner/project.yml Sources/Demo/Resources/camera-silhouette/article.txt Xcode/DemoDeviceRunner/DemoDeviceRunner.xcodeproj
git commit -m "feat: add camera permission and sample article resources"
```

## Chunk 2: Pure Silhouette Layout Engine

### Task 3: Add blocked-span regression tests before implementing layout

**Files:**
- Create: `Tests/DemoTests/CameraSilhouetteLayoutTests.swift`
- Create: `Sources/Demo/CameraSilhouette/CameraSilhouetteLayout.swift`

- [ ] **Step 1: Write failing pure tests for silhouette geometry**

In `Tests/DemoTests/CameraSilhouetteLayoutTests.swift`, add tests for:

- no silhouette -> standard full-width layout
- centered silhouette band -> blocked span in the middle of the page
- off-edge silhouette -> clipping to page bounds
- multi-open-region band -> largest open region wins

Example skeleton:

```swift
func testBlockedSpansClipToPageBounds() {
    let spans = blockedSpans(
        occupancy: [.init(minX: -0.2, maxX: 0.35)],
        pageWidth: 300
    )

    XCTAssertEqual(spans, [ClosedRange(uncheckedBounds: (0, 105))])
}
```

- [ ] **Step 2: Run the failing layout test**

Run: `swift test --filter CameraSilhouetteLayoutTests`
Expected: FAIL because the layout file and helpers do not exist yet.

- [ ] **Step 3: Implement the minimal pure geometry layer**

Create `Sources/Demo/CameraSilhouette/CameraSilhouetteLayout.swift` with:

- normalized silhouette row model
- page metrics for the reading column
- blocked-span derivation helpers
- a pure snapshot type for laid-out lines

Use `Pretext` line-by-line layout rather than a custom line breaker.

- [ ] **Step 4: Re-run the layout test**

Run: `swift test --filter CameraSilhouetteLayoutTests`
Expected: PASS

- [ ] **Step 5: Expand tests for fallback and representative wrap behavior**

Add tests asserting:

- fallback layout is chosen when silhouette rows are empty
- lines after evaluation avoid blocked spans for a representative mask
- normalized-to-page coordinate mapping is stable across portrait and landscape-like page sizes

- [ ] **Step 6: Re-run the layout test slice**

Run: `swift test --filter CameraSilhouetteLayoutTests`
Expected: PASS with all new tests green

- [ ] **Step 7: If the user has approved commits in this repo, commit this chunk**

```bash
git add Tests/DemoTests/CameraSilhouetteLayoutTests.swift Sources/Demo/CameraSilhouette/CameraSilhouetteLayout.swift
git commit -m "feat: add camera silhouette layout engine"
```

## Chunk 3: Camera and Vision Pipeline

### Task 4: Build the front-camera capture component

**Files:**
- Create: `Sources/Demo/CameraSilhouette/CameraSilhouetteCapture.swift`
- Create: `Sources/Demo/CameraSilhouette/CameraSilhouettePreviewView.swift`

- [ ] **Step 1: Add the capture state types**

Define explicit capture states for:

- permission pending
- denied/restricted
- session unavailable
- running with live frames

- [ ] **Step 2: Implement the front-camera session owner**

`CameraSilhouetteCapture.swift` should:

- request permission
- choose the front camera
- configure `AVCaptureVideoDataOutput`
- publish frames for segmentation
- publish a preview-layer-backed session for live display

- [ ] **Step 3: Implement the preview bridge**

Create `CameraSilhouettePreviewView.swift` as the thin SwiftUI wrapper around the iOS camera preview layer. Keep this file view-only and free of layout logic.

- [ ] **Step 4: Verify the package test/build layer still compiles**

Run: `swift test --filter ContentViewTests`
Expected: PASS and compile success for the new camera files

- [ ] **Step 5: If the user has approved commits in this repo, commit this chunk**

```bash
git add Sources/Demo/CameraSilhouette/CameraSilhouetteCapture.swift Sources/Demo/CameraSilhouette/CameraSilhouettePreviewView.swift
git commit -m "feat: add live front camera capture pipeline"
```

### Task 5: Build the Vision segmentation component

**Files:**
- Create: `Sources/Demo/CameraSilhouette/CameraSilhouetteSegmentation.swift`
- Modify: `Tests/DemoTests/CameraSilhouetteLayoutTests.swift`

- [ ] **Step 1: Add a failing test for mask-to-row conversion**

Write a pure test around the mask-conversion helper using synthetic occupancy grids or synthetic normalized rows rather than live `CVPixelBuffer` fixtures.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CameraSilhouetteLayoutTests`
Expected: FAIL because the conversion helper does not yet exist.

- [ ] **Step 3: Implement the segmentation service**

`CameraSilhouetteSegmentation.swift` should:

- own `VNGeneratePersonSegmentationRequest`
- accept incoming video frames
- produce normalized silhouette rows or occupancy data
- expose a lightweight output struct consumed by `CameraSilhouetteLayout`

Keep Vision-specific code isolated here so layout tests remain pure.

- [ ] **Step 4: Re-run the layout test slice**

Run: `swift test --filter CameraSilhouetteLayoutTests`
Expected: PASS

- [ ] **Step 5: If the user has approved commits in this repo, commit this chunk**

```bash
git add Sources/Demo/CameraSilhouette/CameraSilhouetteSegmentation.swift Tests/DemoTests/CameraSilhouetteLayoutTests.swift
git commit -m "feat: add vision person segmentation pipeline"
```

## Chunk 4: Screen Composition and Runtime Verification

### Task 6: Compose the end-to-end SwiftUI screen

**Files:**
- Create: `Sources/Demo/CameraSilhouette/CameraSilhouetteView.swift`
- Modify: `Sources/Demo/ContentView.swift`
- Modify: `Sources/Demo/CameraSilhouette/CameraSilhouetteLayout.swift`

- [ ] **Step 1: Add the minimal screen shell**

Create `CameraSilhouetteView.swift` with:

- permission/error state handling
- camera preview layer
- bundled article loading
- live segmentation subscription
- overlay text rendering driven by `CameraSilhouetteLayout`

- [ ] **Step 2: Keep fallback behavior explicit**

When there is:

- no permission -> show CTA + ordinary article
- no person -> show camera + ordinary article
- active person -> show camera + live wrapped article

- [ ] **Step 3: Make the layout update path incremental**

Only re-evaluate the `Pretext` snapshot when a new segmentation result arrives or the viewport changes.

- [ ] **Step 4: Re-run the focused test slices**

Run:

```bash
swift test --filter ContentViewTests
swift test --filter CameraSilhouetteLayoutTests
```

Expected: both PASS

- [ ] **Step 5: Re-run the broader demo test target**

Run: `swift test --filter DemoTests`
Expected: PASS

- [ ] **Step 6: If the user has approved commits in this repo, commit this chunk**

```bash
git add Sources/Demo/CameraSilhouette Sources/Demo/ContentView.swift Tests/DemoTests
git commit -m "feat: add live camera silhouette article demo"
```

### Task 7: Device validation on physical iPhone

**Files:**
- No source changes expected unless a device-only bug appears

- [ ] **Step 1: Build the iOS runner**

Run:

```bash
xcodebuild -project Xcode/DemoDeviceRunner/DemoDeviceRunner.xcodeproj \
  -scheme DemoDeviceRunner \
  -destination 'generic/platform=iOS' \
  -configuration Release build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Find the physical iPhone destination**

Run: `xcrun xctrace list devices`
Expected: an online physical iPhone identifier is listed.

- [ ] **Step 3: Install the build on the physical iPhone**

Run:

```bash
xcrun devicectl device install app \
  --device <iphone-udid> \
  /Users/liang/Library/Developer/Xcode/DerivedData/DemoDeviceRunner-*/Build/Products/Release-iphoneos/Demo.app
```

Expected: install succeeds for `com.liang.pretextswift.demodevicerunner`

- [ ] **Step 4: Launch the app**

Run:

```bash
xcrun devicectl device process launch \
  --device <iphone-udid> \
  --terminate-existing \
  com.liang.pretextswift.demodevicerunner
```

Expected: launch succeeds

- [ ] **Step 5: Manually verify the live feature**

Check:

- the new tab is visible
- the camera permission prompt appears correctly
- front camera feed is visible behind the text
- text reflows around the body silhouette while moving
- switching away and back does not crash

- [ ] **Step 6: If the user has approved commits in this repo, commit any device-fix follow-up**

```bash
git add <files fixed during device validation>
git commit -m "fix: stabilize live camera silhouette demo on device"
```

## Chunk 5: Documentation and Closeout

### Task 8: Sync the design and implementation docs if execution changed scope

**Files:**
- Modify: `docs/superpowers/specs/2026-03-31-live-camera-silhouette-design.md` only if execution reveals a real scope or architecture change
- Modify: `docs/superpowers/plans/2026-03-31-live-camera-silhouette.md` as boxes are completed

- [ ] **Step 1: Reconcile any real scope changes**

If execution diverges from the spec in a meaningful way, update the spec and the plan so they match the shipped behavior. Do not add speculative future work.

- [ ] **Step 2: Capture final verification evidence**

Record the exact commands and results used for the final claim:

```bash
swift test --filter DemoTests
swift test --filter PretextTests
```

Expected: PASS

- [ ] **Step 3: If the user has approved commits in this repo, commit docs-only updates**

```bash
git add docs/superpowers/specs/2026-03-31-live-camera-silhouette-design.md docs/superpowers/plans/2026-03-31-live-camera-silhouette.md
git commit -m "docs: sync live camera silhouette spec and plan"
```
