# UCI Parametric EQ Plugin — Build Notes

Status: **control-script layer built and tested; native audio schematic not
built** (requires Q-SYS Designer, which this environment doesn't have).

## What's in this repo

- `ParametricEQPlugin.lua` — the full Lua control script layer: 10-channel
  link-group ganging, named preset save/recall/delete with rapidjson
  persistence, reentrancy guards, `pcall`-wrapped JSON and cross-control
  writes. Defines its own `GetProperties`/`GetControls`/`GetControlLayout`
  so it loads and is testable as a standalone plugin right now, using stock
  Knob/ComboBox/Button/Text controls only.
- `tests/test_link_and_presets.lua` — mocks the Q-SYS `Controls`/`Properties`/
  `rapidjson` globals and exercises link propagation and preset recall
  end-to-end. Run with `lua5.3 tests/test_link_and_presets.lua` from the
  repo root.

## Resolved design decision

**Open Question #4** from the spec (does recalling a preset onto a linked
channel propagate to the group, or stay local?) is resolved: **recall stays
local**. `RecallPreset()` sets the `Propagating` guard while applying the
snapshot so the per-band `EventHandler`s don't gang it out to the rest of
the group. This is implemented and covered by the test.

## What's NOT built, and why

The spec's own architecture note (section 2) is correct: this plugin needs
actual audio-rate processing (parametric EQ filtering, FFT for RTA) that a
Lua control script cannot do. That part has to be built as a native
schematic in Q-SYS Designer and bundled into a `.qplug` via "Create Plugin
from Selected Components" (or the current Designer version's equivalent
workflow — confirm the exact menu path, spec Open Question #1). That's a
GUI workflow inside Designer; nothing here can substitute for it.

Consequently, several things in `ParametricEQPlugin.lua` are **placeholders
that assume a naming convention**, not verified facts:

| Open Question | Where it shows up in the script | What to do in Designer |
|---|---|---|
| #1 — plugin-from-schematic workflow | N/A, purely a Designer step | Confirm current menu path before laying out the schematic |
| #2 — max bands per native EQ block | `NumBands` property (default 10, range 6–16); `BAND_TYPES` list | Check the Parametric EQ block's Properties panel; if it caps below 10, cascade two blocks and set `NumBands` to match total |
| #3 — RTA per-band magnitude as Named Controls | Not implemented (see below) | Check the RTA block's control list in Designer |
| #5 — draggable EQ point editor | Not implemented; layout uses only stock ComboBox/Knob controls | Check QSC's stock EQ/Positioner plugin source for the Layout API pattern before attempting freeform draggable points |

The single seam to fix once the real schematic exists is
`EQControlName(channel, band, param)` in the runtime section — right now it
returns the plugin's own `Band_c_b_param` controls (which is why the script
is self-contained and testable today). Once the native EQ block's actual
control names are known, point that function at them (e.g. via
`Component.New(...)` if the blocks aren't merged into the same control
namespace) and the linking/preset logic above it needs no other changes.

## RTA overlay — deliberately not implemented

Spec section 4 recommends prototyping **Approach A** (native RTA graphic,
UCI toggle swaps which tap — pre/post — feeds it) first, since it's wired
entirely in Designer's routing/layout and needs no Lua. A `RTAShowPost_{c}`
toggle control exists in this script as a placeholder for that switch, but
wiring it to real pre/post tap routing is a Designer step.

**Approach B** (custom dual-trace overlay, pulled via Lua at 10–15 Hz) is
intentionally not attempted — it depends on Open Question #3 (RTA magnitude
exposed as Named Controls) and the same class of Layout-drawing uncertainty
as the draggable EQ point editor (#5). Don't build against assumptions here;
verify both in Designer first. If confirmed, add a single throttled
`Timer.New()` (10–15 Hz, matching spec section 8) — never per-channel
timers or polling loops.

## Verification checklist before continuing the build in Designer

1. Confirm current Designer workflow for "create plugin from schematic
   selection" (#1).
2. Open a native Parametric EQ block's Properties panel, note max band
   count; decide single-block vs. cascaded, set `NumBands` property to match
   (#2).
3. Confirm exact band-type enum in the block's Properties (Bell/Shelf/HP/LP/
   Notch/etc.) and update `BAND_TYPES` in the script if it differs (#2).
4. Open an RTA block's control list; check whether per-band magnitude is
   exposed as a readable Named Control (#3).
5. Check the Layout API's graphic primitives (or QSC's stock EQ/Positioner
   plugin source) for freeform curve/draggable-point support (#5).
6. Once the schematic exists and native control names are known, update
   `EQControlName()` and re-run `tests/test_link_and_presets.lua` against
   the change (adjust the test's mock `Controls` table to match if the
   naming convention changes).

## Out of scope (per spec section 10)

Distance attenuation/room acoustics, automatic feedback detection/notching.
