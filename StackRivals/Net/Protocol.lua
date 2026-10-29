--[[
  StackRivals duel protocol v1 - encode / decode / validate. Pure Lua, no WoW API.

  Every message is plain printable ASCII, fields separated by ":", at most 255 bytes (the WoW
  addon-message limit), so it also works with the "logged" send variant. Nothing ever sends the
  board: the match is a score race on a shared seed, so players exchange a few control messages,
  a score heartbeat every 2 seconds and, at the end, their compressed input log for a peer check.

    1:HEL:<addonVer>:<engine>                       who has StackRivals? (guild/party broadcast)
    1:HI:<addonVer>:<engine>:<busy>                 reply (whisper)
    1:INV:<mid>:<ruleset>:<engine>:<commitA>        challenge; commitA = hex FNV-1a of "srcommit-<mid>-<nonceA>"
    1:ACC:<mid>:<nonceB>                            accept: the guest picks nonceB without knowing nonceA
    1:DEC:<mid>:<reason>                            decline / cancel before start
    1:RDY:<mid>[:<loadout>]                         I'm ready (Spell Battle: + my 4 spells, locked; 0.5+)
    1:GO:<mid>:<nonceA>[:<loadout>]                 inviter: both ready, countdown starts now; reveals
                                                    nonceA (must match commitA). seed = srduel-<mid>-<nonceA><nonceB>,
                                                    so neither player can pick or grind the seed
    1:PNG:<mid>                                     keep-alive while not playing
    1:SC:<mid>:<tick36>:<score36>:<lines36>:<over>  live score heartbeat
    1:END:<mid>:<ticks36>:<score36>:<lines36>:<level36>:<hash>:<chunks>
    1:LOG:<mid>:<i>:<n>:<payload>                   input log chunk i of n
    1:RQ:<mid>:<i>                                  please (re)send log chunk i
    1:BYE:<mid>:<reason>                            forfeit (during play) / left (after my own run ended)
    1:FIN:<mid>                                     I have your END and your complete log: stop re-sending
                                                    (an accepted send is never proof of delivery)
    1:SP:<mid>:<seq>:<tick36>:<spell>               Spell Battle (0.5+): I cast a spell on you at my tick;
                                                    it lands on your board at tick + 90 (Spells.DELIVERY_TICKS)

  Spell Battle (ruleset s180) uses the same flow; only clients 0.5+ know s180, SP and the cast
  letters in the log (H..P = cast codes 100..108). Classic duels (b120 / r180) are unchanged, so
  0.4 and 0.5 clients still duel each other in those.
]]
local _, ns = ...
ns = ns or {}

local P = {}
ns.Protocol = P

P.VERSION = 1
P.PREFIX = "StackRivals"       -- 11 of the allowed 16 characters
P.MAX_LEN = 255
P.CHUNK_PAYLOAD = 200

P.RULESETS = {
  -- id = { name, ticks, countdown ticks }
  b120 = { id = "b120", name = "Duel - Blitz 2:00", limitTicks = 7200, countdownTicks = 180 },
  r180 = { id = "r180", name = "Duel - 3:00 (web rules)", limitTicks = 10800, countdownTicks = 240 },
  -- Spell Battle: the web's 3:00 cap and 4 s countdown; the result = lockstep replay of both logs
  s180 = { id = "s180", name = "Spell Duel - 3:00 (web rules)", limitTicks = 10800, countdownTicks = 240, spell = true },
}
--- Oldest addon version that knows each ruleset (for the duel sheet: who can play what).
P.RULESET_MIN_VERSION = { s180 = "0.5.0" }

