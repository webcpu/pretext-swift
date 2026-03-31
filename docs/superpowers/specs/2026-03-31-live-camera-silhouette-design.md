# Live Camera Silhouette Article Design

## Summary

Add a new iOS-only demo tab where bundled article text continuously wraps around a user's live silhouette from the front-facing camera. The app uses Apple's Vision person segmentation to derive a moving exclusion shape, shows the live camera feed behind the article, and recomputes text layout in real time with the existing `Pretext` engine.

The intended effect is a reading surface that feels spatially aware rather than decorative: the article should genuinely reflow around the user's body as they move.

## Goals

- Add a new demo tab to the existing `Demo` app.
- Support iOS only.
- Use the front-facing camera by default.
- Show the live camera feed behind the article text.
- Use a bundled sample article for the first version.
- Continuously reflow text as the person moves.
- Use Apple's Vision framework for person segmentation.
- Reuse `Pretext` for true text layout around exclusion geometry rather than faking displacement.

## Non-Goals

- No macOS implementation.
- No user-supplied article import in v1.
- No still-capture workflow.
- No smoothing-first or freeze-first reading mode.
- No exact pixel contour typography around every mask edge.

## Product Behavior

### Primary Experience

The new tab opens to a full-screen reading canvas:

- live front-camera feed in the background
- article text layered above it
- a live exclusion region derived from the user's segmented silhouette
- continuous text reflow as the silhouette changes

### Fallback Behavior

- If camera permission is not granted, show a camera-permission CTA and render the article in standard layout.
- If the camera is unavailable or interrupted, show a nonfatal error state and fall back to standard layout.
- If Vision temporarily fails to detect a person, keep showing the camera feed and article, but use ordinary layout until a silhouette returns.

## Approaches Considered

### A. Live exclusion layout with Vision mask

Chosen.

- Camera frames feed Vision segmentation.
- Segmentation produces a live silhouette shape.
- `Pretext` lays text around blocked spans derived from that silhouette.

Why chosen:

- This is the only approach that actually satisfies "article text dynamically wraps around a user's live camera silhouette."
- It leverages the repo's strongest existing asset: custom layout infrastructure in `Pretext`.

### B. Stable line layout with local visual displacement

Rejected.

- Cheaper at runtime, but the text would not truly wrap.
- Would look like an effect layered on top of fixed layout.

### C. Snapshot silhouette with manual recapture

Rejected.

- Simpler, but directly conflicts with the requirement for continuous reflow.

## Architecture

Create a new iOS-only demo subsystem with four responsibilities.

### 1. Screen and Demo Integration

- Extend `DemoScreen` with a new case, title, compact title, and symbol.
- Route the new case from `ContentView` to a new `CameraSilhouetteView`.
- Keep the tab visible only on iOS if needed, but prefer a shared enum with an iOS-only destination guarded inside the view layer.

### 2. Camera Capture

`CameraSilhouetteCapture`

Responsibilities:

- own `AVCaptureSession`
- select the front-facing camera
- manage permission flow
- surface live preview frames
- surface a SwiftUI-compatible preview layer or image stream

Constraints:

- must be iOS-only
- must stay isolated from layout code
- should publish normalized video dimensions and orientation-aware transforms

### 3. Vision Segmentation

`CameraSilhouetteSegmentation`

Responsibilities:

- run `VNGeneratePersonSegmentationRequest` on incoming frames
- produce a low-resolution normalized person mask
- threshold the mask into a silhouette occupancy map
- emit shape data suitable for text exclusion

Output model:

- normalized mask dimensions
- silhouette bounds in normalized coordinates
- per-row occupancy samples or derived blocked spans

### 4. Article Layout + Rendering

`CameraSilhouetteLayout`

Responsibilities:

- map the normalized silhouette into page-space geometry
- convert live silhouette occupancy into blocked intervals for each text band
- run `Pretext` line-by-line layout against available spans
- produce a pure snapshot for rendering

`CameraSilhouetteView`

Responsibilities:

- compose camera preview, text overlay, permission/error states, and optional debug overlay
- update layout as segmentation frames arrive
- own the bundled article content and page metrics

## Geometry Model

The layout engine should not attempt to trace an exact vector contour each frame.

Instead:

