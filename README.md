# Show Control ~ Cue Engine

A single-file Q-SYS plugin (`ShowCueEngine.qplug`) that acts as a live-show
cue engine: up to 30 operator-programmable cues, each firing a numbered,
reorderable sequence of actions — triggering Media/Stream Players, sending
UDP messages to networked devices, setting/triggering any Named Control on
any in-house component, optionally pausing the rest of the sequence with a
`wait` action, and invoking freely-defined, reusable **Action Groups** (a
"Mute All" or "Gain Reset" you build once and call from as many cues as
you like).

Written for Q-SYS Designer 9.x, Lua 5.3, using only documented Q-SYS Lua
extensions (`UdpSocket`, `Component`, `Controls`, `Timer`, `rapidjson`,
`Ping`).

## Install

1. In Q-SYS Designer, open **File > Plugins... > Build New Plugin from
   Lua Script**, or simply copy `ShowCueEngine.qplug` into your project's
   `Plugins` folder (or `%UserProfile%\Documents\QSC\Q-Sys Designer\Plugins`)
   and it will appear in the Schematic Library / Components panel as
   **Show Control ~ CueEngine**.
2. Drag it onto the design canvas.
3. Set its Properties (see below) to size the show, then wire up cues.

The component has five pages (visible as tabs at the top of its
properties/control panel in Designer):

- **Live Show** — the compact operator view: show/lock strip, status bar,
  GO / STOP ALL / **E-STOP** / **CLEAR E-STOP** / RESET transport, large
  Current/Next Cue Notes ("cue words") views, the quick-fire cue grid, and
  a live activity log. Sized to fit comfortably on one screen (~920px
  wide).
