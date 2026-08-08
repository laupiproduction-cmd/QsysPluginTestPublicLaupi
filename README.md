# Show Control ~ Cue Engine

A single-file Q-SYS plugin (`ShowCueEngine.qplug`) that acts as a live-show
cue engine: up to 30 operator-programmable cues, each firing multiple
simultaneous actions — triggering Media/Stream Players, sending UDP messages
to networked devices, and setting/triggering any Named Control on any
in-house component.

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

The component has three pages (visible as tabs at the top of its
properties/control panel in Designer):

- **Live Show** — the compact operator view: show/lock strip, status bar,
  GO/STOP ALL/PANIC transport, the quick-fire cue grid, and a live activity
  log. Sized to fit comfortably on one screen (~920px wide).
- **Devices** — a curated list of Q-SYS components ("Devices") and UDP
  targets. This is the only place the full, raw list of every component in
  your design is shown; everywhere else (the Show Editor's action Target
  dropdown) only sees the friendly names you define here. Keeps the editor
  from being flooded with every gain block and router in the design.
- **Show Editor** — pick **one** cue from a dropdown and edit it: name,
  color, armed, confirm-before-fire, notes, and its actions. Actions are
  revealed one at a time with **+ Add Action** (and removed with each row's
  **X** button) instead of always showing every action slot for every cue —
  so a 30-cue show with a handful of actions per cue doesn't fill the screen
  with 100+ mostly-empty rows.

Paging is purely a Designer-canvas display choice — every control behaves
identically regardless of which page it's shown on. All three pages share
one color palette (blue accent, green/amber/red for success/warning/danger)
with card-style grouped sections and section headings.

## Properties

| Property | Purpose | Default | Range |
|---|---|---|---|
| **Max Cues** | Size of the cue grid | 30 | 1–30 |
| **Max Actions Per Cue** | Max actions any single cue can have | 4 | 1–25 |
| **Max Devices** | Size of the curated component list (Devices page) | 12 | 0–24 |
| **UDP Targets** | Number of configurable UDP devices | 6 | 0–12 |
| **Show Debug** | Show the Lua debug window; also gates `print()` mirroring of errors/cue-fire log lines | false | — |

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
   the gap). Each visible row has:
   - **Type**: `none` / `player_trigger` / `udp_send` / `named_control_set`
   - **Target**: a Device name (for `player_trigger` / `named_control_set`)
     or a UDP target name (for `udp_send`) — dropdown populated from the
     **Devices** page, not the raw design.
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
     ASCII payload** sent byte-for-byte (see "Assumptions").

Switching **Select Cue** doesn't lose anything — every field writes straight
into that cue's stored data as you edit it, and the editor bank just gets
repointed to show whichever cue is currently selected.

**GO** (Live Show page) fires the "next cue" shown in the status bar and
advances it. **STOP ALL** triggers the control named in **Player Stop
Control Name** (Show Editor page, default `stop`) on every component
referenced anywhere in the show. **PANIC** does the same and, if **Panic
UDP Payload** is non-empty, sends that payload to every configured UDP
target — bypassing the normal cue path entirely.

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

- **Export** serializes the current show (cues, devices, UDP targets) to
  the read-only **Export JSON** box for manual copy (no filesystem access
  is available in the plugin sandbox, so this is copy/paste only).
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

## Reliability notes

- No polling loops anywhere — everything is event-driven (`EventHandler`,
  `Timer`).
- Cue re-fires are debounced (150ms).
- UDP sockets and component references are all resolved once at init and
  cached; the cue-fire path never opens a socket or resolves a component.
- Every external I/O call (`UdpSocket:Send`, component control access) is
  wrapped in `pcall`; one failing action in a cue reports a specific error
  without blocking that cue's other simultaneous actions or any other cue.

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
underlying mock control (not just the plugin's own stored string). The
layout check also confirms every declared control appears on exactly one
of the three pages (never more than one, never zero, except the
intentionally-hidden `ShowData`). It has **not** been run inside actual
Q-SYS Designer or against real hardware — do that before a live show, per
the persistence note above.
