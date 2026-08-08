--[[
  LAUPI Cue Creator
  --------------------------------------------------------------------------
  A Q-SYS Plugin with three tabs:

    Cues    - click "+ Add Cue" to create a renamable cue. Each cue can run
              several Actions (from the Actions tab) in sequence when you
              press its "Go" button. The row of the most recently fired cue
              lights up (green LED) so you can see which one is active.
    Actions - click "+ Add Action" to build a reusable action. Two kinds:
                "Set Component Control" - type a Named Component's Code Name,
                pick one of its real controls (mute, bypass, gain, play,
                stop, cross-point gain on a matrix mixer, etc. - whatever
                that component actually exposes) from the auto-populated
                list, and the value field adapts to that control: a
                True/False switch for Boolean controls, a number box for
                numeric controls (gain, position, frequency...), a text box
                for text controls, or nothing at all for pure triggers
                (play/stop/etc. just fire).
                "Send UDP Message" - send text to a Device (from the
                Devices tab).
    Devices - click "+ Add Device" to register a Name/IP/Port for UDP, with
              a "Test" button to send a test packet.

  To link multiple Q-SYS components (players, gains, matrix mixers, ...):
  create one Action per control you want to touch, each with its own
  Target Component Code Name (see that component's own Properties for its
  Code Name) and Control selection. There's no fixed limit on how many
  distinct components you can reference - just add one Action per
  component+control combo you need, then pick whichever ones you want on
  each Cue's action slots.

  A Q-SYS component's control set is fixed once compiled, so the "Add"
  buttons reveal pre-built hidden slots rather than creating new controls.
  Raise the relevant "Number of..." property (right-click component >
  Properties) if you run out of slots.

  Author: LAUPI
--]]

