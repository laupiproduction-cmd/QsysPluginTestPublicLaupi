# VBAP 3D Panner — Q-SYS Plugin

A Q-SYS Designer plugin implementing Vector-Base Amplitude Panning (VBAP) in
full 3D for live show use. Supports up to **20 speakers** and **15 sound
sources**. Extends the concept of QSC's stock 2D Positioner/Panner into a
full 3D object-based panner.

The plugin file is [`VBAP3DPanner.qplug`](./VBAP3DPanner.qplug) — a single
plain-text Lua file, the standard format for a Q-SYS plugin's control script.

## How it works

The plugin never touches audio directly. It computes a gain per
(source × speaker) crosspoint from geometry, at control rate, and writes
those gains into a Matrix Mixer's Named Controls. All the VBAP/triangulation
math runs on a throttled Lua `Timer`, never in the audio path — this is what
keeps CPU load low enough for a live show with many moving sources.

1. **Setup phase** (speaker layout edit time only): speaker positions are
   triangulated into a set of triangles covering the sphere around the room
   origin (standard VBAP convex-hull triangulation), and each triangle's
   3×3 basis matrix is inverted and cached.
2. **Runtime phase** (source position change only, throttled): a source
   direction is matched to its active triangle (checking the previously
   active triangle and its neighbors first — sources move continuously, so
   this is nearly always an O(1) lookup instead of a full scan), gains are
   solved via the cached inverse, normalized for constant power, blended
   with a wider DBAP-style vector if Spread > 0, and converted to dB before
   being written to the mixer.

## Loading the plugin into Q-SYS Designer

`VBAP3DPanner.qplug` is plain Lua source, in the same format used by
community Q-SYS plugins. In Designer: **Schematic → Manage Plugins → Build
new plugin**, paste (or open) the contents of `VBAP3DPanner.qplug` into the
Plugin Builder's code editor, then **Save As** — Designer will save it as a
`.qplug` file you can drag onto a design like any other component.

## Properties (design-time)

