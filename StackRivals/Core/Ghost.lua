--[[
  StackRivals - Race My Best (Ghost Mode): play the same pieces as your best run, with that run replayed
  beside you tick for tick. Local only: no XP, Shards, rank or web reward, never sent anywhere, and a ghost
  race never changes the normal records (you know the pieces: it is a different contest). Pure Lua.

  What a ghost needs, and where it comes from (no new data format):
    * The best run of a mode is already saved as its input log (records[mode].bestLog, Engine.serializeLog):
      "engineVersion;seed;startLevel;ticks;tick,action tick,action ...". That is everything a replay needs.
    * A ghost race you win is kept as the new ghost (db.ghosts[mode]), so the next race is against it.
    * Old records without a log, or with a log from another engine version or that doesn't replay to the
      record's score, are NOT offered as a ghost (Ghost.source / Ghost.validate say why).

  Determinism: the ghost is advanced with the engine's own functions in exactly the order Engine.replay
  uses (inputs of a tick, then the tick), one tick at a time as your run ticks. Same seed, start level,
  rules and engine version as the original, so it plays out exactly as it did.
]]
local _, ns = ...
ns = ns or {}

local G = {}
ns.Ghost = G

G.MODES = { classic = "ghost_classic", blitz = "ghost_blitz" } -- which modes can be raced (Daily: new pieces every day)
G.BASE = { ghost_classic = "classic", ghost_blitz = "blitz" }
G.MAX_LOG = 300000 -- chars kept for a won ghost race (a 2:00 run is ~8 KB; long Classic runs fit too)

local function E() return ns.Engine end

--- Short id of a ghost (its log): ties a saved, unfinished race to the ghost it was against.
function G.id(log) return string.format("%08x", ns.Prng.hashString(log)) end

