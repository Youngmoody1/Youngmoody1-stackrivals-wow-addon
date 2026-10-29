--[[
  StackRivals - saved data (SavedVariables: StackRivalsDB, account-wide).
  Everything read from disk is validated: wrong types, missing tables or a corrupted file
  fall back to defaults instead of throwing Lua errors. Pure Lua (no WoW API).
]]
local _, ns = ...
ns = ns or {}

local DB = {}
DB.SCHEMA = 1
-- Max stored input-log length (chars). ~1.5 MB covers many hours of continuous Classic play.
DB.MAX_LOG = 1500000

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
  return { best = 0, bestLines = 0, bestLevel = 0, games = 0, totalLines = 0, quads = 0, playSeconds = 0, bestDate = nil, bestLog = nil, top = {} }
end
DB.TOP_N = 5

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
  out.bestLog = str(r.bestLog, DB.MAX_LOG)
  if type(r.top) == "table" then
    for i = 1, DB.TOP_N do
      local e = r.top[i]
      if type(e) == "table" and type(e.s) == "number" and e.s >= 0 then
        out.top[#out.top + 1] = { s = math.floor(num(e.s, 0, 0, 1e12)), l = math.floor(num(e.l, 0, 0, 1e9)), v = math.floor(num(e.v, 1, 1, 1e6)), d = str(e.d, 16) }
      end
    end
    table.sort(out.top, function(a, b) return a.s > b.s end)
  end
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
  s.scale = num(rs.scale, s.scale, 0.7, 1.4)
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

  -- Records belong to a ruleset (= engine version). If the rules ever change, old scores are not
  -- comparable any more: they are moved to db.archive["rules<N>"] (never deleted) and the
  -- current rules start with fresh records.
  local current = (ns.Engine and ns.Engine.ENGINE_VERSION) or 1
  local savedRules = math.floor(num(raw.rules, 1, 0, 1e6)) -- data from before this field = rules 1
  local function cleanRecords(rr)
    rr = (type(rr) == "table") and rr or {}
    local out = { classic = cleanRecord(rr.classic), blitz = cleanRecord(rr.blitz), daily = cleanRecord(rr.daily) }
    local rd = (type(rr.dailyToday) == "table") and rr.dailyToday or {}
    out.dailyToday = { date = str(rd.date, 16), best = math.floor(num(rd.best, 0, 0, 1e12)), tries = math.floor(num(rd.tries, 0, 0, 1e6)) }
    return out
  end
  db.archive = {}
  if type(raw.archive) == "table" then
    local n = 0
    for k, v in pairs(raw.archive) do
      if type(k) == "string" and k:match("^rules%d+$") and n < 8 then n = n + 1; db.archive[k] = cleanRecords(v) end
    end
  end
  if savedRules == current then
    db.records = cleanRecords(raw.records)
  else
    if type(raw.records) == "table" then db.archive["rules" .. savedRules] = cleanRecords(raw.records) end
    db.records = cleanRecords(nil)
    db.rulesChangedFrom = savedRules
  end
  db.rules = current

  local w = (type(raw.window) == "table") and raw.window or {}
  db.window = {
    point = str(w.point, 16), relPoint = str(w.relPoint, 16),
    x = num(w.x, nil, -10000, 10000), y = num(w.y, nil, -10000, 10000),
    cx = num(w.cx, nil, -20000, 20000), cy = num(w.cy, nil, -20000, 20000),
  }
  db.seenIntro = bool(raw.seenIntro, false)
  db.seenHelp = bool(raw.seenHelp, false)

  -- Diagnostics (written on every load; read back after a test to see what the client reported).
  local rd = (type(raw.diag) == "table") and raw.diag or {}
  db.diag = {
    loads = math.floor(num(rd.loads, 0, 0, 1e9)),
    firstSeen = str(rd.firstSeen, 32),
    clients = {},
  }
  if type(rd.clients) == "table" then
    local n = 0
    for k, v in pairs(rd.clients) do
      if type(k) == "string" and #k <= 32 and type(v) == "table" and n < 16 then
        n = n + 1
        db.diag.clients[k] = {
          version = str(v.version, 32), build = str(v.build, 32), interface = math.floor(num(v.interface, 0, 0, 1e7)),
          project = math.floor(num(v.project, 0, 0, 1e4)), addon = str(v.addon, 32), last = str(v.last, 32),
          loads = math.floor(num(v.loads, 0, 0, 1e9)),
        }
      end
    end
  end

  -- An unfinished run saved at logout / reload (mode + web-compatible input log).
  local su = raw.suspended
  if type(su) == "table" and ns.Session and ns.Session.MODES[su.mode] and str(su.log, DB.MAX_LOG) then
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

--- Insert into a top list; returns the 1-based rank or nil if it didn't make the list.
local function insertTop(top, entry)
  local rank = #top + 1
  for i, e in ipairs(top) do if entry.s > e.s then rank = i; break end end
  if rank > DB.TOP_N then return nil end
  table.insert(top, rank, entry)
  while #top > DB.TOP_N do table.remove(top) end
  return rank
end

--- Record a finished run. `runDate` = UTC date the run started, `today` = UTC date now
--- (defaults to runDate). Returns { newBest, prevBest, newTodayBest, rank }.
function DB.recordRun(db, modeKey, state, playSeconds, runDate, logStr, today)
  today = today or runDate
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
    r.bestDate = runDate
    if logStr and #logStr <= DB.MAX_LOG then r.bestLog = logStr end
  end
  local rank = nil
  if state.score > 0 then rank = insertTop(r.top, { s = state.score, l = state.lines, v = state.level, d = runDate }) end
  local todayBest = nil
  if modeKey == "daily" and runDate == today then
    local d = db.records.dailyToday
    if d.date ~= today then d.date, d.best, d.tries = today, 0, 0 end
    d.tries = d.tries + 1
    todayBest = state.score > d.best
    if todayBest then d.best = state.score end
  end
  return { newBest = newBest and state.score > 0, prevBest = prev, newTodayBest = todayBest, rank = rank }
end

function DB.resetRecords(db)
  db.rules = (ns.Engine and ns.Engine.ENGINE_VERSION) or 1
  db.records = { classic = emptyRecord(), blitz = emptyRecord(), daily = emptyRecord(), dailyToday = { date = nil, best = 0, tries = 0 } }
end

ns.DB = DB
return DB