PluginInfo = {
  Name = "LAUPI~Cue Creator",
  Version = "3.0",
  Id = "qsc.plugin.laupi.cuecreator.74302a81-ce41-4d85-956d-007ca844cdc8",
  Description = "Create renamable cues that each run one or more actions against the real controls of any Named Component (mute, bypass, gain, play, stop, matrix cross-points, ...) or send UDP, with a highlighted active-cue row.",
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
-- Pages (tabs)
-- ============================================================================
local pagenames = { "Cues", "Actions", "Devices" }

function GetPages(props)
  local pages = {}
  for _, name in ipairs(pagenames) do
    table.insert(pages, { name = name })
  end
  return pages
end

-- ============================================================================
-- Properties
-- ============================================================================
function GetProperties()
  local props = {
    { Name = "Number of Cue Slots", Type = "integer", Min = 1, Max = 16, Value = 6 },
    { Name = "Max Actions per Cue", Type = "integer", Min = 1, Max = 6, Value = 3 },
    { Name = "Number of Actions", Type = "integer", Min = 1, Max = 24, Value = 10 },
    { Name = "Number of Devices", Type = "integer", Min = 1, Max = 12, Value = 4 },
  }
  return props
end

function RectifyProperties(props)
  return props
end

-- ============================================================================
-- Controls (the full control set exists regardless of which tab is active;
-- pages only control which controls are laid out on which tab)
-- ============================================================================
function GetControls(props)
  local maxCues = props["Number of Cue Slots"].Value
  local maxActionsPerCue = props["Max Actions per Cue"].Value
  local maxActions = props["Number of Actions"].Value
  local maxDevices = props["Number of Devices"].Value

  local ctrls = {}

  -- Cues -----------------------------------------------------------------
  table.insert(ctrls, { Name = "AddCue", ControlType = "Button", ButtonType = "Trigger", UserPin = false })
  table.insert(ctrls, { Name = "CueStatus", ControlType = "Text", UserPin = false })

  for i = 1, maxCues do
    table.insert(ctrls, { Name = "CueActiveLed_" .. i, ControlType = "Indicator", IndicatorType = "LED", UserPin = false })
    table.insert(ctrls, { Name = "CueName_" .. i, ControlType = "Text", UserPin = false })
    table.insert(ctrls, { Name = "RemoveCue_" .. i, ControlType = "Button", ButtonType = "Trigger", UserPin = false })
    table.insert(ctrls, { Name = "FireCue_" .. i, ControlType = "Button", ButtonType = "Trigger", UserPin = true, PinStyle = "Input" })
    for j = 1, maxActionsPerCue do
      table.insert(ctrls, { Name = "CueAction_" .. i .. "_" .. j, ControlType = "Text", UserPin = false })
    end
  end

  -- Actions ----------------------------------------------------------------
  table.insert(ctrls, { Name = "AddAction", ControlType = "Button", ButtonType = "Trigger", UserPin = false })
  table.insert(ctrls, { Name = "ActionStatus", ControlType = "Text", UserPin = false })

  for a = 1, maxActions do
    table.insert(ctrls, { Name = "ActionName_" .. a, ControlType = "Text", UserPin = false })
    table.insert(ctrls, { Name = "RemoveAction_" .. a, ControlType = "Button", ButtonType = "Trigger", UserPin = false })
    table.insert(ctrls, { Name = "ActionType_" .. a, ControlType = "Text", UserPin = false })

    -- "Set Component Control" fields
    table.insert(ctrls, { Name = "ActionTarget_" .. a, ControlType = "Text", UserPin = false })
    table.insert(ctrls, { Name = "ScanAction_" .. a, ControlType = "Button", ButtonType = "Trigger", UserPin = false })
    table.insert(ctrls, { Name = "ActionControl_" .. a, ControlType = "Text", UserPin = false })
    -- Value input - only one of these three is shown, based on the selected
    -- control's detected type (Boolean / numeric / text).
    table.insert(ctrls, { Name = "ActionValueBool_" .. a, ControlType = "Button", ButtonType = "Toggle", UserPin = false })
    table.insert(ctrls, { Name = "ActionValueNumber_" .. a, ControlType = "Text", UserPin = false })
    table.insert(ctrls, { Name = "ActionValueText_" .. a, ControlType = "Text", UserPin = false })

    -- "Send UDP Message" fields
    table.insert(ctrls, { Name = "ActionDevice_" .. a, ControlType = "Text", UserPin = false })
    table.insert(ctrls, { Name = "ActionUdpMessage_" .. a, ControlType = "Text", UserPin = false })
  end

  -- Devices ------------------------------------------------------------------
  table.insert(ctrls, { Name = "AddDevice", ControlType = "Button", ButtonType = "Trigger", UserPin = false })
  table.insert(ctrls, { Name = "DeviceStatus", ControlType = "Text", UserPin = false })

  for d = 1, maxDevices do
    table.insert(ctrls, { Name = "DeviceName_" .. d, ControlType = "Text", UserPin = false })
    table.insert(ctrls, { Name = "RemoveDevice_" .. d, ControlType = "Button", ButtonType = "Trigger", UserPin = false })
    table.insert(ctrls, { Name = "DeviceIP_" .. d, ControlType = "Text", UserPin = false })
    table.insert(ctrls, { Name = "DevicePort_" .. d, ControlType = "Knob", ControlUnit = "Integer", Min = 1, Max = 65535, UserPin = false })
    table.insert(ctrls, { Name = "TestDevice_" .. d, ControlType = "Button", ButtonType = "Trigger", UserPin = false })
  end

  return ctrls
end

-- ============================================================================
-- Layout (one tab per call, selected via props["page_index"])
-- ============================================================================
function GetControlLayout(props)
  local layout = {}
  local graphics = {}
  local CurrentPage = pagenames[props["page_index"].Value]

  local maxCues = props["Number of Cue Slots"].Value
  local maxActionsPerCue = props["Max Actions per Cue"].Value
  local maxActions = props["Number of Actions"].Value
  local maxDevices = props["Number of Devices"].Value

  local rowHeight = 26
  local top = 56

  if CurrentPage == "Cues" then
    local actionColW = 130
    local actionsX = 216

    table.insert(graphics, { Type = "Header", Text = "Cues", Position = { 8, 8 }, Size = { 600, 20 } })
    table.insert(graphics, { Type = "Text", Text = "Name", Position = { 68, 34 }, Size = { 140, 16 } })
    for j = 1, maxActionsPerCue do
      table.insert(graphics, { Type = "Text", Text = "Action " .. j, Position = { actionsX + (j - 1) * actionColW, 34 }, Size = { actionColW, 16 } })
    end

    for i = 1, maxCues do
      local y = top + (i - 1) * rowHeight

      layout["CueActiveLed_" .. i] = { PrettyName = "Cue " .. i .. " Active", Style = "LED", Color = { 0, 200, 0 }, Position = { 8, y + 3 }, Size = { 16, 16 } }
      layout["RemoveCue_" .. i] = { PrettyName = "Remove Cue " .. i, Legend = "X", Style = "Button", ButtonStyle = "Trigger", Position = { 30, y }, Size = { 24, 22 } }
      layout["CueName_" .. i] = { PrettyName = "Cue " .. i .. " Name", Style = "Text", Position = { 68, y }, Size = { 140, 22 } }

      for j = 1, maxActionsPerCue do
        layout["CueAction_" .. i .. "_" .. j] = {
          PrettyName = "Cue " .. i .. " Action " .. j,
          Style = "ComboBox",
          Position = { actionsX + (j - 1) * actionColW, y },
          Size = { actionColW - 6, 22 },
        }
      end

      local fireX = actionsX + maxActionsPerCue * actionColW
      layout["FireCue_" .. i] = { PrettyName = "Fire Cue " .. i, Legend = "Go", Style = "Button", ButtonStyle = "Trigger", Position = { fireX, y }, Size = { 60, 22 } }
    end

    local bottomY = top + maxCues * rowHeight + 8
    layout["AddCue"] = { PrettyName = "Add Cue", Legend = "+ Add Cue", Style = "Button", ButtonStyle = "Trigger", Position = { 8, bottomY }, Size = { 100, 22 } }
    layout["CueStatus"] = { PrettyName = "Cue Status", Style = "Text", Position = { 116, bottomY }, Size = { 300, 22 } }

  elseif CurrentPage == "Actions" then
    local nameW, typeW, col3W, scanW, col4W, valueW = 130, 160, 130, 40, 150, 110

    local xName = 40
    local xType = xName + nameW + 6
    local xCol3 = xType + typeW + 6
    local xScan = xCol3 + col3W + 4
    local xCol4 = xScan + scanW + 6
    local xValue = xCol4 + col4W + 6

    table.insert(graphics, { Type = "Header", Text = "Actions Library", Position = { 8, 8 }, Size = { 850, 20 } })
    table.insert(graphics, { Type = "Text", Text = "Name", Position = { xName, 34 }, Size = { nameW, 16 } })
    table.insert(graphics, { Type = "Text", Text = "Type", Position = { xType, 34 }, Size = { typeW, 16 } })
    table.insert(graphics, { Type = "Text", Text = "Target / Device", Position = { xCol3, 34 }, Size = { col3W, 16 } })
    table.insert(graphics, { Type = "Text", Text = "Control / Message", Position = { xCol4, 34 }, Size = { col4W, 16 } })
    table.insert(graphics, { Type = "Text", Text = "Value", Position = { xValue, 34 }, Size = { valueW, 16 } })

    for a = 1, maxActions do
      local y = top + (a - 1) * rowHeight

      layout["RemoveAction_" .. a] = { PrettyName = "Remove Action " .. a, Legend = "X", Style = "Button", ButtonStyle = "Trigger", Position = { 8, y }, Size = { 24, 22 } }
      layout["ActionName_" .. a] = { PrettyName = "Action " .. a .. " Name", Style = "Text", Position = { xName, y }, Size = { nameW, 22 } }
      layout["ActionType_" .. a] = { PrettyName = "Action " .. a .. " Type", Style = "ComboBox", Position = { xType, y }, Size = { typeW, 22 } }

      -- Col3: Target Component (component mode) OR Device (UDP mode)
      layout["ActionTarget_" .. a] = { PrettyName = "Action " .. a .. " Target", Style = "Text", Position = { xCol3, y }, Size = { col3W, 22 } }
      layout["ActionDevice_" .. a] = { PrettyName = "Action " .. a .. " Device", Style = "ComboBox", Position = { xCol3, y }, Size = { col3W, 22 } }

      layout["ScanAction_" .. a] = { PrettyName = "Scan Action " .. a .. " Controls", Legend = "Scan", Style = "Button", ButtonStyle = "Trigger", Position = { xScan, y }, Size = { scanW, 22 } }

      -- Col4: Control picker (component mode) OR UDP Message (UDP mode)
      layout["ActionControl_" .. a] = { PrettyName = "Action " .. a .. " Control", Style = "ComboBox", Position = { xCol4, y }, Size = { col4W, 22 } }
      layout["ActionUdpMessage_" .. a] = { PrettyName = "Action " .. a .. " UDP Message", Style = "Text", Position = { xCol4, y }, Size = { col4W, 22 } }

      -- Value column: only one of these three is visible at a time
      layout["ActionValueBool_" .. a] = { PrettyName = "Action " .. a .. " Value (True/False)", Legend = "True/False", Style = "Button", ButtonStyle = "Toggle", Position = { xValue, y }, Size = { valueW, 22 } }
      layout["ActionValueNumber_" .. a] = { PrettyName = "Action " .. a .. " Value (Number)", Style = "Text", Position = { xValue, y }, Size = { valueW, 22 } }
      layout["ActionValueText_" .. a] = { PrettyName = "Action " .. a .. " Value (Text)", Style = "Text", Position = { xValue, y }, Size = { valueW, 22 } }
    end

    local bottomY = top + maxActions * rowHeight + 8
    layout["AddAction"] = { PrettyName = "Add Action", Legend = "+ Add Action", Style = "Button", ButtonStyle = "Trigger", Position = { 8, bottomY }, Size = { 100, 22 } }
    layout["ActionStatus"] = { PrettyName = "Action Status", Style = "Text", Position = { 116, bottomY }, Size = { 400, 22 } }

  elseif CurrentPage == "Devices" then
    local nameW, ipW, portW, testW = 150, 150, 80, 90

    table.insert(graphics, { Type = "Header", Text = "Devices (for UDP)", Position = { 8, 8 }, Size = { 520, 20 } })
    table.insert(graphics, { Type = "Text", Text = "Name", Position = { 40, 34 }, Size = { nameW, 16 } })
    table.insert(graphics, { Type = "Text", Text = "IP Address", Position = { 40 + nameW + 6, 34 }, Size = { ipW, 16 } })
    table.insert(graphics, { Type = "Text", Text = "Port", Position = { 40 + nameW + ipW + 12, 34 }, Size = { portW, 16 } })

    for d = 1, maxDevices do
      local y = top + (d - 1) * rowHeight
      local x = 40

      layout["RemoveDevice_" .. d] = { PrettyName = "Remove Device " .. d, Legend = "X", Style = "Button", ButtonStyle = "Trigger", Position = { 8, y }, Size = { 24, 22 } }
      layout["DeviceName_" .. d] = { PrettyName = "Device " .. d .. " Name", Style = "Text", Position = { x, y }, Size = { nameW, 22 } }
      x = x + nameW + 6
      layout["DeviceIP_" .. d] = { PrettyName = "Device " .. d .. " IP", Style = "Text", Position = { x, y }, Size = { ipW, 22 } }
      x = x + ipW + 6
      layout["DevicePort_" .. d] = { PrettyName = "Device " .. d .. " Port", Style = "Text", Position = { x, y }, Size = { portW, 22 } }
      x = x + portW + 6
      layout["TestDevice_" .. d] = { PrettyName = "Test Device " .. d, Legend = "Test", Style = "Button", ButtonStyle = "Trigger", Position = { x, y }, Size = { testW, 22 } }
    end

    local bottomY = top + maxDevices * rowHeight + 8
    layout["AddDevice"] = { PrettyName = "Add Device", Legend = "+ Add Device", Style = "Button", ButtonStyle = "Trigger", Position = { 8, bottomY }, Size = { 100, 22 } }
    layout["DeviceStatus"] = { PrettyName = "Device Status", Style = "Text", Position = { 116, bottomY }, Size = { 300, 22 } }
  end

  return layout, graphics
end

-- ============================================================================
-- Runtime behavior
-- ============================================================================
if Controls then
  local maxCues = Properties["Number of Cue Slots"].Value
  local maxActionsPerCue = Properties["Max Actions per Cue"].Value
  local maxActions = Properties["Number of Actions"].Value
  local maxDevices = Properties["Number of Devices"].Value

  local cueActive = {}
  local actionActive = {}
  local deviceActive = {}
  local activeCueIndex = nil

  -- [targetComponentName][controlName] = Type string reported by Component.GetControls
  local componentControlTypes = {}

  -- Kept at this scope (not inside a function) so it isn't garbage collected.
  local udpSocket = UdpSocket.New()
  udpSocket:Open()

  -- Best-effort classification of a discovered control's reported Type into
  -- one of "bool" / "number" / "text" / "trigger" / "unknown".
  local function classifyControlType(t)
    if t == nil then return "unknown" end
    local lt = string.lower(tostring(t))
    if string.find(lt, "trigger") then
      return "trigger"
    elseif string.find(lt, "bool") then
      return "bool"
    elseif string.find(lt, "text") or string.find(lt, "string") then
      return "text"
    elseif string.find(lt, "float") or string.find(lt, "integer") or string.find(lt, "int")
        or string.find(lt, "position") or string.find(lt, "gain") or string.find(lt, "value") then
      return "number"
    end
    return "unknown"
  end

  -- Visibility helpers ------------------------------------------------------
  local function setCueRowVisible(i, visible)
    Controls["CueActiveLed_" .. i].IsInvisible = not visible
    Controls["CueName_" .. i].IsInvisible = not visible
    Controls["RemoveCue_" .. i].IsInvisible = not visible
    Controls["FireCue_" .. i].IsInvisible = not visible
    for j = 1, maxActionsPerCue do
      Controls["CueAction_" .. i .. "_" .. j].IsInvisible = not visible
    end
    if not visible then
      Controls["CueActiveLed_" .. i].Boolean = false
    end
  end

  -- Shows/hides the sub-fields of an Action row based on its Type, and (for
  -- "Set Component Control") which value-input matches the selected control.
  local function updateActionRowFields(a)
    local rowVisible = actionActive[a]
    local atype = Controls["ActionType_" .. a].String
    local isComponent = rowVisible and (atype == "Set Component Control")
    local isUdp = rowVisible and (atype == "Send UDP Message")

    Controls["ActionTarget_" .. a].IsInvisible = not isComponent
    Controls["ScanAction_" .. a].IsInvisible = not isComponent
    Controls["ActionControl_" .. a].IsInvisible = not isComponent
    Controls["ActionDevice_" .. a].IsInvisible = not isUdp
    Controls["ActionUdpMessage_" .. a].IsInvisible = not isUdp

    local valueKind = "none"
    if isComponent then
      local target = Controls["ActionTarget_" .. a].String
      local ctrlName = Controls["ActionControl_" .. a].String
      local t = componentControlTypes[target] and componentControlTypes[target][ctrlName]
      valueKind = classifyControlType(t)
    end

    Controls["ActionValueBool_" .. a].IsInvisible = not (valueKind == "bool")
    Controls["ActionValueNumber_" .. a].IsInvisible = not (valueKind == "number" or valueKind == "unknown")
    Controls["ActionValueText_" .. a].IsInvisible = not (valueKind == "text")
  end

  local function setActionRowVisible(a, visible)
    Controls["ActionName_" .. a].IsInvisible = not visible
    Controls["RemoveAction_" .. a].IsInvisible = not visible
    Controls["ActionType_" .. a].IsInvisible = not visible
    updateActionRowFields(a)
  end

  local function setDeviceRowVisible(d, visible)
    Controls["DeviceName_" .. d].IsInvisible = not visible
    Controls["RemoveDevice_" .. d].IsInvisible = not visible
    Controls["DeviceIP_" .. d].IsInvisible = not visible
    Controls["DevicePort_" .. d].IsInvisible = not visible
    Controls["TestDevice_" .. d].IsInvisible = not visible
  end

  local function updateCueStatus()
    local count = 0
    for i = 1, maxCues do if cueActive[i] then count = count + 1 end end
    Controls.CueStatus.String = count .. " / " .. maxCues .. " cue slots used"
  end

  local function updateActionStatus()
    local count = 0
    for a = 1, maxActions do if actionActive[a] then count = count + 1 end end
    Controls.ActionStatus.String = count .. " / " .. maxActions .. " action slots used"
  end

  local function updateDeviceStatus()
    local count = 0
    for d = 1, maxDevices do if deviceActive[d] then count = count + 1 end end
    Controls.DeviceStatus.String = count .. " / " .. maxDevices .. " device slots used"
  end

  -- Keep the Cue-Action dropdowns in sync with the active Action names.
  local function refreshActionChoices()
    local names = { "None" }
    for a = 1, maxActions do
      if actionActive[a] then
        table.insert(names, Controls["ActionName_" .. a].String)
      end
    end
    for i = 1, maxCues do
      for j = 1, maxActionsPerCue do
        Controls["CueAction_" .. i .. "_" .. j].Choices = names
      end
    end
  end

  -- Keep the Action "Device" dropdowns in sync with the active Device names.
  local function refreshDeviceChoices()
    local names = { "None" }
    for d = 1, maxDevices do
      if deviceActive[d] then
        table.insert(names, Controls["DeviceName_" .. d].String)
      end
    end
    for a = 1, maxActions do
      Controls["ActionDevice_" .. a].Choices = names
    end
  end

  local function findActionByName(name)
    for a = 1, maxActions do
      if actionActive[a] and Controls["ActionName_" .. a].String == name then
        return a
      end
    end
    return nil
  end

  local function findDeviceByName(name)
    for d = 1, maxDevices do
      if deviceActive[d] and Controls["DeviceName_" .. d].String == name then
        return d
      end
    end
    return nil
  end

  -- Looks up a Named Component by its Code Name and lists its real controls
  -- (mute, bypass, gain, play, stop, matrix cross-points, etc.) into the
  -- Action's Control dropdown, caching each control's reported Type.
  local function scanComponentControls(a)
    local target = Controls["ActionTarget_" .. a].String

    if target == nil or target == "" then
      Controls["ActionControl_" .. a].Choices = { "" }
      return
    end

    local ok, comp = pcall(Component.New, target)
    if not ok or comp == nil then
      print("LAUPI Cue Creator: could not find a Named Component called '" .. target .. "'.")
      Controls["ActionControl_" .. a].Choices = { "" }
      return
    end

    local ok2, ctrlList = pcall(Component.GetControls, comp)
    if not ok2 or ctrlList == nil then
      print("LAUPI Cue Creator: could not read the controls of '" .. target .. "'.")
      Controls["ActionControl_" .. a].Choices = { "" }
      return
    end

    local names = {}
    componentControlTypes[target] = {}
    for _, c in ipairs(ctrlList) do
      if c.Name then
        table.insert(names, c.Name)
        componentControlTypes[target][c.Name] = c.Type
      end
    end
    table.sort(names)
    Controls["ActionControl_" .. a].Choices = names
  end

  -- Applies a value to a control on another component, using the input
  -- widget that matches its detected type (Trigger / Boolean / number / text).
  local function setComponentControlValue(comp, ctrlName, kind, a)
    local ctrl = comp[ctrlName]
    if not ctrl then return false, "control not found" end

    if kind == "trigger" then
      local ok = pcall(function() ctrl:Trigger() end)
      if ok then return true end
      ok = pcall(function() ctrl.Boolean = true; ctrl.Boolean = false end)
      return ok, (ok and nil or "could not trigger control")

    elseif kind == "bool" then
      local val = Controls["ActionValueBool_" .. a].Boolean
      local ok = pcall(function() ctrl.Boolean = val end)
      return ok, (ok and nil or "could not set Boolean value")

    elseif kind == "text" then
      local txt = Controls["ActionValueText_" .. a].String
      local ok = pcall(function() ctrl.String = txt end)
      return ok, (ok and nil or "could not set text value")

    else -- "number" or "unknown": try numeric first, then fall back generically
      local numStr = Controls["ActionValueNumber_" .. a].String
      local num = tonumber(numStr)
      if num ~= nil then
        local ok = pcall(function() ctrl.Value = num end)
        if ok then return true end
      end
      local ok = pcall(function() ctrl:Trigger() end)
      if ok then return true end
      ok = pcall(function() ctrl.Boolean = true; ctrl.Boolean = false end)
      if ok then return true end
      return false, "unsupported control type or invalid value"
    end
  end

  local function fireAction(a)
    local actionType = Controls["ActionType_" .. a].String
    local actionName = Controls["ActionName_" .. a].String

    if actionType == "Set Component Control" then
      local targetName = Controls["ActionTarget_" .. a].String
      local ctrlName = Controls["ActionControl_" .. a].String

      if targetName == nil or targetName == "" or ctrlName == nil or ctrlName == "" then
        print("LAUPI Cue Creator: action '" .. actionName .. "' needs both a Target Component and a Control selected.")
        return
      end

      local ok, comp = pcall(Component.New, targetName)
      if not ok or comp == nil then
        print("LAUPI Cue Creator: could not find a Named Component called '" .. targetName .. "'.")
        return
      end

      local t = componentControlTypes[targetName] and componentControlTypes[targetName][ctrlName]
      local kind = classifyControlType(t)
      local success, err = setComponentControlValue(comp, ctrlName, kind, a)
      if not success then
        print("LAUPI Cue Creator: action '" .. actionName .. "' failed to set '" .. targetName .. "'.'" .. ctrlName .. "' - " .. tostring(err))
      end

    elseif actionType == "Send UDP Message" then
      local deviceName = Controls["ActionDevice_" .. a].String
      local d = findDeviceByName(deviceName)
      if not d then
        print("LAUPI Cue Creator: action '" .. actionName .. "' has no valid Device selected.")
        return
      end

      local ip = Controls["DeviceIP_" .. d].String
      local port = math.floor(Controls["DevicePort_" .. d].Value)
      local message = Controls["ActionUdpMessage_" .. a].String

      if ip == nil or ip == "" then
        print("LAUPI Cue Creator: device '" .. Controls["DeviceName_" .. d].String .. "' has no IP address set.")
        return
      end

      local ok, err = pcall(function() udpSocket:Send(ip, port, message) end)
      if not ok then
        print("LAUPI Cue Creator: failed to send UDP to " .. ip .. ":" .. port .. " - " .. tostring(err))
      end
    end
  end

  local function setActiveCue(i)
    activeCueIndex = i
    for k = 1, maxCues do
      Controls["CueActiveLed_" .. k].Boolean = (k == i)
    end
  end

  local function fireCue(i)
    setActiveCue(i)
    for j = 1, maxActionsPerCue do
      local actionName = Controls["CueAction_" .. i .. "_" .. j].String
      if actionName ~= nil and actionName ~= "" and actionName ~= "None" then
        local a = findActionByName(actionName)
        if a then
          fireAction(a)
        else
          print("LAUPI Cue Creator: cue '" .. Controls["CueName_" .. i].String .. "' references unknown action '" .. actionName .. "'.")
        end
      end
    end
  end

  -- Cues ----------------------------------------------------------------
  for i = 1, maxCues do
    cueActive[i] = (i == 1)

    if Controls["CueName_" .. i].String == "" then
      Controls["CueName_" .. i].String = "Cue " .. i
    end
    for j = 1, maxActionsPerCue do
      if Controls["CueAction_" .. i .. "_" .. j].String == "" then
        Controls["CueAction_" .. i .. "_" .. j].String = "None"
      end
    end

    Controls["CueActiveLed_" .. i].Boolean = false
    setCueRowVisible(i, cueActive[i])

    Controls["FireCue_" .. i].EventHandler = function()
      fireCue(i)
    end

    Controls["RemoveCue_" .. i].EventHandler = function()
      cueActive[i] = false
      setCueRowVisible(i, false)
      if activeCueIndex == i then
        setActiveCue(nil)
      end
      updateCueStatus()
    end
  end

  Controls.AddCue.EventHandler = function()
    for i = 1, maxCues do
      if not cueActive[i] then
        cueActive[i] = true
        setCueRowVisible(i, true)
        updateCueStatus()
        return
      end
    end
    print("LAUPI Cue Creator: all " .. maxCues .. " cue slots are in use. Increase 'Number of Cue Slots' in the component Properties to add more.")
  end

  -- Actions --------------------------------------------------------------
  for a = 1, maxActions do
    actionActive[a] = (a == 1)

    if Controls["ActionName_" .. a].String == "" then
      Controls["ActionName_" .. a].String = "Action " .. a
    end
    if Controls["ActionType_" .. a].String == "" then
      Controls["ActionType_" .. a].String = "None"
    end
    Controls["ActionType_" .. a].Choices = { "None", "Set Component Control", "Send UDP Message" }
    Controls["ActionControl_" .. a].Choices = { "" }

    setActionRowVisible(a, actionActive[a])

    if Controls["ActionTarget_" .. a].String ~= "" then
      scanComponentControls(a)
      updateActionRowFields(a)
    end

    Controls["ActionName_" .. a].EventHandler = function()
      refreshActionChoices()
    end

    Controls["ActionType_" .. a].EventHandler = function()
      updateActionRowFields(a)
    end

    Controls["ActionTarget_" .. a].EventHandler = function()
      scanComponentControls(a)
      updateActionRowFields(a)
    end

    Controls["ScanAction_" .. a].EventHandler = function()
      scanComponentControls(a)
      updateActionRowFields(a)
    end

    Controls["ActionControl_" .. a].EventHandler = function()
      updateActionRowFields(a)
    end

    Controls["RemoveAction_" .. a].EventHandler = function()
      actionActive[a] = false
      setActionRowVisible(a, false)
      updateActionStatus()
      refreshActionChoices()
    end
  end

  Controls.AddAction.EventHandler = function()
    for a = 1, maxActions do
      if not actionActive[a] then
        actionActive[a] = true
        setActionRowVisible(a, true)
        updateActionStatus()
        refreshActionChoices()
        return
      end
    end
    print("LAUPI Cue Creator: all " .. maxActions .. " action slots are in use. Increase 'Number of Actions' in the component Properties to add more.")
  end

  -- Devices --------------------------------------------------------------
  for d = 1, maxDevices do
    deviceActive[d] = (d == 1)

    if Controls["DeviceName_" .. d].String == "" then
      Controls["DeviceName_" .. d].String = "Device " .. d
    end

    setDeviceRowVisible(d, deviceActive[d])

    Controls["DeviceName_" .. d].EventHandler = function()
      refreshDeviceChoices()
    end

    Controls["RemoveDevice_" .. d].EventHandler = function()
      deviceActive[d] = false
      setDeviceRowVisible(d, false)
      updateDeviceStatus()
      refreshDeviceChoices()
    end

    Controls["TestDevice_" .. d].EventHandler = function()
      local ip = Controls["DeviceIP_" .. d].String
      local port = math.floor(Controls["DevicePort_" .. d].Value)
      if ip == nil or ip == "" then
        print("LAUPI Cue Creator: set an IP address before testing device '" .. Controls["DeviceName_" .. d].String .. "'.")
        return
      end
      local ok, err = pcall(function() udpSocket:Send(ip, port, "LAUPI Cue Creator test") end)
      if ok then
        print("LAUPI Cue Creator: test UDP packet sent to " .. ip .. ":" .. port)
      else
        print("LAUPI Cue Creator: failed to send test packet - " .. tostring(err))
      end
    end
  end

  Controls.AddDevice.EventHandler = function()
    for d = 1, maxDevices do
      if not deviceActive[d] then
        deviceActive[d] = true
        setDeviceRowVisible(d, true)
        updateDeviceStatus()
        refreshDeviceChoices()
        return
      end
    end
    print("LAUPI Cue Creator: all " .. maxDevices .. " device slots are in use. Increase 'Number of Devices' in the component Properties to add more.")
  end

  updateCueStatus()
  updateActionStatus()
  updateDeviceStatus()
  refreshActionChoices()
  refreshDeviceChoices()
end
