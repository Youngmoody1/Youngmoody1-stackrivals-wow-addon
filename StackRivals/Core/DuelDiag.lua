--[[
  StackRivals - duel diagnostics (for real two-client tests).

  For each of the last 5 duels, StackRivalsDB.duelDiag keeps:
    * a header: match id, rival, role, ruleset, addon/engine version, client build, result
    * counters: messages sent / received per kind, send result codes, drops, retries,
      longest silence from the rival, largest send queue
    * an event log (max 400 short lines, time = seconds since the match was created):
        12.4 >INV            sent and accepted by the client (accepted is NOT delivered)
        12.4 >SC r3          send returned code 3 (throttled) -> retried by Comm
        13.0 !END offline    given up: rival offline (or "gave_up", "queue_full", "low_priority")
        13.1 <ACC            received
        14.0 <SC 1200/5400   rival's game: tick 1200 (= 20 s of play), score 5400 (every 10th SC)
        15.0 ~lobby          our match state changed
        95.2 =win checked 61200-58800
  Score heartbeats, pings and log chunks are only counted, so a 2:00 duel is about 40 lines.
  Nothing else is stored: no chat, no account data, only the two character names in the duel.
  /sr duel debug prints the live view; the SavedVariables file holds the rest after /reload.
]]
local _, ns = ...
local P = ns.Protocol

local D = { MAX_MATCHES = 5, MAX_LINES = 400 }
ns.DuelDiag = D

local QUIET = { SC = true, PNG = true, LOG = true, RQ = true } -- counted, not logged (when OK)

local function now() return GetTime() end

local function store()
  local db = ns.db
  if not db then return nil end
  db.duelDiag = db.duelDiag or {}
  return db.duelDiag
end

local function find(mid)
  local list = store()
  if not list or not mid then return nil end
  for _, r in ipairs(list) do if r.mid == mid then return r end end
end

