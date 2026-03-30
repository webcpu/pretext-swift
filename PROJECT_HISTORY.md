# Project History

This file is the short internal history of the Swift port: what shipped, where the project stands now, and the decisions that mattered.

## What This Repo Is

Pretext Swift is a native Swift port of [Pretext](https://github.com/chenglou/pretext), Cheng Lou's text layout engine.

It currently ships as three SwiftPM targets:
- `Pretext`: reusable text measurement and layout library
- `Demo`: macOS demo app with editorial and benchmark screens
- `Benchmark`: standalone benchmark app with GUI and CLI modes

The core model is unchanged from the original project:
- `prepare(...)` does the expensive work once
- `layout(...)` and `layoutNextLine(...)` reuse cached widths and stay arithmetic-only

## Current State

- The demo app has three screens: `Situational Awareness`, `Editorial Engine`, and `Benchmark`.
- The benchmark UI is shared between the demo app and the standalone benchmark app through a shared support target.
- `rake demo` now launches the demo in release mode by default.
- The benchmark screen auto-runs only the first time it appears in an app session. After that, users rerun it manually with `Run Again`.

## Performance Outcome

The big arc of the project was getting the Swift port from "correct but much slower than Core Text" to "faster than Core Text on the bundled benchmark."

The meaningful wins were:
- moving benchmarking to release builds
- restoring a true plain-text fast path in `TextAnalysis`
- removing unnecessary prepare/build overhead from simple `prepare(...)`
- keeping richer segmentation only for the cases that actually need it

Current local benchmark results are in the low-`4.x ms` range for the 500-text batch prepare+layout benchmark, versus about `28.x ms` for Core Text.

## Important Technical Decisions

- Text analysis keeps a direct scalar fast path for ordinary western text and bails out to the richer pipeline only for cases that need it.
- Plain `prepare(...)` avoids the richer dual-view prepared-layout machinery when the direct path is sufficient.
- The benchmark UI lives in shared code so the demo and benchmark app do not drift.
- Benchmark auto-run policy is session-scoped and main-actor isolated.

## Lessons Worth Keeping

- Benchmark Swift in release mode, not debug mode.
- Profile before optimizing. The useful fixes came from profiling, not guessing.
- Keep the hot path simple. Most regressions came from making the common case serve rare edge cases.
- Do not "fix" tests by weakening semantics. The parity work only held once the actual root causes were addressed.

## If You Update This File

Keep it short.
Use it for project history and current-state notes, not as a duplicate of `README.md` or `CLAUDE.md`.
