--[[
  StackRivals - Loot Duel: a raid / party settles who gets an item with a short StackRivals race
  instead of /roll. Separate from Quickplay and duels; never ranked; never touches loot.

  Flow (docs/LOOT_DUEL.md):
    1. The raid leader, an assistant or the master looter opens Loot Duel, picks an item (link or
       item ID), a time (1:00 or 2:00) and 2-8 group members, and invites them (LDO + LDI).
    2. Each invitee accepts or declines in a popup (LDA, with a secret seed nonce when accepting).
       Nobody is entered automatically; no answer = not in.
    3. The leader starts with the players who accepted (at least 2): the final list goes out (LDP)
       and the start (LDS) reveals the leader's nonce. The seed comes from ALL accepted nonces, so
       nobody (the leader included) knows the pieces before the start. List and rules can't change.
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
LD.REPEAT = 10           -- s between repeats of the offer / answers while inviting
LD.LIVE_EVERY = 4        -- s between live score broadcasts
LD.GRACE = 60            -- s after the time limit before a missing result is out (pauses, slow PCs)
LD.KEEP_RESULTS = 10     -- finished loot duels kept for the results screen (this session)

local function P() return ns.Protocol end
local function now() return GetTime and GetTime() or 0 end
local function emit(ev, ...) local fn = LD.listeners[ev]; if fn then fn(...) end end
function LD.on(ev, fn) LD.listeners[ev] = fn end
local function me() return ns.Comm and ns.Comm.me() or nil end
local function same(a, b) return ns.Comm and ns.Comm.same(a, b) end
local function rnd(a, b) return math.random(a, b) end

--- PARTY / RAID or nil (not in a group).
function LD.channel()
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  return nil
end

local function bcast(text, opts)
  local ch = LD.channel()
  if not ch then return false end
  return ns.Comm.send(text, ch, nil, nil, opts)
end

--- The group: { name, class, leader, assist, ml } (you included). Every API optional.
function LD.roster()
  local out = {}
  local full = function(n, r) return ns.Social and ns.Social.full(n, r) or n end
  local mlName
  if GetLootMethod then
    local ok, method, partyIdx, raidIdx = pcall(GetLootMethod)
    if ok and method == "master" then
      if raidIdx and UnitName then mlName = full(UnitName("raid" .. raidIdx))
      elseif partyIdx == 0 then mlName = me()
      elseif partyIdx and UnitName then mlName = full(UnitName("party" .. partyIdx)) end
    end
  end
  if IsInRaid and IsInRaid() and GetRaidRosterInfo then
    for i = 1, math.min(GetNumGroupMembers and GetNumGroupMembers() or 0, 40) do
      local name, rank, _, _, _, classFile, _, online, _, _, isML = GetRaidRosterInfo(i)
      if name then
        out[#out + 1] = { name = full(name), class = classFile, leader = rank == 2, assist = rank == 1, ml = isML and true or false, online = online ~= false }
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
          out[#out + 1] = { name = name, class = cls, leader = UnitIsGroupLeader and UnitIsGroupLeader(u) or false, assist = false, online = true }
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
  many = "At most 8 players.",
  busy = "A Loot Duel is already running.",
  duel = "Finish your duel first.",
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

--- name, link, quality, icon for an item ID (nil name while the client hasn't loaded it yet).
function LD.itemInfo(id)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, link, quality, icon
  if get then
    local ok, n, l, q, _, _, _, _, _, _, tex = pcall(get, id)
    if ok then name, link, quality, icon = n, l, q, tex end
  end
  if not icon then
    local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if inst then local ok, _, _, _, _, tex = pcall(inst, id); if ok then icon = tex end end
  end
  return name, link, quality, icon
end

------------------------------------------------------------------------------------------------
-- Seed, list hash, standings (pure: the same on every PC)
------------------------------------------------------------------------------------------------
local function sorted(entries)
  local t = {}
  for _, e in ipairs(entries) do t[#t + 1] = e end
  table.sort(t, function(a, b) return a.name:lower() < b.name:lower() end)
  return t
end
function LD.listHash(lid, rs, itemId, entries)
  local parts = { lid, rs, tostring(itemId) }
  for _, e in ipairs(sorted(entries)) do parts[#parts + 1] = e.name:lower() .. "=" .. e.nonce end
  return string.format("%08x", ns.Prng.hashString(table.concat(parts, "|")))
end
function LD.seedFor(lid, nonceL, entries)
  local parts = { nonceL }
  for _, e in ipairs(sorted(entries)) do parts[#parts + 1] = e.name:lower() .. "=" .. e.nonce end
  return "srloot-" .. lid .. "-" .. string.format("%08x", ns.Prng.hashString(table.concat(parts, "|")))
end

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
  local d = { answers = {}, invitees = {}, inviteChunks = {}, partChunks = {}, results = {}, live = {}, logs = {} }
  for k, v in pairs(o) do d[k] = v end
  return d
end

local function isInvitee(d, name)
  for _, n in ipairs(d.inviteOrder or {}) do if same(n, name) then return true end end
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
    engine = ns.Engine.ENGINE_VERSION, nonceL = P().token(8, rnd), state = "inviting", createdAt = now(), inviteOrder = list,
  })
  d.commit = P().commit(d.lid, d.nonceL)
  LD.current = d
  LD.sendOffer(d)
  -- the leader can be a player too: their own answer counts like anyone else's
  if isInvitee(d, me()) then LD.answer(true) end
  emit("changed", d)
  return true
end

--- Offer + invitee list chunks (names hex; as many per message as fit).
function LD.sendOffer(d)
  d.offerAt = now()
  bcast(P().encode("LDO", d.lid, d.rs, d.engine, d.itemId, d.commit, #d.inviteOrder), { key = "LDO:" .. d.lid })
  local chunks, cur, curLen = {}, {}, 0
  for _, n in ipairs(d.inviteOrder) do
    local h = P().hexName(n)
    if #cur > 0 and curLen + #h + 1 > 200 then chunks[#chunks + 1] = cur; cur, curLen = {}, 0 end
    cur[#cur + 1] = h; curLen = curLen + #h + 1
  end
  if #cur > 0 then chunks[#chunks + 1] = cur end
  for k, c in ipairs(chunks) do bcast(P().encode("LDI", d.lid, k, table.concat(c, ",")), { key = "LDI:" .. d.lid .. ":" .. k }) end
end

--- Invitee (or a leader who invited themselves): accept / decline.
function LD.answer(accept)
  local d = LD.current
  if not d or d.state ~= "inviting" or not isInvitee(d, me()) then return false end
  if accept and ns.Duel and ns.Duel.busy() then accept = false end
  d.myAnswer = accept and "a" or "d"
  d.myNonce = accept and (d.myNonce or P().token(8, rnd)) or nil
  d.answers[me():lower()] = { accept = accept, nonce = d.myNonce, name = me() }
  d.answerAt, d.answerSends = now(), 1
  bcast(P().encode("LDA", d.lid, accept and "a" or "d", accept and d.myNonce or "-"), { key = "LDA:" .. d.lid })
  emit("changed", d)
  return true
end

--- Accepted players so far (name, nonce).
function LD.accepted(d)
  local t = {}
  for _, n in ipairs(d.inviteOrder or {}) do
    local a = d.answers[n:lower()]
    if a and a.accept and a.nonce then t[#t + 1] = { name = n, nonce = a.nonce } end
  end
  return t
end

--- Leader: start with everyone who accepted (at least 2).
function LD.start()
  local d = LD.current
  if not d or d.role ~= "leader" or d.state ~= "inviting" then return false, "busy" end
  local list = LD.accepted(d)
  if #list < 2 then return false, "few" end
  d.participants = sorted(list)
  d.listHash = LD.listHash(d.lid, d.rs, d.itemId, d.participants)
  LD.sendStart(d)
  LD.begin(d)
  return true
end

function LD.sendStart(d)
  d.startSends = (d.startSends or 0) + 1
  d.startSentAt = now()
  local chunks, cur, curLen = {}, {}, 0
  for _, e in ipairs(d.participants) do
    local item = P().hexName(e.name) .. "-" .. e.nonce
    if #cur > 0 and curLen + #item + 1 > 200 then chunks[#chunks + 1] = cur; cur, curLen = {}, 0 end
    cur[#cur + 1] = item; curLen = curLen + #item + 1
  end
  if #cur > 0 then chunks[#chunks + 1] = cur end
  for k, c in ipairs(chunks) do bcast(P().encode("LDP", d.lid, k, #chunks, table.concat(c, ",")), { key = "LDP:" .. d.lid .. ":" .. k }) end
  bcast(P().encode("LDS", d.lid, d.nonceL, d.listHash, #d.participants), { key = "LDS:" .. d.lid })
end

--- Everyone: the race begins (seed from all nonces). Players start their run; others watch.
function LD.begin(d)
  d.seed = LD.seedFor(d.lid, d.nonceL, d.participants)
  d.state = "playing"
  d.startAt = now()
  local rs = P().LOOT_RULESETS[d.rs]
  d.deadline = d.startAt + (rs.limitTicks + rs.countdownTicks) / 60 + LD.GRACE
  d.iPlay = false
  for _, e in ipairs(d.participants) do if same(e.name, me()) then d.iPlay = true end end
  if d.iPlay and ns.App and ns.App.StartLoot then ns.App:StartLoot(d) end
  emit("changed", d)
end

--- Leader: cancel before the start (or leave); everyone sees it.
function LD.cancel(reason)
  local d = LD.current
  if not d then return end
  if d.role == "leader" and (d.state == "inviting" or d.state == "playing") then
    bcast(P().encode("LDX", d.lid, reason == "left" and "left" or "cancel"))
  end
  if d.state == "inviting" or d.role == "leader" then d.state = "cancelled"; d.endReason = "cancelled" end
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
--- My run ended (App:OnRunOver): send my result and log (twice, a message can be lost).
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
  local r = d.results[me():lower()]
  for i, c in ipairs(chunks) do r.parts[i] = c end
  LD.verify(d, me())
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
  local k = name:lower()
  local r = d.results[k]
  if r and r.status and r.status ~= "pending" then return end -- first complete result stands
  r = r or { parts = {} }
  r.name, r.ticks, r.score, r.lines, r.level, r.hash, r.chunks = name, m.ticks, m.score, m.lines, m.level, m.hash, m.chunks
  r.status = "pending"
  d.results[k] = r
end

--- Replay a player's log on the shared seed; verified only if everything matches.
function LD.verify(d, name)
  local r = d.results[name:lower()]
  if not r or r.status ~= "pending" or not r.chunks then return end
  for i = 1, r.chunks do if not r.parts[i] then return end end
  local packed = table.concat(r.parts, "", 1, r.chunks)
  local log = P().unpackLog(packed)
  local rs = P().LOOT_RULESETS[d.rs]
  local why
  if not log then why = "log" end
  if not why and r.ticks > rs.limitTicks then why = "over_time" end
  if not why then for i = 1, #log, 2 do if log[i] > r.ticks or log[i + 1] > 6 then why = "log"; break end end end
  if not why then
    local okR, st = pcall(ns.Engine.replay, d.seed, { startLevel = 1 }, log, r.ticks)
    if not okR then why = "log"
    elseif st.score ~= r.score or st.lines ~= r.lines or st.level ~= r.level or ns.Engine.hashState(st) ~= r.hash then why = "mismatch" end
  end
  r.status = why and "rejected" or "verified"
  r.why = why
  r.class = rosterEntry(name) and rosterEntry(name).class or r.class
end

local function allIn(d)
  for _, p in ipairs(d.participants or {}) do
    local r = d.results[p.name:lower()]
    if not r or r.status == nil or r.status == "pending" then return false end -- log chunks alone aren't a result
  end
  return true
end

function LD.finish(d)
  if d.state == "done" then return end
  d.state = "done"
  d.doneAt = now()
  for _, p in ipairs(d.participants) do
    local r = d.results[p.name:lower()]
    if r and r.status == "pending" then r.status, r.why = "missing", "log_incomplete"
    elseif r and r.status == nil then r.status, r.why = "missing", "no_result" end
  end
  d.standings, d.winner, d.tied = LD.standings(d.participants, d.results)
  if d.role == "leader" then
    bcast(P().encode("LDR", d.lid, d.winner and P().hexName(d.winner) or "-", #d.tied > 1 and 1 or 0))
  end
  table.insert(LD.history, 1, d)
  while #LD.history > LD.KEEP_RESULTS do table.remove(LD.history) end
  emit("result", d)
  emit("changed", d)
end

------------------------------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------------------------------
local function fromLeader(d, sender) return d and same(d.leader, sender) end

local H = {}
function H.LDO(m, sender)
  -- only the group's leader / assistant / master looter may offer; nothing from outside the group
  if not LD.mayLead(sender) then return end
  local d = LD.current
  if d and d.lid == m.lid then return end -- a repeat
  if d and d.state ~= "done" and d.state ~= "cancelled" and not (d.role ~= "leader" and d.state == "inviting" and d.myAnswer == "d") then return end
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
  d.answers[sender:lower()] = { accept = m.accept, nonce = m.nonce, name = sender }
  emit("changed", d)
end
function H.LDP(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and fromLeader(d, sender)) or d.role == "leader" then return end
  d.partChunks[m.k] = m.entries
  d.partTotal = m.total
  LD.tryStart(d)
end
function H.LDS(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and fromLeader(d, sender)) or d.role == "leader" then return end
  d.startMsg = m
  LD.tryStart(d)
end

--- Member: start once the whole list and the start are here, and everything checks out.
function LD.tryStart(d)
  if d.state ~= "inviting" or not d.startMsg or not d.partTotal then return end
  local entries = {}
  for k = 1, d.partTotal do
    if not d.partChunks[k] then return end
    for _, e in ipairs(d.partChunks[k]) do entries[#entries + 1] = e end
  end
  local m = d.startMsg
  local bad
  if #entries ~= m.count then bad = "list" end
  if not bad and P().commit(d.lid, m.nonce) ~= d.commit then bad = "commit" end -- the leader's nonce was fixed at the offer
  if not bad and LD.listHash(d.lid, d.rs, d.itemId, entries) ~= m.listHash then bad = "list" end
  if not bad then
    for _, e in ipairs(entries) do
      if not isInvitee(d, e.name) then bad = "not_invited" end
      if same(e.name, me()) and e.nonce ~= d.myNonce then bad = "my_nonce" end
    end
  end
  if bad then d.state, d.endReason = "cancelled", "bad_start_" .. bad; emit("changed", d); return end
  d.nonceL = m.nonce
  d.listHash = m.listHash
  d.participants = sorted(entries)
  LD.begin(d)
end

function H.LDC(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and d.state == "playing") then return end
  for _, p in ipairs(d.participants) do
    if same(p.name, sender) then d.live[sender:lower()] = { tick = m.tick, score = m.score }; emit("live", d) end
  end
end
local function isPart(d, name)
  for _, p in ipairs(d.participants or {}) do if same(p.name, name) then return p end end
end
function H.LDE(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and (d.state == "playing") and isPart(d, sender)) then return end
  LD.storeResult(d, isPart(d, sender).name, m)
  LD.verify(d, isPart(d, sender).name)
  if allIn(d) then LD.finish(d) end
  emit("changed", d)
end
function H.LDL(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and d.state == "playing") then return end
  local p = isPart(d, sender)
  if not p then return end
  local k = p.name:lower()
  d.results[k] = d.results[k] or { parts = {}, name = p.name }
  local r = d.results[k]
  if r.status and r.status ~= "pending" then return end
  r.parts[m.i] = r.parts[m.i] or m.payload
  LD.verify(d, p.name)
  if allIn(d) then LD.finish(d) end
end
function H.LDX(m, sender)
  local d = LD.current
  if not (d and d.lid == m.lid and fromLeader(d, sender)) then return end
  if d.state == "inviting" then d.state, d.endReason = "cancelled", "leader_cancelled"
  elseif d.state == "playing" then d.leaderLeft = true end -- the race goes on: results are computed on every PC
  emit("changed", d)
end
function H.LDR(m, sender)
  for _, d in ipairs(LD.history) do
    if d.lid == m.lid and fromLeader(d, sender) then
      d.leaderWinner, d.leaderTie = m.winner, m.tie
      d.agreement = ((m.winner == nil) == (d.winner == nil)) and (m.winner == nil or same(m.winner, d.winner)) and "agreed" or "disputed"
      emit("changed", d)
    end
  end
end

--- Every frame (Duel.update): repeats, live score, invite timeout, deadline.
function LD.update(t)
  local d = LD.current
  if not d then return end
  if d.state == "inviting" then
    if d.role == "leader" and t - (d.offerAt or 0) >= LD.REPEAT and t - d.createdAt < LD.INVITE_TIME then LD.sendOffer(d) end
    if d.myAnswer and (d.answerSends or 0) < 3 and t - (d.answerAt or 0) >= LD.REPEAT then
      d.answerSends, d.answerAt = d.answerSends + 1, t
      bcast(P().encode("LDA", d.lid, d.myAnswer, d.myAnswer == "a" and d.myNonce or "-"), { key = "LDA:" .. d.lid })
    end
    if t - d.createdAt > LD.INVITE_TIME + 30 and d.role ~= "leader" then d.state, d.endReason = "cancelled", "not_started"; emit("changed", d) end
  elseif d.state == "playing" then
    if d.role == "leader" and (d.startSends or 0) < 3 and t - (d.startSentAt or 0) >= 4 then LD.sendStart(d) end
    local s = ns.App and ns.App.session
    if d.iPlay and s and s.loot == d and s.phase == "playing" and t - (d.liveAt or 0) >= LD.LIVE_EVERY then
      d.liveAt = t
      d.live[me():lower()] = { tick = s.state.tick, score = s.state.score }
      bcast(P().encode("LDC", d.lid, P().b36(s.state.tick), P().b36(s.state.score)), { key = "LDC:" .. d.lid, low = true })
      emit("live", d)
    end
    if d.myFinal and d.myFinal.sends < 2 and t - d.myFinal.at >= 5 then LD.sendFinal(d) end
    if t > d.deadline then LD.finish(d) end
  end
end

function LD.init()
  if not ns.Comm then return end
  for kind, fn in pairs(H) do ns.Comm.on(kind, fn) end
end

return LD
