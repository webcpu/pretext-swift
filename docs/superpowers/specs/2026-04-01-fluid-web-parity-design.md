# Fluid Web Parity Design

## Summary

Replace the current `Fluid` demo implementation with a parity-focused recreation of the default live scene at `fluid.felixmartinez.dev`. The macOS experience is the primary reference target. iOS uses the same scene model, adapted for touch and smaller typography.

This is a rewrite of the current `Fluid` scene, not a tuning pass. The existing implementation behaves like a justified editorial text block with a fluid offset effect. The target behavior is a sparse, pointer-reactive glyph field where each visible character can separate, drift, and settle independently.

## Goals

- Keep the `Fluid` tab in the existing demo shell.
- Match the default live scene and interaction of the web app as closely as practical in native Swift.
- Prioritize parity against the macOS/browser experience.
- Support iOS as a touch-adapted version of the same scene.
- Preserve the black background, white glyphs, and yellow cursor/accent.
- Reproduce the same phrase corpus and the same viewport-driven content density rule as the live site, with one intentional native startup guard for zero/tiny widths.
- Make the motion model feel like the web app: directional bursts, local shock-wave propagation, and eventual stillness without native-only packing behavior.

## Non-Goals

- No reproduction of the right-side debug or control panel.
- No alternate color palettes.
- No “close enough” editorial fallback that still reads as static wrapped text.
- No watchOS implementation.
- No immediate Metal rewrite unless the CPU parity version proves insufficient after profiling.

## Product Behavior

### Primary Experience

The `Fluid` tab opens into a full-viewport black scene with:

- white uppercase glyphs derived from the same phrase corpus as the web app
- a composition that starts from a justified text layout but quickly reads as a sparse glyph field
- a yellow directional cursor
- pointer-driven motion on macOS and touch-driven motion on iOS

The scene should come to rest when idle:

- glyphs rest in a stable composition
- moving the pointer creates directional disturbance and local fluid spread
- disturbed glyphs drift, separate, and eventually become still without a native-only spring snapping them back into paragraph density

### macOS Behavior

- Match the browser composition first.
- Hide the system cursor while the custom cursor is active over the scene.
- Use hover input continuously, without requiring a drag gesture.
- On hover exit or app/window deactivation, clear pointer state and restore the system cursor immediately.

### iOS Behavior

- Same scene model and phrase corpus.
- Smaller default font sizing.
- Touch interaction substitutes for hover.
- Cursor behavior is touch-adapted rather than pixel-identical to the browser cursor.
- The custom cursor is visible only while an active primary touch exists.

## Approaches Considered

### A. Keep the current `Pretext` line layout and tune the effect

Rejected.

- Lowest-diff path, but the current architecture is wrong for parity.
- The scene still reads as a dense paragraph because words are composed and moved in runs.
- This path optimizes the wrong mental model.

### B. Rebuild as a glyph-particle scene in SwiftUI `Canvas`

Chosen.

- Uses a justified text block only to generate each glyph's rest position.
- After layout, each glyph behaves as an individual particle.
- Keeps the code native, testable, and small enough to iterate.

### C. Rebuild in Metal immediately

Deferred.

- Best long-term performance ceiling.
- Too much complexity for the first parity rewrite.
- Only justified if the CPU implementation cannot hold acceptable frame rate after a faithful rewrite.

## Reference Behavior

The implementation should follow a pinned reference snapshot captured on `2026-04-01`, not an open-ended “whatever the site does later” target.

Pinned reference artifacts:

- live URL: `https://fluid.felixmartinez.dev`
- Next.js build ID captured from the HTML shell: `wH6XWESEo7Qv-YQX2Z_vq`
- deployed layout bundle captured from the HTML shell: `/_next/static/chunks/app/layout-bd19fd6873bab95e.js`
- deployed font asset endpoint: `https://fluid.felixmartinez.dev/assets/fonts/L10-Medium.woff`
- durable in-repo reference note: `docs/superpowers/specs/2026-04-01-fluid-web-parity-reference.md`

The implementation should follow the observable behavior of that pinned artifact set:

- same phrase corpus
- same phrase-count rule based on viewport width for normal visible viewports, with an intentional native clamp only for zero/tiny-width startup edge cases
- same desktop/mobile font-size split
- same black/white/yellow palette
- default scene only, without controls

Important implementation note:

- The site uses a particle simulation over glyphs, not a coarse text displacement effect.
- The native rewrite should therefore match the site at the behavior level rather than copy the current demo's editorial layout structure.

## Architecture

Create a new `Fluid` subsystem with three clear responsibilities.

### 1. `FluidLayout`

Responsibilities:

- own the phrase corpus
- assemble the full display string using the site's viewport-width rule
- choose the desktop/mobile typography defaults
- compute the initial justified composition
- emit a flat glyph array with per-glyph rest metrics

Output model:

- scene metrics
- full source text
- ordered glyph particles
- rest position and glyph measurement data for each visible character

Important boundary:

- `FluidLayout` computes only the deterministic rest composition.
- It does not own motion state.

### 2. `FluidSimulation`

Responsibilities:

- own particle positions and velocities
- own pointer state
- port the web app's pressure, density, and viscosity interaction model
- apply pointer-driven impulse and directional disturbance
- enforce damping and point-particle viewport bounds
- produce cursor state

Important boundary:

- `FluidSimulation` does not know how text is rendered.
- It consumes glyph rest data and produces frame-state transforms.
- It must not add native-only glyph-rectangle collision, edge packing, or whole-glyph viewport clamping.

### 3. `FluidView`

Responsibilities:

- bridge platform input into simulation pointer state
- run the frame loop
- relayout on viewport changes
- render each glyph individually in `Canvas`
- draw the custom cursor

Important boundary:

- `FluidView` should stay thin.
- It orchestrates layout and simulation, but the math lives outside the view body.
- It also owns the touch/hover translation policy:
  - macOS hover updates pointer continuously
  - macOS hover exit and app/window deactivation clear pointer state and restore the system cursor
  - iOS uses the primary touch only
  - additional concurrent touches are ignored
  - `touchCancelled` and `touchEnded` clear pointer state
  - the iOS custom cursor is shown only during an active primary touch

## Layout Model

The scene still begins from text layout, because the web app does not start from random positions.

Rules:

1. Build the source string from the site phrase list.
2. If `viewportWidth <= 0` or `viewportHeight <= 0`, return an empty layout snapshot with zero visible glyph particles and skip simulation until the viewport becomes positive.
3. Otherwise use the site's phrase-count rule, clamped for deterministic startup behavior:
   - `max(1, round(viewportWidth / 512 * 25))`
4. Match the site's corpus-cycle semantics:
   - shuffle the phrase corpus before the first phrase
   - reshuffle again at each full corpus cycle
   - append `phraseCount` phrases in uppercase with trailing spaces
5. Replace the site's non-deterministic `Math.random()` shuffle with a fixed native seed so tests and relayouts stay stable.
6. Use the site's desktop/mobile font sizing:
   - desktop/macOS: `16`
   - mobile/iOS: `12`
7. Use `Pretext` to compute justified line flow and rest positions.
8. Convert that rest layout into a flat visible-glyph particle list without re-trimming or re-justifying the line after `Pretext` has already decided the flow.
9. Treat spaces as layout guides and advance contributors, not visible particles.

Vertical clipping contract:

- layout produces glyphs only for lines whose glyph bounds intersect the viewport height
- partially visible glyphs at the top or bottom edge are included if their rest bounds intersect the viewport rect
- fully off-screen lines and fully off-screen glyphs are not emitted into simulation state
- this visible-only particle contract is required to keep particle count bounded and deterministic

Horizontal layout contract:

- macOS rest layout uses the full viewport width as its justification width
- iOS rest layout uses the full scene width as presented by the demo canvas
- no extra aesthetic horizontal padding is added in either case
- safe-area differences are not allowed to introduce editorial-style side margins into the rest composition

Deterministic native phrase-order contract:

- use one fixed bundled shuffle seed for the scene, exposed as a constant such as `FluidPhraseSeed.default`
- the same viewport and same platform metrics must produce the same phrase ordering and same rest layout on every run
- exact launch-to-launch phrase order parity with the web app is not an acceptance criterion because the web app randomizes on load
- corpus-cycle behavior parity is an acceptance criterion

Crucially:

- words and lines do not remain the render unit
- visible glyphs become the render and simulation unit
- `Pretext` owns line breaking and spacing; the simulation only owns particle motion

That is the core difference between parity and the current implementation.

## Interfaces And State Transitions

The rewrite should make immutable layout data and mutable simulation state separate types.

Required boundary:

- `FluidLayoutSnapshot`
  - immutable
  - scene metrics
  - source text
  - `[FluidGlyphLayout]`
- `FluidGlyphLayout`
  - immutable
  - glyph identifier
  - source character
  - rest position
  - baseline / width / bounds metrics
- `FluidSimulationState`
  - mutable
  - `[FluidParticleState]`
  - pointer state
  - cursor state inputs
- `FluidParticleState`
  - mutable
  - glyph identifier
  - current position
  - velocity

Contract:

- `FluidSimulationState` is keyed by glyph identifier and consumes `FluidLayoutSnapshot` as input
- layout types never store current position or velocity
- simulation types never own font measurement or line-breaking logic

Relayout/reset policy:

- any layout-affecting viewport change rebuilds `FluidLayoutSnapshot`
- rebuilding layout resets all particle positions to the new rest positions
- rebuilding layout zeroes particle velocities
- pointer state may be preserved only if it still lies inside the new viewport bounds; otherwise it is cleared
- this reset-on-relayout behavior is the required policy for resize, rotation, and platform typography changes

Why this policy:

- deterministic and easy to test
- avoids half-remapped particle state when line breaks change
- matches the fact that the browser composition is regenerated from the new viewport

`FluidSimulation` / `FluidView` handoff contract:

- `reset(from layout: FluidLayoutSnapshot)` replaces particle state from immutable rest layout
- `step(dt:pointer:layout:)` advances one simulation frame using the latest immutable layout snapshot
- `updatePointer(...)` applies pointer position, direction, and strength updates
- `clearPointer()` clears pointer state and returns cursor visibility to the inactive state

Required `FluidCursorState` contract:

- `isVisible`
- `center`
- `angle`
- `size`

Frame-timing policy:

- clamp simulation `dt` to the closed interval `[1/240, 1/20]`
- if app/window deactivation or a large frame gap causes `dt > 1/10`, clear pointer state before the next step and restart simulation timing from a nominal `1/60`
- resize and relayout already use the explicit reset policy above

## Simulation Model

The site uses a GPU particle simulation with pressure, density, and viscosity passes. The native rewrite should follow that model closely, while replacing only the web text-layout stage with `Pretext`.

Required parity rules:

- keep the web pass structure: positions, densities/forces, then velocities
- keep the web substep policy: `3` substeps per frame
- keep the web interaction constants unless measurement proves a native unit conversion is required:
  - `range = 14`
  - `pressureMultiplier = 10`
  - `viscosityFactor = 600.1`
  - `dampingFactor = 0.999`
  - `originalPositionFactor = 0`
- keep the web pointer smoothing and mouse-strength evolution model
- use point-particle viewport bounce/clamp, not glyph-rectangle bounce/clamp
- do not add pairwise rectangle overlap resolution
- do not add edge packing near viewport borders
- do not add synthetic ambient idle drift

The native backend may differ in implementation language and buffer types, but it must preserve the web solver's behavior:

- pointer impulse based on location, direction, and strength
- local density and pressure propagation
- local viscosity propagation
- damping so disturbed glyphs eventually become still
- point-center boundary handling so particles stay on-screen without rectangle compression

### Data Model

Each visible glyph layout record should carry:

- scalar identifier
- source character
- rest position
- width / baseline metrics for rendering

Each particle simulation record should carry:

- glyph identifier
- current position
- velocity

The simulation state should carry:

- particle array
- pointer position
- pointer direction
- pointer strength
- platform-adjusted cursor state

### Neighbor Search

Do not use all-pairs interaction.

Use a uniform spatial grid:

