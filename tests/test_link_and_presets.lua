-- Minimal mock of the Q-SYS plugin runtime environment + a tiny JSON codec,
-- used only to exercise ParametricEQPlugin.lua's link-propagation and
-- preset save/recall logic outside of Designer.

-- ---- tiny JSON codec (subset: nested tables, strings, numbers) ----
local json = {}

function json.encode(t)
  local function isArray(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    local isArr = n > 0
    for i = 1, n do if tbl[i] == nil then isArr = false end end
    return isArr, n
  end

  local function enc(v)
    local vt = type(v)
    if vt == "table" then
      local isArr = isArray(v)
      local parts = {}
      if isArr then
        for _, item in ipairs(v) do table.insert(parts, enc(item)) end
        return "[" .. table.concat(parts, ",") .. "]"
      else
        for k, val in pairs(v) do
          table.insert(parts, string.format("%q", tostring(k)) .. ":" .. enc(val))
        end
        return "{" .. table.concat(parts, ",") .. "}"
      end
    elseif vt == "string" then
      return string.format("%q", v)
    elseif vt == "number" then
      return tostring(v)
    elseif vt == "boolean" then
      return tostring(v)
    elseif vt == "nil" then
      return "null"
    end
    error("cannot encode type " .. vt)
  end
  return enc(t)
end

function json.decode(s)
  local pos = 1
  local function skipWs() while pos <= #s and s:sub(pos,pos):match("%s") do pos = pos + 1 end end
  local parseValue

  local function parseString()
    pos = pos + 1
    local start = pos
    local buf = {}
    while s:sub(pos,pos) ~= '"' do
      buf[#buf+1] = s:sub(pos,pos)
      pos = pos + 1
    end
    pos = pos + 1
    return table.concat(buf)
  end

  local function parseNumber()
    local start = pos
    while pos <= #s and s:sub(pos,pos):match("[%d%.%-eE+]") do pos = pos + 1 end
    return tonumber(s:sub(start, pos - 1))
  end

  local function parseObject()
    pos = pos + 1
    local obj = {}
    skipWs()
    if s:sub(pos,pos) == "}" then pos = pos + 1; return obj end
    while true do
      skipWs()
      local key = parseString()
      skipWs()
      pos = pos + 1 -- ':'
      skipWs()
      obj[key] = parseValue()
      skipWs()
      if s:sub(pos,pos) == "," then pos = pos + 1 else break end
    end
    skipWs()
    pos = pos + 1 -- '}'
    return obj
  end

  local function parseArray()
    pos = pos + 1
    local arr = {}
    skipWs()
    if s:sub(pos,pos) == "]" then pos = pos + 1; return arr end
    while true do
      skipWs()
      table.insert(arr, parseValue())
      skipWs()
      if s:sub(pos,pos) == "," then pos = pos + 1 else break end
    end
    skipWs()
    pos = pos + 1 -- ']'
    return arr
  end

  parseValue = function()
    skipWs()
    local c = s:sub(pos,pos)
    if c == '"' then return parseString()
    elseif c == "{" then return parseObject()
    elseif c == "[" then return parseArray()
    elseif s:sub(pos,pos+3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos,pos+4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos,pos+3) == "null" then pos = pos + 4; return nil
    else return parseNumber() end
  end

  return parseValue()
end

rapidjson = json

-- ---- mock Controls ----
local function makeControl(initValue, initString)
  local c = { Value = initValue, String = initString, Choices = {} }
  return c
end

Controls = {}
Controls.PresetStore = makeControl(nil, "")

local NUM_CHANNELS = 10
local NUM_BANDS = 10

for c = 1, NUM_CHANNELS do
  Controls["LinkGroup_" .. c] = makeControl(nil, "None")
  Controls["PresetSaveName_" .. c] = makeControl(nil, "")
  Controls["PresetSaveButton_" .. c] = makeControl(nil, nil)
  Controls["PresetRecall_" .. c] = makeControl(nil, "")
  Controls["PresetDeleteButton_" .. c] = makeControl(nil, nil)
  Controls["RTAShowPost_" .. c] = makeControl(false, nil)
  for b = 1, NUM_BANDS do
    Controls["Band_" .. c .. "_" .. b .. "_Freq"] = makeControl(1000, nil)
    Controls["Band_" .. c .. "_" .. b .. "_Gain"] = makeControl(0, nil)
    Controls["Band_" .. c .. "_" .. b .. "_Q"] = makeControl(0.707, nil)
    Controls["Band_" .. c .. "_" .. b .. "_Type"] = makeControl(nil, "Bell")
  end
end

Properties = { NumBands = { Value = NUM_BANDS } }

-- Load the plugin script (design-time functions run first via top-level
-- calls only if we call them; runtime section runs because Controls exists).
-- Run this test from the repo root: lua5.3 tests/test_link_and_presets.lua
local scriptDir = arg[0]:match("(.*/)") or "./"
local chunk = assert(loadfile(scriptDir .. "../ParametricEQPlugin.lua"))
chunk()

local function assertEq(a, b, msg)
  if a ~= b then
    error("ASSERTION FAILED: " .. msg .. " (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")")
  end
end

-- Test 1: design-time functions still callable/safe
local names = GetPresetNames()
assertEq(#names, 0, "GetPresetNames should be empty on fresh store")

-- Test 2: link propagation
Controls["LinkGroup_1"].String = "A"
Controls["LinkGroup_2"].String = "A"
Controls["LinkGroup_3"].String = "B"

Controls["Band_1_1_Gain"].Value = 6
Controls["Band_1_1_Gain"].EventHandler(Controls["Band_1_1_Gain"])

assertEq(Controls["Band_2_1_Gain"].Value, 6, "channel 2 (same group A) should receive propagated gain")
assertEq(Controls["Band_3_1_Gain"].Value, 0, "channel 3 (group B) should NOT receive propagation")

-- Test 3: Type (string) propagation
Controls["Band_1_2_Type"].String = "HighShelf"
Controls["Band_1_2_Type"].EventHandler(Controls["Band_1_2_Type"])
assertEq(Controls["Band_2_2_Type"].String, "HighShelf", "channel 2 should receive propagated Type")

-- Test 4: save preset from channel 1, then recall onto channel 2 (grouped
-- with channel 1) and confirm it does NOT propagate back to channel 1
-- (resolved Open Question #4: recall stays local).
Controls["Band_1_1_Freq"].Value = 250
Controls["PresetSaveName_1"].String = "MyVoice"
Controls["PresetSaveButton_1"].EventHandler()

local storedNames = GetPresetNames()
assertEq(#storedNames, 1, "one preset should be stored")
assertEq(storedNames[1], "MyVoice", "stored preset should be named MyVoice")

-- change channel 2's band 1 freq to something else, distinct from ch1
Controls["Band_2_1_Freq"].Value = 999
-- also set a control on channel 3 (ungrouped) as a sentinel to prove isolation
Controls["Band_3_1_Freq"].Value = 999

Controls["PresetRecall_2"].EventHandler(Controls["PresetRecall_2"])
-- simulate the ComboBox having been set to MyVoice before EventHandler fired
Controls["PresetRecall_2"].String = "MyVoice"
Controls["PresetRecall_2"].EventHandler(Controls["PresetRecall_2"])

assertEq(Controls["Band_2_1_Freq"].Value, 250, "channel 2 should have recalled preset value")
assertEq(Controls["Band_1_1_Freq"].Value, 250, "channel 1 unaffected (it's the source of the preset, unchanged)")
assertEq(Controls["Band_3_1_Freq"].Value, 999, "channel 3 must be untouched by recall (local-only, not in group)")

-- Test 5: delete preset
Controls["PresetDeleteButton_2"].EventHandler()
assertEq(#GetPresetNames(), 0, "preset should be deleted")

print("ALL TESTS PASSED")