- **Devices** — a curated list of Q-SYS components ("Devices") and UDP
  targets. This is the only place the full, raw list of every component in
  your design is shown; everywhere else (the Show Editor's/Action Groups'/
  Timecode Show's action Target dropdown) only sees the friendly names you
  define here. Keeps the editor from being flooded with every gain block
  and router in the design.
- **Action Groups** — pick **one** reusable group from a dropdown and edit
  its actions (same Type/Target/Control/Value/Move Up/Down/Remove editor as
  a cue's own actions, in its own bank of controls). Build a "Mute All" or
  "Gain Reset" once here, then invoke it from any cue (or TC cue) — or
  another group — with a `group` action. See "Reusable Action Groups" below.
- **Show Editor** — pick **one** cue from a dropdown and edit it: name,
  color, armed, confirm-before-fire, notes, and its actions. Actions are
  revealed one at a time with **+ Add Action** (and removed with each row's
  **X** button) instead of always showing every action slot for every cue —
  so a 30-cue show with a handful of actions per cue doesn't fill the screen
  with 100+ mostly-empty rows.
- **Timecode Show** — a SECOND, independent show, driven by timecode
  instead of GO/the cue grid, sharing the same Devices and Action Groups as
  the Live Show. Reads a real Q-SYS SMPTE LTC Reader component directly —
  there is no internal software clock, and no drop-frame support — see
  "Timecode Show" below.

Paging is purely a Designer-canvas display choice — every control behaves
identically regardless of which page it's shown on. All five pages share
one color palette (blue accent, green/amber/red for success/warning/danger)
with card-style grouped sections and section headings.

## Properties

| Property | Purpose | Default | Range |
|---|---|---|---|
| **Max Cues** | Size of the cue grid | 30 | 1–30 |
| **Max Actions Per Cue** | Max actions any single cue (or Action Group) can have | 4 | 1–25 |
| **Max Devices** | Size of the curated component list (Devices page) | 12 | 0–24 |
| **Max Action Groups** | Number of reusable Action Groups | 8 | 0–24 |
| **UDP Targets** | Number of configurable UDP devices | 6 | 0–12 |
| **Show Debug** | Show the Lua debug window; also gates `print()` mirroring of errors/cue-fire log lines | false | — |
| **Max TC Cues** | Size of the Timecode Show's cue list | 16 | 0–30 |

The logo (top-right of every page) is **not** a Property — it's baked
directly into the script; see "Branding and optional logo" below.

Changing any of these **resizes the control set** (`GetControls` declares a
static, fixed-size set of controls sized only from these Properties — the
control count never changes at runtime). Note the control count doesn't
scale with `Max Cues x Max Actions Per Cue` — there is one shared bank of
`Max Actions Per Cue` action-editor controls that gets repointed at whichever
cue is selected, not one per cue. A default configuration (30 cues, 4
actions, 12 devices, 6 UDP targets) is ~130 controls; even at the maximum
(30/25/24/12) it's ~305, versus ~590 in the original per-cue-grid design.

**Max Actions Per Cue goes up to 25.** There's no dedicated "scrollable
list" widget in the Q-SYS Lua layout API — a component whose canvas is
taller than the visible pane just scrolls natively inside Designer's
Properties/Schematic panel, the same way this page already behaved before.
Setting this Property well above the default makes the Cue Editor card tall
enough that you'll be scrolling to reach the lower action rows, which is
expected, not a bug.

## Setting up Devices (do this first)

On the **Devices** page, each row picks:

- **Friendly Name** — what you'll select in the Show Editor's Target
  dropdown (e.g. `House Player`, `Lobby Display`).
- **Q-SYS Component** — a dropdown of every named component in the design
  (from `Component.GetComponents()`), i.e. the *real* component to bind to.

Only components added here show up as Targets for `player_trigger` /
`named_control_set` actions in the Show Editor — this is the curated list
the brief asked for, so the action editor isn't a dropdown of every audio
gain block and router in the building.

UDP targets (Name/IP/Port) live on this same page for the same reason —
they're setup, not something an operator edits mid-show.

## Programming a cue

On the **Show Editor** page:

1. Pick a cue from **Select Cue**.
2. Edit **Rename Cue**, **Color** (`#RRGGBB`, used for the cue button's idle
   color), **Arm**, **Confirm** (require a double-press within 2s before
   firing — for destructive cues), and **Notes** (run-sheet text, never
   fired).
3. Press **+ Add Action** to reveal an action row (up to **Max Actions Per
   Cue**); press a row's **X** to remove it (later rows shift down to fill
   the gap). Each row is numbered (its firing order) and has **^ / v** Move
   Up/Down buttons — see "Ordered, movable actions" below. Each visible row
   has:
   - **Type**: `none` / `player_trigger` / `udp_send` / `named_control_set` /
     `wait` / `group`
   - **Target**: a Device name (for `player_trigger` / `named_control_set`),
     a UDP target name (for `udp_send`), or an Action Group name (for
     `group`) — dropdown populated from the **Devices** page or the
     **Action Groups** page respectively, never the raw design.
   - **Control**: the Named Control on that device to act on
     (`player_trigger` / `named_control_set` only). Auto-suggested from the
     live component's own controls via `Component.GetControls()`; always
     editable as plain text too, since control names differ by
     component/Player type (see "Assumptions" below).
   - **Value**: **auto-adjusts to the selected control's type.** Once a
     `named_control_set` action has a Control picked, the plugin looks up
     that control's real type (via the same `Component.GetControls()` call)
     and swaps the editor accordingly: a **TRUE/FALSE toggle** for Boolean
     controls (mute, power, etc. — writes `.Boolean` directly), **hidden
     entirely** for Trigger-type controls (nothing to set, only fire), or
     the free-text field for everything else (Float/Integer/Text/Position),
     using `V:<number>` (sets `.Value`), `P:<number>` (sets `.Position`,
     0–1), or `S:<text>` (sets `.String`). If the control's type can't be
     determined (unresolved target, lookup failure, etc.) it falls back to
     the free-text field, `T` / empty for either meaning "just `:Trigger()`
     it". For `udp_send`, Value is always the free-text field — the **raw
     ASCII payload** sent byte-for-byte (see "Assumptions"). For `wait`,
     Value is the free-text field too — a plain number of **seconds**
     (e.g. `2.5`); an empty or non-numeric value is treated as 0 (no delay).

Switching **Select Cue** doesn't lose anything — every field writes straight
into that cue's stored data as you edit it, and the editor bank just gets
repointed to show whichever cue is currently selected.

### Ordered, movable actions — and `wait`

A cue's actions fire **in order** — row 1, then row 2, and so on; the
numbered row position *is* the firing order, and export/import preserve it
exactly. Use each row's **^** / **v** buttons to reorder without deleting
and re-adding (both grey out at the ends: row 1 can't move up, the last row
can't move down).

Without any `wait` actions, a cue's rows still dispatch back-to-back as
fast as Lua can loop through them — effectively simultaneous, same as
before. The **`wait`** action type changes that on purpose: it pauses
*everything after it* in that cue for its Value (seconds), while
everything *before* it has already fired by the time it's reached. Put a
`wait` between two actions to space them out — e.g. trigger a video, `wait`
8 seconds for it to finish, then bring the house lights up.

A cue with a pending `wait` shows the **Firing** (amber) color for its
entire duration, not just a brief flash, and won't become the new **Active**
cue (see below) until every action — including everything after the last
`wait` — has actually dispatched. Firing the *same* cue again while its own
`wait` is still pending is ignored (it's still mid-sequence); firing a
*different* cue in the meantime works normally, since each cue's wait state
is independent. **E-STOP**, **STOP ALL**, and **RESET** all cancel any cue
currently mid-`wait` — its queued remaining actions never fire, and it's
logged as `CANCELLED` in the Activity Log — so a delayed action can never
sneak out after you've told the show to stop or start over.

### Reusable Action Groups

For anything you find yourself repeating across cues — a "Gain Reset", a
"Mute All", a standard house-lights-down sequence — build it **once** on
the **Action Groups** page and invoke it from any cue with a `group`
action (Target = the group's name). A group is edited with the exact same
Type/Target/Control/Value/Move Up/Down/Remove tools as a cue's own actions
(including `wait`), just in its own bank of controls, so editing a group
never touches or shares controls with any cue.

Groups are freely reusable — the same group can be called from as many
cues as you like, and calling it doesn't "use it up" or affect other cues
using it. Groups can even call **other** groups (a "Full Reset" group that
itself invokes "Gain Reset" and "Mute All"), which is expanded recursively
in firing order right where the `group` action sits — including any
`wait`s inside the nested group.

The one thing this can't do safely is reference itself, directly or
indirectly (group A calling group A, or A calling B calling A) — that's
caught at fire time (not import/save time, since the cycle only matters
once something actually tries to run it) and reported as a specific
"circular action group reference" error on the cue that triggered it,
rather than hanging or crashing. A `group` action naming a group that
doesn't exist (typo, or the group was renamed) fails the same clear way —
"action group not found" — without touching anything else in the cue.

### Clearing and resetting

Every place you can build up a list of actions also has a matching pair of
**Clear** buttons — one for what's currently selected, one for everything
at once:

- **Show Editor, Cue Editor card**: **CLEAR ACTIONS** wipes the *selected*
  cue's actions only (name, color, notes, armed/confirm, and condition are
  untouched). **CLEAR ALL ACTIONS** does the same for **every** cue at
  once.
- **Action Groups page, Group Editor card**: **CLEAR ACTIONS** /
  **CLEAR ALL ACTIONS** — identical pair, for the selected group / every
  group.
- **Devices page**: each device row has its own **CLEAR** button (resets
  just that Friendly Name + Q-SYS Component, one click, no confirmation —
  as low-risk as removing a single action row). **CLEAR ALL DEVICES**
  resets every device row at once.
- **Devices page, UDP Targets card**: same pair for UDP targets — each
  row's own **CLEAR** button (resets Name/IP/Port, one click, no
  confirmation) and **CLEAR ALL UDP TARGETS** for every row at once.

Anything that clears **more than one thing at once** requires **pressing
the button twice within 2 seconds** (the same confirm pattern as a cue's
own Confirm Before Fire) — the first press changes its label to ask for
confirmation and reverts on its own if you don't press again in time, so a
single accidental click can never wipe a bank of actions.

**CLEAR ALL** (Show Editor page, Global Settings card) is the big one: two
presses wipes the **entire authored show** — every cue, device, action
group, UDP target, and Timecode Show cue, back to blank defaults — and logs
it in the Activity Log. This is **not the same thing as RESET** (Live Show
page): RESET only rewinds *playback position* (which cue is active/played,
Current/Next) and never touches what you've authored; CLEAR ALL only
touches what you've authored and never touches playback position (though
in practice there's nothing meaningful left to play after a full clear).
Use RESET to restart a show you've built; use CLEAR ALL to start building a
new one from scratch without deleting and re-adding the plugin.

### Optional fire conditions

Every cue can optionally require a condition to be met before it's allowed
to fire — e.g. "only fire if this Block Controller's enable toggle is
pressed" (or *not* pressed). This is entirely **off by default and never
required** — a cue with **Condition** left off fires exactly as before,
with zero extra configuration.

- **Per-cue condition** (Show Editor page, in the Cue Editor card): flip
  **Condition** on for the currently selected cue, then pick a **Target**
  (a Device from the Devices page) and **Control** (auto-suggested from
  that device's real controls, same as an action's Control field), and
  **Must be ON / Must be OFF** for the state it needs to be in. A cue with
  an active condition shows a small `*` after its name on the Live Show
  grid, so you can tell at a glance which cues are gated.
- **Global Condition** (Show Editor page, in the Global Settings card):
  the same Target/Control/Required shape, but applies to **every** cue in
  addition to whatever per-cue condition (if any) that cue also has. Also
  off by default. Useful for a single "show is live" / "rehearsal lockout"
  toggle that should gate the whole show at once, rather than configuring
  the same condition on every cue individually.

Conditions are checked **live**, right when a cue is pressed (via the cue
grid or **GO**) — they read the referenced control's actual current
`.Boolean` state at that moment, not a cached or stored value. A cue
blocked by a condition doesn't fire any of its actions, doesn't count
toward the 150ms debounce, and logs as `BLOCKED` (not `OK`/`ERROR`) with
the specific reason shown in the status bar's error field. **E-STOP** and
**STOP ALL** always bypass conditions entirely, same as they bypass the
normal cue path — they're an emergency override by design. While **E-STOP**
is engaged, no cue can fire at all (GO or the grid) — see "E-Stop (Emergency
Stop)" below.

**GO** (Live Show page) fires the "next cue" shown in the status bar and
advances it. **STOP ALL** triggers the control named in **Player Stop
Control Name** (Show Editor page, default `stop`) on every component
referenced anywhere in the show, and cancels any cue mid-`wait`. **E-STOP**
does the same and, if **E-Stop UDP Payload** is non-empty, sends that
payload to every configured UDP target — bypassing the normal cue path
entirely, and clears the grid's active/played coloring (but does **not**
rewind the show position — it's a halt-in-place, not a restart; use
**RESET** for that). Unlike the old momentary Panic button, **E-STOP now
latches** — see the next section.