- assign glyphs into cells each frame
- evaluate forces only against nearby cells
- keep the interaction radius local

Why:

- preserves performance with thousands of glyphs
- gives a clear future path to a Metal backend if needed

## Rendering Model

Render each visible glyph independently in `Canvas`.

Requirements:

- correct Core Graphics text transform so glyphs are upright
- no word-level draw grouping that keeps words locked together
- black background
- white glyphs
- yellow custom cursor

The scene should visually open up under interaction:

- glyphs separate enough to read as a particle field
- motion decays into a still post-interaction arrangement instead of being forcibly repacked into the original paragraph

The custom cursor should be directional and motion-reactive, but it should remain subordinate to the glyph behavior. The scene's parity comes from how the text reacts, not from cursor ornament.

## Typography And Assets

Typography affects parity materially.

The site uses a specific web font asset: `assets/fonts/L10-Medium.woff`.

Preferred plan:

- bundle the same font in the native demo, sourced from the pinned asset endpoint
- the default shipping target is the exact site font, stored under `Sources/Demo/Resources/Fluid/`
- `FluidFontAssets.swift` is the integration point responsible for loading and exposing the font to layout/render code

Fallback plan:

- if bundling the site font is blocked, use `Helvetica Neue` as the explicit deterministic fallback on both macOS and iOS
- tests should treat `Helvetica Neue` as the only allowed fallback, not “closest available”
- the fallback path is only valid if exact-font bundling fails because of proven redistribution or Core Text loading constraints discovered during implementation

Explicit font decision gate:

- `FluidFontAssets.swift` must expose the chosen font mode as either `exact` or `fallback`
- the exact-font path is the default shipping target
- the fallback path is allowed only after an explicit loadability or redistribution failure is confirmed during implementation

Important caveat:

- if the exact font is not used, motion may match while composition still differs visibly

Acceptance rule when fallback is active:

- motion, interaction, phrase assembly, and general composition class must still match the pinned browser reference
- exact glyph metrics and exact line-break parity are no longer required

This fallback is acceptable only if the exact asset cannot be bundled.

## Platform Rules

### macOS

- primary parity target
- hover drives interaction continuously
- custom cursor hides the system cursor while active
- hover exit and app/window deactivation clear pointer state and unhide the system cursor

### iOS

- same glyph field and simulation model
- touch updates pointer state
- smaller default type
- scene remains full-screen and touch-reactive
- only the primary touch drives the scene
- the custom cursor is visible only during active touch and disappears on touch end/cancel

### watchOS

- excluded

## Files And Modules

Likely touched existing files:

- `Sources/Demo/ContentView.swift`
- `Tests/DemoTests/ContentViewTests.swift`
- `Tests/DemoTests/DemoWatchCatalogTests.swift`

Expected rewritten files:

- `Sources/Demo/Fluid/FluidLayout.swift`
- `Sources/Demo/Fluid/FluidSimulation.swift`
- `Sources/Demo/Fluid/FluidView.swift`

Required support file:

- `Sources/Demo/Fluid/FluidFontAssets.swift`

Expected tests:

- `Tests/DemoTests/FluidLayoutTests.swift`
- `Tests/DemoTests/FluidSimulationTests.swift`

## Acceptance Criteria

The rewrite is successful only if the resulting scene satisfies these conditions:

- demo-shell contract is preserved:
  - `DemoScreen.rawValue == "fluid"`
  - title: `Fluid`
  - compact title: `Fluid`
  - order: after `Live Camera Silhouette`, before `Benchmark`
  - excluded from `watchOS`
- macOS no longer reads as a dense paragraph block
- glyphs are upright
- glyphs move independently rather than by whole-word runs
- interaction produces visible directional bursts and local fluid spread
- the scene becomes still eventually without synthetic idle drift
- runtime parity comes from the web-style point-particle solver rather than a native rectangle correction layer
- the default browser scene is the obvious visual reference
- iOS remains recognizably the same demo, adapted for touch
- parity is checked against the three named states in `docs/superpowers/specs/2026-04-01-fluid-web-parity-reference.md`:
  - `idle`
  - `active-sweep`
  - `post-settle`
