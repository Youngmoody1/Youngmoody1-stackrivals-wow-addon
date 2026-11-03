--[[
  StackRivals - Quickplay: press one button, meet a random StackRivals player.

  Who can be found (honestly): only players this addon can actually reach AND who are searching
  too, right now, for the same mode. WoW Classic gives addons no global channel to find strangers,
  and an addon can't reach stackrivals.io, so the pool is:
    * your guild and your party / raid (one broadcast each, every AD_EVERY seconds while searching);
    * friends, Battle.net friends on your realm and recent rivals whose StackRivals answered (whisper).
  Matching: when two searchers hear each other (QS), the one with the lower "name-realm" invites
  (INV with the Quickplay flag); the other accepts automatically because it was searching for
  exactly that. Then the normal duel takes over (lobby = ready check, countdown, match, result,
  rematch, every fairness rule). A searcher that hears several others takes the first one; several
  searchers in one guild pair off.

  Adapters: `native` (the above) and `web` (stackrivals.io matchmaking). `web` reports
  "not_connected" until a verified, allowed transport exists - it never pretends to search.
  Adapter interface: { id, label, status() -> "available"|"unavailable"|"not_connected", reason?,
  search(mode) -> ok, why, cancel() }. Events go to Quickplay.listeners (Quickplay.on).
]]
local _, ns = ...
ns = ns or {}

local QP = { state = "idle", candidates = {}, excluded = {}, listeners = {} }
ns.Quickplay = QP

QP.AD_EVERY = 20        -- s between "I'm searching" announcements
QP.SEARCH_MAX = 300     -- s before "no opponent found"
QP.CANDIDATE_TTL = 60   -- s a heard searcher stays a candidate
QP.EXCLUDE_FOR = 120    -- s a player who didn't accept is skipped
QP.REPLY_GAP = 10       -- s between whispered replies to the same searcher
QP.MODES = { b120 = true, s180 = true }

local function now() return GetTime and GetTime() or 0 end
local function P() return ns.Protocol end
local function emit(ev, ...) local fn = QP.listeners[ev]; if fn then fn(...) end end
function QP.on(ev, fn) QP.listeners[ev] = fn end

QP.adapters = {
  native = {
    id = "native", label = "WoW players you can reach",
    status = function()
      if not (ns.Comm and ns.Comm.enabled) then return "unavailable", "addon messages are not available in this client" end
      if ns.Comm.trial then return "unavailable", "Trial / Veteran accounts can't send addon messages" end
      return "available"
    end,
  },
  web = {
    id = "web", label = "StackRivals.io players",
    status = function() return "not_connected", "a WoW addon can't reach the website; no verified connection exists yet" end,
    search = function() return false, "not_connected" end,
    cancel = function() end,
  },
}

local function me() return ns.Comm and ns.Comm.me and ns.Comm.me() or "" end
local function ignored(name) return ns.Social and ns.Social.isIgnored(name) end

