--[[
  LAUPI Cue Creator
  --------------------------------------------------------------------------
  A Q-SYS Plugin that lets you build a list of "cues" at runtime.

  - Click "+ Add Cue" to activate the next free cue slot.
  - Each active cue has:
      * A renamable Name field
      * An Action dropdown (None / Play Audio Player / Stop Audio Player)
      * A Target field: the exact Code Name of the Named Component to act on
      * A "Fire" button that runs the action
      * A "Remove" button that deactivates the cue again
  - The total number of cue slots is set via the "Number of Cue Slots"
    property (right-click the component > Properties) since a Q-SYS
    component's control set is fixed at compile time. "+ Add Cue" reveals
    slots up to that limit; raise the property if you need more.

  Author: LAUPI
--]]

PluginInfo = {
  Name = "LAUPI~Cue Creator",
  Version = "1.0",
  Id = "qsc.plugin.laupi.cuecreator.74302a81-ce41-4d85-956d-007ca844cdc8",
  Description = "Create renamable cues that trigger actions such as Play/Stop on an Audio Player.",
  ShowDebug = false,
  Author = "LAUPI",
}

-- ============================================================================
-- Color shown on the schematic block
-- ============================================================================
function GetColor(props)
  return { 61, 133, 198 }
end

-- ============================================================================
-- Properties
-- ============================================================================
function GetProperties()
  local props = {
    {
      Name = "Number of Cue Slots",
      Type = "integer",
      Min = 1,
      Max = 24,
      Value = 8,
    },
  }
  return props
end

function RectifyProperties(props)
  return props
end

-- ============================================================================
-- Controls
-- ============================================================================
function GetControls(props)
  local maxCues = props["Number of Cue Slots"].Value
  local ctrls = {}

  table.insert(ctrls, {
    Name = "AddCue",
    ControlType = "Button",
    ButtonType = "Trigger",
    UserPin = false,
  })

  table.insert(ctrls, {
    Name = "Status",
    ControlType = "Text",
    UserPin = false,
  })

  for i = 1, maxCues do
    table.insert(ctrls, {
      Name = "CueName_" .. i,
      ControlType = "Text",
      UserPin = false,
    })

    table.insert(ctrls, {
      Name = "ActionType_" .. i,
      ControlType = "Text",
      Choices = { "None", "Play Audio Player", "Stop Audio Player" },
      UserPin = false,
    })

    table.insert(ctrls, {
      Name = "TargetComponent_" .. i,
      ControlType = "Text",
      UserPin = false,
    })

    table.insert(ctrls, {
      Name = "Fire_" .. i,
      ControlType = "Button",
      ButtonType = "Trigger",
      UserPin = true,
      PinStyle = "Input",
    })

    table.insert(ctrls, {
      Name = "Remove_" .. i,
      ControlType = "Button",
      ButtonType = "Trigger",
      UserPin = false,
    })
  end

  return ctrls
end

-- ============================================================================
-- Layout
-- ============================================================================
function GetControlLayout(props)
  local maxCues = props["Number of Cue Slots"].Value
  local layout = {}
  local graphics = {}

  local panelWidth = 620
  local rowHeight = 26
  local top = 56

  table.insert(graphics, {
    Type = "Header",
    Text = "LAUPI Cue Creator",
    Position = { 8, 8 },
    Size = { panelWidth - 16, 20 },
  })

  table.insert(graphics, {
    Type = "Label",
    Text = "Name",
    Position = { 40, 34 },
    Size = { 150, 16 },
  })
  table.insert(graphics, {
    Type = "Label",
    Text = "Action",
    Position = { 196, 34 },
    Size = { 170, 16 },
  })
  table.insert(graphics, {
    Type = "Label",
    Text = "Target Component (Code Name)",
    Position = { 372, 34 },
    Size = { 170, 16 },
  })

  layout["AddCue"] = {
    PrettyName = "Add Cue",
    Legend = "+ Add Cue",
    Style = "Button",
    ButtonStyle = "Trigger",
    Position = { 8, top + maxCues * rowHeight + 8 },
    Size = { 100, 22 },
  }

  layout["Status"] = {
    PrettyName = "Status",
    Style = "Text",
    IsReadOnly = true,
    Position = { 116, top + maxCues * rowHeight + 8 },
    Size = { panelWidth - 124, 22 },
  }

  for i = 1, maxCues do
    local y = top + (i - 1) * rowHeight

    layout["Remove_" .. i] = {
      PrettyName = "Remove Cue " .. i,
      Legend = "X",
      Style = "Button",
      ButtonStyle = "Trigger",
      Position = { 8, y },
      Size = { 24, 22 },
    }

    layout["CueName_" .. i] = {
      PrettyName = "Cue " .. i .. " Name",
      Style = "Text",
      Position = { 40, y },
      Size = { 150, 22 },
    }

    layout["ActionType_" .. i] = {
      PrettyName = "Cue " .. i .. " Action",
      Style = "ComboBox",
      Position = { 196, y },
      Size = { 170, 22 },
    }

    layout["TargetComponent_" .. i] = {
      PrettyName = "Cue " .. i .. " Target",
      Style = "Text",
      Position = { 372, y },
      Size = { 170, 22 },
    }

    layout["Fire_" .. i] = {
      PrettyName = "Fire Cue " .. i,
      Legend = "Go",
      Style = "Button",
      ButtonStyle = "Trigger",
      Position = { 548, y },
      Size = { 64, 22 },
    }
  end

  return layout, graphics
