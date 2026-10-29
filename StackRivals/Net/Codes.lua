--[[
  StackRivals - cross-platform copy/paste codes, format "SR1" (spec: docs/CROSS_PLATFORM_MULTIPLAYER.md §6).
  Pure Lua, no WoW API. The website implements the same format in TypeScript; both are checked
  against the shared test vectors in docs/vectors/sr1.json.

  Challenge code (made by the website or the addon):
    SR1C.<ruleset>.e<engine>.<seed>.<check>
  Result code (made by the addon after playing a challenge, pasted on the website):
    SR1R.<platform>.<ruleset>.e<engine>.<seed>.<ticks36>.<score36>.<lines36>.<level36>.<hash>.<playerHex>.<link>.<log>.<check>

    ruleset    b120 | r180 | daily120           (time cap, countdown and seed rule: RULESETS below)
    engine     ENGINE_VERSION as a decimal number without leading zeros, 1..4 digits
    seed       [a-z0-9-], 1..64 characters (daily120: exactly "srwow-daily-YYYY-MM-DD")
    platform   wow-forever | wow-retail | wow-classic
    ticks36..  lowercase base 36, no leading zeros ("0" for zero), at most 9 characters
    hash       8 lowercase hex = hashState of the final state (claimed)
    playerHex  lowercase hex of the UTF-8 bytes of "Name-Realm" (1..64 bytes, valid UTF-8)
    link       "-" or a one-time account link code [A-Z0-9]{6,12} (future, §6)
    log        compact input log: per input, tick delta from the previous input in base 36
               (no leading zeros) + action letter A..G (left,right,rotateCW,rotateCCW,softDrop,
               hardDrop,hold). Canonical: re-encoding must give the same text.
    check      8 lowercase hex = FNV-1a 32 of everything before ".<check>" (typo detection only;
               anyone can recompute it - trust comes from the server replay, never from this)
]]
local _, ns = ...
ns = ns or {}

local C = {}
ns.Codes = C

C.FORMAT = "SR1"
C.RULESETS = {
  b120 = { timeCapMs = 120000, countdownMs = 3000, startLevel = 1 },
  r180 = { timeCapMs = 180000, countdownMs = 4000, startLevel = 1 },
  daily120 = { timeCapMs = 120000, countdownMs = 3000, startLevel = 1, seedPattern = "^srwow%-daily%-%d%d%d%d%-%d%d%-%d%d$" },
}
C.PLATFORMS = { ["wow-forever"] = true, ["wow-retail"] = true, ["wow-classic"] = true }
C.MAX_CODE = 32768

local function P() return ns.Protocol end

local function check(body) return string.format("%08x", ns.Prng.hashString(body)) end

local function isSeed(s) return type(s) == "string" and #s >= 1 and #s <= 64 and s:match("^[a-z0-9%-]+$") ~= nil end

local function b36(n) return P().b36(n) end
local function unb36(s)
  if type(s) ~= "string" or (s ~= "0" and s:sub(1, 1) == "0") then return nil end -- canonical only
  return P().unb36(s)
end

function C.hex(s) return (s:gsub(".", function(ch) return string.format("%02x", ch:byte()) end)) end
function C.unhex(h)
  if type(h) ~= "string" or #h % 2 ~= 0 or not h:match("^[0-9a-f]+$") then return nil end
  return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end))
end

--- Strict UTF-8 check (no overlongs, no surrogates, max U+10FFFF).
function C.utf8ok(s)
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local len, lo, hi = 1, 0x80, 0xBF
    if c < 0x80 then len = 1
    elseif c >= 0xC2 and c <= 0xDF then len = 2
    elseif c >= 0xE0 and c <= 0xEF then len = 3; if c == 0xE0 then lo = 0xA0 elseif c == 0xED then hi = 0x9F end
    elseif c >= 0xF0 and c <= 0xF4 then len = 4; if c == 0xF0 then lo = 0x90 elseif c == 0xF4 then hi = 0x8F end
    else return false end
    if len > 1 then
      if i + len - 1 > n then return false end
      local c2 = s:byte(i + 1)
      if c2 < lo or c2 > hi then return false end
      for k = i + 2, i + len - 1 do local ck = s:byte(k); if ck < 0x80 or ck > 0xBF then return false end end
    end
    i = i + len
  end
  return true
end

local function seedOk(rulesetId, seed)
  local rs = C.RULESETS[rulesetId]
  if not rs or not isSeed(seed) then return false end
  return not rs.seedPattern or seed:match(rs.seedPattern) ~= nil
