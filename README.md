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

The component has four pages (visible as tabs at the top of its
properties/control panel in Designer):

- **Live Show** — the compact operator view: show/lock strip, status bar,
  GO/STOP ALL/PANIC/RESET transport, large Current/Next Cue Notes ("cue
  words") views, the quick-fire cue grid, and a live activity log. Sized to
  fit comfortably on one screen (~920px wide).
- **Devices** — a curated list of Q-SYS components ("Devices") and UDP
  targets. This is the only place the full, raw list of every component in
  your design is shown; everywhere else (the Show Editor's/Action Groups'
  action Target dropdown) only sees the friendly names you define here.
  Keeps the editor from being flooded with every gain block and router in
  the design.
- **Action Groups** — pick **one** reusable group from a dropdown and edit
  its actions (same Type/Target/Control/Value/Move Up/Down/Remove editor as
  a cue's own actions, in its own bank of controls). Build a "Mute All" or
  "Gain Reset" once here, then invoke it from any cue — or another group —
  with a `group` action. See "Reusable Action Groups" below.
- **Show Editor** — pick **one** cue from a dropdown and edit it: name,
  color, armed, confirm-before-fire, notes, and its actions. Actions are
  revealed one at a time with **+ Add Action** (and removed with each row's
  **X** button) instead of always showing every action slot for every cue —
  so a 30-cue show with a handful of actions per cue doesn't fill the screen
  with 100+ mostly-empty rows.

Paging is purely a Designer-canvas display choice — every control behaves
identically regardless of which page it's shown on. All four pages share
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
is independent. **PANIC**, **STOP ALL**, and **RESET** all cancel any cue
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
the specific reason shown in the status bar's error field. **PANIC** and
**STOP ALL** always bypass conditions entirely, same as they bypass the
normal cue path — they're an emergency override by design.

**GO** (Live Show page) fires the "next cue" shown in the status bar and
advances it. **STOP ALL** triggers the control named in **Player Stop
Control Name** (Show Editor page, default `stop`) on every component
referenced anywhere in the show, and cancels any cue mid-`wait`. **PANIC**
does the same and, if **Panic UDP Payload** is non-empty, sends that
payload to every configured UDP target — bypassing the normal cue path
entirely, and clears the grid's active/played coloring (but does **not**
rewind the show position — it's a halt-in-place, not a restart; use
**RESET** for that).

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

**RESET** (Live Show page, next to PANIC) rewinds *playback position only* —
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
appears on exactly one of the four pages (never more than one, never
zero, except the intentionally-hidden `ShowData`). It has **not** been
run inside actual Q-SYS Designer or against real hardware — do that
before a live show, per the persistence note above.
