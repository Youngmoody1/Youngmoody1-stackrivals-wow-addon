--[[
  Builds the shared SR1 test vectors (docs/vectors/sr1.json) with the Lua implementation.
  The website's TypeScript implementation must reproduce every expectation with its own decoder
  and the REAL web verifyLog (tools/sr1/check_vectors.ts does exactly that against a web checkout).

    lua5.1 tests/sr1_vectors.lua StackRivals tests > docs/vectors/sr1.json

  Deterministic: same input -> byte-identical JSON (the Lua test checks the file is current).
]]
local root, testdir = ...
root, testdir = root or "StackRivals", testdir or "tests"
local H = dofile(testdir .. "/harness.lua")
local ns = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Engine/Verify.lua", "Net/Protocol.lua", "Net/Codes.lua" })
local E, V, P, C = ns.Engine, ns.Verify, ns.Protocol, ns.Codes
local fx = dofile(testdir .. "/fixtures/parity.lua")

local M = {}

------------------------------------------------------------------------------------------------
-- Minimal deterministic JSON writer (sorted keys, no floats)
------------------------------------------------------------------------------------------------
local function esc(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end
local function isArray(t)
  if next(t) == nil then return true end
  local n = 0
  for k in pairs(t) do if type(k) ~= "number" then return false end n = n + 1 end
  return n == #t
end
local function json(v, ind)
  ind = ind or ""
  local t = type(v)
  if t == "string" then return esc(v)
  elseif t == "number" then assert(v % 1 == 0, "integers only"); return string.format("%d", v)
  elseif t == "boolean" then return tostring(v)
  elseif v == nil then return "null"
  elseif v == M.NULL then return "null" end
  local nxt = ind .. "  "
  if isArray(v) then
    if #v == 0 then return "[]" end
    local simple = true
    for _, x in ipairs(v) do if type(x) == "table" then simple = false end end
    local parts = {}
    for i, x in ipairs(v) do parts[i] = json(x, nxt) end
    if simple then return "[" .. table.concat(parts, ", ") .. "]" end
    return "[\n" .. nxt .. table.concat(parts, ",\n" .. nxt) .. "\n" .. ind .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = esc(k) .. ": " .. json(v[k], nxt) end
  return "{\n" .. nxt .. table.concat(parts, ",\n" .. nxt) .. "\n" .. ind .. "}"
end
M.NULL = setmetatable({}, { __tostring = function() return "null" end })
M.json = json

------------------------------------------------------------------------------------------------
-- Games
------------------------------------------------------------------------------------------------
local function caseBySeed(seed)
  for _, c in ipairs(fx.cases) do if c.seed == seed then return c end end
  error("no fixture " .. seed)
end

--- Play a recorded web bot game on `seed` up to `cap` ticks; returns final state (applied inputs only).
local function play(seed, logSeed, cap)
  local src = caseBySeed(logSeed).log
  local s = E.replay(seed, { startLevel = 1 }, src, cap)
  return s
end

--- A simple scripted game for seeds without a fixture (e.g. the Daily): tops out eventually.
local function scripted(seed, cap)
  local s = E.createGame(seed, { startLevel = 1 })
  local pattern = { { 0, 2 }, { 4, 0 }, { 8, 0 }, { 14, 5 }, { 30, 1 }, { 34, 1 }, { 38, 5 }, { 60, 5 }, { 75, 2 }, { 78, 5 } }
  local cycle = 90
  while s.tick < cap and not s.gameOver do
    local ph = s.tick % cycle
    for _, p in ipairs(pattern) do
      if p[1] == ph then E.applyInput(s, E.INPUT_ACTIONS[p[2] + 1]); if s.gameOver then break end end
    end
    if s.gameOver then break end
    E.tick(s)
  end
  return s
end

local function capTicks(rs) return math.ceil(C.RULESETS[rs].timeCapMs / 1000 * E.TICKS_PER_SECOND) end

local function copy(t) local o = {} for i, x in ipairs(t) do o[i] = x end return o end

local function resultOf(s, platform, rs, player, link)
  return {
    platform = platform, ruleset = rs, seed = s.seed, ticks = s.tick, score = s.score, lines = s.lines,
    level = s.level, hash = E.hashState(s), player = player, link = link, log = copy(s.inputLog),
  }
end

local function pairs2(flat)
  local out = {}
  for i = 1, #flat, 2 do out[#out + 1] = { flat[i], flat[i + 1] } end
  return out
end

------------------------------------------------------------------------------------------------
-- The server import algorithm (spec §6), Lua edition. TS must give identical output.
------------------------------------------------------------------------------------------------
function M.importResult(code, challenge, elapsedMs)
  local r, err = C.parseResult(code)
  if not r then return { decode = err } end
  local out = { decode = "ok", platform = r.platform, ruleset = r.ruleset, engine = r.engine, seed = r.seed,
    player = r.player, link = r.link or M.NULL, ticks = r.ticks, inputs = #r.log / 2,
    claimed = { score = r.score, lines = r.lines, level = r.level, hash = r.hash } }
  if r.ruleset ~= challenge.ruleset then out.verify = { ok = false, reasons = { "ruleset_mismatch" } }; return out end
  local v = V.verify(r.log, r.seed, r.ticks, {
    engine = r.engine, seed = challenge.seed, capTicks = capTicks(challenge.ruleset), elapsedMs = elapsedMs,
    claimed = { score = r.score, lines = r.lines, level = r.level, hash = r.hash },
  })
  local early = v.hash == nil -- verifyLog failed before replaying (engine, seed, malformed)
  out.verify = { ok = v.ok, reasons = v.reasons }
  if not early then
    out.verify.score, out.verify.lines, out.verify.level, out.verify.hash = v.score, v.lines, v.level, v.hash
    out.verify.toppedOut = v.toppedOut
  end
  out.verification = v.ok and "server_verified" or "rejected"
  return out
end

------------------------------------------------------------------------------------------------
-- Vectors
------------------------------------------------------------------------------------------------
local function rebuild(code, mutate)
  -- change fields of a valid code and recompute the check (a "valid-looking" forged code)
  local f = {}
  for part in (code .. "."):gmatch("([^.]*)%.") do f[#f + 1] = part end
  table.remove(f) -- old check
  mutate(f)
  local body = table.concat(f, ".")
  return body .. "." .. string.format("%08x", ns.Prng.hashString(body))
end

function M.build()
  local vec = {
    format = "SR1", engineVersion = E.ENGINE_VERSION, webCommit = fx.webCommit or "",
    rulesets = {}, actions = E.INPUT_ACTIONS, platforms = { "wow-classic", "wow-forever", "wow-retail" },
    importAlgorithm = "docs/CROSS_PLATFORM_MULTIPLAYER.md §6.4",
    challenges = {}, results = {}, checksums = {},
  }
  for id, rs in pairs(C.RULESETS) do
    vec.rulesets[id] = { timeCapMs = rs.timeCapMs, countdownMs = rs.countdownMs, startLevel = rs.startLevel,
      capTicks = capTicks(id), seedRule = rs.seedPattern and "srwow-daily-YYYY-MM-DD (UTC date)" or "[a-z0-9-]{1,64}" }
  end
  -- ASCII only: the web hashes UTF-16 code units, Lua hashes bytes; they agree on ASCII, and codes
  -- and seeds are ASCII by definition (names travel as hex).
  for _, s in ipairs({ "", "a", "SR1C.b120.e1.srchal-7f3k2p9d", "srwow-daily-2026-11-05", "srduel-k3x9qa-ab12cd34ef56gh78" }) do
    vec.checksums[#vec.checksums + 1] = { input = s, fnv1a = string.format("%08x", ns.Prng.hashString(s)) }
  end

  -- challenge codes
  local function ch(name, code)
    local c, err = C.parseChallenge(code)
    vec.challenges[#vec.challenges + 1] = { name = name, code = code,
      expect = c and { ok = true, ruleset = c.ruleset, engine = c.engine, seed = c.seed } or { ok = false, error = err } }
  end
  local cB = C.challenge("b120", "srchal-7f3k2p9d")
  ch("blitz challenge", cB)
  ch("3:00 web-rules challenge", C.challenge("r180", "srchal-k20x9a1m"))
  ch("daily challenge", C.challenge("daily120", "srwow-daily-2026-11-05"))
  ch("pasted with spaces and a line break", cB:sub(1, 10) .. " \n " .. cB:sub(11))
  ch("typo (check fails)", cB:sub(1, -2) .. (cB:sub(-1) == "0" and "1" or "0"))
  ch("daily ruleset with a non-daily seed", rebuild(C.challenge("b120", "srchal-7f3k2p9d"), function(f) f[2] = "daily120" end))
  ch("unknown ruleset", rebuild(cB, function(f) f[2] = "z999" end))
  ch("uppercase seed", rebuild(cB, function(f) f[4] = "SRCHAL-7F3K2P9D" end))
  ch("missing engine field", "SR1C.b120.srchal-7f3k2p9d." .. string.format("%08x", ns.Prng.hashString("SR1C.b120.srchal-7f3k2p9d")))

  -- result codes
  local function rv(name, code, challenge, elapsedMs, note)
    local exp = M.importResult(code, challenge, elapsedMs)
    vec.results[#vec.results + 1] = { name = name, note = note, code = code, challenge = challenge, elapsedMs = elapsedMs, expect = exp }
  end
  local chB = { ruleset = "b120", seed = "bot-elite-1" }
  local sB = play("bot-elite-1", "bot-elite-1", capTicks("b120")) -- still alive at 2:00
  assert(not sB.gameOver and sB.tick == capTicks("b120"))
  local okB = C.result(resultOf(sB, "wow-forever", "b120", "Alice-Realm"))
  local slow = 125000 -- 2:05 between challenge creation and import
  rv("valid Blitz 2:00 (web elite bot game), WoW Forever", okB, chB, slow)

  local chR = { ruleset = "r180", seed = "bot-rival-1" }
  local sR = play("bot-rival-1", "bot-rival-1", capTicks("r180"))
  rv("valid 3:00 web rules, retail, unicode name + link code",
    C.result(resultOf(sR, "wow-retail", "r180", "Ægir-Draenor", "K7Q2M9XA")), chR, 200000)

  local daySeed = "srwow-daily-2026-11-05"
  local sD = scripted(daySeed, capTicks("daily120"))
  rv("valid Daily (scripted game that tops out early)", C.result(resultOf(sD, "wow-classic", "daily120", "Bob-Firemaw")),
    { ruleset = "daily120", seed = daySeed }, 130000)

  rv("pasted with whitespace", okB:sub(1, 40) .. "\n  " .. okB:sub(41), chB, slow)
  rv("typo (check fails)", okB:sub(1, -2) .. (okB:sub(-1) == "a" and "b" or "a"), chB, slow)
  rv("inflated score (check recomputed)", rebuild(okB, function(f) f[7] = P.b36(sB.score + 50000) end), chB, slow,
    "decodes fine; the replay gives the real score -> claim_mismatch")
  rv("wrong hash (check recomputed)", rebuild(okB, function(f) f[10] = "00000000" end), chB, slow)
  rv("other engine version", rebuild(okB, function(f) f[4] = "e2" end), chB, slow)
  rv("answers another challenge (seed mismatch)", okB, { ruleset = "b120", seed = "bot-elite-2" }, slow)
  rv("ruleset differs from the challenge", okB, { ruleset = "r180", seed = "bot-elite-1" }, slow)
  rv("imported faster than the game can be played", okB, chB, 60000, "elapsedMs 60 s < 120 s game - 3 s slack")
  rv("imported just in time (2:00 game, 117 s + 3 s slack)", okB, chB, 117000)

  -- over the time cap: a 3:00 game claimed as Blitz 2:00
  local sLong = play("bot-elite-1", "bot-elite-1", capTicks("r180")) -- 9692 ticks, then top-out
  assert(sLong.tick > capTicks("b120"))
  rv("over the 2:00 time cap (a 2:41 game claimed as Blitz)", C.result(resultOf(sLong, "wow-forever", "b120", "Alice-Realm")), chB, 300000,
    "the replay stops at the cap, so the claimed score also mismatches")
  -- inhuman input: 5 inputs on one tick
  local burst = copy(sB.inputLog)
  for _ = 1, 5 do burst[#burst + 1] = sB.tick; burst[#burst + 1] = 0 end
  local rb = resultOf(sB, "wow-forever", "b120", "Alice-Realm"); rb.log = burst
  rv("inhuman input rate (5 inputs in one tick)", C.result(rb), chB, slow)
  -- inputs after top-out
  local sTop = scripted(daySeed, capTicks("daily120"))
  if sTop.gameOver and sTop.tick + 30 <= capTicks("daily120") then
    local late = copy(sTop.inputLog)
    late[#late + 1] = sTop.tick + 20; late[#late + 1] = 5
    local rl = resultOf(sTop, "wow-classic", "daily120", "Bob-Firemaw"); rl.log = late; rl.ticks = sTop.tick + 30
    rv("inputs after top-out", C.result(rl), { ruleset = "daily120", seed = daySeed }, 130000)
  end
  rv("non-canonical log (leading zero)", rebuild(okB, function(f) f[13] = "0" .. f[13] end), chB, slow)
  rv("unknown platform", rebuild(okB, function(f) f[2] = "wow-mobile" end), chB, slow)
  rv("engine with a leading zero", rebuild(okB, function(f) f[4] = "e01" end), chB, slow)
  rv("player name is not valid UTF-8", rebuild(okB, function(f) f[11] = "c328" end), chB, slow)
  rv("link code with lowercase letters", rebuild(okB, function(f) f[12] = "k7q2m9xa" end), chB, slow)
  rv("input after the claimed end tick", rebuild(okB, function(f) f[6] = P.b36(10) end), chB, slow)
  rv("empty log is valid (no inputs, pieces fall until top-out or time)",
    C.result(resultOf(E.replay("srchal-emptylog", { startLevel = 1 }, {}, capTicks("b120")), "wow-forever", "b120", "Idle-Realm")),
    { ruleset = "b120", seed = "srchal-emptylog" }, slow)
  return vec
end

function M.render() return json(M.build()) .. "\n" end

if arg and arg[0] and arg[0]:match("sr1_vectors%.lua$") then
  io.write(M.render())
end
return M
