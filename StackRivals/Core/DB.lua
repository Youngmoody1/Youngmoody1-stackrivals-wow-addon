--[[
  StackRivals - saved data (SavedVariables: StackRivalsDB, account-wide).
  Everything read from disk is validated: wrong types, missing tables or a corrupted file
  fall back to defaults instead of throwing Lua errors. Pure Lua (no WoW API).
]]
local _, ns = ...
ns = ns or {}

local DB = {}
DB.SCHEMA = 1
DB.DUEL_HISTORY = 20
-- Max stored input-log length (chars). ~1.5 MB covers many hours of continuous Classic play.
DB.MAX_LOG = 1500000

DB.DEFAULT_BINDINGS = {
  left = "LEFT", right = "RIGHT", softDrop = "DOWN", hardDrop = "SPACE",
  rotateCW = "UP", rotateCCW = "Z", hold = "C", pause = "P",
  -- Spell Battle: the web's Q / E / R / F. Only read during a Spell Battle run (while a run is
  -- live every key is the game's anyway; outside a run these keys are WoW's).
  spell1 = "Q", spell2 = "E", spell3 = "R", spell4 = "F",
}
-- Extra fixed keys that always work while playing (like the web game's alternates).
-- 1-4 cast spells too (action-bar habit).
DB.ALT_KEYS = {
  A = "left", D = "right", S = "softDrop", W = "rotateCW", X = "rotateCW",
  LSHIFT = "hold", RSHIFT = "hold", LCTRL = "rotateCCW", ESCAPE = "pause",
  ["1"] = "spell1", ["2"] = "spell2", ["3"] = "spell3", ["4"] = "spell4",
}
DB.BIND_ORDER = { "left", "right", "softDrop", "hardDrop", "rotateCW", "rotateCCW", "hold", "pause", "spell1", "spell2", "spell3", "spell4" }
DB.BIND_LABEL = {
  left = "Move left", right = "Move right", softDrop = "Soft drop", hardDrop = "Hard drop",
  rotateCW = "Rotate right", rotateCCW = "Rotate left", hold = "Hold", pause = "Pause",
  spell1 = "Spell 1", spell2 = "Spell 2", spell3 = "Spell 3", spell4 = "Spell 4",
}
DB.SPELL_DIFFICULTIES = { "rookie", "challenger", "contender", "elite", "rival" }

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

  -- Duel results (local; "checked" = the rival's log replayed to the same score on this PC).
  local rdu = (type(raw.duels) == "table") and raw.duels or {}
  db.duels = {
    wins = math.floor(num(rdu.wins, 0, 0, 1e9)), losses = math.floor(num(rdu.losses, 0, 0, 1e9)),
    draws = math.floor(num(rdu.draws, 0, 0, 1e9)), voids = math.floor(num(rdu.voids, 0, 0, 1e9)),
    disputes = math.floor(num(rdu.disputes, 0, 0, 1e9)),
    -- wins / losses / draws = played-out, replay-checked duels only; these are the rest
    fwins = math.floor(num(rdu.fwins, 0, 0, 1e9)), flosses = math.floor(num(rdu.flosses, 0, 0, 1e9)),
    history = {},
  }
  if type(rdu.history) == "table" then
    for i = 1, math.min(#rdu.history, DB.DUEL_HISTORY) do
      local h = rdu.history[i]
      if type(h) == "table" and str(h.rival, 64) then
        db.duels.history[#db.duels.history + 1] = {
          rival = h.rival, me = math.floor(num(h.me, 0, 0, 1e12)), them = math.floor(num(h.them, 0, 0, 1e12)),
          res = str(h.res, 8) or "void", how = str(h.how, 24) or "", rs = str(h.rs, 8) or "b120", d = str(h.d, 16),
          b = str(h.b, 8),
        }
      end
    end
  end

  -- Duel diagnostics (Core/DuelDiag.lua): last 5 duels, counters + short event lines.
  db.duelDiag = {}
  if type(raw.duelDiag) == "table" then
    for i = 1, math.min(#raw.duelDiag, 5) do
      local r = raw.duelDiag[i]
      if type(r) == "table" and str(r.mid, 10) and str(r.rival, 64) then
        local function counts(t)
          local out, n = {}, 0
          if type(t) == "table" then
            for k, v in pairs(t) do
              if type(k) == "string" and #k <= 8 and type(v) == "number" and n < 32 then n = n + 1; out[k] = math.floor(num(v, 0, 0, 1e9)) end
            end
          end
          return out
        end
        local lines = {}
        if type(r.lines) == "table" then
          for j = 1, math.min(#r.lines, 400) do local l = str(r.lines[j], 80); if l then lines[#lines + 1] = l end end
        end
        db.duelDiag[#db.duelDiag + 1] = {
          mid = r.mid, rival = r.rival, role = str(r.role, 8) or "?", rs = str(r.rs, 8) or "?", d = str(r.d, 16) or "",
          addon = str(r.addon, 32) or "?", engine = math.floor(num(r.engine, 0, 0, 9999)), build = str(r.build, 32) or "",
          iface = math.floor(num(r.iface, 0, 0, 1e7)), result = str(r.result, 12), how = str(r.how, 24),
          sent = counts(r.sent), recv = counts(r.recv), codes = counts(r.codes),
          drops = math.floor(num(r.drops, 0, 0, 1e9)), maxGap = num(r.maxGap, 0, 0, 1e6), maxQueue = math.floor(num(r.maxQueue, 0, 0, 1e6)),
          cut = math.floor(num(r.cut, 0, 0, 1e9)), lines = lines,
        }
      end
    end
  end

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

  -- Spell Battle: chosen loadout + bot level, and results vs each bot level (local, never ranked).
  local rsp = (type(raw.spell) == "table") and raw.spell or {}
  local Sp = ns.Spells
  local lo = str(rsp.loadout, 4)
  db.spell = {
    loadout = (Sp and lo and Sp.decodeLoadout(lo)) and lo or (Sp and Sp.encodeLoadout(Sp.DEFAULT_LOADOUT) or "1057"),
    difficulty = "challenger", stats = {},
  }
  for _, d in ipairs(DB.SPELL_DIFFICULTIES) do
    if rsp.difficulty == d then db.spell.difficulty = d end
    local r = (type(rsp.stats) == "table" and type(rsp.stats[d]) == "table") and rsp.stats[d] or {}
    db.spell.stats[d] = {
      wins = math.floor(num(r.wins, 0, 0, 1e9)), losses = math.floor(num(r.losses, 0, 0, 1e9)),
      draws = math.floor(num(r.draws, 0, 0, 1e9)), best = math.floor(num(r.best, 0, 0, 1e12)),
    }
  end

  -- An unfinished run saved at logout / reload (mode + web-compatible input log).
  local su = raw.suspended
  if type(su) == "table" and ns.Session and ns.Session.MODES[su.mode] and su.mode == "spellbot" then
    -- Spell Battle vs Bot: your log (moves + casts); the bot is rebuilt from the seed
    if str(su.seed, 64) and str(su.slog, DB.MAX_LOG) and str(su.loadout, 4) and str(su.difficulty, 16) and type(su.ticks) == "number" then
      db.suspended = {
        mode = su.mode, seed = su.seed, slog = su.slog, loadout = su.loadout, difficulty = su.difficulty,
        ticks = math.floor(num(su.ticks, 0, 0, 1e6)), createdAtMs = num(su.createdAtMs, nil, 0, 1e15),
        playSeconds = num(su.playSeconds, 0, 0, 1e9), date = str(su.date, 16),
      }
    end
  elseif type(su) == "table" and ns.Session and ns.Session.MODES[su.mode] and str(su.log, DB.MAX_LOG) then
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

--- Store a finished duel (match table from Core/Duel.lua).
--- Which counter a duel result goes to: wins / losses / draws only for a played-out duel whose
--- result rests on a replay of the rival's game (basis "replay"). A win because the rival left,
--- lost contact, withheld their log or failed the check is a forfeit win (fwins), never a "win".
local function duelKey(res, basis)
  if res == "void" then return "voids" end
  if basis == "replay" then return (res == "win" and "wins") or (res == "loss" and "losses") or "draws" end
  return (res == "win" and "fwins") or (res == "loss" and "flosses") or "voids"
end
DB.duelKey = duelKey

function DB.recordDuel(db, m, today)
  local d = db.duels
  local res = m.outcome or "void"
  local basis = m.basis or ((m.endReason == "checked") and "replay") or "void"
  local key = duelKey(res, basis)
  d[key] = (d[key] or 0) + 1
  local entry = { rival = m.rival, me = m.myScore or 0, them = m.theirScore or 0, res = res, how = m.endReason or "", rs = m.rulesetId, d = today, b = basis, k = key }
  table.insert(d.history, 1, entry)
  while #d.history > DB.DUEL_HISTORY do table.remove(d.history) end
  return entry
end

--- The two PCs disagree about a duel's result: it no longer counts as a win, loss or draw.
function DB.disputeDuel(db, m)
  local d = db.duels
  local key = (m.historyRef and m.historyRef.k) or duelKey(m.outcome or "void", m.basis or "void")
  d[key] = math.max(0, (d[key] or 0) - 1)
  d.disputes = (d.disputes or 0) + 1
  if m.historyRef then m.historyRef.res = "disputed" end
end

function DB.resetRecords(db)
  db.rules = (ns.Engine and ns.Engine.ENGINE_VERSION) or 1
  db.records = { classic = emptyRecord(), blitz = emptyRecord(), daily = emptyRecord(), dailyToday = { date = nil, best = 0, tries = 0 } }
end

ns.DB = DB
return DB