end

-- ============================================================================
-- Runtime behavior
-- ============================================================================
if Controls then
  local maxCues = Properties["Number of Cue Slots"].Value
  local cueActive = {}

  local function setRowVisible(i, visible)
    Controls["CueName_" .. i].IsInvisible = not visible
    Controls["ActionType_" .. i].IsInvisible = not visible
    Controls["TargetComponent_" .. i].IsInvisible = not visible
    Controls["Fire_" .. i].IsInvisible = not visible
    Controls["Remove_" .. i].IsInvisible = not visible
  end

  local function updateStatus()
    local count = 0
    for i = 1, maxCues do
      if cueActive[i] then count = count + 1 end
    end
    Controls.Status.String = count .. " / " .. maxCues .. " cue slots used"
  end

  -- Fires a control on another Named Component, trying Trigger() first
  -- and falling back to a momentary Boolean pulse.
  local function pressComponentControl(comp, ctrlName)
    local ctrl = comp[ctrlName]
    if not ctrl then return false end
    local ok = pcall(function() ctrl:Trigger() end)
    if not ok then
      pcall(function()
        ctrl.Boolean = true
        ctrl.Boolean = false
      end)
    end
    return true
  end

  local function fireCue(i)
    local actionType = Controls["ActionType_" .. i].String
    local targetName = Controls["TargetComponent_" .. i].String

    if actionType == "None" or actionType == "" then return end
    if targetName == nil or targetName == "" then
      print("LAUPI Cue Creator: Cue '" .. Controls["CueName_" .. i].String .. "' has no Target Component set.")
      return
    end

    local ok, comp = pcall(Component.New, targetName)
    if not ok or comp == nil then
      print("LAUPI Cue Creator: could not find a Named Component called '" .. targetName .. "'.")
      return
    end

    if actionType == "Play Audio Player" then
      if not pressComponentControl(comp, "play") then
        print("LAUPI Cue Creator: '" .. targetName .. "' has no 'play' control.")
      end
    elseif actionType == "Stop Audio Player" then
      if not pressComponentControl(comp, "stop") then
        print("LAUPI Cue Creator: '" .. targetName .. "' has no 'stop' control.")
      end
    end
  end

  for i = 1, maxCues do
    -- Only the first slot starts active; the rest are hidden until "Add Cue" is used
    cueActive[i] = (i == 1)

    if Controls["CueName_" .. i].String == "" then
      Controls["CueName_" .. i].String = "Cue " .. i
    end
    if Controls["ActionType_" .. i].String == "" then
      Controls["ActionType_" .. i].String = "None"
    end

    setRowVisible(i, cueActive[i])

    Controls["Fire_" .. i].EventHandler = function()
      fireCue(i)
    end

    Controls["Remove_" .. i].EventHandler = function(idx)
      cueActive[i] = false
      setRowVisible(i, false)
      updateStatus()
    end
  end

  Controls.AddCue.EventHandler = function()
    for i = 1, maxCues do
      if not cueActive[i] then
        cueActive[i] = true
        setRowVisible(i, true)
        updateStatus()
        return
      end
    end
    print("LAUPI Cue Creator: all " .. maxCues .. " cue slots are in use. Increase 'Number of Cue Slots' in the component Properties to add more.")
  end

  updateStatus()
end
