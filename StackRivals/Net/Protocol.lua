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
    1:PSE:<mid>:<n>:<reason>[:<tick36>]             (0.5+) my run is paused (pause #n: combat, chat, ...) at my
                                                    tick; yours pauses too; repeated while it lasts. A score
                                                    heartbeat (SC) past that tick also means "resumed"
    1:RSM:<mid>:<n>                                 (0.5+) I'm ready again after pause #n (both resume together)
    1:VER:<mid>:<w|l|d|v>:<my36>:<your36>:<basis>[:<ack>]  (0.5+) my final verdict (ack 1 = I have yours), so both PCs can confirm the same
                                                    result. basis = what my verdict rests on: r = both games
                                                    replayed, x = your result failed my replay check,
                                                    f = forfeit / left / log never sent, t = lost contact or
                                                    out of time, v = no result (0 / 1 = x / r, older builds)
    1:INV:...:<nonce>[:q]                           (0.6.1+) q = a Quickplay match (both players were searching)
    1:QS:<qid>:<ruleset>:<version>                  (0.6.1+) Quickplay: I'm searching for a <ruleset> match
                                                    (broadcast to GUILD / PARTY / RAID, whispered to friends
                                                    whose StackRivals answered); repeated while searching
    1:PRF:<mid>:<faction>:<race>:<class>:<level>:<w36>:<l36>:<chat>
                                                    (0.6.1+) my character card for this match, self-reported:
                                                    A / H / N(eutral) / -, race and class tokens (UnitRace /
                                                    UnitClass file names) or "-", level 0-200 (0 = hidden),
                                                    my played-out duel W / L, chat 1 = match chat on
    1:CH:<mid>:<n>:<hex>                            (0.6.1+) match chat line n (UTF-8 as hex, max 80 bytes)
    1:QM:<mid>:<n>:<code>                           (0.6.1+) quick message n: 1 GL, 2 GG, 3 WP, 4 Rematch?
    Loot Duel (0.7.2: 2-40 players at once), all on the group channel (PARTY / RAID / INSTANCE_CHAT);
    <lid> = loot duel id, names = hex of "Name-Realm" (UTF-8), <i> = 1-based position in the invite
    list (every PC has it from LDI). See docs/LOOT_DUEL.md. The offer kind changes whenever the start
    messages change, so dev builds never mix half-way: 0.7.0 dev LDO, 0.7.1 dev LDF, 0.7.2 dev LDH,
    0.7.3 LDJ.
    1:LDJ:<lid>:<l060|l120>:<engine>:<itemId>:<commitL16>:<invitees>   offer (leader / assist / loot master)
    1:LDI:<lid>:<k>:<hexName>[,<hexName>...]         invitee list chunk k (1-20); a name on the leader's
                                                     realm is sent without "-Realm" (0.7.2)
    1:LDA:<lid>:<a|d>:<commit16|->                    my answer (+ the commitment to my secret seed nonce)
    1:LDQ:<lid>:<listHash>:<count>:<k>:<n>:<i>-<commit16>[,...]  the fixed list, chunk k of n: reveal now
    1:LDS:<lid>:<listHash>:<count>:<mask10>:<leaderCommit16|->  (0.7.2, > 10 players) the fixed list in
                                                     ONE message: places as a bit mask; every PC already has
                                                     each player's commitment from their LDA (the leader's,
                                                     sent right behind the offer, is repeated here). LDQ
                                                     follows only on repeats, for whoever missed an LDA.
    1:LDN:<lid>:<nonce>                               my nonce (matches my commitment)
    1:LDG:<lid>:<nonceL>:<revealHash>:<leaderNonce|->:<age>  (0.7.3, > 10 players) go in ONE message: every
                                                     PC has the players' nonces from their LDN; LDW follows
                                                     right behind it for whoever missed one. <age> = s since
                                                     the leader's go (0 on the first send): a player whose go
                                                     came late plays the rest, so every run ends together
    1:LDW:<lid>:<nonceL>:<revealHash>:<age>:<k>:<n>:<i>-<nonce>[,...]  go, chunk k of n: every nonce + the
                                                     leader's; <age> as in LDG (0.7.3)
    1:LDC:<lid>:<tick36>:<score36>                     my live score
    1:LDE:<lid>:<ticks36>:<score36>:<lines36>:<level36>:<hash>:<chunks>   my final result
    1:LDL:<lid>:<i>:<n>:<payload>                      my log chunk i of n (as LOG)
    1:LDK:<lid>:<i>:<e|chunks>                         (0.7.3) "player at place i: send again" - e = your claim
                                                     (LDE), or the log chunks I miss, as 1.4.5; anyone
                                                     missing the same waits instead of asking too
    1:CTP:<id>                                       (0.8.1) /sr commtest: "who gets this?" (group channel)
    1:CTA:<id>:<addonVersion>                        (0.8.1) answer on the same channel, once per id
    1:LDX:<lid>:<cancel|left|noreveal>                 the leader cancelled
    1:LDR:<lid>:<hexWinner|->:<tie 0|1>                the leader's computed result (display only)
  Older clients ignore kinds they don't know (decode -> "kind"), so these never break a 0.4 duel.

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
  b120 = { id = "b120", name = "Duel 2:00", limitTicks = 7200, countdownTicks = 180 },
  r180 = { id = "r180", name = "Duel 3:00", limitTicks = 10800, countdownTicks = 240 },
  -- Spell Battle: the web's 3:00 cap and 4 s countdown; the result = lockstep replay of both logs
  s180 = { id = "s180", name = "Spell Duel 3:00", limitTicks = 10800, countdownTicks = 240, spell = true },
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
local function isC16(s) return type(s) == "string" and #s == 16 and s:match("^[0-9a-f]+$") ~= nil end
local function isNonce(s) return type(s) == "string" and #s >= 4 and #s <= 12 and s:match("^[0-9a-z]+$") ~= nil end
local function isVer(s) return type(s) == "string" and #s >= 1 and #s <= 20 and s:match("^[%w%.%-]+$") ~= nil end
local function isInt(s, lo, hi)
  local n = tonumber(s)
  return n ~= nil and n % 1 == 0 and n >= lo and n <= hi and tostring(s):match("^%d+$") ~= nil
