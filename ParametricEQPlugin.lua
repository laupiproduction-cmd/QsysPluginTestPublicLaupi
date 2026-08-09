--[[
  UCI Parametric EQ Plugin — Control Script layer
  ================================================

  Scope of this file (see BUILD_NOTES.md for the full picture):

  This plugin is architected as a native audio schematic (Parametric EQ /
  RTA blocks, built in Designer's Schematic view and bundled via
  "Create Plugin from Selected Components") PLUS this Lua control script,
  which owns UI logic, link-group ganging, and preset save/recall. The
  control script never touches audio directly — it only reads/writes
  control values, some of which live on native blocks once the schematic
  is built.

  This file was written WITHOUT access to Q-SYS Designer, so it cannot
  verify: exact native Parametric EQ control names, the real max band
  count per block, whether RTA exposes per-band magnitude as Named
  Controls, or Layout drawing primitives. Every place that depends on one
  of those is isolated behind the EQControlName() function or marked
  "VERIFY IN DESIGNER" below — see BUILD_NOTES.md, open questions #1-3, #5.

  Resolved design decision (per user, overrides spec Open Question #4):
  Recalling a saved preset onto a channel that belongs to a link group
  applies LOCALLY ONLY. It does not propagate to the rest of the group.
  The group stays gathered around its live-edit value until the next
  live edit is made on a banded control.
]]--

PluginInfo = {
  Name = "UCI~Parametric EQ (10ch)",
  Version = "0.1.0",
  Id = "com.laupiproduction.plugins.parametriceq10",
  Description = "10-channel parametric EQ strip with link groups and named presets",
  ShowDebug = true,
}

function GetColor(props)
  return { 60, 120, 200 }
end

function GetPrettyName(props)
  return "Parametric EQ (10ch)"
end

-- ===========================================================================
-- Constants
-- ===========================================================================

local NUM_CHANNELS = 10

-- LinkGroup choices: "None" plus groups A-J (10 groups, one per channel worst case)
local LINK_GROUPS = { "None", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" }

-- VERIFY IN DESIGNER (Open Question #2): confirm actual band-type list against
-- the native Parametric EQ block's Properties panel. Placeholder list below
-- matches the spec's assumed set.
local BAND_TYPES = { "Bell", "HighShelf", "LowShelf", "HighPass", "LowPass", "Notch" }

local MIN_BANDS = 6
local MAX_BANDS = 16
local DEFAULT_BANDS = 10

-- Design-time safe: GetControlLayout() calls this before the runtime script
-- section below has run (Controls is nil during design-time introspection),
-- so it must be defined here, not inside the `if Controls then` block, and
-- must degrade gracefully when there's no live preset store to read yet.
function GetPresetNames()
  if not Controls or not Controls.PresetStore then return {} end
  local raw = Controls.PresetStore.String
  if raw == nil or raw == "" then return {} end
  local ok, decoded = pcall(rapidjson.decode, raw)
  if not ok or type(decoded) ~= "table" then return {} end
  local names = {}
  for name, _ in pairs(decoded) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

-- ===========================================================================
-- Properties
-- ===========================================================================

function GetProperties()
  return {
    {
      Name = "NumBands",
      Type = "integer",
      Min = MIN_BANDS,
      Max = MAX_BANDS,
      Value = DEFAULT_BANDS,
    },
  }
end

function RectifyProperties(props)
  if props["NumBands"].Value < MIN_BANDS then
    props["NumBands"].Value = MIN_BANDS
  elseif props["NumBands"].Value > MAX_BANDS then
    props["NumBands"].Value = MAX_BANDS
  end
  return props
end

-- ===========================================================================
-- Controls
-- ===========================================================================

function GetControls(props)
  local numBands = props["NumBands"].Value
  local ctrls = {}

  -- One shared, hidden JSON store for the named preset library. See
  -- BUILD_NOTES.md / spec section 7 re: reboot persistence being unconfirmed.
  table.insert(ctrls, {
    Name = "PresetStore",
    ControlType = "Text",
    UserPin = false,
  })

  for c = 1, NUM_CHANNELS do
    table.insert(ctrls, {
      Name = "LinkGroup_" .. c,
      ControlType = "Text",
      ControlUnit = "Text",
      UserPin = false,
    })

    table.insert(ctrls, {
      Name = "PresetSaveName_" .. c,
      ControlType = "Text",
      UserPin = false,
    })

    table.insert(ctrls, {
      Name = "PresetSaveButton_" .. c,
      ControlType = "Button",
      ButtonType = "Trigger",
      UserPin = false,
    })

    table.insert(ctrls, {
      Name = "PresetRecall_" .. c,
      ControlType = "Text",
      UserPin = false,
    })

    table.insert(ctrls, {
      Name = "PresetDeleteButton_" .. c,
      ControlType = "Button",
      ButtonType = "Trigger",
      UserPin = false,
    })

    -- RTA display toggle — Approach A from spec section 4 (native display,
    -- toggle-swapped). Left as a plain boolean; wiring it to the actual
    -- pre/post tap routing controls is a Designer step (BUILD_NOTES.md).
    table.insert(ctrls, {
      Name = "RTAShowPost_" .. c,
      ControlType = "Button",
      ButtonType = "Toggle",
      UserPin = false,
    })

    for b = 1, numBands do
      table.insert(ctrls, {
        Name = "Band_" .. c .. "_" .. b .. "_Freq",
        ControlType = "Knob",
        ControlUnit = "Hz",
        Min = 20,
        Max = 20000,
        Value = 1000,
      })
      table.insert(ctrls, {
        Name = "Band_" .. c .. "_" .. b .. "_Gain",
        ControlType = "Knob",
        ControlUnit = "dB",
        Min = -15,
        Max = 15,
        Value = 0,
      })
      table.insert(ctrls, {
        Name = "Band_" .. c .. "_" .. b .. "_Q",
        ControlType = "Knob",
        ControlUnit = "Float",
        Min = 0.1,
        Max = 10,
        Value = 0.707,
      })
      table.insert(ctrls, {
        Name = "Band_" .. c .. "_" .. b .. "_Type",
        ControlType = "Text",
        UserPin = false,
      })
    end
  end

  return ctrls
end

-- ===========================================================================
-- Layout — simple grid of stock controls only (knobs/combo/buttons/text).
-- Deliberately avoids custom freeform curve drawing (spec Open Question #4 /
-- section 4 Approach B, and the draggable point editor in section 5): those
-- both depend on confirming Layout graphic primitives in Designer first.
-- This layout gives you something loadable/testable now; rearrange freely
-- once you're doing real layout work in Designer.
-- ===========================================================================

function GetControlLayout(props)
  local numBands = props["NumBands"].Value
  local layout = {}
  local graphics = {}

  local channelWidth = 140
  local bandRowHeight = 20
  local headerHeight = 90

  for c = 1, NUM_CHANNELS do
    local x = (c - 1) * channelWidth + 10
    local y = 10

    table.insert(graphics, {
      Type = "Text",
      Text = "Ch " .. c,
      Position = { x, y },
      Size = { channelWidth - 10, 20 },
    })

    layout["LinkGroup_" .. c] = {
      PrettyName = "Ch " .. c .. " Link Group",
      Style = "ComboBox",
      Position = { x, y + 20 },
      Size = { channelWidth - 10, 18 },
      Choices = LINK_GROUPS,
    }

    layout["PresetSaveName_" .. c] = {
      PrettyName = "Ch " .. c .. " Save As",
      Style = "Text",
      Position = { x, y + 40 },
      Size = { channelWidth - 40, 18 },
    }
    layout["PresetSaveButton_" .. c] = {
      PrettyName = "Ch " .. c .. " Save Preset",
      Style = "Button",
      Position = { x + channelWidth - 36, y + 40 },
      Size = { 30, 18 },
    }

    layout["PresetRecall_" .. c] = {
      PrettyName = "Ch " .. c .. " Recall Preset",
      Style = "ComboBox",
      Position = { x, y + 60 },
      Size = { channelWidth - 40, 18 },
      Choices = GetPresetNames(),
    }
    layout["PresetDeleteButton_" .. c] = {
      PrettyName = "Ch " .. c .. " Delete Preset",
      Style = "Button",
      Position = { x + channelWidth - 36, y + 60 },
      Size = { 30, 18 },
    }

    layout["RTAShowPost_" .. c] = {
      PrettyName = "Ch " .. c .. " RTA Post",
      Style = "Button",
      Position = { x, y + headerHeight - 18 },
      Size = { channelWidth - 10, 16 },
    }

    for b = 1, numBands do
      local by = y + headerHeight + (b - 1) * bandRowHeight

      layout["Band_" .. c .. "_" .. b .. "_Type"] = {
        PrettyName = "Ch " .. c .. " Band " .. b .. " Type",
        Style = "ComboBox",
        Position = { x, by },
        Size = { channelWidth - 10, 16 },
        Choices = BAND_TYPES,
      }
    end
  end

  return layout, graphics
end

-- ===========================================================================
-- Runtime script (skipped during design-time GetControls/GetControlLayout
-- introspection calls, per standard Q-SYS plugin convention)
-- ===========================================================================

if Controls then

  local NumBands = Properties and Properties["NumBands"].Value or DEFAULT_BANDS

  -- Reentrancy guard: prevents propagation writes from re-triggering the
  -- EventHandlers that perform propagation (spec section 6/8).
  local Propagating = false

  local BAND_PARAMS = { "Freq", "Gain", "Q", "Type" }

  ---------------------------------------------------------------------------
  -- VERIFY IN DESIGNER (Open Question #2/#3): once the native schematic
  -- exists, per-band EQ parameters live on the native Parametric EQ block's
  -- controls, not on Band_c_b_Type/etc directly (those are this script's own
  -- UI controls). This function is the single seam to change: point it at
  -- the real named controls (e.g. via Component.New(...)) instead of
  -- returning the plugin's own control, and have the EventHandlers below
  -- push into it. Left as an identity mapping so the file is self-contained
  -- and testable before the schematic exists.
  ---------------------------------------------------------------------------
  local function EQControlName(channel, band, param)
    return "Band_" .. channel .. "_" .. band .. "_" .. param
  end

  local function GetBandParam(channel, band, param)
    local ctl = Controls[EQControlName(channel, band, param)]
    if not ctl then return nil end
    if param == "Type" then
      return ctl.String
    end
    return ctl.Value
  end

  local function SetBandParam(channel, band, param, value)
    local ctl = Controls[EQControlName(channel, band, param)]
    if not ctl then return end
    if param == "Type" then
      ctl.String = value
    else
      ctl.Value = value
    end
  end

  local function GetLinkGroup(channel)
    local ctl = Controls["LinkGroup_" .. channel]
    if not ctl then return "None" end
    local g = ctl.String
    if g == nil or g == "" then return "None" end
    return g
  end

  local function ChannelsInGroup(group, excludeChannel)
    local list = {}
    if group == "None" then return list end
    for c = 1, NUM_CHANNELS do
      if c ~= excludeChannel and GetLinkGroup(c) == group then
        table.insert(list, c)
      end
    end
    return list
  end

  -----------------------------------------------------------------------
  -- Live gang propagation (spec section 6, "Live gang")
  -----------------------------------------------------------------------

  local function OnBandParamChanged(sourceChannel, band, param, value)
    if Propagating then return end

    local group = GetLinkGroup(sourceChannel)
    if group == "None" then return end

    local targets = ChannelsInGroup(group, sourceChannel)
    if #targets == 0 then return end

    Propagating = true
    local ok, err = pcall(function()
      for _, targetChannel in ipairs(targets) do
        SetBandParam(targetChannel, band, param, value)
      end
    end)
    Propagating = false

    if not ok then
      print("ParametricEQ: link propagation error: " .. tostring(err))
    end
  end

  for c = 1, NUM_CHANNELS do
    for b = 1, NumBands do
      for _, param in ipairs(BAND_PARAMS) do
        local ctl = Controls[EQControlName(c, b, param)]
        if ctl then
          -- capture c, b, param by value for the closure
          local channel, band, parameter = c, b, param
          ctl.EventHandler = function(control)
            local value
            if parameter == "Type" then
              value = control.String
            else
              value = control.Value
            end
            OnBandParamChanged(channel, band, parameter, value)
          end
        end
      end
    end
  end

  -----------------------------------------------------------------------
  -- Named presets (spec section 6, "Saved presets")
  -- Storage shape: { [presetName] = { [bandIndex] = {Freq=, Gain=, Q=, Type=} } }
  -----------------------------------------------------------------------

  local function LoadPresetStore()
    local raw = Controls.PresetStore.String
    if raw == nil or raw == "" then
      return {}
    end
    local ok, decoded = pcall(rapidjson.decode, raw)
    if not ok or type(decoded) ~= "table" then
      print("ParametricEQ: preset store decode failed, resetting store")
      return {}
    end
    return decoded
  end

  local function SavePresetStore(store)
    local ok, encoded = pcall(rapidjson.encode, store)
    if not ok then
      print("ParametricEQ: preset store encode failed: " .. tostring(encoded))
      return false
    end
    Controls.PresetStore.String = encoded
    return true
  end

  local function RefreshRecallChoices()
    local names = GetPresetNames()
    for c = 1, NUM_CHANNELS do
      local ctl = Controls["PresetRecall_" .. c]
      if ctl and ctl.Choices then
        ctl.Choices = names
      end
    end
  end

  local function SavePreset(channel, name)
    if name == nil or name == "" then
      print("ParametricEQ: cannot save preset with empty name")
      return
    end
    local snapshot = {}
    for b = 1, NumBands do
      snapshot[tostring(b)] = {
        Freq = GetBandParam(channel, b, "Freq"),
        Gain = GetBandParam(channel, b, "Gain"),
        Q = GetBandParam(channel, b, "Q"),
        Type = GetBandParam(channel, b, "Type"),
      }
    end

    local ok = pcall(function()
      local store = LoadPresetStore()
      store[name] = snapshot
      SavePresetStore(store)
    end)
    if not ok then
      print("ParametricEQ: failed to save preset '" .. name .. "'")
      return
    end
    RefreshRecallChoices()
  end

  -- Resolved decision (overrides spec Open Question #4): preset recall is
  -- LOCAL ONLY, even if the target channel belongs to a link group. The
  -- Propagating guard below suppresses the group-ganging EventHandlers
  -- while the recalled values are being written, so the rest of the group
  -- is left untouched.
  local function RecallPreset(channel, name)
    if name == nil or name == "" then return end

    local ok, store = pcall(LoadPresetStore)
    if not ok then
      print("ParametricEQ: preset store unreadable")
      return
    end

    local snapshot = store[name]
    if snapshot == nil then
      print("ParametricEQ: no such preset '" .. tostring(name) .. "'")
      return
    end

    Propagating = true
    local applyOk, applyErr = pcall(function()
      for b = 1, NumBands do
        local band = snapshot[tostring(b)]
        if band then
          SetBandParam(channel, b, "Freq", band.Freq)
          SetBandParam(channel, b, "Gain", band.Gain)
          SetBandParam(channel, b, "Q", band.Q)
          SetBandParam(channel, b, "Type", band.Type)
        end
      end
    end)
    Propagating = false

    if not applyOk then
      print("ParametricEQ: preset recall error: " .. tostring(applyErr))
    end
  end

  local function DeletePreset(name)
    if name == nil or name == "" then return end
    local ok = pcall(function()
      local store = LoadPresetStore()
      store[name] = nil
      SavePresetStore(store)
    end)
    if not ok then
      print("ParametricEQ: failed to delete preset '" .. name .. "'")
      return
    end
    RefreshRecallChoices()
  end

  for c = 1, NUM_CHANNELS do
    local channel = c

    Controls["PresetSaveButton_" .. c].EventHandler = function()
      local name = Controls["PresetSaveName_" .. channel].String
      SavePreset(channel, name)
    end

    Controls["PresetRecall_" .. c].EventHandler = function(control)
      RecallPreset(channel, control.String)
    end

    Controls["PresetDeleteButton_" .. c].EventHandler = function()
      local name = Controls["PresetRecall_" .. channel].String
      DeletePreset(name)
    end
  end

  RefreshRecallChoices()

  -----------------------------------------------------------------------
  -- RTA overlay: NOT implemented here. Spec section 4 recommends
  -- prototyping Approach A (native RTA graphic, toggle-swapped between pre
  -- and post tap) first, wired entirely in Designer's Layout/routing, with
  -- no Lua required. Approach B (custom dual-trace overlay) needs Open
  -- Question #3 (RTA per-band magnitude as Named Controls) and Open
  -- Question #4/section-5-class Layout drawing support confirmed first —
  -- do not build it against assumptions. If/when both are confirmed, add a
  -- single Timer.New() polling at 10-15 Hz (per spec section 8's no-polling-
  -- loops / throttle-only rule) that reads both taps and writes to a custom
  -- graphic control; do not poll per-channel timers.
  -----------------------------------------------------------------------

end