| Property | Range | Purpose |
|---|---|---|
| `NumSources` | 1–15 | How many sources this instance needs. Sizes the embedded mixer and all source-related controls — a 3-source show doesn't pay for 15. |
| `NumSpeakers` | 1–20 | How many speakers this instance needs. Same sizing logic. |
| `Units` | Feet / Meters | Cosmetic label only (shown in the Room Setup header); does not rescale existing X/Y/Z values if changed. |
| `MixerMode` | Internal (Embedded) / External (Named Component) | See [Mixer wiring](#mixer-wiring) below. |
| `ExternalMixerName` | string | Named Component to reference when `MixerMode` is External. Hidden when Internal. |
| `UpdateRateHz` | 10–30 | Shared Timer rate driving path automation and gain recomputation. |
| `MaxWaypoints` | 2–16 | Path-automation waypoint slots reserved **per source**. |
| `RoomExtent` | 5–200 | ± range (in `Units`) for every X/Y/Z position control and the top-down canvas. |

Changing `NumSources`, `NumSpeakers`, or `MaxWaypoints` resizes the control
set and (for `NumSources`/`NumSpeakers` in Internal mode) the embedded
Matrix Mixer — this is a Designer property change, so it reloads the plugin
instance like any other property edit.

## Mixer wiring

**Internal (Embedded)** — default. The plugin declares its own Matrix Mixer
component (`GetComponents`/`GetWiring`), sized to exactly
`NumSources × NumSpeakers` (never a fixed 15×20 regardless of the show).
Plugin pins `Source N In` and `Speaker N Out` appear on the plugin's block
in the schematic; wire your source and speaker feeds directly to those pins.

**External (Named Component)** — for shows where the Matrix Mixer already
exists in the design (e.g. shared with other processing, or you want the
mixer visible/editable as its own schematic block). Place a native Matrix
Mixer, name it, wire its inputs/outputs by hand exactly as you would
normally, then set `MixerMode = External` and `ExternalMixerName` to that
component's name. The plugin does no audio routing in this mode — it only
writes crosspoint gains via `Component.New(ExternalMixerName)`.

Either way, crosspoint gains are addressed with the Matrix Mixer's standard
Named Control convention: `input.<source>.output.<speaker>.gain` (dB).

## Runtime controls (per source / per speaker)

- **Speakers**: Name, X/Y/Z position (draggable on the shared top-down pad
  on the *Room Setup* page, or typed numerically), Trim (dB).
- **Sources**: Name, X/Y/Z position, Level (dB), Mute, Spread (0–100%),
  Automation Mode (Path / External), Live Override, external X/Y/Z inputs
  (for OSC/MIDI/show-control), path transport (Play/Stop/Loop), and a
  waypoint grid (X/Y/Z/time-to-next/eased/active) per `MaxWaypoints` slot.
- **Global**: triangulation status/diagnostics, a manual "recompute
  triangulation" trigger.

**Transport semantics**: `Stop` pauses (holds position and path time); it
does not reset to waypoint 1. `Play` resumes from wherever it paused, or
starts fresh from waypoint 1 if the path had never been played. This avoids
position jumps and matches the spec's "resume from current path time"
requirement for Live Override release.

**Live Override**: while engaged, a source's position is driven entirely by
its `SourceExternalX/Y/Z` controls, regardless of Automation Mode. On
release, the plugin crossfades from the last external position back to the
Path/manual position over 300 ms rather than snapping, avoiding a zipper
artifact.

## Expected performance / update-rate behavior

- Triangulation (the only O(n³)-ish step) runs **only** when a speaker
  X/Y/Z control changes, debounced 250 ms so a drag doesn't retrigger it on
  every intermediate frame — never during normal show playback.
- Per-source gain recomputation runs on a single shared `Timer` at
  `UpdateRateHz` (default 20 Hz), and only for sources that actually moved,
  are mid-path, mid-crossfade, or under Live Override since the last tick —
  not on every control write.
- With 20 speakers, worst-case triangulation is a few dozen triangles;
  finding a source's active triangle is a coherence-cached lookup, not a
  full scan, so 15 simultaneously-moving sources at 20–30 Hz is cheap
  control-rate Lua work with no audio-path impact.

## Out of scope (matches the original spec)

Doppler/pitch-shift, automatic distance-based attenuation (use Level trim
or external automation), and any reverb/room acoustic modeling — this
plugin is panning only.

## API verification notes

This plugin was written against real, working example Q-SYS plugin source
(fetched from public community repositories) rather than against the
official Developer Reference pages, which were unreachable from the
environment this was built in (`help.qsys.com` / `q-syshelp.qsc.com` were
both blocked by network egress policy while writing this). Specifically
confirmed against real source before use:

- `PluginInfo`, `GetProperties`, `GetControls`, `GetControlLayout`,
  `GetPins`, `GetComponents`, `GetWiring` field names and shapes.
- The embedded-mixer pattern (`GetComponents` with `Type = "mixer"`,
  `Properties = { n_inputs=, n_outputs= }`), and that an embedded named
  component is reachable at runtime as a plain global table by its
  `Name`.
- The crosspoint gain Named Control convention:
  `input.<n>.output.<m>.gain`, accessed by indexing a component reference
  with that string, e.g. `mixerRef["input.1.output.1.gain"].Value`.
- `Component.New(name)` for referencing an externally-placed named
  component; `Timer.New()` / `:Start(seconds)` / `:Stop()` /
  `.EventHandler` for the shared throttled update loop; `GetPages` +
  `props["page_index"]` for the tabbed Room Setup / Source Control / Global
  Settings layout.

**Not independently confirmable given the above:** Q-SYS's stock 2D
Positioner/Panner is a native (non-Lua) component, so its exact drag-widget
implementation isn't inspectable from a plugin at all, regardless of docs
access. This plugin instead builds its draggable top-down pad from a
confirmed building block — `Style = "Fader"` on a Knob control — using two
overlapping Faders (X and Y) per point sharing one canvas rectangle, each
speaker/source rendered as its own distinctly-colored handle. Precise
numeric X/Y/Z entry is always available alongside it as the authoritative
fallback. If you have access to Designer and the official docs, it's worth
double-checking this against the `GetControlLayout`/`Style` reference and
adjusting if a more direct 2D-pad mechanism exists.

## Testing performed

The VBAP core math (triangulation, coherence search, spread blend, dB
conversion) and the full runtime control flow (triangulation rebuild,
debounced speaker edits, dirty-flag-gated gain updates, path automation
timing/looping, Live Override + crossfade, mute, Internal/External mixer
resolution) were verified with standalone Lua test harnesses against a
mocked Q-SYS `Controls`/`Properties`/`Timer`/`Component` runtime — including
full-sphere coverage sampling against an icosahedron-based speaker rig,
degenerate coplanar-ring and singular-triple inputs, and duplicate-triangle
collapsing for coplanar hull faces (e.g. a perfectly rectangular speaker
wall). This was **not** tested inside an actual Q-SYS Designer/Core, since
neither was available in the environment this was built in — validate in
Designer before a live show.
