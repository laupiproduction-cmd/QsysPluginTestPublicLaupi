# Parametric EQ + RTA Visualizer — Build Notes

Status: **display/math layer built and tested; draggable-point interaction
not implemented; native control names/ranges unverified.**

## What's in this repo

- `ParametricEQVisualizer.lua` — the plugin: resolves PEQ/RTA Named
  Component references (pcall-wrapped, degrades to a "not connected" graph
  rather than erroring), draws gridlines + RTA spectrum fill + composite EQ
  curve + static band markers as one SVG pushed into a Button's Legend
  (`DrawChrome=false` + base64 `IconData`), driven entirely by
  EventHandlers — PEQ band changes redraw immediately, RTA updates are
  debounced through a `Timer` to `CONFIG.Graph.RedrawHz` (25 Hz by
  default). Each layer only recomputes when its own source data changed;
  the other layer's cached SVG is reused.
- `tests/test_eq_math_and_render.lua` — mocks `Component`/`Controls`/
  `Properties`/`Timer`/`rapidjson`/`Crypto` and covers: per-band-type
  magnitude math (Bell/LowShelf/HighShelf/HighPass/LowPass), composite
  summation, axis mapping, SVG element generation, the not-connected
  fallback, EventHandler wiring, and the RTA debounce (a burst of RTA
  control events produces no redraw until the debounce timer actually
  ticks, then exactly one). Run with `lua5.3 tests/test_eq_math_and_render.lua`
  from the repo root.

## What's NOT built, and why

**Draggable band-point interaction is not implemented.** Per your call:
rather than guess at a mechanism, everything else was built and band
points render as static markers. The spec is explicit that this needs
QSC's stock Positioner/PEQ plugin source inspected in Designer first — I
don't have Designer or access to QSC's shipped plugin files here, so
there was nothing to verify it against. To add it once you've checked:

1. Open QSC's stock Parametric EQ (or a plugin with a similar draggable
   curve, e.g. Positioner) in Designer's Plugin Builder / view its script,
   and see how it captures drag gestures on a custom graphic.
2. Two candidates the spec names, neither confirmed: (a) invisible
   Knob/Fader controls layered over the graphic per band, remapped from
   their native drag gesture to frequency/gain; (b) MouseDown/position
   control events, if the current Lua control API actually has them —
   don't assume it does.
3. Q adjustment needs its own path regardless (it isn't a point in
   frequency/gain space) — decide the UX (secondary drag gesture? a small
   per-band Q control?) once you know what the base drag mechanism even
   supports.
4. Wherever the mechanism lands, it should write back through the same
   `peqComponent[CONFIG.PEQ.BandControlName(i, param)]` controls the
   EventHandlers already read from — the redraw/cache path doesn't change.

## Everything CONFIG-gated — verify in Designer

Every assumption about the native components lives in the `CONFIG` table
at the top of the script, so fixing any of these is a data change, not a
rewrite:

| Field | Assumption made | Why unverified |
|---|---|---|
| `PEQ.BandControlName` | `"band<N>.freq"` / `.gain` / `.q` / `.type` | No live PEQ component to inspect its control names |
| `PEQ.HasTypeControl` | `true` | Spec's own open question — if the native PEQ has no per-band Type control, flip to `false` and every band renders as Bell |
| `PEQ.TypeValues` | Bell/LowShelf/HighShelf/HighPass/LowPass/Notch strings | Guessed to match the spec's assumed list; the real component's exact strings need confirming |
| `PEQ.FreqMin/Max`, `GainMin/Max`, `QMin/Max` | 20 Hz–20 kHz, ±24 dB, Q 0.1–10 | Used for axis bounds; the graph's dB range should match the real component's gain range or the curve will visually clip wrong |
| `RTA.Mode` | `"per_band"` | Spec's own open question: per-band controls vs. one array/blob control. Both code paths exist (`ReadRTAMagnitudes` branches on this flag) but only `per_band` has any test coverage |
| `RTA.PerBandControlName`, `NumPoints` | `"band<N>.magnitude"`, 31 points | No live RTA component to inspect |
| `RTA.OutputIsDB` | `true` | Spec's own open question — if the RTA outputs linear magnitude, this needs to flip to `false`; the conversion code path exists but is untested since it depends on the same unverified assumption |

There's a second, narrower assumption buried in `ReadRTAMagnitudes()`'s
per-band path: it assumes the per-band magnitude controls don't carry
their own frequency, and evenly spaces them in log-frequency across
`RTA.FreqMin`–`FreqMax` instead. If the real RTA's per-band controls do
carry a frequency (common for 1/3-octave style RTAs with non-uniform
band spacing), that placeholder needs replacing with real per-band
frequencies.

## Filter-response math — confidently correct, independent of Designer

Unlike the control-name/format questions above, the per-type magnitude
math doesn't depend on anything Q-SYS-specific and is unit tested:
continuous-domain approximations (not exact digital biquad evaluation,
which would also require knowing the audio sample rate — this plugin has
no way to query that) for Bell (constant-Q peaking), Low/High Shelf
(logistic transition), High/Low Pass (2-pole Butterworth-shaped
roll-off), and Notch (fixed-depth narrow cut). Bands combine correctly by
summing dB across the chain (log of a product of magnitudes = sum of
logs, which is how series-cascaded biquads actually combine). If exact
bit-for-bit matching to the native DSP's response is ever required
instead of a representative visual curve, that's a targeted swap of
`EQMath.BandMagnitudeDb` — nothing else in the file depends on the
specific math used there.

## Constraints honored

- All external component access is `pcall`-wrapped; a missing/misresolved
  PEQ or RTA reference renders a labeled "not connected" state rather than
  erroring (`TryResolveComponent` checks a probe control, not just that
  `Component.New` didn't error — so a wrong-type component degrades the
  same way a missing one does).
- No polling loop: the RTA debounce `Timer` only starts once the RTA
  reference actually resolves, and each tick is a no-op unless an RTA
  control fired since the last one.
- EQ curve recompute is skipped on RTA-only updates and vice versa
  (`cachedEQCurve/cachedRTACurve`), per the "avoid recomputing the full
  transfer-function curve unless a band actually changed" constraint.
- No filesystem/persistence — this plugin mirrors live component state
  only, nothing is saved.

## Suggested verification order in Designer

1. Confirm `PEQ.HasTypeControl` and the real band-type strings.
2. Confirm `PEQ.BandControlName` pattern and gain/freq/Q ranges.
3. Confirm `RTA.Mode`, its control-name pattern, point count, and whether
   output is already in dB.
4. Only then start the QSC-source investigation for the drag mechanism —
   there's no reason to block on it before the display half works.
