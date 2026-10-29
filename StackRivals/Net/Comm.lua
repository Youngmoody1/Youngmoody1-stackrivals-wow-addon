--[[
  StackRivals - addon-message transport.

  * Registers our prefix and listens to CHAT_MSG_ADDON.
  * Every outgoing message goes through a queue with our own conservative token buckets, below
    Blizzard's documented per-prefix limit (10 messages, +1 per second):
      - broadcasts (GUILD/PARTY/RAID): burst 4, 1 every 2 s
      - whispers:                       burst 8, 2 per second
    The server limits can change at any time, so result codes are also honoured: throttle or
    lockdown -> retry later with back-off; offline / not in group / not in guild -> give up and
    tell the duel logic.
  * Never sends anything in a protected way, never touches chat frames, never needs combat-free.
  * Ignores our own echoes (guild/party messages come back to the sender).
  * A message can carry a key (e.g. "SC:<mid>"): a newer message with the same key replaces the
    queued one instead of piling up behind a throttle or lockdown.
  * Unsolicited replies (HI, "busy" declines) are low priority: they are dropped when the queue is
    already busy, so nobody can starve a running duel by spamming hellos or invites.
  * Whispering an offline player makes the server print "No player named ... is currently
    playing." Only for players we whispered in the last 30 s, that line is hidden and reported
    to the duel logic as "offline" (API names from memory; guarded, not client-verified).
]]
local _, ns = ...
local P = ns.Protocol

local Comm = { handlers = {}, queue = {}, enabled = false, stats = { sent = 0, received = 0, dropped = 0, rejected = 0, maxQueue = 0, codes = {} } }
ns.Comm = Comm

local BUCKETS = {
  broadcast = { cap = 4, rate = 0.5 },
  whisper = { cap = 8, rate = 2 },
}
-- Inside instances whispers count against Blizzard's per-prefix limit (10, +1/s): stay below it.
local INSTANCE_WHISPER_RATE = 0.8
local MAX_QUEUE = 64
local LOW_PRIORITY_MAX = 16      -- low-priority messages only while the queue is shorter than this
local MAX_TRIES = 6
local recentTargets = {}          -- lower-case name -> time we last whispered them

local function now() return GetTime and GetTime() or 0 end

--- "Name" or "Name-Realm" -> "Name-Realm" (realm without spaces, like the client reports it).
function Comm.fullName(name)
  if type(name) ~= "string" or name == "" then return nil end
  local base, realm0 = name:match("^([^%-]+)%-(.+)$")
  if base then
    -- the client reports realms without spaces or hyphens ("Azjol-Nerub" -> "AzjolNerub")
    local r = realm0:gsub("[%s%-]", "")
    if r == "" then return base end
    return base .. "-" .. r
  end
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName() or ""):gsub("%s", "")
  if realm == nil or realm == "" then return name end
  return name .. "-" .. realm
end

function Comm.me()
  local n = UnitName and UnitName("player")
  return Comm.fullName(n)
end

--- Same player? Compares full names, case-insensitive.
function Comm.same(a, b)
  a, b = Comm.fullName(a), Comm.fullName(b)
  return a ~= nil and b ~= nil and a:lower() == b:lower()
end

function Comm.init()
  if Comm.frame then return end
  local api = C_ChatInfo
  if not (api and api.SendAddonMessage and api.RegisterAddonMessagePrefix) then
    Comm.unavailable = true
    return
  end
  -- Registrations are lost on every /reload, so this runs on every PLAYER_LOGIN (which also fires
  -- after a reload). warcraft.wiki.gg: returns Enum.RegisterAddonMessagePrefixResult since 10.2.7 /
  -- Classic 4.4.0 (0 Success, 1 DuplicatePrefix, 2 InvalidPrefix, 3 MaxPrefixes); older clients a boolean.
  local res = Comm.result(pcall(api.RegisterAddonMessagePrefix, P.PREFIX))
  Comm.registerResult = res
  if res ~= 0 and res ~= 1 then Comm.unavailable = true; return end
  -- Trial and Veteran accounts can't send addon messages (Forever 1.60.1 / 12.1.7, warcraft.wiki.gg)
  local trial = (IsTrialAccount and IsTrialAccount()) or (IsVeteranTrialAccount and IsVeteranTrialAccount())
  if trial then Comm.trial = true end
  local f = CreateFrame("Frame")
  Comm.frame = f
  pcall(f.RegisterEvent, f, "CHAT_MSG_ADDON")
  f:SetScript("OnEvent", function(_, _, prefix, text, channel, sender) Comm.receive(prefix, text, channel, sender) end)
  f:SetScript("OnUpdate", function()
    Comm.flush()
    if Comm.tick then Comm.tick() end
  end)
  for _, b in pairs(BUCKETS) do b.tokens, b.at = b.cap, now() end
  Comm.enabled = true
  Comm.hookOffline()
