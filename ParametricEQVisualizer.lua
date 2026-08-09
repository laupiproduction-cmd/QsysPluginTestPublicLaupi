--[[
  Parametric EQ + RTA Visualizer Plugin — Control Script

  Wraps an existing native Parametric Equalizer component and an existing
  native Real-Time Analyzer component: draws the EQ curve and RTA spectrum
  on one combined graph via an SVG-in-Button-Legend graphic, and lets the
  operator drag band points to rewrite the PEQ component's controls.

  This file was written WITHOUT access to Q-SYS Designer, so it cannot
  verify the native components' exact control names/ranges/format, or the
  draggable-point interaction mechanism. Every place that depends on one of
  those is isolated in the CONFIG table below or explicitly stubbed with a
  "NOT IMPLEMENTED — see BUILD_NOTES.md" marker. See BUILD_NOTES.md for the
  full list of open questions and what to verify before this is production
  ready.

  Implemented and unit-tested independent of any live component (see
  tests/test_eq_math_and_render.lua): log-frequency/dB axis mapping, per-
  band-type magnitude-response math (Bell/LowShelf/HighShelf/HPF/LPF/
  Notch), composite curve summation, "not connected" degraded rendering,
  and RTA-update debounce/redraw caching.

  NOT implemented (explicit product decision — see BUILD_NOTES.md):
  draggable band-point interaction. The spec calls for verifying this
  against QSC's stock Positioner/PEQ plugin source before writing it; that
  verification requires Designer access this environment doesn't have.
  Band points are drawn as static (non-draggable) markers for now.
]]--

PluginInfo = {
  Name = "UCI~Parametric EQ + RTA Visualizer",
  Version = "0.1.0",
  Id = "com.laupiproduction.plugins.peqrtavisualizer",
  Description = "Combined EQ curve / before-after-style RTA overlay for an existing native PEQ + RTA pair",
  ShowDebug = true,
}

function GetColor(props)
  return { 60, 120, 200 }
end

function GetPrettyName(props)
  return "PEQ + RTA Visualizer"
end

-- ===========================================================================
-- CONFIG — every assumption about the native components' control names,
-- ranges, and data format lives here. VERIFY each marked field against the
-- real components in a live Designer session before relying on this in a
-- show; see BUILD_NOTES.md for the checklist. Changing an assumption should
-- only ever require editing this table, not the logic below it.
-- ===========================================================================

local CONFIG = {
  PEQ = {
    -- VERIFY: real native Parametric EQ control-name pattern. Placeholder
    -- assumes "band<N>.freq" / "band<N>.gain" / "band<N>.q" / "band<N>.type".
    BandControlName = function(bandIndex, param)
      local suffix = ({ Freq = "freq", Gain = "gain", Q = "q", Type = "type" })[param]
      return "band" .. bandIndex .. "." .. suffix
    end,

    -- VERIFY: does the native PEQ actually expose a per-band Type control?
    -- If not, HasTypeControl=false makes every band render as Bell.
    HasTypeControl = true,

    -- VERIFY: exact type strings the native control uses. Placeholder set
    -- matches the spec's assumed list.
    TypeValues = {
      Bell = "Bell",
      LowShelf = "LowShelf",
      HighShelf = "HighShelf",
      HighPass = "HighPass",
      LowPass = "LowPass",
      Notch = "Notch",
    },

    -- VERIFY: real native gain/freq/Q ranges — used for axis bounds and to
    -- clamp interaction (once interaction exists). Placeholder is a common
    -- broad default, not the confirmed component limit.
    FreqMin = 20,
    FreqMax = 20000,
    GainMin = -24,
    GainMax = 24,
    QMin = 0.1,
    QMax = 10,
  },

  RTA = {
    -- VERIFY: "per_band" (one control per magnitude point, indexed like PEQ
    -- bands) vs "array_blob" (single control holding an encoded array).
    -- Placeholder assumes per_band; ReadRTAMagnitudes() below has both paths
    -- implemented so switching this one flag is enough once confirmed.
    Mode = "per_band",

    -- VERIFY: real control name pattern if Mode == "per_band".
    PerBandControlName = function(pointIndex)
      return "band" .. pointIndex .. ".magnitude"
    end,
    NumPoints = 31, -- VERIFY: how many magnitude points the RTA exposes

    -- VERIFY: real control name if Mode == "array_blob", and its encoding
    -- (this assumes a JSON array of {freq=, mag=} via rapidjson).
    ArrayBlobControlName = "Spectrum",

    -- VERIFY (explicit open question in the spec): is RTA output already in
    -- dB, or linear magnitude needing 20*log10() before it's plotted on the
    -- same dB-scaled axis as the EQ curve?
    OutputIsDB = true,

    FreqMin = 20,
    FreqMax = 20000,
  },

  Graph = {
    Width = 600,
    Height = 300,
    Margin = 24,
    -- Shared y-axis bounds. VERIFY these bracket the real PEQ gain range
    -- (CONFIG.PEQ.GainMin/Max above) and a sensible RTA display floor.
    DbMin = -30,
    DbMax = 30,
    CurveSamples = 128, -- frequency points sampled for the EQ curve
    RedrawHz = 25,       -- debounce rate for RTA-driven redraws (spec: 20-30 Hz)
  },
}

