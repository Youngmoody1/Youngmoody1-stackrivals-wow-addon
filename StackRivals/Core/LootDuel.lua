--[[
  StackRivals - Loot Duel: a raid / party settles who gets an item with a short StackRivals race
  instead of /roll. Separate from Quickplay and duels; never ranked; never touches loot.

  Flow (docs/LOOT_DUEL.md):
    1. The party leader, raid leader, an assistant or the master looter opens Loot Duel, picks an
       item (link or item ID), a time (1:00 or 2:00) and 2-10 group members, and invites them
       (LDF + LDI). All of them play at once: one race, no 1v1 rounds.
    2. Each invitee accepts or declines in a popup (LDA). Accepting sends only a COMMITMENT to a
       secret seed nonce. Nobody is entered automatically; no answer = not in.
    3. The leader starts with the players who accepted (at least 2): the final list of names and
       commitments goes out in one message (LDQ, players by their place in the invite list). Every PC checks it against the answers it saw itself
       (a player who joined and was left out is told so). Then every player reveals their nonce
       (LDN); the leader relays them all and reveals its own committed nonce in one go (LDW). All
       commitments are fixed before anyone reveals, so nobody - the leader included - can know or
       steer the pieces; a missing reveal cancels the whole race (no re-roll by leaving someone out).
    4. Everyone plays the same pieces at once, no spells. Live scores (LDC) feed a leaderboard.
    5. Each player sends their final score and input log (LDE + LDL). EVERY PC replays EVERY log.
    6. Standings: replay-checked results by score, then lines. A tie at the top stays a tie (roll
       off with /roll). Missing (disconnect, past the deadline) or failed replay = out. No result
       is invented for anyone.
    7. The loot master hands out the item in WoW, by hand. StackRivals only shows the result.

  Trust: peer-checked (every PC replays every run) - good against a typo or a broken client, NOT
  proof against a modified addon. Said on screen.
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
LD.LIVE_EVERY = 4        -- s between live score broadcasts
LD.GRACE = 90            -- s after the time limit (1:00) before a missing result is out (logs travel slowly
LD.GRACE_LONG = 120      --   on the group channel: about 100 bytes/s); 2:00 races get GRACE_LONG
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

--- Can this member take part? "yes" (StackRivals 0.7.1+ answered), "old" (an older StackRivals
--- answered: it can't join a Loot Duel for 10), "you", or nil (no answer yet).
function LD.addonStatus(name)
  if same(name, me()) then return "you" end
  local p = ns.Duel and ns.Duel.presence(name)
  if not p then return nil end
  if p.addon and P().versionAtLeast and not P().versionAtLeast(p.addon, LD.MIN_VERSION) then return "old" end
  return "yes"
end
LD.MIN_VERSION = "0.7.1"

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
      elseif d.state == "playing" and t - (lv and lv.at or d.startAt or t) > 3 * LD.LIVE_EVERY + 4 then row.status = "no_signal"
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
  many = "At most 10 players.",
  many_heats = "At most 10 play in one Loot Duel. More want it? Agree who plays first (for example /roll), or run a second Loot Duel.",
  all_many = "More than 10 online: pick up to 10 with the boxes, then Invite Selected.",
  busy = "A Loot Duel is already running.",
  duel = "Finish your duel first.",
  expired = "This invite has expired: start a new Loot Duel.",
  combat = "Not in combat.",
  unavailable = "Addon messages are not available here.",
}

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
    list[#list + 1] = { name = p.name, status = r.status or "missing", score = r.score or 0, lines = r.lines or 0, class = r.class }
  end
  table.sort(list, function(a, b)
    local va, vb = a.status == "verified", b.status == "verified"
    if va ~= vb then return va end
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
  ns.Comm.unqueue(function(q) return q.key and (q.key:find("^LDF:" .. d.lid) or q.key:find("^LDI:" .. d.lid) or q.key:find("^LDA:" .. d.lid)) ~= nil end)
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
  if not (ns.Comm and ns.Comm.enabled) then return false, "unavailable" end
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
  for _, n in ipairs(d.inviteOrder) do hx[#hx + 1] = P().hexName(n) end
  for k, c in ipairs(chunked(hx)) do bcast(P().encode("LDI", d.lid, k, table.concat(c, ",")), { key = "LDI:" .. d.lid .. ":" .. k, front = opts and opts.front }) end
end

--- Offer + invitee list.
function LD.sendOffer(d)
  d.offerAt = now()
  bcast(P().encode("LDF", d.lid, d.rs, d.engine, d.itemId, d.commit, #d.inviteOrder), { key = "LDF:" .. d.lid })
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
  local list = LD.accepted(d)
  if #list < 2 then return false, "few" end
  d.participants = sorted(list)
  d.listHash = LD.listHash(d.lid, d.rs, d.itemId, d.participants)
  dropRepeats(d)
  LD.sendList(d)
  LD.enterReveal(d)
  return true
end

--- The fixed list in ONE message: <place>-<commit> for every player (10 fit in 255 bytes).
function LD.sendList(d)
  d.listSends, d.listAt = (d.listSends or 0) + 1, now()
  local items = {}
  for _, e in ipairs(d.participants) do items[#items + 1] = placeOf(d, e.name) .. "-" .. e.commit end
  bcast(P().encode("LDQ", d.lid, d.listHash, #d.participants, table.concat(items, ",")), { key = "LDQ:" .. d.lid, front = true })
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
  LD.sendGo(d)
  LD.begin(d)
end

--- Go in ONE message: the leader's own nonce, the reveal hash and every player's nonce by place.
function LD.sendGo(d)
  d.goSends, d.goAt = (d.goSends or 0) + 1, now()
  local items = {}
  for _, e in ipairs(d.revealed) do items[#items + 1] = placeOf(d, e.name) .. "-" .. e.nonce end
  bcast(P().encode("LDW", d.lid, d.nonceL, d.revealHashV, table.concat(items, ",")), { key = "LDW:" .. d.lid, front = true })
end

--- Everyone: the race begins (seed from all nonces). Players start their run; others watch.
function LD.begin(d)
  d.seed = LD.seedFor(d.lid, d.nonceL, d.revealed)
  d.state = "playing"
  d.startAt = now()
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
    chunks = chunks, sends = 0,
  }
  LD.sendFinal(d)
  -- my own result counts like anyone's: replayed from my own log
  LD.storeResult(d, me(), { ticks = st.tick, score = st.score, lines = st.lines, level = st.level, hash = ns.Engine.hashState(st), chunks = #chunks })
  local r = d.results[key(me())]
  for i, c in ipairs(chunks) do r.parts[i] = c end
  LD.verify(d, me())
  if LD.allIn(d) then LD.finish(d) end -- I may be the last one
  emit("changed", d)
end

function LD.sendFinal(d)
  local f = d.myFinal
  if not f then return end
  f.sends, f.at = f.sends + 1, now()
  bcast(f.msg, { key = "LDE:" .. d.lid })
  for i, c in ipairs(f.chunks) do bcast(P().encode("LDL", d.lid, i, #f.chunks, c), { key = "LDL:" .. d.lid .. ":" .. i }) end
end

function LD.storeResult(d, name, m)
  local k = key(name)
  local r = d.results[k]
  if r and r.status and r.status ~= "pending" then return end -- first complete result stands
  r = r or { parts = {} }
  r.name, r.ticks, r.score, r.lines, r.level, r.hash, r.chunks = name, m.ticks, m.score, m.lines, m.level, m.hash, m.chunks
  r.status = "pending"
  d.results[k] = r
end

--- Replay a player's log on the shared seed with the same checks as duels and the web
--- (Engine/Verify.lua: time cap, input rate, inputs after top-out, claimed score / lines / hash).
function LD.verify(d, name)
  local r = d.results[key(name)]
  if not d.seed or not r or r.status ~= "pending" or not r.chunks then return end
  for i = 1, r.chunks do if not r.parts[i] then return end end
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
end

function LD.allIn(d)
  if not d.participants or d.state ~= "playing" then return false end
  for _, p in ipairs(d.participants) do
    local r = d.results[key(p.name)]
    if not r or r.status == nil or r.status == "pending" then return false end -- log chunks alone aren't a result
  end
  return true
end

function LD.finish(d)
  if d.state == "done" then return end
  d.state = "done"
  d.doneAt = now()
  for _, p in ipairs(d.participants) do
    local r = d.results[key(p.name)]
    if r and r.status == "pending" then r.status, r.why = "missing", "log_incomplete"
    elseif r and r.status == nil then r.status, r.why = "missing", "no_result" end
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
function H.LDF(m, sender)
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
  d.inviteChunks[m.k] = m.names
  local order = {}
  for k = 1, 9 do for _, n in ipairs(d.inviteChunks[k] or {}) do if #order < P().LOOT_MAX then order[#order + 1] = n end end end
  d.inviteOrder = order
  -- a start list that arrived before the whole invite list can be checked now
  if d.listMsg and d.count and #order >= d.count then LD.tryList(d) end
  if d.role == "member" and isInvitee(d, me()) and not d.prompted then
    d.prompted = true
    if d.engine ~= ns.Engine.ENGINE_VERSION then LD.answer(false); d.versionMismatch = true
    else emit("invite", d) end
  end
  emit("changed", d)
end
function H.LDA(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and d.state == "inviting" and isInvitee(d, sender)) then return end
  d.answers[key(sender)] = { accept = m.accept, commit = m.commit, name = sender }
  emit("changed", d)
end
function H.LDQ(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and fromLeader(d, sender)) or d.role == "leader" then return end
  d.listMsg = m
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

function H.LDN(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and d.state == "revealing") then return end
  local p = isPart(d, sender)
  if not p or P().commit16(d.lid, m.nonce) ~= p.commit then return end -- not theirs to reveal
  d.reveals[key(p.name)] = m.nonce
  LD.tryGo(d)
end
function H.LDW(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and fromLeader(d, sender)) or d.role == "leader" then return end
  d.goMsg = m
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
function LD.update(t)
  local d = LD.current
  if not d then return end
  if d.cancelMsg and d.cancelSends < 3 and t - d.cancelAt >= 3 then
    d.cancelSends, d.cancelAt = d.cancelSends + 1, t
    bcast(d.cancelMsg, { key = "LDX:" .. d.lid })
  end
  if d.state == "inviting" then
    -- repeat the offer only while someone hasn't answered (a 10-player invite is 5 messages)
    if d.role == "leader" and t - (d.offerAt or 0) >= LD.REPEAT and t - d.createdAt < LD.INVITE_TIME and unanswered(d) then LD.sendOffer(d) end
    if d.myAnswer and (d.answerSends or 0) < 3 and t - (d.answerAt or 0) >= LD.REPEAT then
      d.answerSends, d.answerAt = d.answerSends + 1, t
      bcast(P().encode("LDA", d.lid, d.myAnswer, d.myAnswer == "a" and d.myCommit or "-"), { key = "LDA:" .. d.lid, low = true })
    end
    if t - d.createdAt > LD.START_WAIT and d.role ~= "leader" then d.state, d.endReason = "cancelled", "not_started"; emit("changed", d) end
  elseif d.state == "revealing" then
    -- repeats only help someone who missed a message; each costs the sender's message budget
    if d.role == "leader" and (d.listSends or 0) < 3 and t - (d.listAt or 0) >= 5 then
      -- someone's share is missing: maybe they lost part of the invite list (the start refers to
      -- it by place) - send it again, then the list (front of the queue: the list goes first)
      LD.sendInvitees(d, { front = true })
      LD.sendList(d)
    end
    if d.role ~= "leader" and d.myNonce and isPart(d, me()) and (d.nSends or 0) < 4 and t - (d.nAt or 0) >= 5 then LD.sendReveal(d) end
    if t - d.revealAt > LD.REVEAL_TIME then
      if d.role == "leader" then LD.cancel("noreveal")
      elseif t - d.revealAt > LD.REVEAL_TIME + 15 then d.state, d.endReason = "cancelled", "not_started"; emit("changed", d) end
    end
  elseif d.state == "playing" then
    if d.role == "leader" and (d.goSends or 0) < 3 and t - (d.goAt or 0) >= 5 then LD.sendGo(d) end
    local s = ns.App and ns.App.session
    if d.iPlay and s and s.loot == d and not s.recorded then
      if s.phase == "playing" and t - (d.liveAt or 0) >= LD.LIVE_EVERY then
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
    if t > d.deadline then LD.finish(d) end
  end
  if (d.state == "playing" or d.state == "done") and d.myFinal and d.myFinal.sends < 3 and t - d.myFinal.at >= 5 then LD.sendFinal(d) end
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