local function line(r, m, text)
  if #r.lines >= D.MAX_LINES then table.remove(r.lines, 1); r.cut = (r.cut or 0) + 1 end
  local t = m and m.createdAt and (now() - m.createdAt) or 0
  r.lines[#r.lines + 1] = string.format("%.1f %s", t, text):sub(1, 80)
end

local function bump(tbl, k) tbl[k] = (tbl[k] or 0) + 1 end

--- A new match (called by Duel when it creates one).
function D.begin(m)
  local list = store()
  if not list or find(m.mid) then return end
  local build, _, _, iface = "", nil, nil, 0
  if GetBuildInfo then build, _, _, iface = GetBuildInfo() end
  table.insert(list, 1, {
    mid = m.mid, rival = m.rival, role = m.role, rs = m.rulesetId,
    d = ns.App and ns.App.Today and ns.App:Today() or "", addon = ns.VERSION or "?",
    engine = ns.Engine and ns.Engine.ENGINE_VERSION or 0, build = tostring(build or ""), iface = tonumber(iface) or 0,
    sent = {}, recv = {}, codes = {}, drops = 0, maxGap = 0, maxQueue = 0, lines = {},
  })
  while #list > D.MAX_MATCHES do table.remove(list) end
end

local function matchOf(mid)
  local Duel = ns.Duel
  if Duel.current and Duel.current.mid == mid then return Duel.current end
  if Duel.past and Duel.past.mid == mid then return Duel.past end
end

--- Comm trace hook: every send attempt, receive, reject and drop.
function D.trace(event, text, who, info)
  local kind, mid = tostring(text):match("^%d+:(%u+):([0-9a-z]+)")
  local m = mid and matchOf(mid)
  if not m and ns.Duel.current then m = ns.Duel.current end
  local r = m and find(m.mid)
  if not r then return end
  if m.mid ~= mid and event ~= "reject" then return end -- other players' messages (hello, spam)
  if event == "send" then
    bump(r.codes, tostring(info))
    if info == 0 then bump(r.sent, kind) end
    local q = ns.Comm.queue and #ns.Comm.queue or 0
    if q > r.maxQueue then r.maxQueue = q end
    if info ~= 0 then line(r, m, ">" .. kind .. " r" .. tostring(info))
    elseif not QUIET[kind] then line(r, m, ">" .. kind) end
  elseif event == "recv" then
    bump(r.recv, kind)
    local t = now()
    if r.lastRecvAt then
      local gap = t - r.lastRecvAt
      if gap > r.maxGap then r.maxGap = math.floor(gap * 10) / 10 end
    end
    r.lastRecvAt = t
    if kind == "SC" then
      if (r.recv.SC or 0) % 10 == 1 then
        local f = {}
        for x in text:gmatch("[^:]+") do f[#f + 1] = x end
        line(r, m, string.format("<SC %s/%s", tostring(P.unb36(f[4] or "")), tostring(P.unb36(f[5] or ""))))
      end
    elseif not QUIET[kind] then
      line(r, m, "<" .. kind .. ((kind == "DEC" or kind == "BYE") and (" " .. (text:match(":([%a_]+)$") or "")) or ""))
    end
  elseif event == "drop" then
    r.drops = r.drops + 1
    line(r, m, "!" .. tostring(kind) .. " " .. tostring(info))
  elseif event == "reject" then
    line(r, m, "!reject " .. tostring(info))
  end
end

--- Called every frame by Duel.update: logs state changes and the result once.
function D.poll(m)
  if not m or m.diagState == m.state then return end
  m.diagState = m.state
  local r = find(m.mid)
  if not r then return end
  if m.state == "done" then
    r.result = m.outcome
    r.how = m.endReason
    line(r, m, string.format("=%s %s %d-%d", tostring(m.outcome), tostring(m.endReason), m.myScore or 0, m.theirScore or 0))
  elseif m.state == "cancelled" then
    r.result = "cancelled"
    r.how = m.endReason
    line(r, m, "=cancelled " .. tostring(m.endReason))
  else
    line(r, m, "~" .. m.state)
  end
end

--- Live status for /sr duel debug (one string per chat line).
function D.status()
  local out = {}
  local C, Duel = ns.Comm, ns.Duel
  local function add(s) out[#out + 1] = s end
  add(string.format("transport: %s%s, prefix result %s, queue %d (max %d), sent %d, received %d, dropped %d, rejected %d",
    C.enabled and "on" or "off", C.trial and " (Trial/Veteran: can't send)" or "", tostring(C.registerResult),
    #C.queue, C.stats.maxQueue, C.stats.sent, C.stats.received, C.stats.dropped, C.stats.rejected))
  local codes = {}
  for k, v in pairs(C.stats.codes) do codes[#codes + 1] = k .. "=" .. v end
  table.sort(codes)
  add("send result codes: " .. (#codes > 0 and table.concat(codes, " ") or "none yet") .. "  (0 ok, 3/8 throttle, 11 lockdown, 12 offline)")
  local m = Duel.current or Duel.past
  if not m then add("no duel."); return out end
  local t = now()
  add(string.format("duel %s vs %s (%s, %s): %s%s", m.mid, Duel.short(m.rival) or "?", m.role, m.rulesetId, m.state,
    m.endReason and (" / " .. m.endReason) or ""))
  add(string.format("last heard %.1f s ago%s%s", t - (m.lastHeard or t), m.rivalGone and ", marked gone" or "",
    m.rivalOffline and ", offline" or ""))
  local r = m.rival_ or {}
  local s = ns.App.session
  add(string.format("rival: tick %s score %s%s | me: tick %s score %s", tostring(r.tick or "-"), tostring(r.score or "-"),
    r.over and " (done)" or "", s and s.duel == m and s.state.tick or "-", s and s.duel == m and s.state.score or "-"))
  if m.rivalEnd then
    local have = 0
    for i = 1, m.rivalEnd.chunks do if m.chunks[i] then have = have + 1 end end
    add(string.format("rival log: %d/%d chunks%s", have, m.rivalEnd.chunks, m.check and (", check " .. (m.check.ok and "OK" or table.concat(m.check.reasons or {}, ","))) or ""))
  end
  if m.outChunks then add(string.format("my log: %d chunks, streamed %d%s", #m.outChunks, (m.outNext or 1) - 1, m.rivalHasMine and ", rival confirmed (FIN)" or "")) end
  return out
end

return D
