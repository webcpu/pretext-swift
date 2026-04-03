# Pretext TS Parity Delta Design

## Summary

Update `pretext-swift` to match the meaningful TypeScript library changes that landed after the Swift port started on 2026-03-30. Keep scope narrow: focus on permanent engine behavior, exported library APIs, and durable invariant tests. Do not pull in unrelated demos, browser tooling, or packaging work.

## Goals

- Port the post-baseline TS library deltas that affect the Swift core engine or public API.
- Update the permanent Swift tests first so the missing behavior is stated explicitly before engine edits.
- Keep the diff small and maintainable.
- Preserve current Apple-platform constraints: iOS, macOS, and watchOS support for the Swift package targets that already exist.

## Non-Goals

- No attempt to mirror TS browser tooling, corpora automation, or demo pages.
- No dependency changes.
- No new broad abstraction layer over the current Swift engine.
- No `inline-flow` sidecar in this change unless the user explicitly expands scope later.

## Upstream Delta To Port

These TypeScript changes are the parity target for this update:

- `a9652fd` / `9364741`: rich-path `measureNaturalWidth(...)` helper is part of the public TS surface.
- `39b38e5`: rich line round-trip invariants.
- `2c52171`: binary search for chunk lookup in the line-break core.
- `f707bb2`: simple-path line-start normalization fix around `ZWSP`, collapsible spaces, and resumable streaming.

These are already present in Swift and are therefore out of scope for this delta:

- explicit locale control
- `pre-wrap` mode
- tabs and hard breaks in `pre-wrap`
- `layoutNextLine`
- `walkLineRanges`
- soft hyphen handling

## Approach Options

### A. Patch tests only

Rejected.

- Would document the missing behavior but knowingly leave the parity gap open.

### B. Patch tests plus the exact missing engine/API delta

Chosen.

- Smallest complete parity diff.
- Lets the tests drive the implementation.
- Avoids dragging in the new TS `inline-flow` subsystem.

### C. Full modern TS surface, including `inline-flow`

Deferred.

- Larger API design problem.
- Not required by the current parity request.

## Design

### 1. Tests First

Extend `Tests/PretextTests/CoreEngineTests.swift` so Swift permanently encodes the newer TS invariants:

- `layout`, `layoutWithLines`, and `layoutNextLine` stay aligned on `ZWSP`-driven breaks.
- `layoutWithLines` and `layoutNextLine` stay aligned when collapsible space follows a `ZWSP` break.
- `layoutNextLine` can resume from any line start without hidden state.
- variable-width `layoutNextLine` streaming remains contiguous and reconstructs the normalized source in both normal and `pre-wrap` modes.
- `measureNaturalWidth` returns the widest forced line for rich prepared text.

These tests should initially fail where Swift is behind TS, and pass where Swift already converged.

### 2. Public API

Add:

- `measureNaturalWidth(_ prepared: PreparedText) -> Double`

Implementation rule:

- reuse `walkLineRanges(..., maxWidth: .infinity)` rather than introducing a separate intrinsic-width walker.

### 3. Line-Break Core

Port the two upstream line-break improvements:

- replace the linear scan in `findChunkIndexForStart` with binary search
- normalize simple-path fresh line starts the same way the rich path does, skipping collapsible spaces, `zeroWidthBreak`, and `softHyphen` markers before placing content

### 4. Validation

Run the narrowest useful test target:

- `swift test --filter CoreEngineTests`

If a failure shows an existing Swift behavior intentionally differs from TS, stop and reassess before broadening the patch.

## Acceptance Criteria

- `CoreEngineTests` contains the new TS-derived invariants.
- The Swift library exports `measureNaturalWidth`.
- The new tests pass without regressing existing `CoreEngineTests`.
- The implementation remains small and centered in `Sources/Pretext/`.
