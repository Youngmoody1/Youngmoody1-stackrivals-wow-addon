--[[
  StackRivals - saved data (SavedVariables: StackRivalsDB, account-wide).
  Everything read from disk is validated: wrong types, missing tables or a corrupted file
  fall back to defaults instead of throwing Lua errors. Pure Lua (no WoW API).
]]
local _, ns = ...
ns = ns or {}

local DB = {}
DB.SCHEMA = 1

DB.DEFAULT_BINDINGS = {
  left = "LEFT", right = "RIGHT", softDrop = "DOWN", hardDrop = "SPACE",
  rotateCW = "UP", rotateCCW = "Z", hold = "C", pause = "P",
}
-- Extra fixed keys that always work while playing (like the web game's alternates).
DB.ALT_KEYS = {
  A = "left", D = "right", S = "softDrop", W = "rotateCW", X = "rotateCW",
  LSHIFT = "hold", RSHIFT = "hold", LCTRL = "rotateCCW", ESCAPE = "pause",
}
DB.BIND_ORDER = { "left", "right", "softDrop", "hardDrop", "rotateCW", "rotateCCW", "hold", "pause" }
DB.BIND_LABEL = {
  left = "Move left", right = "Move right", softDrop = "Soft drop", hardDrop = "Hard drop",
  rotateCW = "Rotate right", rotateCCW = "Rotate left", hold = "Hold", pause = "Pause",
}

local function defaultSettings()
  return { sound = true, ghost = true, hideInCombat = true, scale = 1.0, minimapHide = false, minimapAngle = 215 }
end

local function emptyRecord()
  return { best = 0, bestLines = 0, bestLevel = 0, games = 0, totalLines = 0, quads = 0, playSeconds = 0, bestDate = nil, bestLog = nil }
end

local function num(v, default, lo, hi)
  if type(v) ~= "number" or v ~= v then return default end -- also rejects NaN
  if lo and v < lo then return lo end
  if hi and v > hi then return hi end
  return v
end
local function bool(v, default) if type(v) == "boolean" then return v end return default end
local function str(v, maxLen) if type(v) == "string" and #v <= (maxLen or 64) then return v end return nil end

local function cleanRecord(r)
  local out = emptyRecord()
  if type(r) ~= "table" then return out end
  out.best = math.floor(num(r.best, 0, 0, 1e12))
  out.bestLines = math.floor(num(r.bestLines, 0, 0, 1e9))
  out.bestLevel = math.floor(num(r.bestLevel, 0, 0, 1e6))
  out.games = math.floor(num(r.games, 0, 0, 1e9))
  out.totalLines = math.floor(num(r.totalLines, 0, 0, 1e12))
  out.quads = math.floor(num(r.quads, 0, 0, 1e9))
  out.playSeconds = num(r.playSeconds, 0, 0, 1e12)
  out.bestDate = str(r.bestDate, 32)
  out.bestLog = str(r.bestLog, 400000)
  return out
end

local function validKey(k) return type(k) == "string" and #k > 0 and #k <= 32 and k:match("^[%u%d%-]+$") ~= nil end

--- Return a clean DB table built from whatever was on disk (never errors).
function DB.sanitize(raw)
  local db = { schema = DB.SCHEMA }
  if type(raw) ~= "table" then raw = {} end

  local s, rs = defaultSettings(), (type(raw.settings) == "table") and raw.settings or {}
  s.sound = bool(rs.sound, s.sound)
  s.ghost = bool(rs.ghost, s.ghost)
  s.hideInCombat = bool(rs.hideInCombat, s.hideInCombat)
  s.scale = num(rs.scale, s.scale, 0.6, 1.6)
  s.minimapHide = bool(rs.minimapHide, s.minimapHide)
  s.minimapAngle = num(rs.minimapAngle, s.minimapAngle, 0, 360)
  db.settings = s

  local b, rb = {}, (type(raw.bindings) == "table") and raw.bindings or {}
  local used = {}
  for _, action in ipairs(DB.BIND_ORDER) do
    local k = rb[action]
    if validKey(k) and not used[k] then b[action] = k else b[action] = nil end
    if b[action] then used[b[action]] = true end
  end
  for _, action in ipairs(DB.BIND_ORDER) do -- fill gaps with defaults that are still free
    if not b[action] then
      local d = DB.DEFAULT_BINDINGS[action]
      if not used[d] then b[action] = d; used[d] = true end
    end
  end
  db.bindings = b

  local rr = (type(raw.records) == "table") and raw.records or {}
  db.records = { classic = cleanRecord(rr.classic), blitz = cleanRecord(rr.blitz), daily = cleanRecord(rr.daily) }
  local rd = (type(rr.dailyToday) == "table") and rr.dailyToday or {}
  db.records.dailyToday = { date = str(rd.date, 16), best = math.floor(num(rd.best, 0, 0, 1e12)), tries = math.floor(num(rd.tries, 0, 0, 1e6)) }

  local w = (type(raw.window) == "table") and raw.window or {}
  db.window = {
    point = str(w.point, 16), relPoint = str(w.relPoint, 16),
    x = num(w.x, nil, -10000, 10000), y = num(w.y, nil, -10000, 10000),
  }
  db.seenIntro = bool(raw.seenIntro, false)

  -- An unfinished run saved at logout / reload (mode + web-compatible input log).
  local su = raw.suspended
  if type(su) == "table" and ns.Session and ns.Session.MODES[su.mode] and str(su.log, 400000) then
    db.suspended = { mode = su.mode, log = su.log, playSeconds = num(su.playSeconds, 0, 0, 1e9), date = str(su.date, 16) }
  end
  return db
end

--- Action bound to a WoW key name while playing (custom binding first, then fixed alternates).
function DB.actionForKey(db, key)
  for action, k in pairs(db.bindings) do if k == key then return action end end
  local alt = DB.ALT_KEYS[key]
  if alt then
    -- An alternate key is ignored if the player bound it to something else.
    for _, k in pairs(db.bindings) do if k == key then return nil end end
    return alt
  end
  return nil
end

--- Bind `key` to `action`; if another action had that key, the two swap keys.
function DB.setBinding(db, action, key)
  if not validKey(key) or not DB.DEFAULT_BINDINGS[action] then return false end
  local old = db.bindings[action]
  for a, k in pairs(db.bindings) do
    if k == key and a ~= action then db.bindings[a] = old end
  end
  db.bindings[action] = key
  return true
end

function DB.resetBindings(db)
  db.bindings = {}
  for a, k in pairs(DB.DEFAULT_BINDINGS) do db.bindings[a] = k end
end

--- Record a finished run. `today` is the UTC date string. Returns { newBest = bool, prevBest = n }.
function DB.recordRun(db, modeKey, state, playSeconds, today, logStr)
  local r = db.records[modeKey]
  if not r then return { newBest = false, prevBest = 0 } end
  local prev = r.best
  r.games = r.games + 1
  r.totalLines = r.totalLines + state.lines
  r.quads = r.quads + (state.clears and state.clears.quad or 0)
  r.playSeconds = r.playSeconds + (playSeconds or 0)
  if state.lines > r.bestLines then r.bestLines = state.lines end
  if state.level > r.bestLevel then r.bestLevel = state.level end
  local newBest = state.score > prev
  if newBest then
    r.best = state.score
    r.bestDate = today
    if logStr and #logStr <= 400000 then r.bestLog = logStr end
  end
  local todayBest = nil
  if modeKey == "daily" then
    local d = db.records.dailyToday
    if d.date ~= today then d.date, d.best, d.tries = today, 0, 0 end
    d.tries = d.tries + 1
    todayBest = state.score > d.best
    if todayBest then d.best = state.score end
  end
  return { newBest = newBest and state.score > 0, prevBest = prev, newTodayBest = todayBest }
end

function DB.resetRecords(db)
  db.records = { classic = emptyRecord(), blitz = emptyRecord(), daily = emptyRecord(), dailyToday = { date = nil, best = 0, tries = 0 } }
end

ns.DB = DB
return DB