end

--- Commitment to the inviter's nonce (sent in INV, checked against the nonce revealed in GO).
--- 64-bit commitment (two independent FNV-1a 32 hashes): finding a second nonce with the same
--- commitment to steer a seed is out of reach in a game session (Loot Duel).
function P.commit16(id, nonce)
  local H = ns.Prng and ns.Prng.hashString
  if not H then return "0000000000000000" end
  return string.format("%08x%08x", H("srcommit-" .. id .. "-" .. nonce), H(nonce .. "|" .. id .. "|srloot-c2"))
end
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
  SP = 4, PSE = 3, RSM = 2, VER = 5,
  QS = 3, PRF = 8, CH = 3, QM = 3,
  LDJ = 6, LDI = 3, LDA = 3, LDQ = 6, LDS = 5, LDN = 2, LDG = 5, LDW = 7, LDC = 3, LDE = 7, LDL = 4, LDK = 3, LDX = 2, CTP = 1, CTA = 2, LDR = 3,
}
--- Loot Duel rules (WoW-only, peer-checked): same pieces for everyone, no spells, highest score.
P.LOOT_RULESETS = {
  l060 = { id = "l060", name = "Loot Duel 1:00", limitTicks = 3600, countdownTicks = 180 },
  l120 = { id = "l120", name = "Loot Duel 2:00", limitTicks = 7200, countdownTicks = 180 },
}
P.LOOT_MAX = 40 -- participants (all play at once; 2-40, a full raid)
--- Places (1..LOOT_MAX) as a fixed-length hex bit mask: 10 digits for 40, digit j holds places
--- 4j-3..4j (lowest bit first). Pure arithmetic: Lua 5.1 has no bit operators.
function P.placeMask(places)
  local dig = {}
  for j = 1, P.LOOT_MAX / 4 do dig[j] = 0 end
  local seen = {}
  for _, pl in ipairs(places) do
    if not seen[pl] and pl >= 1 and pl <= P.LOOT_MAX then
      seen[pl] = true
      local j = math.floor((pl - 1) / 4) + 1
      dig[j] = dig[j] + 2 ^ ((pl - 1) % 4)
    end
  end
  for j = 1, #dig do dig[j] = string.format("%x", math.floor(dig[j])) end
  return table.concat(dig)