--- "0.4.0" < "0.5.0"? (numeric parts; anything unparsable counts as old)
function P.versionAtLeast(v, min)
  local a = {}
  for n in tostring(v or ""):gmatch("%d+") do a[#a + 1] = tonumber(n) end
  local b = {}
  for n in tostring(min):gmatch("%d+") do b[#b + 1] = tonumber(n) end
  if #a == 0 then return false end
  for i = 1, math.max(#a, #b) do
    local x, y = a[i] or 0, b[i] or 0
    if x ~= y then return x > y end
  end
  return true
end

P.DECLINE = { no = true, busy = true, combat = true, version = true, timeout = true, cancel = true, ruleset = true }
P.BYE = { forfeit = true, left = true, quit = true, timeout = true, combat = true }

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"

function P.b36(n)
  n = math.floor(n)
  if n < 0 then return nil end
  if n == 0 then return "0" end
  local s = ""
  while n > 0 do
    local d = n % 36
    s = B36:sub(d + 1, d + 1) .. s
    n = math.floor(n / 36)
  end
  return s
end

function P.unb36(s)
  if type(s) ~= "string" or s == "" or #s > 9 or not s:match("^[0-9a-z]+$") then return nil end
  return tonumber(s, 36)
end

local function isMid(s) return type(s) == "string" and #s >= 4 and #s <= 10 and s:match("^[0-9a-z]+$") ~= nil end
local function isNonce(s) return type(s) == "string" and #s >= 4 and #s <= 12 and s:match("^[0-9a-z]+$") ~= nil end
local function isVer(s) return type(s) == "string" and #s >= 1 and #s <= 20 and s:match("^[%w%.%-]+$") ~= nil end
local function isInt(s, lo, hi)
  local n = tonumber(s)
  return n ~= nil and n % 1 == 0 and n >= lo and n <= hi and tostring(s):match("^%d+$") ~= nil
end

--- Commitment to the inviter's nonce (sent in INV, checked against the nonce revealed in GO).
function P.commit(mid, nonce)
  local h = ns.Prng and ns.Prng.hashString("srcommit-" .. mid .. "-" .. nonce)
  return string.format("%08x", h or 0)
end

--- Build a message string (fields are validated by decode on the receiving side and in tests).
function P.encode(kind, ...)
  local parts = { tostring(P.VERSION), kind }
  local n = select("#", ...)
  while n > 0 and select(n, ...) == nil do n = n - 1 end -- optional trailing fields left out
  for i = 1, n do parts[#parts + 1] = tostring((select(i, ...))) end
  local s = table.concat(parts, ":")
  assert(#s <= P.MAX_LEN, "message too long")
  return s
end

local SPEC = {
  HEL = 2, HI = 3, INV = 4, ACC = 2, DEC = 2, RDY = 1, GO = 2, PNG = 1, SC = 5, END = 7, LOG = 4, BYE = 2, RQ = 2, FIN = 1,
  SP = 4,
}
local OPTIONAL = { RDY = 1, GO = 1 } -- extra trailing fields a kind may carry (newer clients)

--- Parse and validate. Returns a table {kind=..., ...} or nil, reason.
function P.decode(s)
  if type(s) ~= "string" or #s == 0 or #s > P.MAX_LEN then return nil, "size" end
  if s:find("[^%w%.%-:,]") then return nil, "chars" end
  local f = {}
  for part in (s .. ":"):gmatch("([^:]*):") do f[#f + 1] = part end
  if f[1] ~= tostring(P.VERSION) then return nil, "version" end
  local kind = f[2]
  local want = SPEC[kind]
  if not want then return nil, "kind" end
  if #f - 2 ~= want and not (OPTIONAL[kind] and #f - 2 > want and #f - 2 <= want + OPTIONAL[kind]) then return nil, "fields" end
  local m = { kind = kind }
  if kind == "HEL" then
    if not isVer(f[3]) or not isInt(f[4], 1, 9999) then return nil, "bad" end
    m.addon, m.engine = f[3], tonumber(f[4])
  elseif kind == "HI" then
    if not isVer(f[3]) or not isInt(f[4], 1, 9999) or (f[5] ~= "0" and f[5] ~= "1") then return nil, "bad" end
    m.addon, m.engine, m.busy = f[3], tonumber(f[4]), f[5] == "1"
  elseif kind == "INV" then
    if not isMid(f[3]) or not P.RULESETS[f[4]] or not isInt(f[5], 1, 9999) or not isNonce(f[6]) then return nil, "bad" end
    m.mid, m.ruleset, m.engine, m.nonce = f[3], f[4], tonumber(f[5]), f[6]
  elseif kind == "ACC" then
    if not isMid(f[3]) or not isNonce(f[4]) then return nil, "bad" end
    m.mid, m.nonce = f[3], f[4]
  elseif kind == "DEC" or kind == "BYE" then
    local allowed = (kind == "DEC") and P.DECLINE or P.BYE
    if not isMid(f[3]) or not allowed[f[4]] then return nil, "bad" end
    m.mid, m.reason = f[3], f[4]
  elseif kind == "GO" then
    if not isMid(f[3]) or not isNonce(f[4]) then return nil, "bad" end
    m.mid, m.nonce = f[3], f[4]
    if f[5] then -- Spell Battle: the host's loadout again (its RDY may arrive after GO)
      if not (ns.Spells and ns.Spells.decodeLoadout(f[5])) then return nil, "bad" end
      m.loadout = f[5]
    end
  elseif kind == "RDY" or kind == "PNG" or kind == "FIN" then
    if not isMid(f[3]) then return nil, "bad" end
    m.mid = f[3]
    if kind == "RDY" and f[4] then
      if not (ns.Spells and ns.Spells.decodeLoadout(f[4])) then return nil, "bad" end
      m.loadout = f[4]
    end
  elseif kind == "SP" then
    local t, sp = P.unb36(f[5]), tonumber(f[6])
    if not isMid(f[3]) or not isInt(f[4], 1, 9999) or not t or not isInt(f[6], 0, 8) then return nil, "bad" end
    local id = ns.Spells and ns.Spells.SPELLS[sp + 1]
    if not id or ns.Spells.INFO[id].target ~= "opponent" then return nil, "bad" end
    m.mid, m.seq, m.tick, m.spell = f[3], tonumber(f[4]), t, id
  elseif kind == "SC" then
    local t, sc, ln = P.unb36(f[4]), P.unb36(f[5]), P.unb36(f[6])
    if not isMid(f[3]) or not t or not sc or not ln or (f[7] ~= "0" and f[7] ~= "1") then return nil, "bad" end
    m.mid, m.tick, m.score, m.lines, m.over = f[3], t, sc, ln, f[7] == "1"
  elseif kind == "END" then
    local t, sc, ln, lv = P.unb36(f[4]), P.unb36(f[5]), P.unb36(f[6]), P.unb36(f[7])
    if not isMid(f[3]) or not t or not sc or not ln or not lv or not f[8]:match("^%x%x%x%x%x%x%x%x$") or not isInt(f[9], 0, 200) then return nil, "bad" end
    m.mid, m.ticks, m.score, m.lines, m.level, m.hash, m.chunks = f[3], t, sc, ln, lv, f[8], tonumber(f[9])
  elseif kind == "RQ" then
    if not isMid(f[3]) or not isInt(f[4], 1, 200) then return nil, "bad" end
    m.mid, m.i = f[3], tonumber(f[4])
  elseif kind == "LOG" then
    if not isMid(f[3]) or not isInt(f[4], 1, 200) or not isInt(f[5], 1, 200) or tonumber(f[4]) > tonumber(f[5]) then return nil, "bad" end
    if #f[6] > P.CHUNK_PAYLOAD or not f[6]:match("^[0-9a-zA-P]*$") then return nil, "bad" end
    m.mid, m.i, m.n, m.payload = f[3], tonumber(f[4]), tonumber(f[5]), f[6]
  end
  return m
end

------------------------------------------------------------------------------------------------
-- Compact input-log codec: each input = tick delta in base36 (lowercase/digits) + action letter
-- A..G (action index 0..6). "3A0Bc C" style, no separators. ~2.5 bytes per input.
-- Spell Battle casts (codes 100..108) are the letters H..P; classic logs never contain them.
------------------------------------------------------------------------------------------------
local function codeLetter(c)
  if c >= 0 and c <= 6 then return string.char(65 + c) end
  if c >= 100 and c <= 108 then return string.char(72 + c - 100) end
  error("code can't be packed: " .. tostring(c))
end
local function letterCode(b) return (b <= 71) and (b - 65) or (100 + b - 72) end

function P.packLog(log)
  local out, prev = {}, 0
  for i = 1, #log, 2 do
    local d = log[i] - prev
    prev = log[i]
    out[#out + 1] = P.b36(d) .. codeLetter(log[i + 1])
  end
  return table.concat(out)
end

function P.unpackLog(s)
  if type(s) ~= "string" or not s:match("^[0-9a-zA-P]*$") then return nil end
  local log, t = {}, 0
  for d, a in s:gmatch("([0-9a-z]+)([A-P])") do
    local delta = P.unb36(d)
    if not delta then return nil end
    t = t + delta
    log[#log + 1] = t
    log[#log + 1] = letterCode(a:byte())
  end
  -- every character must belong to a pair
  if P.packLog(log) ~= s then return nil end
  return log
end

--- Split a packed log into chunks that fit one LOG message each (never inside a pair).
function P.chunk(packed)
  local chunks, i, n = {}, 1, #packed
  while i <= n do
    local j = math.min(n, i + P.CHUNK_PAYLOAD - 1)
    if j < n then
      -- move the cut back to just after an action letter
      while j > i and not packed:sub(j, j):match("[A-P]") do j = j - 1 end
    end
    chunks[#chunks + 1] = packed:sub(i, j)
    i = j + 1
  end
  if #chunks == 0 then chunks[1] = "" end
  return chunks
end

--- Random lowercase base36 token from a random function returning integers in [0, 35].
function P.token(len, rnd)
  local t = {}
  for i = 1, len do
    local d = rnd(0, 35)
    t[i] = B36:sub(d + 1, d + 1)
  end
  return table.concat(t)
end

function P.seed(mid, nonceA, nonceB) return "srduel-" .. mid .. "-" .. nonceA .. nonceB end

return P