end

local function split(code)
  local f = {}
  for part in (code .. "."):gmatch("([^.]*)%.") do f[#f + 1] = part end
  return f
end

local function finish(fields)
  local body = table.concat(fields, ".")
  return body .. "." .. check(body)
end

--- Challenge code for a ruleset and seed.
function C.challenge(rulesetId, seed, engine)
  assert(seedOk(rulesetId, seed), "bad ruleset/seed")
  return finish({ "SR1C", rulesetId, "e" .. (engine or ns.Engine.ENGINE_VERSION), seed })
end

local function clean(code)
  if type(code) ~= "string" or #code > C.MAX_CODE then return nil end
  return (code:gsub("%s", "")) -- pasted codes may be wrapped or have spaces
end

local function verifyCheck(f)
  local last = f[#f]
  local body = table.concat(f, ".", 1, #f - 1)
  return last:match("^%x%x%x%x%x%x%x%x$") ~= nil and last == check(body)
end

--- Parse a challenge code -> { ruleset, engine, seed } or nil, reason.
function C.parseChallenge(code)
  code = clean(code)
  if not code then return nil, "size" end
  local f = split(code)
  if f[1] ~= "SR1C" then return nil, "format" end
  if #f ~= 5 then return nil, "fields" end
  if not verifyCheck(f) then return nil, "check" end
  local eng = f[3]:match("^e([1-9]%d?%d?%d?)$")
  if not eng then return nil, "engine" end
  if not seedOk(f[2], f[4]) then return nil, "ruleset_or_seed" end
  return { ruleset = f[2], engine = tonumber(eng), seed = f[4] }
end

--- Result code. r = { platform, ruleset, seed, ticks, score, lines, level, hash, player, link?, log (flat {t,a,...}), engine? }
function C.result(r)
  assert(C.PLATFORMS[r.platform], "platform")
  assert(seedOk(r.ruleset, r.seed), "ruleset/seed")
  assert(type(r.hash) == "string" and r.hash:match("^%x%x%x%x%x%x%x%x$"), "hash")
  local link = r.link or "-"
  assert(link == "-" or link:match("^[A-Z0-9]+$") and #link >= 6 and #link <= 12, "link")
  local player = C.hex(r.player)
  assert(#player >= 2 and #player <= 128 and C.utf8ok(r.player), "player")
  return finish({
    "SR1R", r.platform, r.ruleset, "e" .. (r.engine or ns.Engine.ENGINE_VERSION), r.seed,
    b36(r.ticks), b36(r.score), b36(r.lines), b36(r.level), r.hash:lower(), player, link, P().packLog(r.log),
  })
end

--- Parse a result code -> table or nil, reason. Decoding only: the score is NOT trusted until the
--- receiver replays the log (website: verifyLog; addon tests: Engine/Verify.lua).
function C.parseResult(code)
  code = clean(code)
  if not code then return nil, "size" end
  local f = split(code)
  if f[1] ~= "SR1R" then return nil, "format" end
  if #f ~= 14 then return nil, "fields" end
  if not verifyCheck(f) then return nil, "check" end
  if not C.PLATFORMS[f[2]] then return nil, "platform" end
  local eng = f[4]:match("^e([1-9]%d?%d?%d?)$")
  if not eng then return nil, "engine" end
  if not seedOk(f[3], f[5]) then return nil, "ruleset_or_seed" end
  local ticks, score, lines, level = unb36(f[6]), unb36(f[7]), unb36(f[8]), unb36(f[9])
  if not (ticks and score and lines and level) then return nil, "numbers" end
  if not f[10]:match("^[0-9a-f]+$") or #f[10] ~= 8 then return nil, "hash" end
  local player = (#f[11] >= 2 and #f[11] <= 128) and C.unhex(f[11])
  if not player or not C.utf8ok(player) then return nil, "player" end
  local link = f[12]
  if not (link == "-" or (link:match("^[A-Z0-9]+$") and #link >= 6 and #link <= 12)) then return nil, "link" end
  local log = P().unpackLog(f[13])
  if not log then return nil, "log" end
  for i = 1, #log, 2 do if log[i] > ticks then return nil, "log" end end
  return {
    platform = f[2], ruleset = f[3], engine = tonumber(eng), seed = f[5], ticks = ticks, score = score,
    lines = lines, level = level, hash = f[10], player = player, link = (link ~= "-") and link or nil, log = log,
  }
end

return C