-- ===========================================================================
-- Properties — PEQ/RTA Named Component references + band count, resolved at
-- design time by the integrator (never hardcoded component names).
-- ===========================================================================

function GetProperties()
  return {
    { Name = "PEQ Reference", Type = "string", Value = "" },
    { Name = "RTA Reference", Type = "string", Value = "" },
    { Name = "NumBands", Type = "integer", Min = 1, Max = 31, Value = 8 },
  }
end

function RectifyProperties(props)
  -- Populate PEQ/RTA Reference as dropdowns of components already in the
  -- design, per "do not hardcode component names — use the properties API
  -- to resolve these references." VERIFY Component.GetComponents() is
  -- available/behaves this way in your Designer version; if not, the
  -- properties still work as free-typed component-name strings.
  local ok, components = pcall(function() return Component.GetComponents() end)
  if ok and type(components) == "table" then
    local names = {}
    for _, c in ipairs(components) do
      if c.Name then table.insert(names, c.Name) end
    end
    table.sort(names)
    props["PEQ Reference"].Choices = names
    props["RTA Reference"].Choices = names
  end

  if props["NumBands"].Value < 1 then
    props["NumBands"].Value = 1
  elseif props["NumBands"].Value > 31 then
    props["NumBands"].Value = 31
  end

  return props
end

-- ===========================================================================
-- Controls — a single Button used as the SVG canvas via the Legend/IconData
-- trick (DrawChrome=false + base64 SVG IconData). No per-band UI controls
-- here: interaction is stubbed (see header comment / BUILD_NOTES.md), so
-- there is nothing yet for the operator to directly manipulate.
-- ===========================================================================

function GetControls(props)
  return {
    { Name = "GraphDisplay", ControlType = "Button", ButtonType = "Trigger", UserPin = false },
  }
end

function GetControlLayout(props)
  local w, h = CONFIG.Graph.Width, CONFIG.Graph.Height
  return {
    GraphDisplay = {
      PrettyName = "EQ / RTA Graph",
      Style = "Button",
      Position = { 10, 10 },
      Size = { w, h },
    },
  }, {}
end

-- ===========================================================================
-- Pure helper module: minimal EzSVG-compatible SVG builder (Document, Path,
-- Line, Circle, Text; moveToA/lineToA/setStyle/toString). Written from
-- scratch for this plugin — no external EzSVG library was available to pull
-- in. API shape intentionally matches the spec's vocabulary so a real EzSVG
-- library can be swapped in later with minimal churn.
--
-- Defined at file scope (not inside the `if Controls then` runtime guard)
-- so it can be exercised by unit tests without mocking the Q-SYS runtime.
-- ===========================================================================

EzSVG = {}

