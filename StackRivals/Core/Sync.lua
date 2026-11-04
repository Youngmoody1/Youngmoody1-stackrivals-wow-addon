--[[
  StackRivals - manual sync with stackrivals.io (Account > Sync): play SR1 challenge codes,
  export SR1 result codes. Copy / paste only: the addon has no internet access and never claims
  live sync. The website replays every result itself (SR1 import, docs/CROSS_PLATFORM_MULTIPLAYER.md
  section 6), so nothing exported here is trusted until the server's replay agrees.

  Exportable today:
    * runs of pasted challenge codes (rulesets b120 / r180 / daily120), last MAX_RESULTS;
    * today's best Daily Challenge run (ruleset daily120, seed srwow-daily-<UTC date>).
  Not exportable (no agreed format or server check yet): Time Trial / Classic with private seeds,
  duels (peer-checked only), Spell Battle (waits for SR2).
  The SR1 `link` field carries this character's account linkId (uppercase) when linked, so the
  website can file the result under the linked account (the website decides; see the handoff).
]]
local _, ns = ...
ns = ns or {}

local Sync = {}
ns.Sync = Sync

Sync.MAX_RESULTS = 10
Sync.ERRORS = {
  empty = "Paste a challenge code first.",
  size = "That code is too long.",
  chars = "The code has characters that don't belong in it (copy it again).",
  format = "That isn't a challenge code (it should start with SR1C).",
  fields = "The code is incomplete (copy all of it).",
  check = "The code has a typo or was cut off (checksum doesn't match).",
  engine = "This challenge was made for another engine version: update StackRivals (or the website).",
  ruleset_or_seed = "Unknown rules or seed in this code.",
  combat = "Not in combat. Play it after the fight.",
  duel = "Finish or leave your duel first.",
  loot = "You're in a Loot Duel: finish it (or pass) first.",
  too_long = "This run is too long for a result code.",
}

local function db()
  local d = ns.db
  if not d then return { results = {} } end
  d.sync = d.sync or { results = {} }
  d.sync.results = d.sync.results or {}
  return d.sync
end
local function now() return ns.Account and ns.Account.now() or 0 end

local function summary(state, ruleset, seed)
  local E = ns.Engine
  return {
    ruleset = ruleset, seed = seed, engine = state.engineVersion or E.ENGINE_VERSION, ticks = state.tick, score = state.score,
    lines = state.lines, level = state.level, hash = E.hashState(state), log = ns.Protocol.packLog(state.inputLog),
    player = ns.Comm and ns.Comm.me() or nil, at = now(),
  }
end

--- A finished challenge run (App:OnRunOver).
function Sync.saveChallengeRun(s)
  -- after /reload + Continue the session has no `challenge` table: the mode and seed say it all
  local ch = s.challenge or (s.mode and s.mode.challenge and { ruleset = s.mode.challenge, seed = s.seed })
  if not ch then return end
  local r = summary(s.state, ch.ruleset, ch.seed)
  local list = db().results
  table.insert(list, 1, r)
  while #list > Sync.MAX_RESULTS do table.remove(list) end
  return r
end

--- Today's best Daily Challenge run (only when it beat today's best).
function Sync.saveDailyRun(s)
  local date = s.date
  if not date then return end
  local r = summary(s.state, "daily120", ns.Session.dailySeed(date))
  r.date = date
  db().daily = r
  return r
end

--- What can be exported: { label, r } newest first (today's Daily first).
function Sync.exportable(today)
  local out = {}
  local d = db().daily
  if d and d.date == today then out[#out + 1] = { kind = "daily", r = d } end
  for _, r in ipairs(db().results) do out[#out + 1] = { kind = "challenge", r = r } end
  return out
end

--- SR1 result code for a saved run, or nil, reason.
function Sync.resultCode(r)
  local A = ns.Account
  local link = "-"
  if A then
    local st, rec = A.state()
    if (st == "linked" or st == "not_synced") and rec.link then link = rec.link.linkId:upper() end
  end
  local log = ns.Protocol.unpackLog(r.log)
  if not log or not r.player then return nil, "log" end
  local okC, code = pcall(ns.Codes.result, {
    platform = A and A.platform() or "wow-classic", ruleset = r.ruleset, seed = r.seed, engine = r.engine, ticks = r.ticks,
    score = r.score, lines = r.lines, level = r.level, hash = r.hash, player = r.player, link = link, log = log,
  })
  if not okC then return nil, "invalid" end
  if #code > ns.Codes.MAX_CODE then return nil, "too_long" end
  r.exported = true
  return code
end

--- Play a pasted challenge code. Returns true or false, reason.
function Sync.play(code)
  return ns.App:StartChallenge(code)
end

--- Clean saved sync data on load (DB.sanitize).
function Sync.sanitize(raw)
  local out = { results = {} }
  if type(raw) ~= "table" then return out end
  local C = ns.Codes
  local function num(v, hi) return (type(v) == "number" and v == v and v >= 0 and v <= hi) and math.floor(v) or nil end
  local function clean(r)
    if type(r) ~= "table" then return nil end
    if not (C and C.RULESETS[r.ruleset]) then return nil end
    if type(r.seed) ~= "string" or #r.seed > 64 or not r.seed:match("^[a-z0-9%-]+$") then return nil end
    if type(r.hash) ~= "string" or not r.hash:match("^%x%x%x%x%x%x%x%x$") then return nil end
    if type(r.log) ~= "string" or #r.log > 30000 or not r.log:match("^[0-9a-zA-P]*$") then return nil end
    if type(r.player) ~= "string" or not C.nameOk(r.player) then return nil end
    local t = { ruleset = r.ruleset, seed = r.seed, hash = r.hash:lower(), log = r.log, player = r.player,
      engine = num(r.engine, 9999), ticks = num(r.ticks, 1e7), score = num(r.score, 1e12), lines = num(r.lines, 1e9),
      level = num(r.level, 1e6), at = num(r.at, 1e11) or 0, exported = r.exported == true }
    if not (t.engine and t.ticks and t.score and t.lines and t.level) then return nil end
    if type(r.date) == "string" and r.date:match("^%d%d%d%d%-%d%d%-%d%d$") then t.date = r.date end
    return t
  end
  if type(raw.results) == "table" then
    for i = 1, math.min(#raw.results, Sync.MAX_RESULTS) do
      local t = clean(raw.results[i])
      if t then out.results[#out.results + 1] = t end
    end
  end
  local d = clean(raw.daily)
  if d and d.date and d.ruleset == "daily120" then out.daily = d end
  return out
end

return Sync
