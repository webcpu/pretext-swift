# Fluid Web Parity Reference

This note captures the pinned reference artifacts and observed default-scene behavior for the `Fluid` parity rewrite.

## Pinned Site Snapshot

- Capture date: `2026-04-01`
- Live URL: `https://fluid.felixmartinez.dev`
- Next.js build ID: `wH6XWESEo7Qv-YQX2Z_vq`
- Layout bundle: `/_next/static/chunks/app/layout-bd19fd6873bab95e.js`
- Font asset endpoint: `https://fluid.felixmartinez.dev/assets/fonts/L10-Medium.woff`

## Phrase Corpus

Observed in the deployed layout bundle:

1. GPU shaders are like tiny wizards, casting millions of pixel spells per second!
2. Real-time ray tracing is basically teaching light how to play hide and seek in your GPU.
3. Vertex shaders are the cosmic sculptors of the 3D universe, shaping digital realities.
4. Fragment shaders are the pixel whisperers, convincing each dot to show its true colors.
5. Tessellation shaders are digital plasticians, giving flat polygons an extreme makeover.
6. Compute shaders turn your GPU into a math-crunching monster with an appetite for data.
7. Deferred rendering is like a procrastinator's dream - putting off the hard work until later!
8. PBR is the art of making virtual materials so real, you'll want to lick your screen.
9. Ambient occlusion is the shadow puppeteer of the rendering world, adding depth with a flick of the wrist.
10. Normal mapping is like giving your 3D models an instant facelift without the surgery.
11. Temporal anti-aliasing is a time-bending technique that smooths edges by peeking into the future.
12. Screen space reflections are mirror magic that works even when there's nothing to reflect!
13. Volumetric lighting lets you slice through god rays with your mouse cursor.
14. GPU instancing is cloning on steroids - copy-paste a million trees without breaking a sweat!
15. Shader permutations are like a choose-your-own-adventure book, but for your GPU.

## Observed Default Scene Rules

From the pinned bundle:

- desktop font size: `16`
- mobile font size: `12`
- `maxWidth = window.innerWidth`
- text align: `justify`
- phrase count rule: `Math.round(window.innerWidth / 512 * 25)`
- phrase assembly behavior:
  - shuffle corpus before first phrase
  - reshuffle again every full corpus cycle
  - append uppercase phrases with trailing spaces
- background color: `#000000`
- text color: `#ffffff`
- cursor color: `#ffd831`

## Observed Interaction Rules

- macOS/browser uses continuous pointer movement
- iOS/web uses touchmove and touchstart
- cursor rotates from pointer direction
- cursor scale reacts to pointer strength
- glyph field responds directionally and then settles

## Visual Acceptance Notes

The native parity target should visibly satisfy all of the following:

- full-viewport black stage
- dense justified text as the rest composition source, but not as the persistent visual read
- white uppercase glyphs that separate into a sparse particle field under interaction
- yellow directional cursor
- no debug or control panel in the native demo

## Required Parity States

Implementation review should compare the native scene against these three named states:

1. `idle`
   - no active pointer/touch input
   - glyphs rest in the stable composition
   - the scene must not read as a solid editorial paragraph block
2. `active-sweep`
   - pointer/touch is moving continuously across the scene
   - glyphs should separate directionally and show local fluid spread
3. `post-settle`
   - input has stopped long enough for the scene to calm
   - glyphs should visibly reconverge toward the stable composition instead of drifting indefinitely

## Native Determinism Policy

The web app randomizes phrase order per load. The native rewrite does not need to match the web app's exact phrase order on each run.

Instead, the native rewrite should:

- preserve the same corpus-cycle semantics
- use one fixed bundled shuffle seed
- produce deterministic rest layout for the same viewport and platform inputs

## Font Policy

The default shipping target is the exact site font, bundled locally for the native demo.

If that exact font cannot be redistributed or cannot be loaded in a Core Text-compatible local format, the only approved fallback is `Helvetica Neue`.
