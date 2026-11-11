--[[
  StackRivals - Loot Duel: a raid / party settles who gets an item with a short StackRivals race
  instead of /roll. Separate from Quickplay and duels; never ranked; never touches loot.

  Flow (docs/LOOT_DUEL.md):
    1. The party leader, raid leader, an assistant or the master looter opens Loot Duel, picks an
       item (link or item ID), a time (1:00 or 2:00) and 2-40 group members, and invites them
       (LDJ + LDI). All of them play at once: one race, no 1v1 rounds.
    2. Each invitee accepts or declines in a popup (LDA). Accepting sends only a COMMITMENT to a
       secret seed nonce. Nobody is entered automatically; no answer = not in.
    3. The leader starts with the players who accepted (at least 2). The fixed list (names +
       commitments) goes out as LDQ (10 per message). Over 10 players the first send is ONE message
       (LDS: places as a bit mask + the list hash): every PC builds the list from the commitments it
       saw in the players' own LDA and checks the hash; LDQ follows on repeats for whoever missed an
       LDA. A player who joined and was left out is told so. Then every player reveals their nonce
       (LDN); the leader relays them all and reveals its own committed nonce (LDW, or over 10 the
       one-message LDG built from the LDN every PC saw). All commitments are fixed before anyone
       reveals, so nobody - the leader included - can know or steer the pieces; a missing reveal
       (or a player who goes offline before revealing) cancels the whole race: no re-roll by
       leaving someone out.
    4. Everyone plays the same pieces at once, no spells. Live scores (LDC, every 4-6 s by group
       size) feed a leaderboard.
    5. Each player sends a final claim (LDE). Up to 10 players every claim's input log (LDL) is sent
       and EVERY PC replays EVERY log. Over 10 only the best LD.CONTENDERS (10) claims, ties
       included, send their log, once the claims are known, and every PC replays only those (a
       claim whose log never comes is out, and the next claims are promoted). The rest are shown
       as "unchecked" and can't win.
    6. Standings: replay-checked results by score, then lines. A tie at the top stays a tie (roll
       off with /roll). Missing (disconnect, past the deadline) or failed replay = out. No result
       is invented for anyone.
    7. The loot master hands out the item in WoW, by hand. StackRivals only shows the result.

  Trust: peer-checked (every PC replays the runs that can win) - good against a typo or a broken
  client, NOT proof against a modified addon. Said on screen. Details: docs/LOOT_DUEL.md.
  Loot: no loot API is called (no GiveMasterLoot, no loot method changes, no trade).
]]
local _, ns = ...
ns = ns or {}

local LD = { listeners = {} }
ns.LootDuel = LD