- the native implementation holds at least `55 FPS` average in the named profiling scenario:
  - hardware baseline: `MacBook Pro Mac16,5`
  - chip: `Apple M4 Max`
  - memory: `48 GB`
  - window size: `1280x800`
  - measurement method: Instruments Core Animation FPS while moving the pointer continuously across the full canvas for `10` seconds
- if the result lands in the `50-54 FPS` range, the work is not done yet and requires another CPU optimization pass plus remeasurement before the feature is considered complete

Fallback profiling rule:

- if the named `Mac16,5` baseline machine is unavailable, use the same Instruments method on any Apple Silicon Mac at the same window size and keep the result as a provisional local gate
- the `Mac16,5` measurement remains the canonical parity-performance check when that baseline is accessible

## Test Strategy

### Unit Tests

- phrase-count rule matches the clamped site formula
- zero-size viewport returns an empty layout snapshot and no visible glyph particles
- deterministic corpus shuffling matches the native fixed-seed contract
- layout produces deterministic glyph counts and rest positions
- spaces affect layout but are not emitted as visible particles
- `Pretext` remains the source of truth for line flow and spacing
- desktop/mobile typography rules are applied correctly
- relayout resets simulation particles to new rest positions and zero velocity
- a displaced particle does not spring back toward rest when pointer input is absent
- idle simulation becomes still eventually without synthetic ambient drift
- pointer impulse changes glyph velocity near the pointer
- the solver uses the web-style multi-pass force model with `3` substeps
- boundary handling keeps particle centers inside the viewport
- no native glyph-rectangle overlap or edge-packing pass is required for normal interaction

### Runtime Verification

- `Fluid` tab appears in the correct place in the demo shell
- macOS scene launches and reacts to hover
- system cursor hides and restores correctly on macOS
- macOS hover exit and app/window deactivation clear pointer state and restore the system cursor
- iOS scene reacts to touch without crashes or major frame collapse
- iOS touch end/cancel clears pointer state and hides the custom cursor
- resizing the macOS window triggers relayout cleanly
- the visual feel is checked against the pinned in-repo reference note, not against the previous native implementation
- the three named parity states are reviewed explicitly: `idle`, `active-sweep`, `post-settle`
- exact-font mode or deterministic fallback mode is confirmed explicitly during verification
- large-frame-gap reset behavior is checked by app/window deactivation and reactivation
- the named macOS profiling scenario is measured and compared against the `55 FPS` acceptance bar

## Risks

### 1. Performance regression

The current speed fix depends on word-level draw grouping. Real parity requires per-glyph rendering again.

Mitigation:

- use a uniform spatial grid for local simulation
- keep the view orchestration thin
- cache glyph drawing inputs carefully
- profile after parity behavior is restored

### 2. Font mismatch

If the site font cannot be bundled, composition will still differ.

Mitigation:

- prioritize bundling the exact font asset if feasible
- treat font substitution as a last-resort compromise and call it out explicitly

### 3. Underpowered simulation

A partial imitation of the web solver, or any extra native correction layer, will still look wrong even if glyphs are per-character.

Mitigation:

- keep the web pass structure and constants visible in code and tests
- validate visually against the site, not only through unit tests
- reject native-only rectangle corrections unless the web bundle shows an equivalent behavior

### 4. Scope drift into native-only fixups

It is easy to keep adding collision, clamp, or packing patches when parity is off.

Mitigation:

- treat the deployed web bundle as the source of truth
- prefer deleting native-only correction code over tuning it
- keep `Pretext` scoped to rest layout only

## Open Decisions Already Resolved

- Match only the default live scene: yes
- Reproduce the control/debug panel: no
- Primary parity reference: macOS/browser
- iOS target: touch-adapted version of the same scene

## Implementation Direction

The next step is an implementation plan for a parity rewrite, not incremental edits to the current approximation.

That plan should:

- replace run-based rendering with per-glyph rendering
- use `Pretext` only for rest layout generation
- replace native rectangle correction with the web-style point-particle simulation
- preserve the existing demo-shell integration
- treat parity against the pinned reference bundle as the shipping bar