local function styleToString(style)
  local parts = {}
  local keys = {}
  for k in pairs(style) do table.insert(keys, k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    table.insert(parts, string.format("%s:%s", k, tostring(style[k])))
  end
  return table.concat(parts, ";")
end

local Document = {}
Document.__index = Document
function EzSVG.Document(width, height)
  return setmetatable({ width = width, height = height, children = {} }, Document)
end
function Document:append(element)
  table.insert(self.children, element)
  return element
end
function Document:toString()
  local parts = {
    string.format(
      '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">',
      self.width, self.height, self.width, self.height),
  }
  for _, child in ipairs(self.children) do
    table.insert(parts, child:toString())
  end
  table.insert(parts, "</svg>")
  return table.concat(parts)
end
EzSVG.Document_mt = Document

local Path = {}
Path.__index = Path
function EzSVG.Path()
  return setmetatable({ commands = {}, style = {} }, Path)
end
function Path:moveToA(x, y)
  table.insert(self.commands, string.format("M%.2f,%.2f", x, y))
  return self
end
function Path:lineToA(x, y)
  table.insert(self.commands, string.format("L%.2f,%.2f", x, y))
  return self
end
function Path:close()
  table.insert(self.commands, "Z")
  return self
end
function Path:setStyle(style)
  for k, v in pairs(style) do self.style[k] = v end
  return self
end
function Path:toString()
  if #self.commands == 0 then return "" end
  return string.format('<path d="%s" style="%s" />',
    table.concat(self.commands, " "), styleToString(self.style))
end

local Line = {}
Line.__index = Line
function EzSVG.Line(x1, y1, x2, y2)
  return setmetatable({ x1 = x1, y1 = y1, x2 = x2, y2 = y2, style = {} }, Line)
end
function Line:setStyle(style)
  for k, v in pairs(style) do self.style[k] = v end
  return self
end
function Line:toString()
  return string.format('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" style="%s" />',
    self.x1, self.y1, self.x2, self.y2, styleToString(self.style))
end

local Circle = {}
Circle.__index = Circle
function EzSVG.Circle(cx, cy, r)
  return setmetatable({ cx = cx, cy = cy, r = r, style = {} }, Circle)
end
function Circle:setStyle(style)
  for k, v in pairs(style) do self.style[k] = v end
  return self
end
function Circle:toString()
  return string.format('<circle cx="%.2f" cy="%.2f" r="%.2f" style="%s" />',
    self.cx, self.cy, self.r, styleToString(self.style))
end

local Text = {}
Text.__index = Text
function EzSVG.Text(x, y, str)
  return setmetatable({ x = x, y = y, str = str, style = {} }, Text)
end
function Text:setStyle(style)
  for k, v in pairs(style) do self.style[k] = v end
  return self
end
function Text:toString()
  return string.format('<text x="%.2f" y="%.2f" style="%s">%s</text>',
    self.x, self.y, styleToString(self.style), tostring(self.str))
end

-- ===========================================================================
-- Pure math module: axis mapping + per-band-type magnitude response.
-- File-scope (testable without a live component). These are continuous-
-- domain approximations of each filter type's shape (the standard approach
-- for a visual curve overlay — not a bit-exact digital biquad evaluation,
-- which would also require knowing the audio sample rate this plugin has no
-- way to query). Good enough to show the operator the right curve shape;
-- swap in exact math later if bit-exact matching to the native DSP is ever
-- required.
-- ===========================================================================

EQMath = {}

function EQMath.FreqToX(freq, plotX, plotWidth, freqMin, freqMax)
  local minLog = math.log(freqMin, 10)
  local maxLog = math.log(freqMax, 10)
  local t = (math.log(freq, 10) - minLog) / (maxLog - minLog)
  return plotX + t * plotWidth
end

function EQMath.DbToY(db, plotY, plotHeight, dbMin, dbMax)
  local t = (db - dbMin) / (dbMax - dbMin)
  -- SVG y grows downward; higher dB must render higher on screen.
  return plotY + (1 - t) * plotHeight
end

-- Peaking/Bell: standard constant-Q continuous approximation.
-- dB(f0) == gainDb exactly; falls off symmetrically in log-frequency.
local function bellMagnitudeDb(freq, f0, gainDb, q)
  local x = q * (freq / f0 - f0 / freq)
  return gainDb / math.sqrt(1 + x * x)
end