1. Vision emits a segmentation mask in normalized coordinates.
2. The app maps that mask into the article page rect.
3. For each text band, it scans the silhouette occupancy and derives one or more blocked horizontal spans.
4. The line layout subtracts those spans from the available width.
5. If a band produces multiple open regions, v1 chooses the largest readable region for that line.

Why this model:

- It maps directly onto how `Pretext` already lays out lines.
- It avoids expensive contour extraction.
- It gives a visually correct wrap effect without overengineering the geometry.

## Layout Rules

- The article lives inside a stable reading page with margins.
- The silhouette only excludes text inside that page rect.
- The wrap shape should be clipped so it cannot shove text fully off-page.
- If the silhouette intersects too much of a band, the line moves below it rather than trying to create fragmented line pieces.
- If no silhouette exists, layout falls back to normal article flow.

## Rendering Model

Layer order:

1. live camera preview
2. subtle readability treatment if needed, such as a light veil or gradient
3. article text
4. optional debug silhouette overlay for development only

The text should remain readable over video, but the design should avoid hiding the camera feed entirely. The visual emphasis stays on live wrap behavior, not on decorative chrome.

## State Model

Suggested view state:

- `requestingPermission`
- `permissionDenied`
- `cameraUnavailable(message)`
- `runningNoPerson`
- `runningWithPerson(snapshot)`

This keeps user-facing state explicit and avoids mixing camera errors with layout failures.

## Performance Strategy

The user explicitly chose raw liveness over stability, so v1 should avoid heavy smoothing. The app should still avoid redundant work.

Practical rules:

- re-layout only when a new segmentation result arrives
- keep segmentation mask resolution modest
- derive blocked spans directly from occupancy rows
- avoid more than one layout recomputation per delivered segmentation frame
- keep rendering on the main actor, but move camera and Vision work off the main thread

## Platform Constraints

- iOS only
- front-facing camera only in v1
- requires camera usage description in app metadata
- physical-device verification required because simulator camera and Vision behavior are not representative

## Files and Modules

Planned new files:

- `Sources/Demo/CameraSilhouette/CameraSilhouetteView.swift`
- `Sources/Demo/CameraSilhouette/CameraSilhouetteCapture.swift`
- `Sources/Demo/CameraSilhouette/CameraSilhouetteSegmentation.swift`
- `Sources/Demo/CameraSilhouette/CameraSilhouetteLayout.swift`
- bundled article resource under `Sources/Demo/Resources/`

Likely touched existing files:

- `Sources/Demo/ContentView.swift`
- iOS app metadata / info plist handling in the Xcode runner if needed for camera permission
- tests covering demo tab integration

## Test Strategy

### Unit Tests

- new demo tab appears in `DemoScreen`
- silhouette occupancy converts into expected blocked spans for representative synthetic masks
- layout falls back to ordinary flow when no silhouette exists
- layout pushes lines away from blocked geometry
- page-space coordinate mapping from normalized Vision output is correct for representative aspect ratios

### Runtime Verification

- build and run on physical iPhone
- permission flow works from first launch and after deny/retry scenarios
- live front camera appears behind text
- text reflows continuously as the person moves
- switching between tabs does not leak camera sessions or crash

## Risks

### 1. Visual jitter

Expected to some degree because the chosen mode favors liveness over stability.

Mitigation:

- keep geometry coarse and band-based rather than pixel-precise
- avoid extra interpolation beyond one update per segmentation frame

### 2. CPU cost

Vision segmentation plus repeated layout can be expensive.

Mitigation:

- use modest mask resolution
- keep the article page width bounded
- derive spans efficiently

### 3. Camera/session lifecycle bugs

Switching tabs could leave capture active or restart incorrectly.

Mitigation:

- isolate camera ownership in one capture component
- explicitly start/stop with view lifecycle

## Open Questions

These can stay deferred for v1:

- whether to expose a developer debug overlay for the silhouette mask
- whether to tint or grade the camera feed for readability
- whether to add a manual pause/freeze mode later

## Recommendation

Proceed with an iOS-only implementation that:

- uses front camera capture
- runs Vision person segmentation continuously
- converts the live silhouette into per-band exclusion spans
- lays out a bundled article with `Pretext` around that live shape
- shows the camera feed behind the text

This is the smallest design that honestly delivers the requested behavior.