--- Start searching for `mode` (b120 Blitz 2:00 or s180 Spell Battle 3:00).
function QP.start(mode)
  mode = QP.MODES[mode] and mode or "b120"
  local st, why = QP.adapters.native.status()
  if st ~= "available" then return false, why end
  if ns.UI and ns.UI.inCombat and ns.UI.inCombat() then return false, "you are in combat" end
  if ns.Duel and ns.Duel.busy() then return false, "you are already in a duel" end
  QP.state, QP.mode = "searching", mode
  QP.qid = P().token(6, function(a, b) return math.random(a, b) end)
  QP.started, QP.lastAd, QP.note = now(), -99, nil
  QP.candidates, QP.rival, QP.replied = {}, nil, {}
  -- learn which friends have StackRivals (one hidden whisper each, at most once a minute)
  if ns.Social and ns.Duel then
    local names = {}
    for _, src in ipairs({ "friends", "bnet", "recent" }) do
      for _, e in ipairs(ns.Social.list(src)) do if e.reach and e.online ~= false then names[#names + 1] = e.name end end
    end
    ns.Duel.pingPresence(names)
  end
  emit("changed")
  return true
end

function QP.cancel(note)
  if QP.state == "idle" then return end
  QP.state, QP.note = "idle", note
  emit("changed")
end

local function sendQS(channel, target)
  ns.Comm.send(P().encode("QS", QP.qid, QP.mode, ns.VERSION or "dev"), channel, target, nil, { low = true })
end

--- Announce: guild + group broadcast, and a whisper to friends whose StackRivals answered (fresh).
local function advertise(t)
  QP.lastAd = t
  QP.reach = { guild = false, group = false, friends = 0 }
  if IsInGuild and IsInGuild() then sendQS("GUILD"); QP.reach.guild = true end
  if IsInRaid and IsInRaid() then sendQS("RAID"); QP.reach.group = true
  elseif IsInGroup and IsInGroup() then sendQS("PARTY"); QP.reach.group = true end
  if ns.Social and ns.Duel then
    local n = 0
    for _, src in ipairs({ "friends", "bnet", "recent" }) do
      for _, e in ipairs(ns.Social.list(src)) do
        local p = e.reach and ns.Duel.presence(e.name)
        if p and t - p.at < 300 and p.compatible and n < 20 and not ignored(e.name) then n = n + 1; sendQS("WHISPER", e.name) end
      end
    end
    QP.reach.friends = n
  end
end

--- A Quickplay invite from `sender`: accepted automatically only while I'm searching for exactly
--- that mode (my search is my consent) and the sender isn't ignored or skipped after a failed
--- match. Anything else gets no popup and no answer. (Their QS may arrive after their INV: the
--- whispered QS is low priority, so it doesn't have to have been heard first.)
function QP.wants(ruleset, sender)
  if QP.state ~= "searching" or ruleset ~= QP.mode or type(sender) ~= "string" then return false end
  if ignored(sender) then return false end
  local ex = QP.excluded[sender:lower()]
  return not (ex and now() < ex)
end

--- The duel for this Quickplay match exists (we invited, or accepted their invite).
function QP.onMatched(m)
  QP.state, QP.rival, QP.match = "matched", m.rival, m
  m.quickplay = true
  emit("changed")
end

local function onSearch(msg, sender)
  if ignored(sender) or sender:lower() == me():lower() then return end
  if QP.state ~= "searching" or msg.ruleset ~= QP.mode then return end
  local k = sender:lower()
  local ex = QP.excluded[k]
  if ex and now() < ex then return end
  QP.candidates[k] = { name = sender, at = now(), addon = msg.addon }
  -- tell them about me (a broadcast only reaches them one way)
  if not QP.replied[k] or now() - QP.replied[k] >= QP.REPLY_GAP then
    QP.replied[k] = now()
    sendQS("WHISPER", sender)
  end
  -- the lower name invites; the other waits for that invite
  if me():lower() < k and not (ns.Duel and ns.Duel.busy()) then
    local okC = ns.Duel.challenge(sender, QP.mode, { quickplay = true })
    if okC then QP.onMatched(ns.Duel.current) end
  end
  emit("changed")
end

--- Called every frame (from Duel.update).
function QP.update(t)
  if QP.state == "searching" then
    if t - QP.started > QP.SEARCH_MAX then
      QP.state, QP.note = "none", "no_opponent"
      emit("changed")
      return
    end
    if t - QP.lastAd >= QP.AD_EVERY then advertise(t); emit("changed") end
  elseif QP.state == "matched" then
    local m = ns.Duel and ns.Duel.current
    if not m or m ~= QP.match then QP.state = "idle"; emit("changed"); return end
    if m.state == "cancelled" then
      QP.excluded[(m.rival or ""):lower()] = t + QP.EXCLUDE_FOR
      QP.candidates[(m.rival or ""):lower()] = nil
      ns.Duel.clear()
      local lobbyFor = m.lobbyAt and (t - m.lobbyAt) or 0
      if not m.myReady and (m.endReason == "lobby_timeout" or lobbyFor >= ns.Duel.LOBBY_TIMEOUT - 1) then
        -- I didn't press Ready (away?): don't put me straight back into the search
        QP.state, QP.note, QP.match = "idle", "you_not_ready", nil
      elseif m.endReason == "you_cancelled" or m.endReason == "you_declined" then
        QP.state, QP.note, QP.match = "idle", "cancelled", nil
      else
        -- they didn't accept / didn't press Ready / left: skip them a while and keep searching
        QP.state, QP.note, QP.match = "searching", "fell_through", nil
        QP.lastAd = -99
      end
      emit("changed")
    elseif m.state == "playing" or m.state == "waiting" or m.state == "done" then
      QP.state = "idle" -- the duel has taken over (result, rematch)
      emit("changed")
    end
  end
end

function QP.init()
  if ns.Comm then ns.Comm.on("QS", onSearch) end
end

return QP