-- Shelf filters: smooth logistic transition in log-frequency space, corner
-- at f0. Steepness fixed (not derived from Q — shelf "Q" semantics vary by
-- implementation; VERIFY if the native component's Q should drive this).
local SHELF_STEEPNESS = 3.0
local function logisticTransition(freq, f0)
  local l = math.log(freq, 10)
  local l0 = math.log(f0, 10)
  return 1 / (1 + math.exp(-SHELF_STEEPNESS * (l - l0)))
end

local function lowShelfMagnitudeDb(freq, f0, gainDb)
  return gainDb * (1 - logisticTransition(freq, f0))
end

local function highShelfMagnitudeDb(freq, f0, gainDb)
  return gainDb * logisticTransition(freq, f0)
end

-- HPF/LPF: 2-pole (12 dB/oct) Butterworth-shaped roll-off, 0 dB in the
-- passband. VERIFY the native component's actual filter order/slope.
local function highPassMagnitudeDb(freq, f0)
  return -10 * math.log(1 + (f0 / freq) ^ 4, 10)
end

local function lowPassMagnitudeDb(freq, f0)
  return -10 * math.log(1 + (freq / f0) ^ 4, 10)
end

-- Notch: narrow, deep, symmetric cut independent of the band's gain sign
-- (notches remove, they don't boost). VERIFY exact depth/parameterization
-- against the native component — NOTCH_DEPTH_DB is a placeholder.
local NOTCH_DEPTH_DB = -40
local function notchMagnitudeDb(freq, f0, q)
  local x = q * (freq / f0 - f0 / freq)
  return NOTCH_DEPTH_DB / (1 + x * x)
end

-- band = { Freq=, Gain=, Q=, Type= }. Unknown/missing Type falls back to Bell.
function EQMath.BandMagnitudeDb(freq, band)
  local t = band.Type
  if t == "LowShelf" then
    return lowShelfMagnitudeDb(freq, band.Freq, band.Gain)
  elseif t == "HighShelf" then
    return highShelfMagnitudeDb(freq, band.Freq, band.Gain)
  elseif t == "HighPass" then
    return highPassMagnitudeDb(freq, band.Freq)
  elseif t == "LowPass" then
    return lowPassMagnitudeDb(freq, band.Freq)
  elseif t == "Notch" then
    return notchMagnitudeDb(freq, band.Freq, band.Q or 1)
  else
    return bellMagnitudeDb(freq, band.Freq, band.Gain, band.Q or 1)
  end
end

-- Composite response: dB sums correctly across a series/cascaded chain
-- (log of a product of magnitudes == sum of logs), which is how a
-- parametric EQ's bands actually combine.
function EQMath.CompositeMagnitudeDb(freq, bands)
  local total = 0
  for _, band in ipairs(bands) do
    total = total + EQMath.BandMagnitudeDb(freq, band)
  end
  return total
end

-- ===========================================================================
-- Runtime script
-- ===========================================================================

if Controls then

  local NumBands = Properties["NumBands"].Value
  local peqRefName = Properties["PEQ Reference"].Value
  local rtaRefName = Properties["RTA Reference"].Value

  local peqComponent = nil
  local rtaComponent = nil
  local peqConnected = false
  local rtaConnected = false

  local cachedEQCurve = nil   -- array of {x=, y=} — recomputed only on PEQ change
  local cachedRTACurve = nil  -- array of {x=, y=} — recomputed only on RTA update
  local cachedBandMarkers = nil

  local plotX = CONFIG.Graph.Margin
  local plotY = CONFIG.Graph.Margin
  local plotWidth = CONFIG.Graph.Width - 2 * CONFIG.Graph.Margin
  local plotHeight = CONFIG.Graph.Height - 2 * CONFIG.Graph.Margin

  ---------------------------------------------------------------------------
  -- Component resolution — pcall-wrapped, degrades to "not connected"
  -- rather than erroring, per the spec's reliability requirement.
  ---------------------------------------------------------------------------

  local function TryResolveComponent(name, probeControlName)
    if name == nil or name == "" then
      return nil, false
    end
    local ok, comp = pcall(function() return Component.New(name) end)
    if not ok or comp == nil then
      return nil, false
    end
    -- Sanity check it's actually the expected type of component by probing
    -- for one control we expect it to have, rather than trusting a type
    -- string we have no confirmed name for.
    local probeOk, probeCtl = pcall(function() return comp[probeControlName] end)
    if not probeOk or probeCtl == nil then
      return comp, false
    end
    return comp, true
  end

  local function ResolveComponents()
    local peqProbe = CONFIG.PEQ.BandControlName(1, "Freq")
    peqComponent, peqConnected = TryResolveComponent(peqRefName, peqProbe)

    local rtaProbe
    if CONFIG.RTA.Mode == "array_blob" then
      rtaProbe = CONFIG.RTA.ArrayBlobControlName
    else
      rtaProbe = CONFIG.RTA.PerBandControlName(1)
    end
    rtaComponent, rtaConnected = TryResolveComponent(rtaRefName, rtaProbe)
  end

  ---------------------------------------------------------------------------
  -- Reading live band/spectrum data — all pcall-wrapped.
  ---------------------------------------------------------------------------

  local function ReadPEQBands()
    if not peqConnected then return nil end
    local bands = {}
    local ok = pcall(function()
      for i = 1, NumBands do
        local freqCtl = peqComponent[CONFIG.PEQ.BandControlName(i, "Freq")]
        local gainCtl = peqComponent[CONFIG.PEQ.BandControlName(i, "Gain")]
        local qCtl = peqComponent[CONFIG.PEQ.BandControlName(i, "Q")]
        if freqCtl and gainCtl then
          local bandType = "Bell"
          if CONFIG.PEQ.HasTypeControl then
            local typeCtl = peqComponent[CONFIG.PEQ.BandControlName(i, "Type")]
            if typeCtl and typeCtl.String and typeCtl.String ~= "" then
              bandType = typeCtl.String
            end
          end
          table.insert(bands, {
            Freq = freqCtl.Value,
            Gain = gainCtl.Value,
            Q = qCtl and qCtl.Value or 1,
            Type = bandType,
          })
        end
      end
    end)
    if not ok then return nil end
    return bands
  end

  local function ReadRTAMagnitudes()
    if not rtaConnected then return nil end
    local points = nil
    local ok = pcall(function()
      if CONFIG.RTA.Mode == "array_blob" then
        local ctl = rtaComponent[CONFIG.RTA.ArrayBlobControlName]
        local decoded = rapidjson.decode(ctl.String)
        points = {}
        for _, p in ipairs(decoded) do
          table.insert(points, { Freq = p.freq, Mag = p.mag })
        end
      else
        points = {}
        for i = 1, CONFIG.RTA.NumPoints do
          local ctl = rtaComponent[CONFIG.RTA.PerBandControlName(i)]
          if ctl then
            -- Even spacing in log-frequency across the configured RTA range
            -- as a placeholder frequency axis — VERIFY whether the real
            -- per-band RTA controls carry their own frequency, or only
            -- magnitude (in which case this even-log-spacing assumption is
            -- what actually needs confirming, per the spec's open question).
            local t = (i - 1) / math.max(1, CONFIG.RTA.NumPoints - 1)
            local minLog = math.log(CONFIG.RTA.FreqMin, 10)
            local maxLog = math.log(CONFIG.RTA.FreqMax, 10)
            local freq = 10 ^ (minLog + t * (maxLog - minLog))
            table.insert(points, { Freq = freq, Mag = ctl.Value })
          end
        end
      end
    end)
    if not ok then return nil end
    if not CONFIG.RTA.OutputIsDB and points then
      for _, p in ipairs(points) do
        if p.Mag and p.Mag > 0 then
          p.Mag = 20 * math.log(p.Mag, 10)
        end
      end
    end
    return points
  end

  ---------------------------------------------------------------------------
  -- Curve / layer builders — pure functions over already-read data, so
  -- recompute cost is isolated from the pcall/read step above.
  ---------------------------------------------------------------------------

  local function BuildGridLayer()
    local doc = EzSVG.Document(CONFIG.Graph.Width, CONFIG.Graph.Height)
    local gridFreqs = { 100, 1000, 10000 }
    for _, f in ipairs(gridFreqs) do
      if f >= CONFIG.PEQ.FreqMin and f <= CONFIG.PEQ.FreqMax then
        local x = EQMath.FreqToX(f, plotX, plotWidth, CONFIG.PEQ.FreqMin, CONFIG.PEQ.FreqMax)
        doc:append(EzSVG.Line(x, plotY, x, plotY + plotHeight)
          :setStyle({ stroke = "#444444", ["stroke-width"] = "1" }))
      end
    end
    local dbStep = 6
    local db = math.ceil(CONFIG.Graph.DbMin / dbStep) * dbStep
    while db <= CONFIG.Graph.DbMax do
      local y = EQMath.DbToY(db, plotY, plotHeight, CONFIG.Graph.DbMin, CONFIG.Graph.DbMax)
      local isZero = (db == 0)
      doc:append(EzSVG.Line(plotX, y, plotX + plotWidth, y)
        :setStyle({
          stroke = isZero and "#888888" or "#333333",
          ["stroke-width"] = isZero and "2" or "1",
        }))
      db = db + dbStep
    end
    return doc
  end

  local function BuildEQCurveLayer(bands)
    local doc = EzSVG.Document(CONFIG.Graph.Width, CONFIG.Graph.Height)
    if bands == nil or #bands == 0 then return doc end

    local path = EzSVG.Path():setStyle({ stroke = "#33aaff", fill = "none", ["stroke-width"] = "2" })
    local minLog = math.log(CONFIG.PEQ.FreqMin, 10)
    local maxLog = math.log(CONFIG.PEQ.FreqMax, 10)
    for i = 0, CONFIG.Graph.CurveSamples - 1 do
      local t = i / (CONFIG.Graph.CurveSamples - 1)
      local freq = 10 ^ (minLog + t * (maxLog - minLog))
      local db = EQMath.CompositeMagnitudeDb(freq, bands)
      db = math.max(CONFIG.Graph.DbMin, math.min(CONFIG.Graph.DbMax, db))
      local x = EQMath.FreqToX(freq, plotX, plotWidth, CONFIG.PEQ.FreqMin, CONFIG.PEQ.FreqMax)
      local y = EQMath.DbToY(db, plotY, plotHeight, CONFIG.Graph.DbMin, CONFIG.Graph.DbMax)
      if i == 0 then path:moveToA(x, y) else path:lineToA(x, y) end
    end
    doc:append(path)

    for _, band in ipairs(bands) do
      local x = EQMath.FreqToX(band.Freq, plotX, plotWidth, CONFIG.PEQ.FreqMin, CONFIG.PEQ.FreqMax)
      local clampedGain = math.max(CONFIG.Graph.DbMin, math.min(CONFIG.Graph.DbMax, band.Gain))
      local y = EQMath.DbToY(clampedGain, plotY, plotHeight, CONFIG.Graph.DbMin, CONFIG.Graph.DbMax)
      -- Static marker only — see header: draggable interaction not implemented.
      doc:append(EzSVG.Circle(x, y, 4):setStyle({ fill = "#33aaff", stroke = "#ffffff", ["stroke-width"] = "1" }))
    end

    return doc
  end

  local function BuildRTALayer(points)
    local doc = EzSVG.Document(CONFIG.Graph.Width, CONFIG.Graph.Height)
    if points == nil or #points == 0 then return doc end

    local path = EzSVG.Path():setStyle({ stroke = "#ffa033", fill = "#ffa033", opacity = "0.35" })
    local floorY = plotY + plotHeight
    for i, p in ipairs(points) do
      local db = math.max(CONFIG.Graph.DbMin, math.min(CONFIG.Graph.DbMax, p.Mag))
      local x = EQMath.FreqToX(p.Freq, plotX, plotWidth, CONFIG.RTA.FreqMin, CONFIG.RTA.FreqMax)
      local y = EQMath.DbToY(db, plotY, plotHeight, CONFIG.Graph.DbMin, CONFIG.Graph.DbMax)
      if i == 1 then
        path:moveToA(x, floorY)
        path:lineToA(x, y)
      else
        path:lineToA(x, y)
      end
    end
    local lastX = EQMath.FreqToX(points[#points].Freq, plotX, plotWidth, CONFIG.RTA.FreqMin, CONFIG.RTA.FreqMax)
    path:lineToA(lastX, floorY)
    path:close()
    doc:append(path)
    return doc
  end

  local function BuildNotConnectedLayer(message)
    local doc = EzSVG.Document(CONFIG.Graph.Width, CONFIG.Graph.Height)
    doc:append(EzSVG.Text(CONFIG.Graph.Width / 2, CONFIG.Graph.Height / 2, message)
      :setStyle({ fill = "#999999", ["font-size"] = "14", ["text-anchor"] = "middle" }))
    return doc
  end

  ---------------------------------------------------------------------------
  -- Compositing + push to the Button's Legend, per the spec's SVG-in-Legend
  -- mechanism. pcall-wrapped: a missing Crypto/rapidjson API degrades to a
  -- no-op rather than throwing.
  ---------------------------------------------------------------------------

  local function Composite()
    local doc = EzSVG.Document(CONFIG.Graph.Width, CONFIG.Graph.Height)
    doc:append(EzSVG.Line(0, 0, CONFIG.Graph.Width, 0):setStyle({ stroke = "none" })) -- keep viewBox stable even if all layers are empty
    local grid = BuildGridLayer()
    for _, child in ipairs(grid.children) do doc:append(child) end

    if not peqConnected and not rtaConnected then
      local nc = BuildNotConnectedLayer("PEQ and RTA not connected")
      for _, child in ipairs(nc.children) do doc:append(child) end
    else
      if rtaConnected and cachedRTACurve then
        for _, child in ipairs(cachedRTACurve.children) do doc:append(child) end
      elseif not rtaConnected then
        local nc = BuildNotConnectedLayer("RTA not connected")
        for _, child in ipairs(nc.children) do doc:append(child) end
      end

      if peqConnected and cachedEQCurve then
        for _, child in ipairs(cachedEQCurve.children) do doc:append(child) end
      elseif not peqConnected then
        local nc = BuildNotConnectedLayer("PEQ not connected")
        for _, child in ipairs(nc.children) do doc:append(child) end
      end
    end

    return doc:toString()
  end

  local function PushGraphic()
    local svg = Composite()
    local ok = pcall(function()
      local encoded = Crypto.Base64Encode(svg)
      Controls.GraphDisplay.Legend = rapidjson.encode({ DrawChrome = false, IconData = encoded })
    end)
    if not ok then
      print("ParametricEQVisualizer: failed to push graphic to Legend")
    end
  end

  ---------------------------------------------------------------------------
  -- Change handlers: PEQ redraws immediately (rare events, spec says no
  -- throttling needed); RTA redraws are debounced to CONFIG.Graph.RedrawHz.
  -- Each only recomputes its own layer and reuses the other's cache, per
  -- the spec's "avoid recomputing full transfer-function curves unless a
  -- band actually changed" guidance.
  ---------------------------------------------------------------------------

  local function RecomputeEQCurve()
    local bands = ReadPEQBands()
    cachedEQCurve = BuildEQCurveLayer(bands)
  end

  local function RecomputeRTACurve()
    local points = ReadRTAMagnitudes()
    cachedRTACurve = BuildRTALayer(points)
  end

  local function OnPEQChanged()
    RecomputeEQCurve()
    PushGraphic()
  end

  local rtaPending = false
  local rtaTimer = Timer.New()
  rtaTimer.EventHandler = function()
    if rtaPending then
      rtaPending = false
      RecomputeRTACurve()
      PushGraphic()
    end
  end

  local function OnRTAChanged()
    rtaPending = true
    -- Timer.Start on an already-running timer just keeps it on the same
    -- cadence; this only actually starts ticking once RTA is connected.
    rtaTimer:Start(1 / CONFIG.Graph.RedrawHz)
  end

  ---------------------------------------------------------------------------
  -- Wire it up
  ---------------------------------------------------------------------------

  ResolveComponents()

  if peqConnected then
    pcall(function()
      for i = 1, NumBands do
        for _, param in ipairs({ "Freq", "Gain", "Q", "Type" }) do
          if param ~= "Type" or CONFIG.PEQ.HasTypeControl then
            local ctl = peqComponent[CONFIG.PEQ.BandControlName(i, param)]
            if ctl then
              ctl.EventHandler = OnPEQChanged
            end
          end
        end
      end
    end)
  end

  if rtaConnected then
    pcall(function()
      if CONFIG.RTA.Mode == "array_blob" then
        local ctl = rtaComponent[CONFIG.RTA.ArrayBlobControlName]
        if ctl then ctl.EventHandler = OnRTAChanged end
      else
        for i = 1, CONFIG.RTA.NumPoints do
          local ctl = rtaComponent[CONFIG.RTA.PerBandControlName(i)]
          if ctl then ctl.EventHandler = OnRTAChanged end
        end
      end
    end)
  end

  -- Initial render: whatever we could resolve, or the not-connected state.
  RecomputeEQCurve()
  RecomputeRTACurve()
  PushGraphic()

  ---------------------------------------------------------------------------
  -- Draggable band-point interaction — NOT IMPLEMENTED.
  --
  -- Per the spec, this needs QSC's stock Positioner/PEQ plugin source
  -- inspected in Designer before committing to a mechanism (candidates:
  -- invisible Knob/Fader controls overlaid per band and remapped to freq/
  -- gain, vs. MouseDown/position-capable control events if those exist in
  -- the current Lua control API — unverified either way). Q adjustment
  -- needs a separate interaction path since it isn't spatially represented
  -- by the point. None of that is guessed at here; band markers above are
  -- static. See BUILD_NOTES.md for what to check and where to hang the
  -- result once you have it.
  ---------------------------------------------------------------------------

end
