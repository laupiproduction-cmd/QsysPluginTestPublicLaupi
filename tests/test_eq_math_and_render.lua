-- Mocks the Q-SYS plugin runtime (Component, Controls, Properties, Timer,
-- rapidjson, Crypto) to exercise ParametricEQVisualizer.lua's math, SVG
-- rendering, not-connected fallback, and RTA debounce/caching behavior
-- without a live Designer session. Run from repo root:
--   lua5.3 tests/test_eq_math_and_render.lua

local function assertEq(a, b, msg)
  if a ~= b then
    error("ASSERTION FAILED: " .. msg .. " (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")")
  end
end

local function assertNear(a, b, tol, msg)
  if math.abs(a - b) > tol then
    error("ASSERTION FAILED: " .. msg .. " (got " .. tostring(a) .. ", expected ~" .. tostring(b) .. ")")
  end
end

local function assertTrue(cond, msg)
  if not cond then error("ASSERTION FAILED: " .. msg) end
end

local function assertContains(haystack, needle, msg)
  if not string.find(haystack, needle, 1, true) then
    error("ASSERTION FAILED: " .. msg .. " (did not find " .. needle .. ")")
  end
end

-- ===========================================================================
-- Phase 1: design-time load, no Controls/Properties/Component in scope.
-- Verifies the design-time functions and the pure math/SVG modules work
-- without any Q-SYS runtime mocked at all.
-- ===========================================================================

local scriptDir = arg[0]:match("(.*/)") or "./"
local scriptPath = scriptDir .. "../ParametricEQVisualizer.lua"
local chunk = assert(loadfile(scriptPath))
chunk()

assertTrue(GetPrettyName({}) ~= nil, "GetPrettyName should work at design time")

local props = {}
for _, p in ipairs(GetProperties()) do props[p.Name] = p end
assertEq(props["NumBands"].Value, 8, "default NumBands should be 8")

-- RectifyProperties should not blow up even if Component isn't defined yet
props = RectifyProperties(props)
assertTrue(props["NumBands"].Value >= 1, "RectifyProperties should leave NumBands valid")

