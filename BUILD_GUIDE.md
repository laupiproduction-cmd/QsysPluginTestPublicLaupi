# Simple Parametric EQ Plugin — Build Guide

Single channel. Parametric EQ with its own visible curve. RTA before and
after. No presets, no link groups, no multi-channel logic.

## Why there's no Lua script here

Q-SYS's native Parametric EQ block already has its own built-in interactive
curve display (draggable points, drawn response), and the native RTA block
already has its own built-in spectrum graphic. Neither needs custom Lua
drawing to show up — you place the block's own graphic in the plugin
layout. Scripting was only load-bearing in the old 10-channel design for
link-group ganging and preset save/recall, both of which are gone now. This
version is pure native-block assembly in Designer; there is no code to
write or maintain.

(Caveat: this is based on standard Q-SYS Designer behavior; the exact block
names/menu wording can shift slightly between Designer versions, so
sanity-check step 1 against your installed version before you start.)

## Build steps (in Q-SYS Designer)

1. **Place three native blocks** in a Schematic view:
   - `RTA` (analyzer, pre-tap)
   - `Parametric EQ` (check its Properties panel for max band count; if it
     caps below what you want, cascade two EQ blocks in series instead of
     one — everything else below still applies)
   - `RTA` (analyzer, post-tap)

2. **Wire the signal path:**
   - `Input → Parametric EQ input`
   - Also branch `Input → RTA (pre) input` (Q-SYS lets one output pin feed
     multiple destinations — this is the "before" tap, not an insert)
   - `Parametric EQ output → Output`
   - Also branch `Parametric EQ output → RTA (post) input` (the "after" tap)

3. **Select all the blocks** (both RTAs + the EQ, or + cascade EQ if used) →
   right-click → **Create Plugin from Selected Components** (confirm the
   exact wording in your Designer version — this has been renamed across
   releases).

4. **In the Plugin Builder's Layout editor**, drag each block's own graphic
   onto the plugin's layout canvas:
   - The Parametric EQ's curve display (this is the "showing the EQ curve"
     requirement — it's the block's native graphic, draggable points and
     all)
   - The pre-tap RTA's spectrum display, labeled "Before"
   - The post-tap RTA's spectrum display, labeled "After"

   Arrange side by side or stacked — whichever reads best at the size
   you'll actually use on a UCI page.

5. **Save as a `.qplug`.**

## Dragging it into your UCI

Once the plugin is placed as a component in your design:

- To drop the **whole panel** (curve + both RTAs, laid out exactly as you
  built it) onto a UCI page as one unit: drag the component directly from
  the Schematic view onto the UCI page canvas.
- To add **individual controls** instead (e.g. just the curve, without the
  RTAs): select the component, open its **Controls** list in the right-hand
  panel, and drag individual entries onto the UCI page one at a time.

Either way is a native Designer drag-and-drop action — nothing extra is
needed in the plugin itself for this to work, as long as the Layout from
step 4 is reasonably laid out.

## Out of scope (dropped from the earlier design)

Multi-channel strips, link groups/ganging, named presets, JSON persistence.
If you want any of those back later, they're a control-script addition on
top of this same schematic — say the word and they can be layered back in.