LD.INVITE_TIME = 60      -- s to answer an invite
LD.START_LIMIT = 80      -- s after the offer the leader may still start (members wait START_WAIT)
LD.START_WAIT = 100      -- s a member waits for the start before giving up
LD.REVEAL_TIME = 20      -- s for every player's nonce to arrive; otherwise the race is cancelled
LD.REPEAT = 10           -- s between repeats of the offer / answers while inviting
LD.LIVE_EVERY = 4        -- s between live score broadcasts (up to 10 players; more: see LD.liveEvery)
LD.CONTENDERS = 10       -- only the best 10 claims (and anyone tied with them) send and replay full logs
LD.PROMOTE_GRACE = 40    -- s more when a contender's log never arrived: then every remaining claim is checked (max 2x)
LD.OFFER_SENDS = 4       -- the offer goes out at most this often (a 40-player invite list is 5 messages)
--- Live score interval: 40 players all broadcasting every 4 s would be 10 messages a second.
function LD.liveEvery(d) local n = #(d.participants or {}); return (n > 20 and 6) or (n > 10 and 5) or LD.LIVE_EVERY end
--- Time for every share to arrive: longer for big groups (the start list is up to 4 messages).
function LD.revealTime(d) return LD.REVEAL_TIME + math.floor(#(d.participants or {}) / 2) end
LD.GRACE = 90            -- s after the time limit (1:00) before a missing result is out (logs travel slowly
LD.GRACE_LONG = 120      --   on the group channel: about 100 bytes/s); 2:00 races get GRACE_LONG
LD.LATE_MIN = 2           -- s: a go later than this (a repeat) shortens my run by that much (see LD.begin)
LD.PAUSE_BUDGET = 15     -- s of pause (combat, chat) per race; past it your run ends where it is
LD.KEEP_RESULTS = 10     -- finished loot duels kept for the results screen (this session)

local function P() return ns.Protocol end
local function now() return GetTime and GetTime() or 0 end
local function emit(ev, ...) local fn = LD.listeners[ev]; if fn then fn(...) end end
function LD.on(ev, fn) LD.listeners[ev] = fn end
local function me() return ns.Comm and ns.Comm.me() or nil end
local function same(a, b) return ns.Comm and ns.Comm.same(a, b) end
local function key(name) return (ns.Comm and ns.Comm.fullName and ns.Comm.fullName(name) or name):lower() end
local function rnd(a, b) return math.random(a, b) end

--- PARTY / RAID / INSTANCE_CHAT or nil (not in a group).
function LD.channel()
  local inst = LE_PARTY_CATEGORY_INSTANCE
  if inst and IsInGroup and IsInGroup(inst) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  return nil
end

local function bcast(text, opts)
  local ch = LD.channel()
  if not ch then return false end
  return ns.Comm.send(text, ch, nil, nil, opts)
end

--- The group: { name, class, level, faction, subgroup, leader, assist, ml, online } (you
--- included). Read only; every API optional.
function LD.roster()
  local out = {}
  local full = function(n, r) return ns.Social and ns.Social.full(n, r) or n end
  local mlName
  -- read only (never changed): C_PartyInfo.GetLootMethod (Enum.LootMethod, 2 = master looter;
  -- Classic Era 1.15.8+, Retail 11.2+), else the old GetLootMethod ("master")
  local getLM = (C_PartyInfo and C_PartyInfo.GetLootMethod) or GetLootMethod
  if getLM then
    local ok, method, partyIdx, raidIdx = pcall(getLM)
    if ok and (method == "master" or method == 2) then
      if raidIdx and UnitName then mlName = full(UnitName("raid" .. raidIdx))
      elseif partyIdx == 0 then mlName = me()
      elseif partyIdx and UnitName then mlName = full(UnitName("party" .. partyIdx)) end
    end
  end
  if IsInRaid and IsInRaid() and GetRaidRosterInfo then
    for i = 1, math.min(GetNumGroupMembers and GetNumGroupMembers() or 0, 40) do
      local name, rank, subgroup, level, _, classFile, _, online, _, _, isML = GetRaidRosterInfo(i)
      if name then
        local fac = UnitFactionGroup and select(1, UnitFactionGroup("raid" .. i)) or nil
        out[#out + 1] = { name = full(name), class = classFile, level = tonumber(level), faction = fac, subgroup = subgroup,
          leader = rank == 2, assist = rank == 1, ml = isML and true or false, online = online ~= false }
      end
    end
  elseif IsInGroup and IsInGroup() and UnitName then
    local units = { "player" }
    for i = 1, 4 do units[#units + 1] = "party" .. i end
    for _, u in ipairs(units) do
      local n, r = UnitName(u)
      if n and (u == "player" or (UnitExists == nil or UnitExists(u))) then
        local cls = UnitClass and select(2, UnitClass(u)) -- (a and f() keeps only the first value)
        local name = (u == "player") and me() or full(n, r)
        if name and not (u ~= "player" and same(name, me())) then
          local lvl = UnitLevel and UnitLevel(u) or nil
          local fac = UnitFactionGroup and select(1, UnitFactionGroup(u)) or nil
          local on = (u == "player") or not UnitIsConnected or UnitIsConnected(u) ~= false
          out[#out + 1] = { name = name, class = cls, level = tonumber(lvl), faction = fac, leader = UnitIsGroupLeader and UnitIsGroupLeader(u) or false,
            assist = false, online = on and true or false }
        end
      end
    end
  end
  for _, e in ipairs(out) do if mlName and same(e.name, mlName) then e.ml = true end end
  return out
end

local function rosterEntry(name)
  for _, e in ipairs(LD.roster()) do if same(e.name, name) then return e end end
end

--- Ask the group (one PARTY / RAID broadcast) which members have StackRivals: their addons answer
--- with a hidden whisper (HI, read through ns.Duel.presence). Not more than once per 20 s.
LD.CHECK_GAP = 20
function LD.checkAddons()
  if not (ns.Comm and ns.Comm.enabled) or (ns.Comm.trial) then return false, "unavailable" end
  local ch = LD.channel()
  if not ch then return false, "not_in_group" end
  local t = now()
  if LD.checkedAt and t - LD.checkedAt < LD.CHECK_GAP then return false, "cooldown" end
  LD.checkedAt = t
  ns.Comm.send(P().encode("HEL", ns.VERSION, ns.Engine.ENGINE_VERSION), ch, nil, nil, { key = "LDHEL", low = true })
  return true
end

--- Can this member take part? "yes" (StackRivals 0.7.2+ answered), "old" (an older StackRivals
--- answered: it can't join a Loot Duel for 10), "you", or nil (no answer yet).
function LD.addonStatus(name)
  if same(name, me()) then return "you" end
  local p = ns.Duel and ns.Duel.presence(name)
  if not p then return nil end
  if p.addon and P().versionAtLeast and not P().versionAtLeast(p.addon, LD.MIN_VERSION) then return "old" end
  return "yes"
end
LD.MIN_VERSION = "0.7.3"

--- Items in the open loot window (read only: GetNumLootItems / GetLootSlotLink / GetLootSlotInfo),
--- uncommon or better, so the leader can pick one with a click. Empty when no loot window is open.
function LD.lootWindowItems()
  local out = {}
  if not (GetNumLootItems and GetLootSlotLink) then return out end
  local okN, n = pcall(GetNumLootItems)
  if not okN or type(n) ~= "number" then return out end
  for slot = 1, math.min(n, 16) do
    local okL, link = pcall(GetLootSlotLink, slot)
    local id = okL and LD.itemIdFrom(link)
    if id then
      local q
      if GetLootSlotInfo then local okI, _, _, _, _, quality = pcall(GetLootSlotInfo, slot); if okI then q = quality end end
      if not q then q = select(3, LD.itemInfo(id)) end
      if (q or 2) >= 2 then out[#out + 1] = { itemId = id, link = link, quality = q } end
    end
  end
  return out
end

--- The live leaderboard: every player by score (live scores are provisional until replayed).
--- rows: { name, class, score, rank, status = playing | topped_out | time_up | no_signal |
---   disconnected | checking | checked | failed | out, checked = true when replay-checked }
function LD.liveBoard(d, t)
  t = t or now()
  local rs = P().LOOT_RULESETS[d.rs]
  local roster = {}
  for _, e in ipairs(LD.roster()) do roster[key(e.name)] = e end
  local rows = {}
  for _, p in ipairs(d.participants or {}) do
    local k = key(p.name)
    local r, lv = d.results[k], d.live[k]
    local row = { name = p.name, class = (roster[k] and roster[k].class) or (r and r.class), score = 0 }
    local s = ns.App and ns.App.session
    if same(p.name, me()) and s and s.loot == d and not r then
      row.score = s.state.score
      row.status = s.state.gameOver and "topped_out" or "playing"
    elseif r and r.score then
      row.score = r.score
      if r.status == "verified" then row.status, row.checked = "checked", true
      elseif r.status == "rejected" then row.status = "failed"
      elseif r.status == "missing" then row.status = "out"
      else row.status = (r.ticks and rs and r.ticks < rs.limitTicks) and "topped_out" or "time_up" end
    else
      row.score = lv and lv.score or 0
      local e = roster[k]
      if e and e.online == false then row.status = "disconnected"
      elseif d.state == "playing" and t - (lv and lv.at or d.startAt or t) > 3 * LD.liveEvery(d) + 4 then
        row.status = (d.lockedNow or (d.lockedAt and t - d.lockedAt < 3 * LD.liveEvery(d) + 4)) and "held" or "no_signal"
      else row.status = "playing" end
    end
    rows[#rows + 1] = row
  end
  table.sort(rows, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name:lower() < b.name:lower() end)
  for i, x in ipairs(rows) do x.rank = i end
  return rows
end

--- WoW class token of a group member (for class colours), nil if unknown.
function LD.classOf(name)
  local e = rosterEntry(name)
  return e and e.class or nil
end

--- May `name` (default: me) run a Loot Duel? Raid / party leader, raid assistant or master looter.
function LD.mayLead(name)
  if not LD.channel() then return false, "not_in_group" end
  local e = rosterEntry(name or me())
  if not e then return false, "not_in_group" end
  if e.leader or e.assist or e.ml then return true end
  return false, "not_leader"
end

LD.WHY = {
  not_in_group = "Join a party or raid first.",
  not_leader = "Only the leader, an assistant or the master looter can start a Loot Duel.",
  no_item = "Pick an item first (shift-click it or paste its link / item ID).",
  few = "Pick at least 2 players.",
  many = "At most 40 players.",
  many_heats = "At most 40 play in one Loot Duel (a full raid).",
  all_many = "More than 40 online: pick up to 40 with the boxes, then Invite Selected.",
  busy = "A Loot Duel is already running.",
  duel = "Finish your duel first.",
  expired = "This invite has expired: start a new Loot Duel.",
  combat = "Not in combat.",
  unavailable = "Addon messages are not available here.",
  trial = "Trial and Veteran accounts can't send addon messages in this WoW version, so they can't take part.",
  locked = "WoW blocks addon messages right now (a boss fight, a Mythic+ run or a PvP match). Start the Loot Duel after it.",
  locked_map = "WoW blocks addon messages in this zone. A Loot Duel can't run here: start it outside, or use your normal loot rules.",
}

--- Can this PC run a Loot Duel at all right now? Nothing is faked: no addon messages = no Loot Duel.
function LD.commState()
  local C = ns.Comm
  if not (C and C.enabled) or C.unavailable then return false, "unavailable" end
  if C.trial then return false, "trial" end
  if C.isLocked and C.isLocked() then
    -- the client may say why: a whole map (dungeon / raid zone) is different from an encounter
    return false, (ns.Client and ns.Client.lockdownReason() == "map") and "locked_map" or "locked"
  end
  return true
end

------------------------------------------------------------------------------------------------
-- Item links
------------------------------------------------------------------------------------------------
--- Item ID from a link ("|Hitem:19019:..."), "item:19019" or a plain number.
function LD.itemIdFrom(text)
  if type(text) == "number" then return (text >= 1 and text <= 9999999) and math.floor(text) or nil end
  if type(text) ~= "string" then return nil end
  local id = text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$")
  id = tonumber(id)
  return (id and id >= 1 and id <= 9999999) and id or nil
end

--- name, link, quality, icon for an item ID (nil name while the client hasn't loaded it yet: the
--- data is requested, GET_ITEM_INFO_RECEIVED refreshes the screens).
function LD.itemInfo(id)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, link, quality, icon
  if get then
    local ok, n, l, q, _, _, _, _, _, _, tex = pcall(get, id)
    if ok then name, link, quality, icon = n, l, q, tex end
  end
  if not name and id then
    local req = C_Item and C_Item.RequestLoadItemDataByID
    if req then pcall(req, id) end
  end
  if not icon then
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if inst then local ok, _, _, _, _, tex = pcall(inst, id); if ok then icon = tex end end
  end
  return name, link, quality, icon
end

------------------------------------------------------------------------------------------------
-- Commitments, seed, list hash, standings (pure: the same on every PC)
------------------------------------------------------------------------------------------------
local function sorted(entries)
  local t = {}
  for _, e in ipairs(entries) do t[#t + 1] = e end
  table.sort(t, function(a, b) return a.name:lower() < b.name:lower() end)
  return t
end
--- Hash of the fixed list: names + commitments (before anyone reveals).
function LD.listHash(lid, rs, itemId, entries)
  local parts = { lid, rs, tostring(itemId) }
  for _, e in ipairs(sorted(entries)) do parts[#parts + 1] = e.name:lower() .. "=" .. e.commit end
  return string.format("%08x", ns.Prng.hashString(table.concat(parts, "|")))
end
--- Hash of the revealed nonces (LDW): every PC must have the same set.
function LD.revealHash(lid, entries)
  local parts = { lid }
  for _, e in ipairs(sorted(entries)) do parts[#parts + 1] = e.name:lower() .. "=" .. e.nonce end
  return string.format("%08x", ns.Prng.hashString(table.concat(parts, "|")))
end
function LD.seedFor(lid, nonceL, entries)
  local parts = { nonceL }
  for _, e in ipairs(sorted(entries)) do parts[#parts + 1] = e.name:lower() .. "=" .. e.nonce end
  return "srloot-" .. lid .. "-" .. string.format("%08x", ns.Prng.hashString(table.concat(parts, "|")))
end
function LD.graceFor(rs) return rs == "l120" and LD.GRACE_LONG or LD.GRACE end

--- Standings from results { [name] = { status, score, lines } }: verified first (score, lines),
--- then the rest. Returns list, winner (nil on a tie or nobody), tied names.
function LD.standings(participants, results)
  local list = {}
  for _, p in ipairs(participants) do
    local r = results[p.name:lower()] or {}
    list[#list + 1] = { name = p.name, status = r.status or "missing", score = r.score or 0, lines = r.lines or 0, class = r.class, why = r.why }
  end
  -- replay-checked first, then claims that weren't needed for the result ("unchecked": below the
  -- best 10, they couldn't win), then everything that is out
  local GROUP = { verified = 1, unchecked = 2 }
  table.sort(list, function(a, b)
    local ga, gb = GROUP[a.status] or 3, GROUP[b.status] or 3
    if ga ~= gb then return ga < gb end
    if a.score ~= b.score then return a.score > b.score end
    if a.lines ~= b.lines then return a.lines > b.lines end
    return a.name:lower() < b.name:lower()
  end)
  local top = list[1]
  if not top or top.status ~= "verified" then return list, nil, {} end
  local tied = { top.name }
  for i = 2, #list do
    local x = list[i]
    if x.status == "verified" and x.score == top.score and x.lines == top.lines then tied[#tied + 1] = x.name end
  end
  if #tied > 1 then return list, nil, tied end
  return list, top.name, {}
end

------------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------------
LD.current = nil    -- the loot duel I lead, was invited to, or play in
LD.history = {}     -- finished ones (this session): the results screen

local function newLd(o)
  local d = { answers = {}, invitees = {}, inviteChunks = {}, reveals = {}, results = {}, live = {} }
  for k, v in pairs(o) do d[k] = v end
  return d
end

local function isInvitee(d, name)
  for _, n in ipairs(d.inviteOrder or {}) do if same(n, name) then return true end end
  return false
end
local function isPart(d, name)
  for _, p in ipairs(d.participants or {}) do if same(p.name, name) then return p end end
end
--- 1-based place of a name in the invite list (the start messages refer to players by it).
local function placeOf(d, name)
  for i, n in ipairs(d.inviteOrder or {}) do if same(n, name) then return i end end
end
--- Everyone still to answer? (the offer is repeated only for them)
local function unanswered(d)
  for _, n in ipairs(d.inviteOrder or {}) do if not d.answers[key(n)] then return true end end
  return false
end
--- Drop this Loot Duel's queued repeats that the start makes useless (offer, invitees, answers).
local function dropRepeats(d)
  if not (ns.Comm and ns.Comm.unqueue) then return end
  ns.Comm.unqueue(function(q) return q.key and (q.key:find("^LDJ:" .. d.lid) or q.key:find("^LDI:" .. d.lid) or q.key:find("^LDA:" .. d.lid)) ~= nil end)
end

--- Am I tied up in a Loot Duel (joined, locking in, or racing)? Duels, Quickplay and solo starts wait.
function LD.busy()
  local d = LD.current
  if not d then return false end
  if d.state == "inviting" then return d.myAnswer == "a" end
  if d.state == "revealing" then return d.iPlay and true or false end
  if d.state == "playing" then
    local s = ns.App and ns.App.session
    return d.iPlay and s ~= nil and s.loot == d and not s.recorded or false
  end
  return false
end

--- Leader: create and invite. names = "Name-Realm" list (2..8, may include yourself).
function LD.create(itemId, rs, names)
  local okComm, whyComm = LD.commState()
  if not okComm then return false, whyComm end
  local okLead, why = LD.mayLead()
  if not okLead then return false, why end
  if LD.current and LD.current.state ~= "done" and LD.current.state ~= "cancelled" then return false, "busy" end
  if not LD.itemIdFrom(itemId) then return false, "no_item" end
  if not P().LOOT_RULESETS[rs] then rs = "l060" end
  local seen, list = {}, {}
  for _, n in ipairs(names or {}) do
    if type(n) == "string" and not seen[n:lower()] and rosterEntry(n) then seen[n:lower()] = true; list[#list + 1] = rosterEntry(n).name end
  end
  if #list < 2 then return false, "few" end
  if #list > P().LOOT_MAX then return false, "many" end
  local d = newLd({
    lid = P().token(6, rnd), role = "leader", leader = me(), rs = rs, itemId = LD.itemIdFrom(itemId),
    engine = ns.Engine.ENGINE_VERSION, nonceL = P().token(10, rnd), state = "inviting", createdAt = now(), inviteOrder = list,
  })
  d.commit = P().commit16(d.lid, d.nonceL)
  LD.current = d
  LD.sendOffer(d)
  -- the leader can be a player too: their own answer counts like anyone else's
  if isInvitee(d, me()) then LD.answer(true) end
  emit("changed", d)
  return true
end

local function chunked(items)
  local chunks, cur, curLen = {}, {}, 0
  for _, it in ipairs(items) do
    if #cur > 0 and curLen + #it + 1 > 200 then chunks[#chunks + 1] = cur; cur, curLen = {}, 0 end
    cur[#cur + 1] = it; curLen = curLen + #it + 1
  end
  if #cur > 0 then chunks[#chunks + 1] = cur end
  return chunks
end

--- The invitee list chunks (names hex; as many per message as fit). The start names players by
--- their place in this list, so it is sent again with the start when a reveal is missing.
function LD.sendInvitees(d, opts)
  local hx = {}
  local myRealm = (me() or ""):match("%-(.+)$")
  for _, n in ipairs(d.inviteOrder) do
    -- on my realm: "Name" only (the receivers add my realm back), so 40 names fit in ~4 messages
    local nm, realm = n:match("^(.-)%-(.+)$")
    hx[#hx + 1] = P().hexName((realm and myRealm and realm:lower() == myRealm:lower()) and nm or n)
  end
  for k, c in ipairs(chunked(hx)) do bcast(P().encode("LDI", d.lid, k, table.concat(c, ",")), { key = "LDI:" .. d.lid .. ":" .. k, front = opts and opts.front }) end
end

--- Offer + invitee list.
function LD.sendOffer(d)
  d.offerAt = now()
  d.offerSends = (d.offerSends or 0) + 1
  bcast(P().encode("LDJ", d.lid, d.rs, d.engine, d.itemId, d.commit, #d.inviteOrder), { key = "LDJ:" .. d.lid })
  LD.sendInvitees(d)
end

--- Invitee (or a leader who invited themselves): join / pass. Joining sends only a commitment.
function LD.answer(accept)
  local d = LD.current
  if not d or d.state ~= "inviting" or not isInvitee(d, me()) then return false end
  if accept and ((ns.Duel and ns.Duel.busy()) or (ns.Quickplay and ns.Quickplay.state == "matched")) then accept = false end
  if accept and d.role ~= "leader" and now() - d.createdAt > LD.START_LIMIT then accept = false end
  d.myAnswer = accept and "a" or "d"
  d.myNonce = accept and (d.myNonce or P().token(10, rnd)) or nil
  d.myCommit = accept and P().commit16(d.lid, d.myNonce) or nil
  d.answers[key(me())] = { accept = accept, commit = d.myCommit, name = me() }
  d.answerAt, d.answerSends = now(), 1
  bcast(P().encode("LDA", d.lid, accept and "a" or "d", accept and d.myCommit or "-"), { key = "LDA:" .. d.lid })
  emit("changed", d)
  return true
end

--- Accepted players so far (name, commit).
function LD.accepted(d)
  local t = {}
  for _, n in ipairs(d.inviteOrder or {}) do
    local a = d.answers[key(n)]
    if a and a.accept and a.commit then t[#t + 1] = { name = n, commit = a.commit } end
  end
  return t
end

--- May the leader still start? (invites expire: members stop waiting at START_WAIT)
function LD.canStart(d)
  return d and d.role == "leader" and d.state == "inviting" and now() - d.createdAt <= LD.START_LIMIT
end

--- Leader: fix the list (everyone who joined, at least 2) and ask for the reveals.
function LD.start()
  local d = LD.current
  if not d or d.role ~= "leader" or d.state ~= "inviting" then return false, "busy" end
  if not LD.canStart(d) then return false, "expired" end
  local okComm, whyComm = LD.commState()
  if not okComm then return false, whyComm end -- e.g. a boss was pulled: start after the fight
  local list = LD.accepted(d)
  if #list < 2 then return false, "few" end
  d.participants = sorted(list)
  d.listHash = LD.listHash(d.lid, d.rs, d.itemId, d.participants)
  dropRepeats(d)
  -- over 10: the one-message list (LDS) AND the full list (LDQ) right away, LDS first. Most PCs start
  -- from LDS; one that missed a join completes from LDQ at once instead of waiting for a repeat
  -- (a 5%-loss network: start 52.8 s -> see LOOT_DUEL.md)
  LD.sendList(d, true)
  LD.enterReveal(d)
  return true
end

--- The fixed list: <place>-<commit> for every player (LDQ; 10 fit in one message, 40 need 4).
--- Over 10 the first send is ONE summary (LDS: places as a bit mask + the list hash): every PC has
--- the commitments from the players' own LDA already. The full list follows on repeats, for
--- whoever missed an LDA (full = true).
function LD.sendList(d, full)
  d.listSends, d.listAt = (d.listSends or 0) + 1, now()
  local items, places = {}, {}
  for _, e in ipairs(d.participants) do
    local pl = placeOf(d, e.name)
    items[#items + 1] = pl .. "-" .. e.commit
    places[#places + 1] = pl
  end
  local chunks = chunked(items) -- 10 players: 1 message; 40: 4
  if #chunks > 1 and not full then
    bcast(P().encode("LDS", d.lid, d.listHash, #d.participants, P().placeMask(places), (isPart(d, me()) or {}).commit or "-"), { key = "LDS:" .. d.lid, front = true })
    return
  end
  -- front of the queue, in order: insert the last chunk first
  for k = #chunks, 1, -1 do
    bcast(P().encode("LDQ", d.lid, d.listHash, #d.participants, k, #chunks, table.concat(chunks[k], ",")), { key = "LDQ:" .. d.lid .. ":" .. k, front = true })
  end
  if #chunks > 1 then
    bcast(P().encode("LDS", d.lid, d.listHash, #d.participants, P().placeMask(places), (isPart(d, me()) or {}).commit or "-"), { key = "LDS:" .. d.lid, front = true })
  end
end

--- Leader: has every player been heard since the go (a live score or a claim)? Then nobody needs
--- the go again.
function LD.allHeard(d)
  for _, p in ipairs(d.participants or {}) do
    local k = key(p.name)
    if not (same(p.name, me()) or d.live[k] or (d.results[k] and d.results[k].score)) then return false end
  end
  return true
end

--- Are start messages of this race still waiting in my send queue? (repeat only when they left)
local function startQueued(d)
  if not (ns.Comm and ns.Comm.queued) then return false end
  local pre = { "^LDQ:", "^LDS:", "^LDI:", "^LDW:", "^LDG:" }
  return ns.Comm.queued(function(q)
    if not q.key then return false end
    for _, x in ipairs(pre) do if q.key:find(x .. d.lid) then return true end end
    return false
  end)
end

--- Everyone: the list is fixed; players reveal their nonce.
function LD.enterReveal(d)
  d.state = "revealing"
  d.revealAt = now()
  d.iPlay = isPart(d, me()) ~= nil
  if d.iPlay then
    if (ns.Duel and ns.Duel.busy()) then d.iPlay = false; d.skipped = "duel" end -- never take over a running duel
  end
  if isPart(d, me()) then
    d.reveals[key(me())] = d.myNonce
    if d.role ~= "leader" then LD.sendReveal(d) end -- the leader's own share goes out with the go (LDW)
  end
  LD.tryGo(d)
  LD.tryGoSummary(d)
  emit("changed", d)
end

function LD.sendReveal(d)
  if not d.myNonce then return end
  d.nSends, d.nAt = (d.nSends or 0) + 1, now()
  bcast(P().encode("LDN", d.lid, d.myNonce), { key = "LDN:" .. d.lid, front = true })
end

--- Leader: when every player's nonce is in, relay them all and reveal its own (go).
function LD.tryGo(d)
  if d.role ~= "leader" or d.state ~= "revealing" then return end
  local entries = {}
  for _, p in ipairs(d.participants) do
    local n = d.reveals[key(p.name)]
    if not n then return end
    entries[#entries + 1] = { name = p.name, nonce = n }
  end
  d.revealed = sorted(entries)
  d.revealHashV = LD.revealHash(d.lid, d.revealed)
  LD.sendGo(d, true) -- over 10: LDG and the full go (LDW) right away, LDG first
  LD.begin(d)
end

--- Go: the leader's own nonce, the reveal hash and every player's nonce by place (LDW; 10 fit in one
--- message, 40 need 3). Over 10 the first send is ONE message (LDG): every PC has the players'
--- nonces from their own LDN; the full go follows on repeats for whoever missed one.
function LD.sendGo(d, full)
  d.goSends, d.goAt = (d.goSends or 0) + 1, now()
  -- s since my go, counted when the message actually leaves my queue (a busy queue delays it too)
  local function ageNow() return d.startAt and math.max(0, math.min(999, math.floor(now() - d.startAt))) or 0 end
  local age = ageNow()
  local items = {}
  for _, e in ipairs(d.revealed) do items[#items + 1] = placeOf(d, e.name) .. "-" .. e.nonce end
  local chunks = chunked(items) -- 10 players: 1 message; 40: 3
  if #chunks > 1 then
    local mine = isPart(d, me()) and d.reveals[key(me())] or "-"
    local g = P().encode("LDG", d.lid, d.nonceL, d.revealHashV, mine, age)
    local function makeG() return P().encode("LDG", d.lid, d.nonceL, d.revealHashV, mine, ageNow()) end
    -- the first go jumps the queue (everyone waits for it); repeats queue normally behind my claim
    -- and live score, and stop once every player has been heard in the race
    if d.goSends == 1 then
      if full then
        for k = #chunks, 1, -1 do
          bcast(P().encode("LDW", d.lid, d.nonceL, d.revealHashV, age, k, #chunks, table.concat(chunks[k], ",")), { key = "LDW:" .. d.lid .. ":" .. k, front = true,
            make = function() return P().encode("LDW", d.lid, d.nonceL, d.revealHashV, ageNow(), k, #chunks, table.concat(chunks[k], ",")) end })
        end
      end
      bcast(g, { key = "LDG:" .. d.lid, front = true, make = makeG }) -- ahead of the full go
    else
      bcast(g, { key = "LDG:" .. d.lid, make = makeG })
      if full then
        for k = 1, #chunks do
          bcast(P().encode("LDW", d.lid, d.nonceL, d.revealHashV, age, k, #chunks, table.concat(chunks[k], ",")), { key = "LDW:" .. d.lid .. ":" .. k,
            make = function() return P().encode("LDW", d.lid, d.nonceL, d.revealHashV, ageNow(), k, #chunks, table.concat(chunks[k], ",")) end })
        end
      end
    end
    return
  end
  for k = #chunks, 1, -1 do
    bcast(P().encode("LDW", d.lid, d.nonceL, d.revealHashV, age, k, #chunks, table.concat(chunks[k], ",")), { key = "LDW:" .. d.lid .. ":" .. k, front = true,
            make = function() return P().encode("LDW", d.lid, d.nonceL, d.revealHashV, ageNow(), k, #chunks, table.concat(chunks[k], ",")) end })
  end
end

--- Everyone: the race begins (seed from all nonces). Players start their run; others watch.
function LD.begin(d)
  d.seed = LD.seedFor(d.lid, d.nonceL, d.revealed)
  d.state = "playing"
  -- a go that came late (lost on the way, picked up from a repeat): this PC's clock is set back to
  -- the leader's go, and my run gets the rest of the time, so every run ends at the same moment
  local late = 0
  if d.role ~= "leader" and d.goAge then late = d.goAge + math.max(0, now() - (d.goAgeAt or now())) end
  if late >= LD.LATE_MIN then d.lateBy = math.floor(late + 0.5) end
  d.startAt = now() - (d.lateBy or 0)
  local rs = P().LOOT_RULESETS[d.rs]
  d.deadline = d.startAt + (rs.limitTicks + rs.countdownTicks) / 60 + LD.graceFor(d.rs)
  if d.iPlay and ns.Duel and ns.Duel.busy() then d.iPlay = false; d.skipped = "duel" end
  if d.iPlay and ns.App and ns.App.StartLoot then ns.App:StartLoot(d) end
  -- results that arrived before my start (out of order): check them now
  for _, p in ipairs(d.participants) do LD.verify(d, p.name) end
  if LD.allIn(d) then LD.finish(d) end
  emit("changed", d)
end

--- Leader: cancel before the start (or leave); everyone sees it (sent 3 times).
function LD.cancel(reason)
  local d = LD.current
  if not d then return end
  if d.role == "leader" and (d.state == "inviting" or d.state == "revealing" or d.state == "playing") then
    d.cancelMsg = P().encode("LDX", d.lid, (reason == "left" or reason == "noreveal") and reason or "cancel")
    d.cancelSends, d.cancelAt = 1, now()
    dropRepeats(d)
    bcast(d.cancelMsg, { key = "LDX:" .. d.lid, front = true })
  end
  if d.state == "inviting" or d.state == "revealing" or (d.role == "leader" and d.state ~= "done") then
    d.state = "cancelled"; d.endReason = (reason == "noreveal") and "noreveal" or "cancelled"
  end
  emit("changed", d)
end

function LD.clear()
  local d = LD.current
  if d and (d.state == "done" or d.state == "cancelled" or (d.state == "inviting" and d.role ~= "leader" and d.myAnswer == "d")) then
    LD.current = nil
    emit("changed", nil)
  end
end

------------------------------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------------------------------
--- My run ended (App:OnRunOver): send my result and log (repeated, a message can be lost).
function LD.onLocalEnd(s)
  local d = LD.current
  if not d or s.loot ~= d then return end
  local st = s.state
  local packed = P().packLog(st.inputLog)
  local chunks = P().chunk(packed)
  if #chunks == 0 then chunks = { "" } end
  d.myFinal = {
    msg = P().encode("LDE", d.lid, P().b36(st.tick), P().b36(st.score), P().b36(st.lines), P().b36(st.level), ns.Engine.hashState(st), #chunks),
    chunks = chunks, sends = 0, logSends = 0,
  }
  -- my own result counts like anyone's: replayed from my own log (stored first, so I know
  -- whether I'm a contender before sending)
  LD.storeResult(d, me(), { ticks = st.tick, score = st.score, lines = st.lines, level = st.level, hash = ns.Engine.hashState(st), chunks = #chunks })
  local r = d.results[key(me())]
  for i, c in ipairs(chunks) do r.parts[i] = c end
  LD.sendFinal(d)
  LD.verify(d, me())
  if LD.allIn(d) then LD.finish(d) end -- I may be the last one
  emit("changed", d)
end

--- My claim (LDE) goes to everyone; my log (LDL) only while my claim is among the best
--- LD.CONTENDERS (ties included): only those can win, so only those are replayed. Up to 10 players
--- everyone is a contender (every PC replays every run, as before).
function LD.sendFinal(d)
  local f = d.myFinal
  if not f then return end
  f.sends, f.at = f.sends + 1, now()
  bcast(f.msg, { key = "LDE:" .. d.lid, front = true }) -- one short message everyone waits for
  if LD.shouldSendLog(d) then LD.sendLog(d) end
end

--- Up to 10 players every run is replayed, so logs go out at once. With more, the claims must be
--- known first: a run that topped out early would otherwise look like a top-10 run to itself. So
--- logs wait until every claim is in, or the race time + pause budget + 5 s is over, and only the
--- best 10 (ties included) send one. Every PC also replays only the runs it sees in its best 10.
function LD.claimsKnown(d, t)
  if #(d.participants or {}) <= LD.CONTENDERS then return true end
  local rs = P().LOOT_RULESETS[d.rs]
  if d.startAt and rs and (t or now()) >= d.startAt + (d.frozen or 0) + (rs.limitTicks + rs.countdownTicks) / 60 + LD.PAUSE_BUDGET + 5 then return true end
  for _, p in ipairs(d.participants) do
    local r = d.results[key(p.name)]
    if not (r and r.score) and not (d.gone and d.gone[key(p.name)]) then return false end
  end
  return true
end
--- My claim (LDE, one short message) goes out 3 times; over 10 players 5 times: every PC needs
--- every claim before it can rank the best 10, and a PC that misses one waits for the deadline.
function LD.claimSends(d) return #(d.participants or {}) > LD.CONTENDERS and 5 or 3 end
function LD.shouldSendLog(d, t)
  return LD.claimsKnown(d, t) and LD.isContender(d, me())
end
function LD.sendLog(d)
  local f = d.myFinal
  if not f then return end
  f.logSends, f.logAt = (f.logSends or 0) + 1, now()
  for i, c in ipairs(f.chunks) do bcast(P().encode("LDL", d.lid, i, #f.chunks, c), { key = "LDL:" .. d.lid .. ":" .. i }) end
end

local function better(a, b)
  if a.score ~= b.score then return a.score > b.score end
  return (a.lines or 0) > (b.lines or 0)
end
--- Is `name`'s claim among the best LD.CONTENDERS still in the running (ties included)?
function LD.isContender(d, name)
  local r = d.results[key(name)]
  if not (r and r.score) or r.status == "rejected" or r.status == "missing" then return false end
  local ahead = 0
  for _, p in ipairs(d.participants or {}) do
    local x = d.results[key(p.name)]
    if x and x ~= r and x.score and x.status ~= "rejected" and x.status ~= "missing" and better(x, r) then
      ahead = ahead + 1
      if ahead >= (d.contenderLimit or LD.CONTENDERS) then return false end
    end
  end
  return true
end

function LD.storeResult(d, name, m)
  local k = key(name)
  local r = d.results[k]
  if r and r.status and r.status ~= "pending" then return end -- first complete result stands
  r = r or { parts = {} }
  r.name, r.ticks, r.score, r.lines, r.level, r.hash, r.chunks = name, m.ticks, m.score, m.lines, m.level, m.hash, m.chunks
  r.status = "pending"
  r.claimAt = r.claimAt or now()
  d.results[k] = r
end

--- Replay a player's log on the shared seed with the same checks as duels and the web
--- (Engine/Verify.lua: time cap, input rate, inputs after top-out, claimed score / lines / hash).
--- A complete log waits in a queue: replays (7-20 ms each) run one per frame, and not while my own
--- run is live, so checking 10 logs never costs FPS mid-race (LD.update -> LD.runChecks).
function LD.verify(d, name)
  local r = d.results[key(name)]
  if not d.seed or not r or r.status ~= "pending" or not r.chunks or not r.parts then return end
  for i = 1, r.chunks do if not r.parts[i] then return end end
  if not (LD.claimsKnown(d) and LD.isContender(d, name)) then return end -- kept; re-checked once claims settle
  if not r.queued then r.queued = true; d.checkQueue = d.checkQueue or {}; d.checkQueue[#d.checkQueue + 1] = name end
  if not LD.myRunLive(d) and not LD.deferChecks then LD.runChecks(d, 1) end
end

function LD.myRunLive(d)
  local s = ns.App and ns.App.session
  return d.iPlay and s ~= nil and s.loot == d and not s.recorded and s.phase ~= "over"
end

--- Replay up to `max` queued logs now. Returns how many were checked.
function LD.runChecks(d, max)
  local q, n = d.checkQueue, 0
  while q and #q > 0 and n < (max or 1) do
    local name = table.remove(q, 1)
    LD.check(d, name)
    n = n + 1
  end
  if n > 0 and d.state == "playing" and LD.allIn(d) then LD.finish(d) end
  return n
end

function LD.check(d, name)
  local r = d.results[key(name)]
  if not r or r.status ~= "pending" or not r.parts then return end
  local c0 = os and os.clock and os.clock()
  local log = P().unpackLog(table.concat(r.parts, "", 1, r.chunks))
  local rs = P().LOOT_RULESETS[d.rs]
  local why
  if not log then why = "log" end
  if not why then for i = 2, #log, 2 do if log[i] > 6 then why = "log"; break end end end -- no spells in a Loot Duel
  if not why then
    local okV, v = pcall(ns.Verify.verify, log, d.seed, r.ticks,
      { seed = d.seed, capTicks = rs.limitTicks, engine = d.engine, claimed = { score = r.score, lines = r.lines, level = r.level, hash = r.hash } })
    if not okV then why = "log"
    elseif not v.ok then why = v.reasons[1] or "mismatch" end
  end
  r.status = why and "rejected" or "verified"
  r.why = why
  r.class = rosterEntry(name) and rosterEntry(name).class or r.class
  r.parts = nil -- the log has done its job: free it (40 players, 10 kept races)
  if c0 then
    local ms = (os.clock() - c0) * 1000
    LD.stats.checks, LD.stats.checkMs = LD.stats.checks + 1, LD.stats.checkMs + ms
    if ms > LD.stats.maxCheckMs then LD.stats.maxCheckMs = ms end
  end
  emit("changed", d)
end
LD.stats = { checks = 0, checkMs = 0, maxCheckMs = 0 } -- measured replay cost (tests, /sr duel debug)

--- Done when every player has a claim and every contender's log is checked (or out). Claims that
--- can't reach the best 10 don't need their log.
function LD.allIn(d)
  if not d.participants or d.state ~= "playing" then return false end
  for _, p in ipairs(d.participants) do
    local r = d.results[key(p.name)]
    if not r or r.status == nil or not r.score then -- log chunks alone aren't a result
      if not (d.gone and d.gone[key(p.name)]) then return false end -- offline / left: can't send one
    end
    if r and r.status == "pending" and LD.isContender(d, p.name) then return false end
  end
  return true
end

--- At the deadline: contenders whose log never came are out. If that lets the next claims in,
--- they get LD.PROMOTE_GRACE more (twice at most). Returns true when it extended the deadline.
function LD.expireContenders(d, t)
  local late = {}
  for _, p in ipairs(d.participants) do
    local r = d.results[key(p.name)]
    if r and r.status == "pending" and r.score and LD.isContender(d, p.name) then late[#late + 1] = r end
  end
  for _, r in ipairs(late) do r.status, r.why = "missing", "log_incomplete"; r.parts = nil end
  -- a top log never came (withheld or lost): from now on EVERY remaining claim sends its log and is
  -- replayed, so checking goes on down the whole list in one more round instead of 10 at a time
  -- (several withheld logs can't push the result past one more grace period)
  if #late > 0 then d.contenderLimit = P().LOOT_MAX end
  local promoted = false
  for _, p in ipairs(d.participants) do
    local r = d.results[key(p.name)]
    if r and r.status == "pending" and LD.isContender(d, p.name) and not (r.parts and r.chunks and #r.parts >= r.chunks) then promoted = true end
  end
  if promoted and (d.extensions or 0) < 2 then
    d.extensions = (d.extensions or 0) + 1
    d.deadline = t + LD.PROMOTE_GRACE
    return true
  end
  return false
end

function LD.finish(d)
  if d.state == "done" then return end
  d.state = "done"
  d.doneAt = now()
  LD.runChecks(d, 99) -- anything still queued is checked now
  local late = {}
  for _, p in ipairs(d.participants) do
    local r = d.results[key(p.name)]
    if not r then d.results[key(p.name)] = { name = p.name, status = "missing", why = "no_result" }
    elseif r.status == nil or not r.score then r.status, r.why = "missing", "no_result"
    elseif r.status == "pending" and LD.isContender(d, p.name) then late[#late + 1] = r end
  end
  for _, r in ipairs(late) do r.status, r.why = "missing", "log_incomplete" end
  -- claims below the best 10 were never needed: shown, not checked, can't win
  for _, p in ipairs(d.participants) do
    local r = d.results[key(p.name)]
    if r.status == "pending" then r.status, r.why = "unchecked", "below_top" end
    r.parts = nil
  end
  d.standings, d.winner, d.tied = LD.standings(d.participants, d.results)
  if d.role == "leader" then
    d.ldrMsg = P().encode("LDR", d.lid, d.winner and P().hexName(d.winner) or "-", #d.tied > 1 and 1 or 0)
    d.ldrSends, d.ldrAt = 1, now()
    bcast(d.ldrMsg, { key = "LDR:" .. d.lid })
  end
  table.insert(LD.history, 1, d)
  while #LD.history > LD.KEEP_RESULTS do table.remove(LD.history) end
  -- the leader's result may have arrived before mine was ready
  local early = LD.earlyLDR and LD.earlyLDR[d.lid]
  if early then LD.earlyLDR[d.lid] = nil; LD.compareLeader(d, early) end
  emit("result", d)
  emit("changed", d)
end

function LD.compareLeader(d, m)
  d.leaderWinner, d.leaderTie = m.winner, m.tie
  local tieHere = #(d.tied or {}) > 1
  local agree = (m.winner == nil) == (d.winner == nil) and (m.winner == nil or same(m.winner, d.winner)) and (m.tie == tieHere)
  d.agreement = agree and "agreed" or "disputed"
end

------------------------------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------------------------------
local function fromLeader(d, sender) return d and same(d.leader, sender) end

local H = {}
function H.LDJ(m, sender)
  -- only the group's leader / assistant / master looter may offer; nothing from outside the group
  if not LD.mayLead(sender) then return end
  local d = LD.current
  if d and d.lid == m.lid then return end -- a repeat
  if d and d.state ~= "done" and d.state ~= "cancelled" then
    -- an open invite is replaced by: the same leader's new offer (after a /reload or crash), or any
    -- offer when this one doesn't involve me (I'm not invited, or I passed)
    local replace = d.role ~= "leader" and d.state == "inviting"
      and (fromLeader(d, sender) or d.myAnswer == "d" or (#d.inviteOrder > 0 and not isInvitee(d, me())))
    if not replace then return end
  end
  LD.current = newLd({ lid = m.lid, role = "member", leader = sender, rs = m.rs, engine = m.engine, itemId = m.itemId,
    commit = m.commit, count = m.count, state = "inviting", createdAt = now(), inviteOrder = {} })
  -- invitee chunks that overtook the offer (messages can arrive out of order)
  local early = LD.early and LD.early[m.lid]
  LD.early = nil
  emit("changed", LD.current)
  if early and same(early.sender, sender) then for _, c in ipairs(early.msgs) do H.LDI(c, sender) end end
end
function H.LDI(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid) then
    -- before its offer: keep it a moment (one pending offer at a time, max 9 chunks)
    if not LD.mayLead(sender) then return end
    LD.early = (LD.early and LD.early[m.lid]) and LD.early or { [m.lid] = { sender = sender, msgs = {} } }
    local e = LD.early[m.lid]
    if same(e.sender, sender) and #e.msgs < 9 then e.msgs[#e.msgs + 1] = m end
    return
  end
  if not (fromLeader(d, sender) and d.state == "inviting") then return end
  if d.inviteChunks[m.k] then return end
  local realm = (d.leader or ""):match("%-(.+)$")
  local names = {}
  for _, n in ipairs(m.names) do names[#names + 1] = (n:find("-", 1, true) or not realm) and n or (n .. "-" .. realm) end
  d.inviteChunks[m.k] = names
  local order = {}
  for k = 1, 20 do for _, n in ipairs(d.inviteChunks[k] or {}) do if #order < P().LOOT_MAX then order[#order + 1] = n end end end
  d.inviteOrder = order
  -- a start list that arrived before the whole invite list can be checked now
  if d.listMsg and d.count and #order >= d.count then LD.tryList(d) end
  LD.trySummary(d)
  if d.role == "member" and isInvitee(d, me()) and not d.prompted then
    d.prompted = true
    if d.engine ~= ns.Engine.ENGINE_VERSION then LD.answer(false); d.versionMismatch = true
    else emit("invite", d) end
  end
  emit("changed", d)
end
function H.LDA(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and d.state == "inviting") then return end
  -- an answer can overtake the invite list chunk with that name (the leader's own answer goes out
  -- right behind the offer): keep it while the list is incomplete; only invitees ever count
  if not (isInvitee(d, sender) or #d.inviteOrder < (d.count or 0)) then return end
  d.answers[key(sender)] = { accept = m.accept, commit = m.commit, name = sender }
  LD.trySummary(d)
  emit("changed", d)
end
--- Chunked start messages: keep chunk k of n; the whole message once every chunk is in (all chunks
--- must agree on the header, or a modified leader could mix two lists).
local function collect(d, field, m, header)
  local c = d[field]
  if not c or c.header ~= header or c.n ~= m.n then c = { header = header, n = m.n, parts = {} }; d[field] = c end
  if c.parts[m.k] then return nil end
  c.parts[m.k] = m.entries
  for k = 1, m.n do if not c.parts[k] then return nil end end
  local all = {}
  for k = 1, m.n do for _, e in ipairs(c.parts[k]) do all[#all + 1] = e end end
  return all
end

function H.LDQ(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and fromLeader(d, sender)) or d.role == "leader" then return end
  local all = collect(d, "listParts", m, m.listHash .. ":" .. m.count)
  if not all then return end
  d.listMsg = { listHash = m.listHash, count = m.count, entries = all }
  LD.tryList(d)
end

--- Member: accept the fixed list once it is complete and matches everything this PC saw.
function LD.tryList(d)
  if d.state ~= "inviting" or not d.listMsg then return end
  -- the list names players by their place in the invite list: wait until I have all of it
  if not d.count or #d.inviteOrder < d.count then return end
  local m = d.listMsg
  local entries, bad = {}, nil
  for _, e in ipairs(m.entries) do
    local n = d.inviteOrder[e.i]
    if not n then bad = "not_invited" else entries[#entries + 1] = { name = n, commit = e.commit } end
  end
  if not bad and (#entries ~= m.count or #entries < 2) then bad = "list" end
  if not bad and LD.listHash(d.lid, d.rs, d.itemId, entries) ~= m.listHash then bad = "list" end
  local mine
  if not bad then
    local seen = {}
    for _, e in ipairs(entries) do
      if seen[key(e.name)] then bad = "list" end
      seen[key(e.name)] = true
      if not isInvitee(d, e.name) then bad = "not_invited" end
      -- every commitment must be the one that player sent when joining (as this PC saw it)
      local a = d.answers[key(e.name)]
      if a and (not a.accept or a.commit ~= e.commit) then bad = "commit_swap" end
      if same(e.name, me()) then mine = e end
    end
  end
  if not bad and mine and mine.commit ~= d.myCommit then bad = "my_commit" end
  if bad then d.state, d.endReason = "cancelled", "bad_start_" .. bad; emit("changed", d); return end
  d.listHash = m.listHash
  d.participants = sorted(entries)
  if d.myAnswer == "a" and not mine then
    -- I joined, but the leader left me out: say so (the others may not know)
    d.leftOut = true
  end
  LD.enterReveal(d)
end

--- Member: the one-message list (LDS). Built from the commitments this PC saw in the players'
--- own LDA; used only if it gives exactly the leader's list hash, else the full list decides.
function H.LDS(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and fromLeader(d, sender)) or d.role == "leader" then return end
  d.listSummary = m
  LD.trySummary(d)
end
function LD.trySummary(d)
  local m = d.listSummary
  if not m or d.state ~= "inviting" or d.listMsg then return end
  if not d.count or #d.inviteOrder < d.count then return end
  local entries, full = {}, {}
  for _, i in ipairs(m.places) do
    local n = d.inviteOrder[i]
    local a = n and d.answers[key(n)]
    local c = (n and same(n, d.leader) and m.leaderCommit) or (a and a.accept and a.commit)
    if not c then return end -- I missed someone's join: wait for the full list
    entries[#entries + 1] = { name = n, commit = c }
    full[#full + 1] = { i = i, commit = c }
  end
  if LD.listHash(d.lid, d.rs, d.itemId, entries) ~= m.listHash then return end
  d.listMsg = { listHash = m.listHash, count = m.count, entries = full }
  LD.tryList(d)
end

function H.LDN(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid) then return end
  local p, commit
  if d.state == "revealing" then
    p = isPart(d, sender)
    commit = p and p.commit
  elseif d.state == "inviting" then
    -- a share can overtake the list (other players got it first): keep it if it matches their join
    local a = d.answers[key(sender)]
    commit = a and a.accept and a.commit
  else return end
  if not commit or P().commit16(d.lid, m.nonce) ~= commit then return end -- not theirs to reveal
  d.reveals[key(p and p.name or sender)] = m.nonce
  LD.tryGo(d)
  LD.tryGoSummary(d)
end
--- Member: the one-message go (LDG): the nonces this PC got from the players' own LDN + the
--- leader's. Used only if they give exactly the leader's reveal hash, else the full go decides.
function H.LDG(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and fromLeader(d, sender)) or d.role == "leader" then return end
  d.goSummary = m
  if not d.goAge or m.age >= d.goAge then d.goAge, d.goAgeAt = m.age, now() end -- the newest repeat says how late
  LD.tryGoSummary(d)
end
function LD.tryGoSummary(d)
  local m = d.goSummary
  if not m or d.role == "leader" or d.state ~= "revealing" or d.goMsg or not d.participants then return end
  local entries = {}
  for _, p in ipairs(d.participants) do
    local n = same(p.name, d.leader) and m.leaderNonce or d.reveals[key(p.name)]
    if not n then return end
    entries[#entries + 1] = { name = p.name, nonce = n }
  end
  if LD.revealHash(d.lid, entries) ~= m.revealHash then return end
  local full = {}
  for _, e in ipairs(sorted(entries)) do full[#full + 1] = { i = placeOf(d, e.name), nonce = e.nonce } end
  d.goMsg = { nonce = m.nonce, revealHash = m.revealHash, entries = full }
  LD.tryGoMember(d)
end
function H.LDW(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and fromLeader(d, sender)) or d.role == "leader" then return end
  if not d.goAge or m.age >= d.goAge then d.goAge, d.goAgeAt = m.age, now() end -- how late this go is
  local all = collect(d, "goParts", m, m.nonce .. ":" .. m.revealHash)
  if not all then return end
  d.goMsg = { nonce = m.nonce, revealHash = m.revealHash, entries = all }
  LD.tryGoMember(d)
end

--- Member: start once every nonce (checked against its commitment) and the leader's are in.
function LD.tryGoMember(d)
  if d.state ~= "revealing" or not d.goMsg then return end
  local m = d.goMsg
  local entries, bad = {}, nil
  for _, e in ipairs(m.entries) do
    local n = d.inviteOrder[e.i]
    if not n then bad = "reveal" else entries[#entries + 1] = { name = n, nonce = e.nonce } end
  end
  if not bad and #entries ~= #d.participants then bad = "reveal" end
  if not bad and P().commit16(d.lid, m.nonce) ~= d.commit then bad = "commit" end -- the leader's nonce was fixed at the offer
  if not bad and LD.revealHash(d.lid, entries) ~= m.revealHash then bad = "reveal" end
  if not bad then
    for _, e in ipairs(entries) do
      local p = isPart(d, e.name)
      if not p or P().commit16(d.lid, e.nonce) ~= p.commit then bad = "reveal" end
      if same(e.name, me()) and e.nonce ~= d.myNonce then bad = "my_nonce" end
    end
  end
  if bad then d.state, d.endReason = "cancelled", "bad_start_" .. bad; emit("changed", d); return end
  d.nonceL = m.nonce
  d.revealed = sorted(entries)
  LD.begin(d)
end

function H.LDC(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and d.state == "playing") then return end
  local p = isPart(d, sender)
  if p then d.live[key(p.name)] = { tick = m.tick, score = m.score, at = now() }; emit("live", d) end
end
local function resultState(d) return d.state == "playing" or d.state == "revealing" end -- results can overtake my start
function H.LDE(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and resultState(d)) then return end
  local p = isPart(d, sender)
  if not p then return end
  LD.storeResult(d, p.name, m)
  LD.verify(d, p.name)
  if LD.allIn(d) then LD.finish(d) end
  emit("changed", d)
end
function H.LDL(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and resultState(d)) then return end
  local p = isPart(d, sender)
  if not p then return end
  local k = key(p.name)
  d.results[k] = d.results[k] or { parts = {}, name = p.name }
  local r = d.results[k]
  if r.status and r.status ~= "pending" then return end
  r.parts[m.i] = r.parts[m.i] or m.payload
  LD.verify(d, p.name)
  if LD.allIn(d) then LD.finish(d) end
end
--- Someone misses my claim or part of my log: send it again (each piece at most every 4 s, 40
--- resends per race in all, so a request can't make me flood the channel).
function H.LDK(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and (d.state == "playing" or d.state == "done")) then d = LD.history[1] end
  if not (d and d.lid == m.lid and d.participants and isPart(d, sender)) then return end
  d.nackSeen = d.nackSeen or {}
  d.nackSeen[m.i .. ":" .. m.what] = now() -- someone already asked: others wait for the answer
  local mine = d.inviteOrder and d.inviteOrder[m.i]
  local f = d.myFinal
  if not (mine and same(mine, me()) and f) then return end
  d.resent = d.resent or {}
  local t, budget = now(), d.resendBudget or 40
  local function once(k, msg, opts)
    if budget <= 0 or t - (d.resent[k] or -99) < 4 then return end
    d.resent[k], budget = t, budget - 1
    bcast(msg, opts)
  end
  if m.what == "e" then once("e", f.msg, { key = "LDE:" .. d.lid })
  else
    for i in m.what:gmatch("%d+") do
      local c = f.chunks[tonumber(i)]
      if c then once("l" .. i, P().encode("LDL", d.lid, tonumber(i), #f.chunks, c), { key = "LDL:" .. d.lid .. ":" .. i }) end
    end
  end
  d.resendBudget = budget
end

--- Every second while results come in: ask for a claim that should be here by now, or for the
--- missing chunks of a log I need (a contender's). At most every 8 s per player, 4 times; not if
--- someone else asked for the same in the last 6 s (their answer reaches me too).
function LD.askMissing(d, t)
  local rs = P().LOOT_RULESETS[d.rs]
  if not (rs and d.startAt) then return end
  local claimsDue = t >= d.startAt + (d.frozen or 0) + (rs.limitTicks + rs.countdownTicks) / 60 + LD.PAUSE_BUDGET + 5
  d.asked = d.asked or {}
  d.nackSeen = d.nackSeen or {}
  if not d.knownAt and LD.claimsKnown(d, t) then d.knownAt = t end -- contenders send their logs from now
  for i, n in ipairs(d.inviteOrder or {}) do
    local p = isPart(d, n)
    if p and not same(n, me()) and not (d.gone and d.gone[key(n)]) then
      local r = d.results[key(n)]
      local what
      if not (r and r.score) then
        if claimsDue then what = "e" end
      elseif r.status == "pending" and r.chunks and d.knownAt and LD.isContender(d, n) and t - math.max(r.claimAt or t, d.knownAt) >= 8 then
        local miss = {}
        for c = 1, r.chunks do
          if not (r.parts and r.parts[c]) and #table.concat(miss, ".") + #tostring(c) < 59 then miss[#miss + 1] = c end
        end
        if #miss > 0 then what = table.concat(miss, ".") end
      end
      if what and what ~= "" then
        local a = d.asked[i] or { n = 0, at = -99 }
        local seen = d.nackSeen[i .. ":" .. what] or d.nackSeen[i .. ":e"]
        if a.n < 4 and t - a.at >= 8 and not (seen and t - seen < 6) then
          a.n, a.at = a.n + 1, t
          d.asked[i] = a
          d.nackSeen[i .. ":" .. what] = t
          bcast(P().encode("LDK", d.lid, i, what), { key = "LDK:" .. d.lid .. ":" .. i })
        end
      end
    end
  end
end

function H.LDX(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and fromLeader(d, sender)) then return end
  if d.state == "inviting" or d.state == "revealing" then
    d.state, d.endReason = "cancelled", (m.reason == "noreveal") and "noreveal" or "leader_cancelled"
  elseif d.state == "playing" then d.leaderLeft = true end -- the race goes on: results are computed on every PC
  emit("changed", d)
end
function H.LDR(m, sender)
  for _, d in ipairs(LD.history) do
    if d.lid == m.lid and fromLeader(d, sender) then LD.compareLeader(d, m); emit("changed", d); return end
  end
  local d = LD.current
  if d and d.lid == m.lid and fromLeader(d, sender) then
    LD.earlyLDR = { [m.lid] = m } -- compared when my own result is ready
  end
end

--- Every frame (Duel.update): repeats, live score, timeouts, pause budget, deadline.
--- My own run in a Loot Duel: live score out every few seconds, and the pause budget (combat,
--- chat). Runs every frame while racing, also while WoW holds addon messages (the game is local).
function LD.localRun(d, t)
  local s = ns.App and ns.App.session
  if d.iPlay and s and s.loot == d and not s.recorded then
    if s.phase == "playing" and t - (d.liveAt or 0) >= LD.liveEvery(d) then
      d.liveAt = t
      d.live[key(me())] = { tick = s.state.tick, score = s.state.score, at = t }
      bcast(P().encode("LDC", d.lid, P().b36(s.state.tick), P().b36(s.state.score)), { key = "LDC:" .. d.lid, low = true })
      emit("live", d)
    end
    -- pauses (combat, chat) are allowed but limited: past the budget the run ends where it is
    if s.phase == "paused" then
      d.paused = (d.paused or 0) + math.max(0, t - (d.pauseT or t))
      if d.paused > LD.PAUSE_BUDGET and s.finish then d.pauseLimit = true; s:finish("pause_limit") end
    end
    d.pauseT = t
  end
end

function LD.update(t)
  local d = LD.current
  if not d then return end
  -- WoW's addon chat lockdown (Retail / Forever: boss fight, Mythic+, PvP match): our messages are
  -- held, not lost, so every waiting time stops too - nobody is "out" because WoW paused the channel
  local dt = math.max(0, t - (d.lastT or t))
  d.lastT = t
  d.lockedNow = ns.Comm and ns.Comm.isLocked and ns.Comm.isLocked() or false
  if d.lockedNow then d.lockedAt = t end
  if d.lockedNow and dt > 0 and dt < 5 then
    d.frozen = (d.frozen or 0) + dt
    if d.revealAt then d.revealAt = d.revealAt + dt end
    if d.deadline then d.deadline = d.deadline + dt end
    if d.createdAt and d.state == "inviting" then d.createdAt = d.createdAt + dt end
    if d.state == "playing" then LD.localRun(d, t) end -- my own run goes on: the game is local
    return -- nothing to send or decide until it lifts
  end
  if d.cancelMsg and d.cancelSends < 3 and t - d.cancelAt >= 3 then
    d.cancelSends, d.cancelAt = d.cancelSends + 1, t
    bcast(d.cancelMsg, { key = "LDX:" .. d.lid })
  end
  if d.state == "inviting" then
    -- repeat the offer only while someone hasn't answered (a 10-player invite is 5 messages)
    if d.role == "leader" and t - (d.offerAt or 0) >= LD.REPEAT and t - d.createdAt < LD.INVITE_TIME and unanswered(d)
      and (d.offerSends or 0) < LD.OFFER_SENDS then LD.sendOffer(d) end
    if d.myAnswer and (d.answerSends or 0) < 3 and t - (d.answerAt or 0) >= LD.REPEAT then
      d.answerSends, d.answerAt = d.answerSends + 1, t
      bcast(P().encode("LDA", d.lid, d.myAnswer, d.myAnswer == "a" and d.myCommit or "-"), { key = "LDA:" .. d.lid, low = true })
    end
    if t - d.createdAt > LD.START_WAIT and d.role ~= "leader" then d.state, d.endReason = "cancelled", "not_started"; emit("changed", d) end
  elseif d.state == "revealing" then
    -- repeats only help someone who missed a message; each costs the sender's message budget
    if d.role == "leader" and d.listSends == 1 and t - (d.listAt or 0) >= 2.5 and not startQueued(d) then
      LD.sendList(d) -- the one-message list once more (cheap; most who missed it need nothing else)
    elseif d.role == "leader" and t - (d.listAt or 0) >= 5 and not startQueued(d) then
      -- someone's share is missing: maybe they lost part of the invite list or someone's join
      -- (the start refers to places and commitments) - send it again, in full. Only once the last
      -- repeat has left the queue (40 players: 8 messages, ~16 s at our rate), until the reveal
      -- time is over.
      LD.sendInvitees(d, { front = true })
      LD.sendList(d, true)
    end
    -- a player who went offline or left the group can't reveal: cancel now (no re-roll without
    -- them, see LOOT_DUEL.md) instead of keeping everyone waiting for the reveal time
    if d.role == "leader" and t - (d.goneAt or 0) >= 1 then
      d.goneAt = t
      local on = {}
      for _, e in ipairs(LD.roster()) do if e.online then on[key(e.name)] = true end end
      for _, p in ipairs(d.participants) do
        if not d.reveals[key(p.name)] and not on[key(p.name)] then d.goneName = p.name; LD.cancel("noreveal"); return end
      end
    end
    -- my share: again after 2.5 s, then every 5 s (one short message; the leader can't start without it)
    if d.role ~= "leader" and d.myNonce and isPart(d, me()) and (d.nSends or 0) < 5 and t - (d.nAt or 0) >= ((d.nSends or 0) <= 1 and 2.5 or 5) then LD.sendReveal(d) end
    if t - d.revealAt > LD.revealTime(d) then
      if d.role == "leader" then LD.cancel("noreveal")
      elseif t - d.revealAt > LD.revealTime(d) + 15 then d.state, d.endReason = "cancelled", "not_started"; emit("changed", d) end
    end
  elseif d.state == "playing" then
    -- go repeats: the one-message go once more after 2.5 s (cheap), then the full go twice
    if d.role == "leader" and (d.goSends or 0) < 4 and t - (d.goAt or 0) >= ((d.goSends or 0) <= 1 and 2.5 or 5) and not startQueued(d)
      and not LD.allHeard(d) then
      LD.sendGo(d, (d.goSends or 0) >= 2)
    end
    LD.localRun(d, t)
    -- once a second: complete logs that were held back (claims not settled, or someone above was
    -- rejected and this run moved into the best 10) are queued now
    if t - (d.requeueAt or 0) >= 1 then
      d.requeueAt = t
      -- who went offline or left the group without a claim: a WoW disconnect ends the run (the UI
      -- reloads), so nobody waits the full grace period for them
      local on = {}
      for _, e in ipairs(LD.roster()) do if e.online then on[key(e.name)] = true end end
      d.gone = {}
      for _, p in ipairs(d.participants) do if not on[key(p.name)] then d.gone[key(p.name)] = true end end
      -- only queue here: the replays run one per frame below (ten in this loop would be one long frame)
      local was = LD.deferChecks
      LD.deferChecks = true
      for _, p in ipairs(d.participants) do LD.verify(d, p.name) end
      LD.deferChecks = was
      if d.state == "playing" and LD.allIn(d) then LD.finish(d) end
      if d.state == "playing" then LD.askMissing(d, t) end
    end
    -- replays: one per frame, never while my own run is live
    if d.checkQueue and #d.checkQueue > 0 and not LD.myRunLive(d) then LD.runChecks(d, 1) end
    if d.state == "playing" and t > d.deadline and not LD.expireContenders(d, t) then LD.finish(d) end
  end
  -- a contender (or promoted into the best 10 because someone above was out) sends the log,
  -- repeated; also after my own PC has finished, because the others may still need it
  local f = d.myFinal
  if f and (d.state == "playing" or d.state == "done") and LD.shouldSendLog(d, t) and (f.logSends or 0) < 3 and t - (f.logAt or -99) >= 5 then LD.sendLog(d) end
  if (d.state == "playing" or d.state == "done") and d.myFinal and d.myFinal.sends < LD.claimSends(d) and t - d.myFinal.at >= 5 then
    d.myFinal.sends, d.myFinal.at = d.myFinal.sends + 1, t
    bcast(d.myFinal.msg, { key = "LDE:" .. d.lid })
  end
  if d.state == "done" and d.ldrMsg and d.ldrSends < 3 and t - d.ldrAt >= 5 then
    d.ldrSends, d.ldrAt = d.ldrSends + 1, t
    bcast(d.ldrMsg, { key = "LDR:" .. d.lid })
  end
end

function LD.init()
  if not ns.Comm then return end
  for kind, fn in pairs(H) do ns.Comm.on(kind, fn) end
  -- leaving the game while I lead an open invite: tell the group (it won't wait for a start)
  if CreateFrame and not LD.frame then
    LD.frame = CreateFrame("Frame")
    pcall(LD.frame.RegisterEvent, LD.frame, "PLAYER_LOGOUT")
    LD.frame:SetScript("OnEvent", function()
      local d = LD.current
      if d and d.role == "leader" and (d.state == "inviting" or d.state == "revealing") then
        pcall(ns.Comm.send, P().encode("LDX", d.lid, "left"), LD.channel() or "PARTY", nil, nil, { front = true })
        if ns.Comm.flush then pcall(ns.Comm.flush) end
      end
    end)
  end
end

return LD