### One active cue, played cues greyed out

At any moment there is only ever **one** active cue on the Live Show grid —
the last cue to *successfully* fire — shown in a distinct highlight color.
The moment a different cue fires successfully, the previous active cue
drops back to a greyed-out **played** color, so a glance at the grid always
shows exactly where the show is and what's already happened:

- **Idle** (never fired, or its own custom **Color**) — not yet played.
- **Armed** (blue) — armed and not yet played.
- **Active** (green) — the current cue; there's only ever one.
- **Played** (grey) — was active, now superseded by a later cue.
- **Error** (red) — the last attempt to fire this cue failed; see **Error
  Text** in the status bar for the specific reason.
- **Firing** (amber) — a brief flash while a cue's actions are dispatching.

A cue whose fire **fails** never becomes the active cue and never advances
**Next Cue** — the show stays sitting on whichever cue last succeeded, so
GO/retry re-targets the same failed cue instead of silently skipping past
it. Conditions (see above) work the same way: a cue blocked by a condition
doesn't touch the active cue either.

**RESET** (Live Show page, next to E-STOP) rewinds *playback position only* —
every cue's active/played/error coloring clears back to idle/armed, Current
Cue and Next Cue reset to "none" / cue 1, and the status bar goes back to
"No cue fired yet". It does **not** touch anything you've authored (cue
names, notes, actions, devices, UDP targets) — it's a "start the show over"
button, not an "erase the show" button. The reset is marked in the
Activity Log so it's visible in the show's history rather than silently
disappearing.

### Current / Next Cue Notes

Two large text views on the Live Show page show the **Notes** field (the
same one you type into on the Show Editor page) for the current cue and
the next one — put your cue words / call notes there and read them
straight off the Live Show page while running the show. Like the rest of
the "current cue" concept, these always reflect the last cue to
*successfully* fire, not a failed attempt, and update live if you edit a
cue's notes while it happens to be the current or next cue.

### E-Stop (Emergency Stop)