--- The ghost to race in a mode, or nil + why. Cheap (the log's header only): safe for menu refreshes.
--- Returns { log, score, lines, level, date, from = "race" | "record", id }.
function G.source(db, base)
  if not G.MODES[base] then return nil, "mode" end
  local slot = db.ghosts and db.ghosts[base]
  local r = db.records and db.records[base]
  local e
  if slot and slot.log then
    e = { log = slot.log, score = slot.score, lines = slot.lines, level = slot.level, date = slot.date, from = "race" }
  elseif r and r.best > 0 and r.bestLog then
    e = { log = r.bestLog, score = r.best, lines = r.bestLines, level = r.bestLevel, date = r.bestDate, from = "record" }
  else
    return nil, (r and r.best > 0) and "no_log" or "no_record"
  end
  local v, startLevel = e.log:match("^(%d+);[^;]*;(%d+);%d+;")
  if not v then return nil, "no_log" end
  if tonumber(v) ~= E().ENGINE_VERSION then return nil, "engine" end
  if tonumber(startLevel) ~= 1 then return nil, "rules" end
  e.id = G.id(e.log)
  return e
end

--- A runner: the original run, rebuilt from its seed and advanced as your run ticks.
local function newRunner(d)
  return { s = E().createGame(d.seed, { startLevel = d.startLevel }), log = d.log, i = 1, ticks = d.ticks, n = #d.log }
end

--- Bring the ghost to tick t exactly as Engine.replay(seed, cfg, log, t) would (never past its own end).
function G.advance(r, t)
  local s, log, A = r.s, r.log, E().INPUT_ACTIONS
  if t > r.ticks then t = r.ticks end
  while not s.gameOver do
    while r.i <= r.n and log[r.i] == s.tick do
      E().applyInput(s, A[log[r.i + 1] + 1])
      r.i = r.i + 2
      if s.gameOver then break end
    end
    if s.gameOver or s.tick >= t then break end
    E().tick(s)
  end
  r.done = s.gameOver or s.tick >= r.ticks
  return s
end

local valid = {} -- ghost id -> true | "why": a full check is done once per ghost per session
--- Full check (replays the whole run): only a ghost that reproduces its own score is raced.
--- Returns the parsed log, or nil + why ("unreadable" | "engine" | "rules" | "mismatch").
function G.validate(e)
  local d = E().deserializeLog(e.log)
  if not d then return nil, "unreadable" end
  if d.v ~= E().ENGINE_VERSION then return nil, "engine" end
  if d.startLevel ~= 1 then return nil, "rules" end
  local known = valid[e.id]
  if known == true then return d end
  if known then return nil, known end
  local okRun, s = pcall(function() return G.advance(newRunner(d), d.ticks) end)
  local why = (not okRun) and "unreadable" or (s.score ~= e.score and "mismatch") or nil
  valid[e.id] = why or true
  if why then return nil, why end
  return d
end

--- A ghost already found not to replay exactly this session: why, or nil (menu: grey it with the reason).
function G.knownBad(id) local v = valid[id]; return v ~= true and v or nil end

--- Give a session its ghost (a fresh race, or one restored after /reload: then brought to its tick).
function G.attach(sess, e, d)
  sess.ghost = { entry = e, id = e.id, runner = newRunner(d), base = G.BASE[sess.mode.key] }
  G.update(sess)
end

--- Keep the ghost level with the run (call once per frame; cheap: the same work as the player's ticks).
function G.update(sess)
  local g = sess.ghost
  if not g or not g.runner then return nil end
  return G.advance(g.runner, sess.state.tick)
end

--- My lead over my best at this moment (positive = ahead), and the ghost's state.
function G.lead(sess)
  local gs = G.update(sess)
  if not gs then return nil end
  return sess.state.score - gs.score, gs
end

--- Race over: did this run beat the best (the ghost's FINAL score, not where it was at this tick)?
--- A win becomes the new ghost (if its log fits). Records are never touched.
function G.finish(db, sess)
  local g = sess.ghost
  if not g then return nil end
  if g.lost or not g.entry then return { me = sess.state.score, best = 0, lost = true } end
  local final = g.entry.score
  local me = sess.state.score
  local res = { me = me, best = final, beat = me > final, tie = me == final, lost = g.runner == nil }
  if res.beat then
    local log = E().serializeLog(sess.state)
    if #log <= G.MAX_LOG then
      db.ghosts = db.ghosts or {}
      db.ghosts[g.base] = { log = log, score = me, lines = sess.state.lines, level = sess.state.level, date = sess.date }
      res.saved = true
    end
  end
  return res
end

--- A new normal record in a mode: it becomes the ghost unless a won ghost race scored higher.
function G.onNewRecord(db, base)
  local slot = db.ghosts and db.ghosts[base]
  local r = db.records[base]
  if slot and r and r.best >= (slot.score or 0) then db.ghosts[base] = nil end
end

--- SavedVariables: { classic = {log, score, lines, level, date}, blitz = {...} } (bounded; anything else dropped).
function G.sanitize(raw)
  local out = {}
  if type(raw) ~= "table" then return out end
  for base in pairs(G.MODES) do
    local g = raw[base]
    if type(g) == "table" and type(g.log) == "string" and #g.log <= G.MAX_LOG and g.log:match("^%d+;[^;]*;%d+;%d+;")
      and type(g.score) == "number" and g.score > 0 and g.score <= 1e12 then
      local function n(x) return (type(x) == "number" and x >= 0 and x <= 1e9) and math.floor(x) or 0 end
      out[base] = { log = g.log, score = math.floor(g.score), lines = n(g.lines), level = n(g.level),
        date = (type(g.date) == "string" and #g.date <= 16) and g.date or nil }
    end
  end
  return out
end

--- Why a mode can't be raced, in words (menu tooltip).
G.WHY = {
  no_record = "Set a score first: your best run becomes the one you race.",
  no_log = "Your best is from an older version and has no saved replay. Set a new best to race it.",
  engine = "Your best was played with another game version: it can't be replayed exactly. Set a new best.",
  rules = "Your best used other rules: it can't be raced. Set a new best.",
  mismatch = "Your best's replay doesn't match its score, so it isn't offered. Set a new best.",
  unreadable = "Your best's replay can't be read. Set a new best.",
}

return G
