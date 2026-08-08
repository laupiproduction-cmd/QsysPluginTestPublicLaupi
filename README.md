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

The component has two pages (visible as tabs at the top of its properties/
control panel in Designer):

- **Live Show** — a compact, card-based operator view: show/lock strip,
  status bar, GO/STOP ALL/PANIC transport, the quick-fire cue grid, and a
  live activity log. Sized to fit comfortably on one screen (~920px wide).
- **Show Editor** — the full authoring surface: global stop/panic settings,
  export/import, UDP target config, and the complete per-cue/per-action
  editor table (one row per cue, every action's fields laid out left to
  right). This page is deliberately wide — it scales with **Max Actions Per
  Cue** and is meant to be viewed in a resized Schematic view or scrolled,
  not to fit in a small pane. Everything on it is setup/authoring, not
  something an operator touches mid-show, which is why it's split off the
  Live Show page.

Paging is purely a Designer-canvas display choice — every control behaves
identically regardless of which page it's shown on, and the two pages
share one consistent color palette (blue accent, green/amber/red for
success/warning/danger) with card-style grouped sections and section
headings.

## Properties

| Property | Purpose | Default | Range |
|---|---|---|---|
| **Max Cues** | Size of the fixed cue grid/editor | 30 | 1–30 |
| **Max Actions Per Cue** | Simultaneous actions per cue | 3 | 1–6 |
| **UDP Targets** | Number of configurable UDP devices | 6 | 0–12 |
| **Show Debug** | Show the Lua debug window; also gates `print()` mirroring of errors/cue-fire log lines | false | — |

Changing any of these **resizes the control set** (`GetControls` declares a
static, fixed-size set of controls sized only from these Properties — the
control count never changes at runtime). If you reduce a count after cues
have been programmed, any cues/actions beyond the new limit are dropped from
the visible control set the next time the component regenerates.

## Programming a cue

Each cue row in the editor has: **Name**, **Color** (`#RRGGBB`, used for the
cue button's idle color), **Arm**, **Confirm** (require a double-press
within 2s before firing — for destructive cues), **Notes** (run-sheet text,
never fired), and one block per action slot:

- **Type**: `none` / `player_trigger` / `udp_send` / `named_control_set`
- **Target**: component name (for `player_trigger` / `named_control_set`) or
  UDP target name (for `udp_send`). This field is a dropdown auto-populated
  from `Component.GetComponents()` (or the configured UDP target names) —
  it also accepts free text.
- **Control**: the Named Control on that component to act on
  (`player_trigger` / `named_control_set` only). Auto-suggested from the
  live component's own controls where possible; always editable as plain
  text, since control names differ by component/Player type (see
  "Assumptions" below).
- **Value**: for `named_control_set`, one of `V:<number>` (sets `.Value`),
  `P:<number>` (sets `.Position`, 0–1), `S:<text>` (sets `.String`), or `T`
  / empty (calls `:Trigger()`). For `udp_send`, this is the **raw ASCII
  payload** sent byte-for-byte (see "Assumptions").

**GO** fires the "next cue" shown in the status bar and advances it.
**STOP ALL** triggers the control named in **Player Stop Control Name**
(default `stop`) on every component referenced anywhere in the show.
**PANIC** does the same and, if **Panic UDP Payload** is non-empty, sends
that payload to every configured UDP target — bypassing the normal cue path
entirely.

## Testing UDP sending

1. Fill in one of the **UDP Targets** rows: Name, IP, Port.
2. Set an action's Type to `udp_send`, Target to that target's Name, and
   Value to the payload you want to send (plain ASCII, e.g. `PLAY`).
3. Fire that cue and confirm the target device receives the packet (a
   packet capture on the Core's network interface, e.g. Wireshark filtering
   on `udp.port == <port>`, is the most reliable way to verify this without
   depending on the receiving device).
4. If the device sends anything back to the same socket, its last
   reply is shown (throttled to ~10 updates/sec) in that target's
   **Status** field.

## Persistence — verify on real hardware before a live show

The full show (cues, actions, UDP targets) is serialized to JSON into a
hidden control (`ShowData`) every time you edit anything, and reloaded from
it on plugin init. **This is not the same as surviving a Core reboot.**

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

- **Export** serializes the current show to the read-only **Export JSON**
  box for manual copy (no filesystem access is available in the plugin
  sandbox, so this is copy/paste only).
- **Import**: paste JSON into **Import JSON** and press **Import**. The
  payload is fully validated (cue/action counts within the configured
  limits, valid action types, valid IP/port formats) *before* anything is
  applied — an invalid import is rejected with a specific reason and the
  live show is left untouched.

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
   the plugin best-effort auto-populates the Control dropdown from the live
   component's own controls via `Component.GetControls()`, but this is
   wrapped in `pcall` and silently falls back to a plain text field if that
   call's shape doesn't match what was assumed — see the comment above
   `RefreshActionControlChoices` in the plugin source.
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
export/import round-trip, and import rejection — across both default and
boundary (`Max Cues`/`Max Actions Per Cue`/`UDP Targets` at 1 and at their
maximums) Property configurations. The layout check also confirms every
declared control appears on exactly one of the two pages (never both, never
neither, except the intentionally-hidden `ShowData`). It has **not** been
run inside actual Q-SYS Designer or against real hardware — do that before
a live show, per the persistence note above.