The old momentary **PANIC** button is now **E-STOP**, a latching Toggle
control that also exposes a **schematic input pin** (visible on the
component's block in the design canvas) so it can be driven by something
outside the plugin entirely — a hardware E-stop relay wired through a
digital I/O card, another block's logic, a global "kill" signal, etc.

- **Engaging**: E-STOP going `true` — from the UI button *or* the input
  pin, it's the same code path either way — immediately triggers **Player
  Stop Control Name** on every referenced component, sends **E-Stop UDP
  Payload** (if set) to every configured UDP target, cancels any cue
  mid-`wait`, and clears the grid's active/played coloring. The status bar
  shows **Error** with an "E-STOP engaged" message until cleared.
- **Clearing**: only the separate **CLEAR E-STOP** button can release it.
  Flipping the E-STOP control back to `false` any other way — clicking it
  again in the UI, or the input pin dropping — is **rejected**: the plugin
  immediately forces it back to `true` and logs that it's latched. This is
  deliberate, matching how a physical E-stop button/relay behaves — it
  can't be un-pressed by accident, only explicitly cleared.
- **While engaged**, no cue can fire — GO and every cue-grid button are
  blocked and log `E-STOP` in the Activity Log, until CLEAR E-STOP is
  pressed. STOP ALL and RESET still work while E-STOP is engaged (they
  don't fire anything).
- **On boot**, the latch itself is **not** persisted (a fresh boot always
  starts un-latched, like a physical E-stop relay resetting with power) —
  but if the input pin is already being held `true` at boot (e.g. a
  hard-wired E-stop upstream), the plugin honors it immediately rather than
  silently ignoring it.

### Branding and optional logo

Every page carries a styled **title bar** at the top: the page name on the
left ("SHOW CUE ENGINE ~ Live Show" etc.) inside a bordered, accent-outlined
bar, with the small **"CUE SYSTEM BY LAUPI PRODUCTION"** branding line on
the right on the Live Show page specifically. The component's `PluginInfo`
(shown in Designer's schematic library, e.g. right-click → Properties)
carries `Author = "LAUPI PRODUCTION"`.

The **logo** renders as a small square image beside the title bar, top-right
corner of every page, bottom-aligned with the bar and matching its 16px
padding to both the page top and the page's right edge. It's **LAUPI
PRODUCTION's logo, baked directly into the plugin script** as a `local
LOGO_BASE64 = "..."` constant near the top of `ShowCueEngine.qplug` —
**not a Property**, so it doesn't appear in Designer's Properties panel at
all; nothing to configure, nothing an integrator can see or accidentally
edit there, it's just always there. The graphics `Type` ("Svg" vs raster
"Image") is auto-detected from the base64 content itself (PNG and JPEG
files always base64-encode to a fixed, recognizable prefix).

The shipped logo is a white mark on a transparent background (a solid
white "P" with thin outline strokes), which reads clearly against this
plugin's dark page background by design.

To replace or remove the logo, edit the `LOGO_BASE64` constant directly in
the script (raw base64 — SVG XML or a PNG/JPEG file's bytes, no
`data:image/...;base64,` prefix; empty string `""` = no logo). This is a
**design-time-only** feature either way: Q-SYS plugin graphics (the card
backgrounds, borders, and this logo image) are baked in once when Designer
runs `GetControlLayout(props)` — there is no documented Lua API for a
running plugin to redraw its own graphics — so the logo was never
something an operator could swap live during a performance; it's now also
not something exposed for a builder to swap from Designer's UI without
touching the script.

### Colors and theming

The plugin uses **one fixed dark theme** — there is no Light Mode, no Dark
Mode toggle, and no "Dark Background" Property. Every card, button, status
color, and text color in the whole plugin is sourced from a single `Theme`
table near the top of `ShowCueEngine.qplug`; to restyle the plugin, edit
the RGB triplets there.

An earlier build had a runtime **DARK MODE** button plus a separate
design-time **Dark Background** Property (two different mechanisms, since
Q-SYS Controls can be recolored live but plugin *graphics* — the page
background, card borders, and card headings — can only be redrawn when
`GetControlLayout(props)` runs at design time, never at runtime). That
whole toggle system has been **removed** in favor of a single theme that's
always applied, since running two visual states in sync across ~300
controls added complexity without a corresponding need. Any show exported
by an older build that still carries a `darkMode` field imports fine — the
field is simply ignored.

**Text boxes and plain text fields** (Cue Log, TC Cue Log, Current/Next Cue
Notes, Export/Import JSON, the current-cue/Ready/Next Cue/Error status
fields, Show Name/Last Modified, and every Device/UDP Target field on the
Devices page) are a special case: Q-SYS's `Text`/`TextBox` control styles
have **no background-fill property at all** — `Fill` only exists on
card/page `GroupBox` graphics. So each of these is given `TextBoxStyle =
"NoBackground"` where applicable (makes a TextBox transparent) plus its own
small themed rectangle drawn behind it at the identical position — the
same mechanism `card()` uses for its own background, not a new technique.

For most of these fields (status/show-strip text, every Device/UDP Target
field, TC transport fields), the *text* color is set the same proven way
every button's color already is: a `Color = {r,g,b}` entry directly in the
layout table `GetControlLayout` returns (`Theme.Text`, a light near-white),
right alongside its background rectangle (`Theme.TextBoxBg`, dark). This
works because these are all **`Style = "Text"`** fields.

**Six fields are different: Cue Log, TC Cue Log, Current/Next Cue Notes,
and Export/Import JSON are `Style = "TextBox"`**, not `"Text"` (they need
to support scrolling/selecting/pasting, which plain `Text` doesn't). For
`TextBox` specifically, `Color` has been confirmed **twice**, independently,
not to affect the actual rendered text in real Designer: an earlier build
tried setting it at *runtime* (`Controls.X.Color = ...` in `Init()`) —
confirmed not to work; a later build moved to *design-time* `Color` in the
layout table instead (the exact mechanism that works for every button and
every `Style = "Text"` field) — **also confirmed not to work**, this time
by the user directly, who reported these six boxes as the only remaining
black-on-dark text in the plugin. Q-SYS appears to render a `TextBox`'s
text in a fixed color regardless of either mechanism, and this plugin has
no further lever to pull on that front.

Rather than keep fighting a property that provably does nothing, these six
fields' background rectangles use `Theme.TextBoxBgOnLight` (a light,
near-white fill) instead of the normal dark `Theme.TextBoxBg` — deliberately
different from the rest of the dark-themed plugin, so that whatever fixed
color Q-SYS actually draws the text in (almost certainly dark, matching the
report) reads clearly against it. They carry no `Color` field at all, since
one demonstrably does nothing here and an untested future Designer version
honoring it against a now-light background would risk the opposite failure
(light-on-light). This is a deliberate design choice working *with* a
confirmed platform constraint, not an oversight.

Every card's heading (e.g. "SHOW", "STATUS", "CUES (tap to fire)") is drawn
as its **own `Text` graphic** with an explicit `Theme.Text` color,
positioned over the card, rather than using the card's `GroupBox`'s
built-in heading text — a `GroupBox` heading's text color isn't exposed by
the documented layout API, so it can't reliably be forced light against a
dark card fill. This was the most likely cause of the "header text not
visible" report against the previous dark-card design; it's now fixed the
same way every other piece of text in this plugin is colored. As with all
graphics in this plugin, this hasn't been pixel-verified against real
Designer — check it there before a live show.

## Testing UDP sending

1. On the **Devices** page, fill in one of the **UDP Targets** rows: Name,
   IP, Port.
2. On the **Show Editor** page, set an action's Type to `udp_send`, Target
   to that target's Name, and Value to the payload you want to send (plain
   ASCII, e.g. `PLAY`).
3. Fire that cue and confirm the target device receives the packet (a
   packet capture on the Core's network interface, e.g. Wireshark filtering
   on `udp.port == <port>`, is the most reliable way to verify this without
   depending on the receiving device).
4. If the device sends anything back to the same socket, its last reply is
   shown (throttled to ~10 updates/sec) in that target's **Status** field
   on the Devices page.

## Persistence — verify on real hardware before a live show

The full show (cues, actions, devices, UDP targets) is serialized to JSON
into a hidden control (`ShowData`) every time you edit anything, and
reloaded from it on plugin init. **This is not the same as surviving a Core
reboot.**

Q-SYS only persists a running Core's live control values across a reboot if
you have used Designer's **Save to Core** (or otherwise deployed/saved the
design with that data baked in) — there is no Lua API available to a plugin
to detect or trigger that action. The **Unsaved Changes** indicator lights
the first time you edit anything in a session and is a *reminder*, not a
guarantee — it cannot clear itself once lit, since the plugin has no way to
know a Save to Core has happened.

**Before relying on this for a live show: build the show, then explicitly
verify** — Save to Core (or redeploy), reboot the actual Core, and confirm
the show reloads exactly as expected — **on the target hardware**, not just
in emulation.

## Export / Import

- **Export** serializes the current show (cues, devices, Action Groups,
  UDP targets) to the read-only **Export JSON** box for manual copy (no
  filesystem access is available in the plugin sandbox, so this is
  copy/paste only).
- **Import**: paste JSON into **Import JSON** and press **Import**. The
  payload is fully validated (cue/action/device counts within the
  configured limits, valid action types, valid IP/port formats) *before*
  anything is applied — an invalid import is rejected with a specific
  reason and the live show is left untouched.

> **Schema note**: as of this Devices-page redesign, a `player_trigger` /
> `named_control_set` action's `target` field is a **Device friendly name**
> (defined on the Devices page), not a raw Q-SYS component name. A show
> exported from an earlier build of this plugin will need its action
> targets renamed to match configured Device names before re-importing.
> The schema also now carries `actionGroups` (reusable Action Groups) and
> `tc` (the Timecode Show's cues, frame rate, and source) — both optional
> on import: a show exported before these features existed imports fine
> without them (no groups, no TC cues). A show carrying an older
> `darkMode` field (from a build that still had the Light/Dark Mode
> toggle) also imports fine — the field is simply ignored, since there's
> now only one theme.

## Timecode Show

A **second, independent show**, on its own page, driven by timecode
instead of GO/the cue grid — build a show that fires by hand on the Live
Show page, a show that follows a timecode track on this page, or both at
once, side by side. TC cues still draw their action Targets from the same
**Devices** and **Action Groups** as the Live Show, so nothing has to be
set up twice.

**Read this before you rely on it for anything time-critical.** This
plugin has **no clock of its own** — it reads a real Q-SYS **SMPTE LTC
Reader** component instead — see "Reliability" below for why, and for
exactly what that means for accuracy.

### Setting it up

1. Place a **SMPTE LTC Reader** component (Q-SYS's own Schematic Library
   component, not part of this plugin) somewhere in your design, and wire
   its audio input to your actual LTC source. This is the component that
   does the real work — decoding LTC is DSP-domain audio processing, which
   a Lua plugin cannot do (see Reliability).
2. On that Reader component's **Properties** panel, find **Script
   Access** (under "Script Access") and set it to something other than
   **None** — it defaults to None, which blocks any Control Script
   (including this plugin) from reading its Named Controls at all.
3. **Frame Rate**: 24, 25, or 30 fps — **no drop-frame** (see Reliability).
   This plugin auto-syncs to whatever the Reader itself reports on its own
   "Frame Rate (fps)" Named Control, so it should always match automatically
   once a **TC Source Component** is selected (step 4) — the dropdown here
   is only a manual fallback for bench-testing with no Reader attached.
4. **TC Source Component**: pick your placed SMPTE LTC Reader from this
   dropdown (populated from every component in the design, same as the
   Devices page's Component picker). Once picked, this plugin reads that
   Reader's **Timecode** Named Control directly — whatever `"HH:MM:SS:FF"`
   string it reports becomes the current TC immediately, and that's what
   drives cue firing. Nothing fires, and the clock never advances, until a
   Source Component is selected and it's actually decoding valid LTC.
5. On the page's cue list: press a slot to pick it, set its **Target Time**
   (`HH:MM:SS:FF`) and **Enabled** (only Enabled cues auto-fire — this is a
   deliberate gate, off by default, so a freshly-added TC cue can't
   surprise-fire while you're still building it), then build its actions
   exactly like a Live Show cue's (**+ Add Action**, Type/Target/Control/
   Value, `wait`, and `group` all work identically).
6. Every TC cue's grid button is also a **manual test-fire** button —
   pressing it fires that cue's actions immediately, **regardless of
   Enabled**, so you can bench-test a cue's actions without waiting for the
   clock (or having a TC source wired in at all yet).

**RESET CLOCK** zeroes the clock back to `00:00:00:00`. **REARM CUES**
clears every TC cue's "already fired" flag without touching the clock —
useful if you want to replay from the current TC position without
rewinding. Both are separate from **STOP ALL** and **E-STOP**, which both
still apply to the Timecode Show exactly as they do the Live Show: they
cancel any TC cue currently mid-`wait`, and E-Stop blocks all TC cue firing
(automatic and manual) until **CLEAR E-STOP** — a TC cue blocked by E-Stop
fires as soon as the next TC value arrives once it's cleared (there's no
internal tick to retry it on its own; the Reader's TC advancing is what
re-checks it, same as it does everything else).

### Reliability

This plugin has gone through two prior designs for getting TC in, both
abandoned, before landing on referencing a real Reader component:

1. **An Internal clock** — a `Timer` ticking once per frame, entirely
   inside this plugin, no external reference needed. Removed: Q-SYS Lua
   control scripts run on the Core's control-plane scheduler alongside
   everything else, with no guaranteed low-jitter execution — a software
   `Timer` tick is fundamentally a *soft* clock. Testing confirmed it:
   firing was never silently *skipped* (the `>=` check below saw to that),
   but firing *time* itself wandered under real load, in a way no amount
   of Lua-side cleverness can bound. That's disqualifying for a TC-driven
   show where operators are trusting specific cues to land on specific
   frames.
2. **A schematic "TC Input" pin** (Text-typed) that another component
   could wire a `"HH:MM:SS:FF"` string into. Removed: it never appeared as
   a wireable pin in real Designer once placed — Text-typed `UserPin`s are
   suspected not to render as real Designer pins at all (unconfirmed root
   cause, but confirmed broken by the user in real Designer).

**This plugin cannot decode real LTC audio itself** — that's DSP-domain
signal processing, and a Lua control script has no access to Q-SYS's audio
engine, full stop. It never could generate broadcast-grade TC on its own,
regardless of which of the two abandoned designs above was tried. Real LTC
decoding needs Q-SYS's own native **SMPTE LTC Reader** component (Schematic
Library, not part of this plugin) — a DSP-backed component that actually
touches the audio signal.

- **TC Source Component is now the only source of time.** Rather than a
  pin, this plugin references a placed SMPTE LTC Reader directly via
  `Component.New(name)["Timecode"].EventHandler` — the exact same
  cross-component mechanism it already uses to trigger Media Players, just
  reading instead of writing. This needs no pin and works because the
  Reader's Named Controls are reachable by any Control Script once its
  **Script Access** Property is set to something other than **None**.
  **Accuracy is now entirely the Reader's** (and, in turn, whatever real
  LTC audio is actually feeding it) — this plugin adds no timing error of
  its own on top, because it no longer runs a clock of its own to add
  error with.
- **Why cue firing is still reliable despite any jitter the Reader (or its
  audio source) has**: a TC cue fires on a **"has TC reached or passed its
  target" check**, not an exact frame-equality match. Even if the Reader's
  reported TC jumps straight past a cue's target frame between two
  updates, that check still catches it and fires the cue — just slightly
  late, **never silently skipped**. This is the actual guarantee this
  plugin makes: cues always fire, in order, eventually — accuracy of
  *when* is on the Reader.
- **Frame rate auto-syncs from the Reader's own "Frame Rate (fps)" Named
  Control** once a TC Source Component is selected, so it can't silently
  drift out of agreement with the Reader's actual configuration the way a
  manually-set dropdown could. The Frame Rate dropdown on this page is
  only consulted when no Source Component is selected (bench-testing with
  manual test-fire only).
- **No drop-frame**: only integer 24/25/30 fps are offered. If your Reader
  is decoding real 29.97 drop-frame timecode, its own "Frame Rate (fps)"
  will very likely report something this plugin can't use cleanly —
  configure the Reader for a non-drop rate, or expect a mismatch (see
  "Assumptions flagged for review").

**Bottom line**: for a genuinely time-critical show, this plugin's role is
now just "reliably fire cues off whatever a real TC Reader reports" —
accuracy is whatever that Reader (and its actual LTC source) delivers,
with nothing this plugin does subtracting from it. There is no built-in
fallback clock to lean on: without a TC Source Component selected and
actually decoding valid LTC, TC cues simply never auto-fire (manual
test-fire via each cue's grid button still works, for bench-testing).

### Persistence

Same split as the Live Show: **authored content** (every TC cue's name,
target time, Enabled state, and actions) plus **setup preferences** (frame
rate, TC Source Component) are saved and restored. The **running clock
position and every cue's fired/armed state are never persisted on their
own** — reloading a show zeroes the clock and rearms every cue first, the
same "authored show vs. playback position" split the Live Show already
uses (see Persistence above) — but if the persisted TC Source Component is
still present and actively decoding, re-attaching to it immediately pulls
in its live current TC rather than leaving the display frozen at a stale
`00:00:00:00` while real time keeps moving.

## Reliability notes

- No polling loops anywhere — everything is event-driven (`EventHandler`,
  `Timer`).
- Cue re-fires are debounced (150ms).
- UDP sockets and component references are all resolved once at init and
  cached; the cue-fire path never opens a socket or resolves a component.
- Every external I/O call (`UdpSocket:Send`, component control access) is
  wrapped in `pcall`; one failing action in a cue reports a specific error
  without blocking that cue's other simultaneous actions or any other cue.
- A Boolean action's Value toggle commits its current position to the stored
  action **as soon as a Boolean control is selected**, not only when the
  operator clicks the toggle. Earlier builds left a freshly-detected Boolean
  action's value blank until touched, which made an untouched "off" toggle
  silently fall through to `:Trigger()` instead of actually setting
  `.Boolean = false` when the cue fired — fixed in `RefreshActionValueEditor`.
- A cue's actions dispatch through a small state machine (`DispatchCueActions`
  / `FinishCueFire`), not a single synchronous loop, so a `wait` can suspend
  mid-cue without blocking anything else in the plugin (still no polling: the
  suspension is a single scheduled `Timer`, cancelled via `:Stop()` rather
  than left to fire into a stopped/reset show). Each cue tracks its own
  in-flight state independently, so cue A being mid-`wait` never blocks or
  interferes with firing cue B.
- `group` actions are resolved by fully expanding them (recursively, for
  nested groups) into a flat, ordered action list *before* anything
  dispatches (`BuildExpandedActionList`) — so the existing per-action
  `pcall` isolation, `wait` handling, and error reporting all apply to a
  group's actions exactly as they do to a cue's own, with no separate code
  path to keep in sync. A hard recursion-depth cap backstops the explicit
  circular-reference guard.
- E-STOP's "only Clear E-Stop can release it" behavior is enforced in the
  control's own `EventHandler`, not just in the UI: if anything drives the
  underlying control back to `false` — the input pin, a script, a stray
  click — the plugin immediately writes it back to `true` (guarded against
  re-entrant handling) and logs that it's latched, so the safety property
  holds regardless of what's driving the control.
- Dark Mode mutates one shared `StateColors` table's *values* in place
  rather than swapping which table every function reads from, so every
  existing color reference (cue grid, status LEDs, etc.) automatically
  picks up the new palette with no per-callsite changes.
- The Timecode Show is a fully separate parallel system (`TcCues`,
  `TcFireCueNow`/`TcDispatchCueActions`/`TcFinishCueFire`) rather than the
  Live Show's cue machinery parameterized to also handle TC cues — same
  reasoning as Action Groups' separate functions: a TC cue firing can never
  touch `Cues`/`ActiveCueIndex` or vice versa, so a bug in one show can't
  corrupt the other's state. It reuses `BuildExpandedActionList`/
  `DispatchAction`/`CallAfter` as-is, since those already just take a plain
  actions array and never reference the Live Show's cue state.
- A TC cue fires on a **"TC has reached or passed its target"** check
  (`>=`), not exact frame equality — see "Timecode Show" → "Reliability"
  for why this, not exact matching, is what makes cue firing trustworthy
  despite unavoidable Lua timer jitter: a cue can be fired late, but never
  silently skipped.

## Assumptions flagged for review

Per the brief, these were left as documented, defensive assumptions rather
than guesses baked into fixed behavior, since the exact hardware wasn't
specified:

1. **Player/component control names** (`player_trigger` /
   `named_control_set`): no specific Player type was specified, so control
   names are never hardcoded. The operator enters/selects them per action;
   the plugin auto-populates the Control dropdown from the live component's
   own controls via `Component.GetControls()`. **This previously failed
   silently** — `Component.GetControls()` requires the actual
   `Component.New()` proxy, not the lightweight descriptor returned by
   `Component.GetComponents()`, and the earlier build passed the wrong one.
   Fixed by resolving through `GetComponent()` (which returns/caches the
   real proxy) before calling `Component.GetControls()` — see the comment
   above `RefreshActionControlChoices` in the plugin source. This also
   covers components whose controls are exposed via a plugin's own
   `GetControls()`/pin wiring rather than built-in DSP blocks, since
   `Component.GetControls()` doesn't distinguish the two once given a valid
   proxy. The dropdown remains best-effort and `pcall`-wrapped; the Control
   field always stays freely editable as plain text regardless. The same
   fixed lookup also powers the auto Boolean-toggle-vs-text-field Value
   editor described above (`RefreshActionValueEditor`), keyed off each
   control descriptor's `.Type` field (`Boolean`/`Trigger`/anything else).
2. **UDP payload format**: raw ASCII, sent exactly as typed, with **no**
   automatically appended line terminator. If your device needs a CR/LF,
   include it explicitly (e.g. via a JSON import where the value string
   contains `\r\n`).
3. **Ping heartbeat** (optional "nice to have" feature, UDP target
   reachability): the exact `Ping.New()` / `:start()` /
   `:setPingInterval()` method signature could not be fully verified against
   a specific Designer version's documentation. It's entirely wrapped in
   `pcall`, so a mismatch only disables this optional heartbeat — it never
   affects core cue-firing reliability. See the comment above
   `StartPingHeartbeat` in the plugin source, and verify against your
   installed Designer version if UDP target status doesn't show
   Reachable/Unreachable as expected.
4. **Plugin graphics cannot be redrawn at runtime**: there is no documented
   Lua API for a running plugin to repaint the card/page backgrounds
   `GetControlLayout` draws at design time. This is why the logo is
   necessarily fixed at build time (see "Branding and optional logo"), and
   why this plugin settled on **one fixed theme** rather than a
   runtime-toggled one — a prior build's separate runtime Dark Mode button
   and design-time Dark Background Property were removed specifically
   because keeping a Controls-only runtime palette in sync with a
   graphics-only design-time one, across two mechanisms with no live link
   between them, added real complexity without a matching need. See
   "Colors and theming".
5. **E-Stop pin semantics**: `UserPin = true, PinStyle = "Input"` on
   `PanicButton` is the confirmed syntax for exposing a schematic input pin
   on a Boolean Toggle control, but the exact behavior of an external pin
   write arriving while the plugin's own script is mid-write to that same
   control (a race, in principle) couldn't be verified outside Designer.
   The `Loading`-guarded re-latch logic is defensive against that, but
   verify the E-Stop pin's behavior against real upstream hardware before
   relying on it for life-safety-adjacent use.
6. **Timecode Show clock accuracy and the SMPTE LTC Reader integration**:
   two earlier designs were tried and abandoned (an Internal `Timer`-driven
   soft clock, then a Text-typed "TC Input" schematic pin that never
   rendered as a real pin in Designer once placed — confirmed broken by
   the user) before landing on referencing a real **SMPTE LTC Reader**
   component's Named Controls directly via `Component.New(name)[...]`
   (the exact mechanism already used elsewhere in this plugin for Media
   Players). The Reader's exact Named Control names (`Timecode`, `Frame
   Rate (fps)`, plus `Hours`/`Minutes`/`Seconds`/`Frames`/`Frame`/`Frame
   Offset`/`Drop Frame` which this plugin doesn't currently use) were
   confirmed directly from a real Designer Properties panel screenshot,
   not guessed — but the actual cross-component `.EventHandler` subscription
   this plugin relies on (`comp["Timecode"].EventHandler = ...`) has **not**
   itself been exercised against a real Reader in real Designer (no Core
   was available to test with). It's a standard, documented Q-SYS Lua
   capability and the harness's mock exercises this plugin's side of it,
   but verify against a real placed Reader (with its Script Access Property
   set to something other than None) before a live show. Accuracy itself is
   then entirely the Reader's (and its actual LTC audio source's) — this
   plugin adds no timing error of its own, but also can't correct any it
   receives.
7. **No drop-frame support, by design**: only integer 24/25/30 fps are
   offered; real 29.97 (or 23.976) drop-frame timecode is deliberately not
   implemented, since its frame-number-skipping math is easy to get subtly
   wrong without real broadcast hardware to validate against — better to
   not offer it than to offer a silently-incorrect implementation. If your
   source is 29.97 non-drop, 30fps here is the closest fit; a true
   drop-frame source will read up to ~3.6 seconds "ahead" of real time
   after an hour, since dropped frame numbers are never accounted for.
8. **`Style = "TextBox"` text color cannot be set at all — confirmed twice
   over, not just suspected**: `Style = "Text"`/`"TextBox"` controls have
   no background-fill property at all (`Fill` exists only on `GroupBox`
   graphics), hence the themed rectangle-behind-the-field approach in
   "Colors and theming". Two separate mechanisms were tried for the actual
   *text* color and both failed in real Designer: (1) an earlier build set
   `Controls.X.Color` at *runtime* (in `Init()`) — confirmed not to work,
   text stayed its default color regardless. (2) A later build moved to
   `Color = {r,g,b}` directly in the layout table at *design time* instead
   — the same mechanism every button's face color and every `Style =
   "Text"` field's color already rely on successfully — but for `Style =
   "TextBox"` specifically, **this was also confirmed not to work**, this
   time by the user directly testing it, who reported the six `TextBox`
   fields (Cue Log, TC Cue Log, Current/Next Cue Notes, Export/Import
   JSON) as the only remaining black-on-dark text in the plugin. Design-time
   `Color` continues to work fine for every `Style = "Text"` field (status
   text, device/UDP fields, etc.) — the failure is specific to `Style =
   "TextBox"`. Since neither mechanism works, those six fields now use a
   **light background** (`Theme.TextBoxBgOnLight`) instead of fighting the
   text color further, trusting whatever fixed color Q-SYS actually renders
   `TextBox` text in to read clearly against it.
9. **Raster logo (`Type = "Image"`)**: PNG/JPEG base64 support (now used by
   the shipped default LAUPI PRODUCTION logo, a 1500x1500 PNG) is built
   from documented syntax (`{ Type = "Image", Image = base64string,
   Position, Size }`) rather than from a real example plugin using it (the
   ones checked only used `Type = "Svg"`). The PNG-vs-JPEG-vs-SVG
   auto-detection (from the base64 string's leading bytes, which are fixed
   for PNG and JPEG file signatures) is straightforward, low-risk, and
   confirmed correct against the actual shipped file's real signature — but
   the `Type = "Image"` *rendering* path itself hasn't been visually
   confirmed in real Designer — verify the logo actually appears (and looks
   right at a 32x32 box) before relying on it for a show.

## Validation performed

This build was checked with `luac5.3 -p` (syntax) and against a hand-written
mock of the Q-SYS Lua runtime (`Controls`, `Component`, `UdpSocket`, `Timer`,
`Ping`, `rapidjson`) that actually executes `GetProperties` / `GetControls`
/ `GetPages` / `GetControlLayout` plus the full runtime path — cue firing,
debounce, confirm-before-fire, per-action error isolation, UDP send,
device-resolved `player_trigger`/`named_control_set` actions, selecting
between cues and confirming their action state stays isolated, adding and
removing action rows, export/import round-trip, and import rejection —
across both default and boundary (`Max Cues`/`Max Actions Per
Cue`/`Max Devices`/`UDP Targets` at 1 and at their maximums, including
`Max Actions Per Cue` = 25) Property configurations. The mock specifically
models the `Component.GetControls()` proxy-vs-descriptor distinction and
asserts every call site passes the correct argument, and includes a
component whose controls are only discoverable that way (simulating a
"wired through code" component) to confirm the fix. It also carries
persistent mock control objects with real `Boolean`/`Value`/`Type` state
(not just presence flags) to verify the auto Value editor: that a Boolean
control swaps in the toggle and hides the text field, that a Trigger-type
control hides both, and that toggling it actually writes `.Boolean` on the
underlying mock control (not just the plugin's own stored string). Fire
conditions are also covered: a cue with no condition configured fires
exactly as before (proving the feature is truly optional); a cue with an
unmet per-cue condition is blocked and logs `BLOCKED`, then fires once the
mocked control's live state is flipped to satisfy it; and a Global
Condition is shown to gate a cue that has no condition of its own, cleared
afterward so it doesn't affect anything else, plus a round-trip through
export/import. The single-active-cue behavior is checked directly: firing
one cue then another confirms the first demotes to the played color and
the second becomes active; a deliberately failing fire confirms the
previously-active cue's color and the Current/Next Cue Notes views are
left untouched (never overwritten by the failed cue); Reset Show is
checked to clear active/played/error coloring and the status bar back to
their boot state while leaving a cue's own authored notes/content intact;
and the notes views are checked to advance correctly across successive
successful fires. Move Up/Down is checked to swap a row's full contents
(not just its Type) and to grey out at both ends of the active row range.
The mocked `Timer` was upgraded to actually schedule and (via a manual
`AdvanceTimers()` the test calls explicitly, since no real time passes in
the harness) fire deferred callbacks, so `wait` is checked end-to-end: the
action before it fires immediately, the action after it is held until the
delay elapses, the cue shows Firing color for the whole span and only
becomes Active once the sequence completes; and PANIC mid-`wait` is
checked to actually stop the pending Timer (not just look like it did) by
advancing time afterward and confirming the queued action still never
fires. Action Groups are checked end-to-end too: a single group invoked
from two different cues actually runs its action both times; a `wait`
nested inside a group correctly delays the rest of that group when it's
invoked from a cue; a self-referencing group and a group naming a
nonexistent group both fail the triggering cue with a specific error
instead of hanging, looping, or crashing; and groups round-trip through
export/import. The layout check also confirms every declared control
appears on exactly one of the five pages (never more than one, never
zero, except the intentionally-hidden `ShowData`).

E-Stop is checked end-to-end too: engaging it (via the same control write
a UI click or the input pin would produce) blocks cue firing with a clear
log entry; attempting to clear it any way other than the dedicated Clear
E-Stop button is confirmed to force the control straight back to engaged;
Clear E-Stop is confirmed to actually release the latch and let cues fire
normally again; and it's confirmed to cancel a cue's pending `wait`, same
as the old Panic button did. The exported show is confirmed to no longer
carry a `darkMode` field, now that the runtime toggle has been removed.
The single-theme design is checked directly too: the page background,
title bar text, and every card's heading are confirmed to resolve to the
fixed `Theme.PageBg`/`Theme.Text` colors returned by `GetControlLayout`,
with no Property able to change them; card headings are confirmed to be
drawn as their own `Text` graphic (not the `GroupBox`'s built-in heading)
so their color is actually controllable; and a couple of design-time
transport button colors (`GoButton`, `ResetShowButton`) are checked against
their expected values to confirm they still resolve correctly now that
they're derived from the single `Theme` table instead of two side-by-side
ones. The text-field background/color workaround is checked too, split by
which mechanism each field type actually uses: `CueLogText` (a `Style =
"TextBox"` field) is confirmed to carry `TextBoxStyle = "NoBackground"`,
to have a themed GroupBox rectangle at its exact position using the LIGHT
`Theme.TextBoxBgOnLight` fill, and to carry **no** `Color` field at all
(confirmed `nil`) — since design-time `Color` is confirmed not to affect a
`TextBox`'s text either. `StatusText`/`ShowNameText` (Live Show page) and
`DeviceName 1`/`UdpTargetName 1` (Devices page) — all `Style = "Text"`
fields, where design-time `Color` does work — are confirmed to still carry
`Color = Theme.Text` as before, as a representative spot-check of the
fields extended to match the user's original report that runtime `.Color`
left these boxes' text unreadable against a dark background, and later,
that design-time `Color` on the `TextBox` fields specifically still didn't
fix it.

The Timecode Show is checked end-to-end through a mocked SMPTE LTC Reader
component (Named Controls `Timecode` and `Frame Rate (fps)`, matching a
real Reader's confirmed names), exercising this plugin's side of the
`Component.New(name)[...].EventHandler` cross-component subscription:
selecting a TC Source Component is confirmed to hook the Reader's
`Timecode` control; a TC cue is confirmed to auto-fire exactly when a TC
value reaching its target frame arrives from it, and to not refire on
subsequent updates; the status text is confirmed to read "No TC Source
Component selected" before one is picked, "Waiting for TC from ‹name›"
once picked but before any valid TC has arrived, and "Receiving from
‹name›" once it has; resetting the clock is confirmed to rearm a passed
cue so it fires again once TC passes it a second time (rewind-safe); a TC
value that jumps straight past a cue's target in one update (simulating a
lag spike or a burst of incoming TC) is confirmed to still fire it —
proving the `>=` threshold design, not exact frame matching, is what's
actually relied on; a TC cue's grid button is confirmed to manually
test-fire even while Disabled, and a Disabled cue is confirmed to never
auto-fire; E-Stop is confirmed to block both automatic and manual TC cue
firing and to let a blocked cue fire once TC keeps advancing after it's
cleared; STOP ALL is confirmed to cancel a TC cue's pending `wait` the
same way it does a Live Show cue's; the exported show is confirmed to no
longer carry the old `tc.source` field but to carry the new
`tc.sourceComponent`; the TC cue list, frame rate, and TC Source Component
are confirmed to round-trip through export/import, with the frame rate
confirmed to auto-sync FROM the (still-attached) Reader's own reported
rate rather than trusting the imported value blindly; and re-attaching to
a still-selected, still-live Source Component on import is confirmed to
immediately reflect its current TC rather than freezing at a stale
`00:00:00:00`.

The Clear/CLEAR ALL buttons are checked end-to-end too: a single-cue Clear
Actions and a group's Clear Actions are both confirmed to require two
presses within the confirm window (a lone press only relabels the button
and changes nothing); Clear All Cue Actions and Clear All Group Actions
are confirmed to wipe every cue's/group's actions while leaving names
untouched; a single device's Clear (and, identically, a single UDP
target's Clear) is confirmed to reset it on one press with no confirmation
step, while Clear All Devices and Clear All UDP Targets both require two;
and CLEAR ALL is confirmed to require two presses, then wipe a cue's name,
a device, a UDP target, and the TC clock all at once, log the event, and
leave the editor pointed back at cue 1 -- while a single press is
confirmed to leave everything untouched. `PluginInfo.Author` and the
Live Show branding text are checked directly; the baked-in logo is
confirmed to render on every page with no corresponding Property exposing
it, auto-detected as a PNG `Image`. The page-background graphic is
confirmed to be inserted at the front of each page's graphics array
(rendered first, behind everything else) rather than appended last (which
would paint an opaque rectangle over the title bar, cards, and text ahead
of it) -- the concrete bug behind an earlier "header text not visible"
report.

It has **not** been run inside actual Q-SYS Designer or against real
hardware — do that before a live show, per the persistence note above,
and per the E-Stop pin, Timecode Show clock-accuracy, and raster-logo
caveats in "Assumptions flagged for review".
