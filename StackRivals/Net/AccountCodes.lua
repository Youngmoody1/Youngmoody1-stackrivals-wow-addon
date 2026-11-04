--[[
  StackRivals - account link and profile codes (DRAFT v1, not final until agreed with the
  stackrivals.io project). Pure Lua, no WoW API. Spec + test vectors: docs/ACCOUNT_SYNC_HANDOFF.md.

  The addon never talks to the website. The player carries short text codes between the two:

  1. Web link code (made by stackrivals.io for a logged-in player, typed into the addon):
       XXXX-XXXX   8 Crockford base32 symbols (0-9 A-Z without I L O U); the 8th is a check symbol
                   = (sum of value_i * (2i - 1) for i = 1..7) mod 32 (odd weights: every
                   single wrong symbol is caught). Case, spaces and the dash are ignored;
                   O -> 0 and I / L -> 1 (Crockford). Short-lived on the web (e.g. 10 minutes).
  2. Link request (made by the addon, pasted on the website):
       SRL1.<code8>.<platform>.<playerHex>.<linkId>.<addon>.<engine>.<issued36>.<check>
         platform   wow-forever | wow-retail | wow-classic
         playerHex  lowercase hex of "Name-Realm" (UTF-8)
         linkId     12 [a-z0-9], random per link request (public; binds the web's answer to it)
         addon      addon version with "-" instead of "." (0-6-1)
         engine     ENGINE_VERSION, decimal
         issued36   unix seconds (WoW server time), base 36
  3. Profile snapshot (made by stackrivals.io, pasted into the addon; also the link confirmation):
       SRP1.<linkId>.<playerHex>.<accountId>.<nameHex>.<issued36>.<expires36>.<level36>.<xp36>
           .<xpNext36>.<rankHex>.<seasonHex>.<seasonPct>.<w36>.<l36>.<d36>.<history>.<ach>.<cos>
           .<sig>.<check>
         accountId  4..40 [a-z0-9_-]: the web's public account ref (never an e-mail, never secret)
         nameHex    display name, 1..32 bytes UTF-8 (no control characters)
         rankHex / seasonHex   "-" or 1..24 bytes UTF-8
         seasonPct  0..100 (decimal)
         history    "-" or 1..10 entries joined by "~": <mode>-<w|l|d>-<my36>-<their36>-<at36>
         ach        "-" or <unlocked36>-<total36>
         cos        "-" or <owned36>-<equippedHex|->
         sig        "-" or 16..128 [A-Za-z0-9_-] (reserved: the web's signature; NOT checked by 0.6.1)
  check = 8 lowercase hex FNV-1a 32 of everything before ".<check>" (typo detection only).

  Nothing in a code is secret and nothing in it is trusted for rewards: the website stays the
  authority; a snapshot is display data for this character.
]]
local _, ns = ...
ns = ns or {}

local A = {}
ns.AccountCodes = A

A.LINK_FORMAT, A.PROFILE_FORMAT = "SRL1", "SRP1"
A.MAX_CODE = 4096
A.CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
A.PLATFORMS = { ["wow-forever"] = true, ["wow-retail"] = true, ["wow-classic"] = true }
A.MAX_HISTORY = 10

local function C() return ns.Codes end
local function P() return ns.Protocol end
local function check(body) return string.format("%08x", ns.Prng.hashString(body)) end
local function b36(n) return P().b36(n) end
local function unb36(s)
  if type(s) ~= "string" or (s ~= "0" and s:sub(1, 1) == "0") then return nil end
  return P().unb36(s)
end

local VAL = {}
for i = 1, #A.CROCKFORD do VAL[A.CROCKFORD:sub(i, i)] = i - 1 end

local function checkSymbol(seven)
  local sum = 0
  for i = 1, 7 do sum = sum + VAL[seven:sub(i, i)] * (2 * i - 1) end
  local v = sum % 32
  return A.CROCKFORD:sub(v + 1, v + 1)
end

--- Normalise a typed web link code -> "ABCD2345" or nil, reason ("format" | "check").
function A.parseWebCode(s)
  if type(s) ~= "string" then return nil, "format" end
  s = s:upper():gsub("[%s%-]", ""):gsub("O", "0"):gsub("[IL]", "1")
  if #s ~= 8 then return nil, "format" end
  for i = 1, 8 do if not VAL[s:sub(i, i)] then return nil, "format" end end
  if checkSymbol(s:sub(1, 7)) ~= s:sub(8, 8) then return nil, "check" end
  return s
end

--- Make a web link code from 7 symbols (tests and the web's reference implementation).
function A.makeWebCode(seven)
  assert(type(seven) == "string" and #seven == 7)
  for i = 1, 7 do assert(VAL[seven:sub(i, i)], "symbol") end
  return seven .. checkSymbol(seven)
end

--- "ABCD2345" -> "ABCD-2345"
function A.prettyWebCode(code) return code:sub(1, 4) .. "-" .. code:sub(5, 8) end

local function split(code)
  local f = {}
  for part in (code .. "."):gmatch("([^.]*)%.") do f[#f + 1] = part end
  return f
end
local function finish(fields)
  local body = table.concat(fields, ".")
  return body .. "." .. check(body)
end
local function verifyCheck(f)
  local last = f[#f]
  return last:match("^%x%x%x%x%x%x%x%x$") ~= nil and last == check(table.concat(f, ".", 1, #f - 1))
end
local function clean(code)
  if type(code) ~= "string" then return nil, "empty" end
  code = code:gsub("[ \t\r\n\f\v]", "")
  if code == "" then return nil, "empty" end
  if code:find("[^\33-\126]") then return nil, "chars" end
  if #code > A.MAX_CODE then return nil, "size" end
  return code
end

local function isLinkId(s) return type(s) == "string" and #s == 12 and s:match("^[a-z0-9]+$") ~= nil end
--- Text from the web for display: valid UTF-8, no control characters, 1..max bytes.
local function textOk(s, max) return type(s) == "string" and #s >= 1 and #s <= max and C().utf8ok(s) and not s:find("[%c]") end
local function hexText(h, max, optional)
  if optional and h == "-" then return true, nil end
  if type(h) ~= "string" or #h < 2 or #h > 2 * max then return false end
  local s = C().unhex(h)
  if not s or not textOk(s, max) then return false end
  return true, s
end

function A.newLinkId(rnd)
  local B = "0123456789abcdefghijklmnopqrstuvwxyz"
  local t = {}
  for i = 1, 12 do local k = rnd(1, 36); t[i] = B:sub(k, k) end
  return table.concat(t)
end

--- Link request code. r = { code, platform, player, linkId, addon, engine, issued }
function A.linkRequest(r)
  assert(A.parseWebCode(r.code) == r.code, "code")
  assert(A.PLATFORMS[r.platform], "platform")
  assert(C().nameOk(r.player), "player")
  assert(isLinkId(r.linkId), "linkId")
  local ver = tostring(r.addon or "dev"):gsub("%.", "-")
  assert(ver:match("^[%w%-]+$") and #ver <= 20, "addon")
  return finish({ A.LINK_FORMAT, r.code, r.platform, C().hex(r.player), r.linkId, ver, tostring(r.engine), b36(r.issued) })
end

--- Parse a link request (the website does this; here for tests and vectors).
function A.parseLinkRequest(code)
  local err
  code, err = clean(code)
  if not code then return nil, err end
  local f = split(code)
  if f[1] ~= A.LINK_FORMAT then return nil, (f[1] or ""):match("^SRL%d+$") and "version" or "format" end
  if #f ~= 9 then return nil, "fields" end
  if not verifyCheck(f) then return nil, "check" end
  if A.parseWebCode(f[2]) ~= f[2] then return nil, "code" end
  if not A.PLATFORMS[f[3]] then return nil, "platform" end
  local player = C().unhex(f[4])
  if not player or not C().nameOk(player) then return nil, "player" end
  if not isLinkId(f[5]) then return nil, "linkId" end
  if not f[6]:match("^[%w%-]+$") or #f[6] > 20 then return nil, "addon" end
  if not f[7]:match("^[1-9]%d?%d?%d?$") then return nil, "engine" end
  local issued = unb36(f[8])
  if not issued then return nil, "issued" end
  return { code = f[2], platform = f[3], player = player, linkId = f[5], addon = f[6]:gsub("%-", "."), engine = tonumber(f[7]), issued = issued }
end

--- Profile snapshot code (made by the website; the Lua encoder is the reference for vectors/tests).
function A.profile(p)
  local hist = "-"
  if p.history and #p.history > 0 then
    local parts = {}
    for i, h in ipairs(p.history) do
      assert(i <= A.MAX_HISTORY, "history")
      parts[i] = table.concat({ h.mode, h.res, b36(h.my), b36(h.their), b36(h.at) }, "-")
    end
    hist = table.concat(parts, "~")
  end
  local function hx(s) return s and C().hex(s) or "-" end
  return finish({
    A.PROFILE_FORMAT, p.linkId, C().hex(p.player), p.accountId, C().hex(p.name), b36(p.issued), b36(p.expires),
    b36(p.level or 0), b36(p.xp or 0), b36(p.xpNext or 0), hx(p.rank), hx(p.season), tostring(p.seasonPct or 0),
    b36(p.wins or 0), b36(p.losses or 0), b36(p.draws or 0), hist,
    p.achUnlocked and (b36(p.achUnlocked) .. "-" .. b36(p.achTotal)) or "-",
    p.cosOwned and (b36(p.cosOwned) .. "-" .. hx(p.cosEquipped)) or "-",
    p.sig or "-",
  })
end

local MAX_DAYS = 30 * 86400

--- Parse a profile snapshot -> table or nil, reason. Checks format and ranges only; whether it
--- belongs to this character / link and isn't stale is decided by Core/Account.lua.
function A.parseProfile(code)
  local err
  code, err = clean(code)
  if not code then return nil, err end
  local f = split(code)
  if f[1] ~= A.PROFILE_FORMAT then
    if (f[1] or ""):match("^SRP%d+$") then return nil, "version" end
    if (f[1] or ""):match("^SR[%u%d]+$") then return nil, "wrong_kind" end
    return nil, "format"
  end
  if #f ~= 21 then return nil, "fields" end
  if not verifyCheck(f) then return nil, "check" end
  local p = { linkId = f[2] }
  if not isLinkId(f[2]) then return nil, "linkId" end
  p.player = C().unhex(f[3])
  if not p.player or not C().nameOk(p.player) then return nil, "player" end
  if #f[4] < 4 or #f[4] > 40 or not f[4]:match("^[a-z0-9_%-]+$") then return nil, "accountId" end
  p.accountId = f[4]
  local okN, name = hexText(f[5], 32)
  if not okN then return nil, "name" end
  p.name = name
  p.issued, p.expires = unb36(f[6]), unb36(f[7])
  if not p.issued or not p.expires or p.expires <= p.issued or p.expires - p.issued > MAX_DAYS then return nil, "time" end
  p.level, p.xp, p.xpNext = unb36(f[8]), unb36(f[9]), unb36(f[10])
  if not p.level or p.level > 9999 or not p.xp or p.xp > 1e12 or not p.xpNext or p.xpNext > 1e12 then return nil, "numbers" end
  local okR, rank = hexText(f[11], 24, true)
  local okS, season = hexText(f[12], 24, true)
  if not okR then return nil, "rank" end
  if not okS then return nil, "season" end
  p.rank, p.season = rank, season
  if not f[13]:match("^%d%d?%d?$") or tonumber(f[13]) > 100 then return nil, "season" end
  p.seasonPct = tonumber(f[13])
  p.wins, p.losses, p.draws = unb36(f[14]), unb36(f[15]), unb36(f[16])
  if not (p.wins and p.losses and p.draws) or p.wins > 1e9 or p.losses > 1e9 or p.draws > 1e9 then return nil, "numbers" end
  p.history = {}
  if f[17] ~= "-" then
    local n = 0
    for entry in (f[17] .. "~"):gmatch("([^~]*)~") do
      n = n + 1
      if n > A.MAX_HISTORY then return nil, "history" end
      local mode, res, my, th, at = entry:match("^([a-z0-9]+)%-([wld])%-([0-9a-z]+)%-([0-9a-z]+)%-([0-9a-z]+)$")
      if not mode or #mode > 12 then return nil, "history" end
      my, th, at = unb36(my), unb36(th), unb36(at)
      if not (my and th and at) then return nil, "history" end
      p.history[n] = { mode = mode, res = res, my = my, their = th, at = at }
    end
  end
  if f[18] ~= "-" then
    local u, t = f[18]:match("^([0-9a-z]+)%-([0-9a-z]+)$")
    u, t = unb36(u), unb36(t)
    if not u or not t or u > t or t > 9999 then return nil, "achievements" end
    p.achUnlocked, p.achTotal = u, t
  end
  if f[19] ~= "-" then
    local o, e = f[19]:match("^([0-9a-z]+)%-(.+)$")
    o = unb36(o)
    if not o or o > 99999 then return nil, "cosmetics" end
    local okE, eq = hexText(e, 24, true)
    if not okE then return nil, "cosmetics" end
    p.cosOwned, p.cosEquipped = o, eq
  end
  if f[20] ~= "-" and not (#f[20] >= 16 and #f[20] <= 128 and f[20]:match("^[%w_%-]+$")) then return nil, "sig" end
  p.sig = f[20] ~= "-" and f[20] or nil
  p.check = f[21]
  return p
end

--[[
  Profile snapshot v2 (made by stackrivals.io; spec: the website's docs/WOW_SRP2.md, shared vectors:
  docs/vectors/srp2_v1.json). SRP1 is unchanged; SRP2 = SRP1's fields 1-18 (same rules) + extras:
    SRP2.<f1..f18>.<shards>.<asOf36>.<equipped>.<owned>.<events>.<sig>.<check>     (26 fields)
      shards    "-" (not shown) or base 36, 0..1e12      -- the website's balance, display only
      asOf36    unix seconds the website read balance / ownership / events: issued-86400 <= asOf <= issued
      equipped  "-" or slot:id joined by "~"; slot skin | frame | victory (each at most once); id [a-z0-9_]{1,32}
      owned     "-" or ids joined by "~", sorted ascending (byte order), unique, at most 64
      events    "-" or up to 4 <kind>-<up|live>-<start36>-<end36>-<value36> joined by "~"; kind storm | overdrive;
                start < end; value: storm = Shards per claim on the website, overdrive = XP multiplier
      sig       "-" or SRP2-SIG v1 (Ed25519 over "SRP2-SIG-v1\n" + fields 0-23; not checked by this version)
  Display only: nothing here buys, claims or credits anything; the website's ledger is the authority.
]]
A.PROFILE2_FORMAT = "SRP2"
A.SLOT_ORDER = { "skin", "frame", "victory" }
A.SLOTS = { skin = true, frame = true, victory = true }
A.EVENT_KINDS = { storm = true, overdrive = true }
A.MAX_OWNED, A.MAX_EVENTS, A.MAX_AS_OF_AGE = 64, 4, 86400

-- byte-order comparison (string "<" uses the C library's locale order, which can differ for "_")
local function byteLess(a, b)
  for i = 1, math.min(#a, #b) do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then return x < y end
  end
  return #a < #b
end
A.byteLess = byteLess
local function idOk(s) return type(s) == "string" and #s >= 1 and #s <= 32 and s:match("^[a-z0-9_]+$") ~= nil end

--- SRP2 code (the website makes these; the Lua encoder is for tests).
function A.profile2(p)
  local f = split(A.profile({
    linkId = p.linkId, player = p.player, accountId = p.accountId, name = p.name, issued = p.issued, expires = p.expires,
    level = p.level, xp = p.xp, xpNext = p.xpNext, rank = p.rank, season = p.season, seasonPct = p.seasonPct,
    wins = p.wins, losses = p.losses, draws = p.draws, history = p.history, achUnlocked = p.achUnlocked, achTotal = p.achTotal,
    cosOwned = p.cosOwned, cosEquipped = p.cosEquipped,
  }))
  local out = { A.PROFILE2_FORMAT }
  for i = 2, 19 do out[#out + 1] = f[i] end
  local eq = {}
  for _, slot in ipairs(A.SLOT_ORDER) do
    local id = p.equipped and p.equipped[slot]
    if id then assert(idOk(id), "equipped"); eq[#eq + 1] = slot .. ":" .. id end
  end
  local owned = {}
  for i, id in ipairs(p.owned or {}) do assert(idOk(id), "owned"); owned[i] = id end
  table.sort(owned, byteLess)
  local ev = {}
  for i, e in ipairs(p.events or {}) do
    assert(i <= A.MAX_EVENTS, "events")
    ev[i] = table.concat({ e.kind, e.state, b36(e.start), b36(e["end"]), b36(e.value) }, "-")
  end
  out[#out + 1] = p.shards and b36(p.shards) or "-"
  out[#out + 1] = b36(p.asOf or p.issued)
  out[#out + 1] = #eq > 0 and table.concat(eq, "~") or "-"
  out[#out + 1] = #owned > 0 and table.concat(owned, "~") or "-"
  out[#out + 1] = #ev > 0 and table.concat(ev, "~") or "-"
  out[#out + 1] = p.sig or "-"
  return finish(out)
end

--- Parse an SRP2 code -> table (parseProfile's fields + format, shards, asOf, equipped, owned, events) or nil, reason.
function A.parseProfile2(code)
  local err
  code, err = clean(code)
  if not code then return nil, err end
  local f = split(code)
  if f[1] ~= A.PROFILE2_FORMAT then
    if (f[1] or ""):match("^SRP%d+$") then return nil, "version" end
    if (f[1] or ""):match("^SR[%u%d]+$") then return nil, "wrong_kind" end
    return nil, "format"
  end
  if #f ~= 26 then return nil, "fields" end
  if not verifyCheck(f) then return nil, "check" end
  -- fields 1-18 + sig: exactly SRP1's rules
  local one = { A.PROFILE_FORMAT }
  for i = 2, 19 do one[#one + 1] = f[i] end
  one[#one + 1] = f[25]
  local p, why = A.parseProfile(finish(one))
  if not p then return nil, (why == "sig") and "sig" or "base", why end
  p.format, p.check = A.PROFILE2_FORMAT, f[26]
  if f[20] ~= "-" then
    local n = unb36(f[20])
    if not n or n > 1e12 then return nil, "shards" end
    p.shards = n
  end
  local asOf = unb36(f[21])
  if not asOf or asOf > p.issued or p.issued - asOf > A.MAX_AS_OF_AGE then return nil, "asOf" end
  p.asOf = asOf
  p.equipped = {}
  if f[22] ~= "-" then
    local n = 0
    for entry in (f[22] .. "~"):gmatch("([^~]*)~") do
      n = n + 1
      local slot, id = entry:match("^([a-z]+):([a-z0-9_]+)$")
      if n > #A.SLOT_ORDER or not slot or not A.SLOTS[slot] or not idOk(id) or p.equipped[slot] then return nil, "equipped" end
      p.equipped[slot] = id
    end
  end
  p.owned = {}
  if f[23] ~= "-" then
    local prev
    for id in (f[23] .. "~"):gmatch("([^~]*)~") do
      if #p.owned >= A.MAX_OWNED or not idOk(id) or (prev and not byteLess(prev, id)) then return nil, "owned" end
      p.owned[#p.owned + 1] = id
      prev = id
    end
  end
  p.events = {}
  if f[24] ~= "-" then
    for entry in (f[24] .. "~"):gmatch("([^~]*)~") do
      local kind, state, s, e, v = entry:match("^([a-z]+)%-([a-z]+)%-([0-9a-z]+)%-([0-9a-z]+)%-([0-9a-z]+)$")
      s, e, v = unb36(s), unb36(e), unb36(v)
      if #p.events >= A.MAX_EVENTS or not kind or not A.EVENT_KINDS[kind] or (state ~= "up" and state ~= "live")
        or not s or not e or not v or e <= s or v > 1e9 then return nil, "events" end
      p.events[#p.events + 1] = { kind = kind, state = state, start = s, ["end"] = e, value = v }
    end
  end
  return p
end

return A
