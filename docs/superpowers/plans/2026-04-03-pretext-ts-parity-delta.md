# Pretext TS Parity Delta Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update `pretext-swift` to match the post-2026-03-30 TypeScript library delta by adding the missing tests first, then the smallest engine/API changes needed to make them pass.

**Architecture:** Keep the current Swift engine structure. Patch only the permanent test suite, `LayoutAPI.swift`, and `LineBreaker.swift`. Reuse the existing line walkers and prepared-text model instead of adding new abstraction layers or sidecar targets.

**Tech Stack:** Swift 6, XCTest, CoreText, Swift Package Manager

---

## Chunk 1: Encode the TS Delta in Tests

### Task 1: Add the missing permanent invariants to `CoreEngineTests`

**Files:**
- Modify: `Tests/PretextTests/CoreEngineTests.swift`

- [ ] **Step 1: Add failing tests for the missing TS parity behaviors**

Add tests for:

- `measureNaturalWidth` on hard-break-separated content
- `layout` and `layoutWithLines` alignment on `ZWSP` narrow widths
- `layoutWithLines` and `layoutNextLine` alignment after `ZWSP` plus collapsible space
- resumable `layoutNextLine` from any fixed-width line start
- variable-width contiguous streaming in normal mode
- variable-width contiguous streaming in `pre-wrap` mode

- [ ] **Step 2: Run the focused test target and confirm the failures**

Run: `swift test --filter CoreEngineTests`
Expected: FAIL because `measureNaturalWidth` is not exported yet, and because the simple-path line walker may still disagree with the richer APIs on the new invariants.

## Chunk 2: Port the Matching Swift Engine Delta

### Task 2: Add the intrinsic-width helper and line-break fixes

**Files:**
- Modify: `Sources/Pretext/LayoutAPI.swift`
- Modify: `Sources/Pretext/LineBreaker.swift`

- [ ] **Step 1: Add `measureNaturalWidth` using the existing line-range walker**

Implementation:

- compute the widest line by calling `walkLineRanges(prepared, maxWidth: .infinity, ...)`
- return `0` for empty prepared text

- [ ] **Step 2: Port the simple-path line-start normalization fix**

Implementation:

- add a helper equivalent to TS `normalizeSimpleLineStartSegmentIndex`
- use it at fresh line starts in the simple walker so leading `.space`, `.zeroWidthBreak`, and `.softHyphen` markers do not become hidden state discrepancies

- [ ] **Step 3: Replace linear chunk lookup with binary search**

Implementation:

- update `findChunkIndexForStart` in `LineBreaker.swift`
- keep existing semantics unchanged except for lookup cost

- [ ] **Step 4: Re-run the focused tests**

Run: `swift test --filter CoreEngineTests`
Expected: PASS

## Chunk 3: Final Validation

### Task 3: Verify the narrow change set

**Files:**
- Modify if needed: `README.md`

- [ ] **Step 1: Update README API surface if needed**

Document `measureNaturalWidth` if the README is meant to mirror the exported Swift API.

- [ ] **Step 2: Re-run the focused target after any doc-adjacent compile changes**

Run: `swift test --filter CoreEngineTests`
Expected: PASS

- [ ] **Step 3: Summarize what was intentionally left out**

Call out that `inline-flow` remains out of scope for this parity delta.