end
function P.unplaceMask(h)
  if type(h) ~= "string" or #h ~= P.LOOT_MAX / 4 or not h:match("^[0-9a-f]+$") then return nil end
  local list = {}
  for j = 1, #h do
    local v = tonumber(h:sub(j, j), 16)
    for b = 0, 3 do
      if v % 2 == 1 then list[#list + 1] = (j - 1) * 4 + b + 1 end
      v = math.floor(v / 2)
    end
  end
  return list
end
local function hexName(h) return type(h) == "string" and #h >= 4 and #h <= 128 and #h % 2 == 0 and h:match("^[0-9a-f]+$") ~= nil end
local function unhexName(h)
  if not hexName(h) then return nil end
  local s = h:gsub("..", function(x) return string.char(tonumber(x, 16)) end)
  if s:find("[%c|]") or not s:find("-", 1, true) then return nil end
  return s
end
P.unhexName = unhexName
--- Like unhexName, but a bare "Name" (no realm) is allowed: the invite list leaves out the
--- leader's own realm to save space (the receiver adds it back).
local function unhexLoose(h)
  if not hexName(h) and not (type(h) == "string" and #h >= 2 and #h <= 128 and #h % 2 == 0 and h:match("^[0-9a-f]+$")) then return nil end
  local s = h:gsub("..", function(x) return string.char(tonumber(x, 16)) end)
  if s:find("[%c|]") or s:find("^%-") or s:find("%-$") then return nil end
  return s
end
P.unhexLoose = unhexLoose
function P.hexName(s) return (s:gsub(".", function(ch) return string.format("%02x", ch:byte()) end)) end
P.FACTIONS = { A = "Alliance", H = "Horde", N = "Neutral" }
P.QUICK = { "Good luck!", "GG!", "Well played!", "Rematch?" }
P.CHAT_MAX = 80 -- bytes of UTF-8 text per chat line
P.PAUSE_REASONS = { combat = true, chat = true, manual = true, hidden = true, loading = true, settings = true, restored = true, frozen = true }
local OPTIONAL = { RDY = 1, GO = 1, PSE = 1, VER = 1, INV = 1 } -- extra trailing fields a kind may carry (newer clients)
--- VER basis codes (see the header). Scores are only compared when both verdicts rest on a replay.
P.VER_BASIS = { r = "replay", x = "rejected", f = "forfeit", t = "timeout", v = "void", ["1"] = "replay", ["0"] = "rejected" }
P.VER_CODE = { replay = "r", rejected = "x", forfeit = "f", timeout = "t", void = "v" }

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
    if f[7] then
      if f[7] ~= "q" then return nil, "bad" end
      m.quickplay = true
    end
  elseif kind == "QS" then
    if not isMid(f[3]) or not P.RULESETS[f[4]] or not isVer(f[5]) then return nil, "bad" end
    m.qid, m.ruleset, m.addon = f[3], f[4], f[5]
  elseif kind == "PRF" then
    local tok = function(x) return x == "-" or (type(x) == "string" and #x <= 16 and x:match("^%a+$") ~= nil) end
    local w, l = P.unb36(f[8]), P.unb36(f[9])
    if not isMid(f[3]) or not (f[4] == "-" or P.FACTIONS[f[4]]) or not tok(f[5]) or not tok(f[6]) or not isInt(f[7], 0, 200)
      or not w or not l or w > 1e7 or l > 1e7 or (f[10] ~= "0" and f[10] ~= "1") then return nil, "bad" end
    m.mid, m.faction, m.race, m.class, m.level, m.wins, m.losses, m.chat = f[3], P.FACTIONS[f[4]], f[5] ~= "-" and f[5] or nil,
      f[6] ~= "-" and f[6] or nil, tonumber(f[7]), w, l, f[10] == "1"
  elseif kind == "CH" then
    local hex = f[5]
    if not isMid(f[3]) or not isInt(f[4], 1, 9999) or type(hex) ~= "string" or #hex < 2 or #hex > 2 * P.CHAT_MAX or #hex % 2 ~= 0 or not hex:match("^[0-9a-f]+$") then return nil, "bad" end
    m.mid, m.n, m.text = f[3], tonumber(f[4]), (hex:gsub("..", function(x) return string.char(tonumber(x, 16)) end))
  elseif kind == "CTP" then
    if not isMid(f[3]) then return nil, "bad" end
    m.id = f[3]
  elseif kind == "CTA" then
    if not isMid(f[3]) or not isVer(f[4]) then return nil, "bad" end
    m.id, m.version = f[3], f[4]
  elseif kind == "QM" then
    if not isMid(f[3]) or not isInt(f[4], 1, 9999) or not isInt(f[5], 1, #P.QUICK) then return nil, "bad" end
    m.mid, m.n, m.code = f[3], tonumber(f[4]), tonumber(f[5])
  elseif kind == "LDJ" then
    if not isMid(f[3]) or not P.LOOT_RULESETS[f[4]] or not isInt(f[5], 1, 9999) or not isInt(f[6], 1, 9999999)
      or not isC16(f[7]) or not isInt(f[8], 2, P.LOOT_MAX) then return nil, "bad" end
    m.lid, m.rs, m.engine, m.itemId, m.commit, m.count = f[3], f[4], tonumber(f[5]), tonumber(f[6]), f[7], tonumber(f[8])
  elseif kind == "LDI" then
    if not isMid(f[3]) or not isInt(f[4], 1, 20) then return nil, "bad" end
    m.lid, m.k, m.names = f[3], tonumber(f[4]), {}
    for part in (f[5] .. ","):gmatch("([^,]*),") do
      local nm = unhexLoose(part)
      if not nm or #m.names >= P.LOOT_MAX then return nil, "bad" end
      m.names[#m.names + 1] = nm
    end
  elseif kind == "LDA" then
    if not isMid(f[3]) or (f[4] ~= "a" and f[4] ~= "d") then return nil, "bad" end
    if f[4] == "a" and not isC16(f[5]) then return nil, "bad" end
    if f[4] == "d" and f[5] ~= "-" then return nil, "bad" end
    m.lid, m.accept, m.commit = f[3], f[4] == "a", f[4] == "a" and f[5] or nil
  elseif kind == "LDQ" then
    if not isMid(f[3]) or not f[4]:match("^%x%x%x%x%x%x%x%x$") or not isInt(f[5], 2, P.LOOT_MAX)
      or not isInt(f[6], 1, 9) or not isInt(f[7], 1, 9) or tonumber(f[6]) > tonumber(f[7]) then return nil, "bad" end
    m.lid, m.listHash, m.count, m.k, m.n, m.entries = f[3], f[4], tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), {}
    for part in (f[8] .. ","):gmatch("([^,]*),") do
      local i, c = part:match("^(%d+)%-([0-9a-f]+)$")
      if not i or not isInt(i, 1, P.LOOT_MAX) or not isC16(c) or #m.entries >= P.LOOT_MAX then return nil, "bad" end
      m.entries[#m.entries + 1] = { i = tonumber(i), commit = c }
    end
  elseif kind == "LDS" then
    local places = P.unplaceMask(f[6])
    if not isMid(f[3]) or not f[4]:match("^%x%x%x%x%x%x%x%x$") or not isInt(f[5], 2, P.LOOT_MAX)
      or not places or #places ~= tonumber(f[5]) or not (f[7] == "-" or isC16(f[7])) then return nil, "bad" end
    m.lid, m.listHash, m.count, m.places, m.leaderCommit = f[3], f[4], tonumber(f[5]), places, f[7] ~= "-" and f[7] or nil
  elseif kind == "LDN" then
    if not isMid(f[3]) or not isNonce(f[4]) then return nil, "bad" end
    m.lid, m.nonce = f[3], f[4]
  elseif kind == "LDG" then
    if not isMid(f[3]) or not isNonce(f[4]) or not f[5]:match("^%x%x%x%x%x%x%x%x$") or not (f[6] == "-" or isNonce(f[6]))
      or not isInt(f[7], 0, 999) then return nil, "bad" end
    m.lid, m.nonce, m.revealHash, m.leaderNonce, m.age = f[3], f[4], f[5], f[6] ~= "-" and f[6] or nil, tonumber(f[7])
  elseif kind == "LDW" then
    if not isMid(f[3]) or not isNonce(f[4]) or not f[5]:match("^%x%x%x%x%x%x%x%x$") or not isInt(f[6], 0, 999)
      or not isInt(f[7], 1, 9) or not isInt(f[8], 1, 9) or tonumber(f[7]) > tonumber(f[8]) then return nil, "bad" end
    m.lid, m.nonce, m.revealHash, m.age, m.k, m.n, m.entries = f[3], f[4], f[5], tonumber(f[6]), tonumber(f[7]), tonumber(f[8]), {}
    for part in (f[9] .. ","):gmatch("([^,]*),") do
      local i, nonce = part:match("^(%d+)%-([0-9a-z]+)$")
      if not i or not isInt(i, 1, P.LOOT_MAX) or not isNonce(nonce) or #m.entries >= P.LOOT_MAX then return nil, "bad" end
      m.entries[#m.entries + 1] = { i = tonumber(i), nonce = nonce }
    end
  elseif kind == "LDK" then
    if not isMid(f[3]) or not isInt(f[4], 1, P.LOOT_MAX) or not (f[5] == "e" or (#f[5] <= 60 and f[5]:match("^%d+[%d%.]*$"))) then return nil, "bad" end
    m.lid, m.i, m.what = f[3], tonumber(f[4]), f[5]
  elseif kind == "LDC" then
    local t, sc = P.unb36(f[4]), P.unb36(f[5])
    if not isMid(f[3]) or not t or not sc then return nil, "bad" end
    m.lid, m.tick, m.score = f[3], t, sc
  elseif kind == "LDE" then
    local t, sc, ln, lv = P.unb36(f[4]), P.unb36(f[5]), P.unb36(f[6]), P.unb36(f[7])
    if not isMid(f[3]) or not t or not sc or not ln or not lv or not f[8]:match("^%x%x%x%x%x%x%x%x$") or not isInt(f[9], 0, 99) then return nil, "bad" end
    m.lid, m.ticks, m.score, m.lines, m.level, m.hash, m.chunks = f[3], t, sc, ln, lv, f[8], tonumber(f[9])
  elseif kind == "LDL" then
    if not isMid(f[3]) or not isInt(f[4], 1, 99) or not isInt(f[5], 1, 99) or tonumber(f[4]) > tonumber(f[5]) then return nil, "bad" end
    if #f[6] > P.CHUNK_PAYLOAD or not f[6]:match("^[0-9a-zA-G]*$") then return nil, "bad" end
    m.lid, m.i, m.n, m.payload = f[3], tonumber(f[4]), tonumber(f[5]), f[6]
  elseif kind == "LDX" then
    if not isMid(f[3]) or (f[4] ~= "cancel" and f[4] ~= "left" and f[4] ~= "noreveal") then return nil, "bad" end
    m.lid, m.reason = f[3], f[4]
  elseif kind == "LDR" then
    if not isMid(f[3]) or (f[4] ~= "-" and not unhexName(f[4])) or (f[5] ~= "0" and f[5] ~= "1") then return nil, "bad" end
    m.lid, m.winner, m.tie = f[3], f[4] ~= "-" and unhexName(f[4]) or nil, f[5] == "1"
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
  elseif kind == "PSE" then
    if not isMid(f[3]) or not isInt(f[4], 1, 999) or not P.PAUSE_REASONS[f[5]] then return nil, "bad" end
    m.mid, m.n, m.reason = f[3], tonumber(f[4]), f[5]
    if f[6] then
      m.tick = P.unb36(f[6])
      if not m.tick then return nil, "bad" end
    end
  elseif kind == "RSM" then
    if not isMid(f[3]) or not isInt(f[4], 0, 999) then return nil, "bad" end
    m.mid, m.n = f[3], tonumber(f[4])
  elseif kind == "VER" then
    local a, b = P.unb36(f[5]), P.unb36(f[6])
    if not isMid(f[3]) or not (f[4] == "w" or f[4] == "l" or f[4] == "d" or f[4] == "v") or not a or not b or not P.VER_BASIS[f[7]] then return nil, "bad" end
    m.mid, m.verdict, m.mine, m.yours, m.basis = f[3], f[4], a, b, P.VER_BASIS[f[7]]
    m.check = m.basis ~= "rejected"
    if f[8] then
      if f[8] ~= "0" and f[8] ~= "1" then return nil, "bad" end
      m.ack = f[8] == "1"
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
    if #f[6] > P.CHUNK_PAYLOAD or not f[6]:match("^[0-9a-zA-Z%.]*$") then return nil, "bad" end
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

--- Spell Battle duel log = the moves + casts, then "Z", then where the RIVAL'S spells actually
--- landed on this board: <landTick36>.<castTick36><Q..Y = spell index 0..8> each. The replay uses
--- exactly those landings (the receiver's board is the authority), so a live board is always its
--- replay, whatever the lag; every landing must match a cast the sender's replay allows.
function P.packSpellLog(log, landings)
  local out = { P.packLog(log), "Z" }
  for _, l in ipairs(landings or {}) do
    out[#out + 1] = P.b36(l.tick) .. "." .. P.b36(l.castTick) .. string.char(81 + ns.Spells.INDEX[l.spell])
  end
  return table.concat(out)
end

function P.unpackSpellLog(s)
  if type(s) ~= "string" then return nil end
  local moves, rest = s:match("^([0-9a-zA-P]*)Z([0-9a-z%.Q-Y]*)$")
  if not moves then return nil end
  local log = P.unpackLog(moves)
  if not log then return nil end
  local landings, prevTick = {}, -1
  local rebuilt = {}
  for lt, ct, letter in rest:gmatch("([0-9a-z]+)%.([0-9a-z]+)([Q-Y])") do
    local t, c = P.unb36(lt), P.unb36(ct)
    if not t or not c or t < prevTick then return nil end
    prevTick = t
    local spell = ns.Spells.SPELLS[letter:byte() - 81 + 1]
    if not spell or ns.Spells.INFO[spell].target ~= "opponent" then return nil end
    landings[#landings + 1] = { tick = t, castTick = c, spell = spell }
    rebuilt[#rebuilt + 1] = lt .. "." .. ct .. letter
  end
  if table.concat(rebuilt) ~= rest then return nil end -- every character belongs to a landing
  return log, landings
end

--- Split a packed log into chunks that fit one LOG message each (never inside a pair).
function P.chunk(packed)
  local chunks, i, n = {}, 1, #packed
  while i <= n do
    local j = math.min(n, i + P.CHUNK_PAYLOAD - 1)
    if j < n then
      -- move the cut back to just after an action letter
      while j > i and not packed:sub(j, j):match("[A-Z]") do j = j - 1 end
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