end

-- The server may print a same-realm player without the realm; only then is the bare name ours.
local function sameRealm(lname)
  local me = Comm.me()
  local r1, r2 = lname:match("%-(.+)$"), me and me:lower():match("%-(.+)$")
  return r1 ~= nil and r1 == r2
end

--- Hide and report the server's "player not found" line for players we just whispered.
function Comm.hookOffline()
  local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
  local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S
  if type(add) ~= "function" or type(fmt) ~= "string" then return end
  pcall(add, "CHAT_MSG_SYSTEM", function(_, _, msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return false end
    local t = now()
    for lname, at in pairs(recentTargets) do
      if t - at > 30 then
        recentTargets[lname] = nil
      elseif msg:lower() == fmt:format(lname):lower() or (sameRealm(lname) and msg:lower() == fmt:format((lname:match("^[^%-]+"))):lower()) then
        local h = Comm.handlers["@offline"]
        if h then h(lname) end
        return true -- hide it
      end
    end
    return false
  end)
end

function Comm.on(kind, fn) Comm.handlers[kind] = fn end

function Comm.receive(prefix, text, channel, sender)
  if prefix ~= P.PREFIX then return end
  if Comm.same(sender, Comm.me()) then return end -- our own guild/party echo
  local m, why = P.decode(text)
  if not m then
    Comm.stats.rejected = Comm.stats.rejected + 1
    Comm.traceEvent("reject", text, sender, why)
    -- a newer (or older) protocol version: tell an inviter instead of leaving them waiting
    if why == "version" and Comm.handlers["@version"] then Comm.handlers["@version"](text, Comm.fullName(sender)) end
    return
  end
  Comm.stats.received = Comm.stats.received + 1
  Comm.traceEvent("recv", text, Comm.fullName(sender))
  local h = Comm.handlers[m.kind] or Comm.handlers["*"]
  if h then h(m, Comm.fullName(sender), channel) end
end

--- Queue a message. channel: "WHISPER" (target required), "GUILD", "PARTY", "RAID".
--- onFail(reason) is called if it can't be delivered (offline, not in guild, too many tries).
--- opts.key: replace a queued message with the same key (and target); opts.low: low priority.
function Comm.send(text, channel, target, onFail, opts)
  if not Comm.enabled then if onFail then onFail("unavailable") end return false end
  if opts and opts.key then
    for _, q in ipairs(Comm.queue) do
      if q.key == opts.key and q.target == target and q.channel == channel then
        q.text, q.onFail = text, onFail or q.onFail
        return true
      end
    end
  end
  if opts and opts.low and #Comm.queue >= LOW_PRIORITY_MAX then
    Comm.stats.dropped = Comm.stats.dropped + 1
    Comm.traceEvent("drop", text, target, "low_priority")
    return false
  end
  if #Comm.queue >= MAX_QUEUE then
    Comm.stats.dropped = Comm.stats.dropped + 1
    Comm.traceEvent("drop", text, target, "queue_full")
    if onFail then onFail("queue_full") end
    return false
  end
  Comm.queue[#Comm.queue + 1] = { text = text, channel = channel, target = target, onFail = onFail, tries = 0, notBefore = 0, key = opts and opts.key }
  if #Comm.queue > Comm.stats.maxQueue then Comm.stats.maxQueue = #Comm.queue end
  Comm.flush()
  return true
end

local function refill(b, t)
  b.tokens = math.min(b.cap, b.tokens + (t - b.at) * b.rate)
  b.at = t
end

--- Result code of a pcall'd send/register call. warcraft.wiki.gg: the code is the LAST return value
--- (a deprecation wrapper put a boolean first on some clients); before 10.2.7 / Classic 4.4.0 it was a
--- boolean. Number -> that code; false -> 9 (general error, retry); true / nothing -> 0 (success).
function Comm.result(okCall, ...)
  if not okCall then return 9 end
  local n = select("#", ...)
  for i = n, 1, -1 do
    local v = select(i, ...)
    if type(v) == "number" then return v end
  end
  for i = n, 1, -1 do
    if select(i, ...) == false then return 9 end
  end
  return 0
end

--- Diagnostics hook: Comm.trace(event, text, who, info) if set (see Core/DuelDiag.lua).
function Comm.traceEvent(event, text, who, info)
  local f = Comm.trace
  if f then pcall(f, event, text, who, info) end
end

-- Enum.SendAddonMessageResult (warcraft.wiki.gg): 0 Success, 1 InvalidPrefix, 2 InvalidMessage,
-- 3 AddonMessageThrottle, 4 InvalidChatType, 5 NotInGroup, 6 TargetRequired, 7 InvalidChannel,
-- 8 ChannelThrottle, 9 GeneralError, 10 NotInGuild (11.1.0), 11 AddOnMessageLockdown (12.0.0),
-- 12 TargetOffline (12.0.0). Success only means "accepted into the queue", never "delivered":
-- the duel logic re-sends and acknowledges (FIN) itself.
local RESULT_RETRY = { [3] = true, [8] = true, [9] = true, [11] = true }  -- throttles, general error, lockdown
local RESULT_FAIL = { [1] = "invalid", [2] = "invalid", [4] = "invalid", [5] = "not_in_group", [6] = "invalid", [7] = "invalid", [10] = "not_in_guild", [12] = "offline" }

function Comm.flush()
  if #Comm.queue == 0 then return end
  local t = now()
  local i = 1
  while i <= #Comm.queue do
    local q = Comm.queue[i]
    local bucket = (q.channel == "WHISPER") and BUCKETS.whisper or BUCKETS.broadcast
    if bucket == BUCKETS.whisper then
      local inInstance = IsInInstance and select(1, IsInInstance())
      bucket.rate = inInstance and INSTANCE_WHISPER_RATE or 2
    end
    refill(bucket, t)
    if q.notBefore > t or bucket.tokens < 1 then
      i = i + 1
    else
      bucket.tokens = bucket.tokens - 1
      q.tries = q.tries + 1
      local code = Comm.result(pcall(C_ChatInfo.SendAddonMessage, P.PREFIX, q.text, q.channel, q.target))
      Comm.stats.codes[code] = (Comm.stats.codes[code] or 0) + 1
      Comm.traceEvent("send", q.text, q.target, code)
      if code == 0 then
        table.remove(Comm.queue, i)
        Comm.stats.sent = Comm.stats.sent + 1
        if q.channel == "WHISPER" and q.target then recentTargets[q.target:lower()] = t end
      elseif RESULT_FAIL[code] or q.tries >= MAX_TRIES then
        table.remove(Comm.queue, i)
        Comm.stats.dropped = Comm.stats.dropped + 1
        Comm.traceEvent("drop", q.text, q.target, RESULT_FAIL[code] or "gave_up")
        if q.onFail then q.onFail(RESULT_FAIL[code] or "gave_up") end
      else
        q.notBefore = t + math.min(8, 0.5 * 2 ^ q.tries) -- back-off: 1, 2, 4, 8 s
        i = i + 1
      end
    end
  end
end

--- Drop queued messages for a match that no longer needs them (old invites, scores, pings).
--- Final messages (decline, bye, end, log chunks) are kept so the rival still learns the outcome.
local KEEP = { DEC = true, BYE = true, END = true, LOG = true, FIN = true }
function Comm.purge(mid)
  for i = #Comm.queue, 1, -1 do
    local text = Comm.queue[i].text
    local kind, qmid = text:match("^%d+:(%u+):([^:]+)")
    if qmid == mid and not KEEP[kind] then table.remove(Comm.queue, i) end
  end
end

return Comm