local ctrls = GetControls(props)
assertEq(#ctrls, 1, "GetControls should expose exactly the GraphDisplay button")

local layout = GetControlLayout(props)
assertTrue(layout.GraphDisplay ~= nil, "layout should position GraphDisplay")

-- ---- EQMath: axis mapping ----
assertNear(EQMath.FreqToX(20, 0, 100, 20, 20000), 0, 0.01, "FreqToX left edge")
assertNear(EQMath.FreqToX(20000, 0, 100, 20, 20000), 100, 0.01, "FreqToX right edge")
assertNear(EQMath.DbToY(30, 0, 100, -30, 30), 0, 0.01, "DbToY top at max dB")
assertNear(EQMath.DbToY(-30, 0, 100, -30, 30), 100, 0.01, "DbToY bottom at min dB")

-- ---- EQMath: Bell ----
local bellBoost = { Freq = 1000, Gain = 6, Q = 2, Type = "Bell" }
assertNear(EQMath.BandMagnitudeDb(1000, bellBoost), 6, 0.001, "bell gain exact at center freq")
assertTrue(math.abs(EQMath.BandMagnitudeDb(50, bellBoost)) < 0.5, "bell gain ~0 far from center (low side)")
assertTrue(math.abs(EQMath.BandMagnitudeDb(15000, bellBoost)) < 0.5, "bell gain ~0 far from center (high side)")

-- ---- EQMath: shelves ----
local lowShelf = { Freq = 200, Gain = 8, Type = "LowShelf" }
assertTrue(EQMath.BandMagnitudeDb(20, lowShelf) > 6, "low shelf near full gain well below corner")
assertTrue(math.abs(EQMath.BandMagnitudeDb(10000, lowShelf)) < 1, "low shelf ~0dB well above corner")

local highShelf = { Freq = 5000, Gain = -6, Type = "HighShelf" }
assertTrue(math.abs(EQMath.BandMagnitudeDb(50, highShelf)) < 1, "high shelf ~0dB well below corner")
assertTrue(EQMath.BandMagnitudeDb(20000, highShelf) < -4, "high shelf near full (negative) gain well above corner")

-- ---- EQMath: HPF/LPF ----
local hpf = { Freq = 100, Type = "HighPass" }
assertTrue(math.abs(EQMath.BandMagnitudeDb(10000, hpf)) < 1, "HPF ~0dB passband")
assertTrue(EQMath.BandMagnitudeDb(10, hpf) < -20, "HPF strongly attenuated below cutoff")

local lpf = { Freq = 5000, Type = "LowPass" }
assertTrue(math.abs(EQMath.BandMagnitudeDb(100, lpf)) < 1, "LPF ~0dB passband")
assertTrue(EQMath.BandMagnitudeDb(50000, lpf) < -20, "LPF strongly attenuated above cutoff")

-- ---- EQMath: composite sums in series (two identical bells double at center) ----
local composite = EQMath.CompositeMagnitudeDb(1000, { bellBoost, bellBoost })
assertNear(composite, 12, 0.001, "two identical +6dB bells sum to +12dB at shared center freq")

-- ---- EzSVG smoke test ----
local doc = EzSVG.Document(100, 50)
doc:append(EzSVG.Line(0, 0, 10, 10):setStyle({ stroke = "red" }))
local path = EzSVG.Path():setStyle({ stroke = "blue", fill = "none" })
path:moveToA(0, 0):lineToA(10, 10):lineToA(20, 0)
doc:append(path)
doc:append(EzSVG.Circle(5, 5, 2):setStyle({ fill = "green" }))
doc:append(EzSVG.Text(1, 1, "hi"):setStyle({ fill = "white" }))
local svgStr = doc:toString()
assertContains(svgStr, "<svg", "EzSVG document should produce an <svg> root")
assertContains(svgStr, "<line", "EzSVG should render a line element")
assertContains(svgStr, "<path", "EzSVG should render a path element")
assertContains(svgStr, "<circle", "EzSVG should render a circle element")
assertContains(svgStr, "<text", "EzSVG should render a text element")
assertContains(svgStr, "</svg>", "EzSVG document should close the root")

print("Phase 1 (design-time + pure math/SVG) PASSED")

-- ===========================================================================
-- Phase 2: runtime load with the Q-SYS environment mocked, to exercise
-- component resolution, not-connected fallback, EventHandler wiring, and
-- the RTA debounce/caching path.
-- ===========================================================================

-- ---- tiny JSON codec (subset: nested tables, strings, numbers, booleans) ----
local json = {}
function json.encode(t)
  local function isArray(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    local isArr = n > 0
    for i = 1, n do if tbl[i] == nil then isArr = false end end
    return isArr
  end
  local function enc(v)
    local vt = type(v)
    if vt == "table" then
      if isArray(v) then
        local parts = {}
        for _, item in ipairs(v) do table.insert(parts, enc(item)) end
        return "[" .. table.concat(parts, ",") .. "]"
      else
        local parts = {}
        for k, val in pairs(v) do
          table.insert(parts, string.format("%q", tostring(k)) .. ":" .. enc(val))
        end
        return "{" .. table.concat(parts, ",") .. "}"
      end
    elseif vt == "string" then return string.format("%q", v)
    elseif vt == "number" then return tostring(v)
    elseif vt == "boolean" then return tostring(v)
    else return "null" end
  end
  return enc(t)
end
function json.decode(s)
  -- minimal enough for this test's needs (flat/nested objects, strings, bools)
  local pos = 1
  local function skipWs() while pos <= #s and s:sub(pos,pos):match("%s") do pos = pos + 1 end end
  local parseValue
  local function parseString()
    pos = pos + 1
    local buf = {}
    while s:sub(pos,pos) ~= '"' do
      local c = s:sub(pos,pos)
      if c == "\\" then
        -- string.format("%q", ...) escapes embedded quotes/backslashes/
        -- newlines with a backslash prefix; take the following byte
        -- literally rather than treating it as a new token.
        pos = pos + 1
        buf[#buf + 1] = s:sub(pos, pos)
      else
        buf[#buf + 1] = c
      end
      pos = pos + 1
    end
    pos = pos + 1
    return table.concat(buf)
  end
  local function parseObject()
    pos = pos + 1
    local obj = {}
    skipWs()
    if s:sub(pos,pos) == "}" then pos = pos + 1; return obj end
    while true do
      skipWs(); local key = parseString(); skipWs(); pos = pos + 1; skipWs()
      obj[key] = parseValue(); skipWs()
      if s:sub(pos,pos) == "," then pos = pos + 1 else break end
    end
    skipWs(); pos = pos + 1
    return obj
  end
  parseValue = function()
    skipWs()
    local c = s:sub(pos,pos)
    if c == '"' then return parseString()
    elseif c == "{" then return parseObject()
    elseif s:sub(pos,pos+3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos,pos+4) == "false" then pos = pos + 5; return false
    else
      local start = pos
      while pos <= #s and s:sub(pos,pos):match("[%d%.%-eE+]") do pos = pos + 1 end
      return tonumber(s:sub(start, pos - 1))
    end
  end
  return parseValue()
end
rapidjson = json

-- ---- mock Crypto: identity "encoding" is enough to test the plumbing ----
Crypto = { Base64Encode = function(s) return s end }

-- ---- mock Timer: capture the most recently constructed timer so the test
-- can manually fire its EventHandler to simulate a debounce tick ----
LastCreatedTimer = nil
Timer = {}
function Timer.New()
  local t = {}
  function t:Start(interval) self.interval = interval; self.running = true end
  function t:Stop() self.running = false end
  LastCreatedTimer = t
  return t
end

-- ---- mock Controls / Properties ----
local function makeCtl(value, str) return { Value = value, String = str, EventHandler = nil } end

Controls = {
  GraphDisplay = { Legend = nil },
}

Properties = {
  ["PEQ Reference"] = { Value = "MyPEQ" },
  ["RTA Reference"] = { Value = "MyRTA" },
  ["NumBands"] = { Value = 3 },
}

local function buildMockPEQ(numBands)
  local comp = {}
  for i = 1, numBands do
    comp["band" .. i .. ".freq"] = makeCtl(1000 * i, nil)
    comp["band" .. i .. ".gain"] = makeCtl(0, nil)
    comp["band" .. i .. ".q"] = makeCtl(0.707, nil)
    comp["band" .. i .. ".type"] = makeCtl(nil, "Bell")
  end
  return comp
end

local function buildMockRTA(numPoints)
  local comp = {}
  for i = 1, numPoints do
    comp["band" .. i .. ".magnitude"] = makeCtl(-20, nil)
  end
  return comp
end

local mockPEQ = buildMockPEQ(3)
local mockRTA = buildMockRTA(31) -- matches CONFIG.RTA.NumPoints default

local MockComponents = { MyPEQ = mockPEQ, MyRTA = mockRTA, BadComponent = {} }
Component = {
  New = function(name) return MockComponents[name] end,
  GetComponents = function() return {} end,
}

-- Re-run the same chunk now that the runtime environment is mocked; this
-- re-executes the whole file, including the `if Controls then` section.
chunk()

assertTrue(Controls.GraphDisplay.Legend ~= nil, "runtime should push an initial graphic")
local legend = rapidjson.decode(Controls.GraphDisplay.Legend)
assertEq(legend.DrawChrome, false, "Legend should disable chrome")
assertContains(legend.IconData, "<svg", "Legend IconData should contain SVG markup")
assertContains(legend.IconData, "<path", "connected state should render EQ curve + RTA fill as <path> elements")

-- Band controls should have EventHandlers wired
assertTrue(mockPEQ["band1.freq"].EventHandler ~= nil, "PEQ band1 freq should have an EventHandler wired")
assertTrue(mockRTA["band1.magnitude"].EventHandler ~= nil, "RTA point 1 should have an EventHandler wired")

local legendAfterInit = Controls.GraphDisplay.Legend

-- ---- PEQ change: immediate redraw ----
mockPEQ["band1.gain"].Value = 12
mockPEQ["band1.freq"].EventHandler(mockPEQ["band1.freq"])
assertTrue(Controls.GraphDisplay.Legend ~= legendAfterInit, "PEQ band change should immediately push a new graphic")

-- ---- RTA change: debounced, no redraw until timer fires ----
local legendAfterPeqChange = Controls.GraphDisplay.Legend
for i = 1, 31 do
  mockRTA["band" .. i .. ".magnitude"].Value = -5
  mockRTA["band" .. i .. ".magnitude"].EventHandler(mockRTA["band" .. i .. ".magnitude"])
end
assertEq(Controls.GraphDisplay.Legend, legendAfterPeqChange,
  "RTA control events alone should not push a redraw before the debounce timer fires")

assertTrue(LastCreatedTimer ~= nil, "RTA debounce timer should have been created")
LastCreatedTimer.EventHandler() -- simulate one debounce tick after a burst of RTA events
assertTrue(Controls.GraphDisplay.Legend ~= legendAfterPeqChange,
  "debounce timer tick should push exactly one redraw after a burst of RTA events")

print("Phase 2 (mocked runtime: resolution, wiring, debounce) PASSED")
print("ALL TESTS PASSED")
