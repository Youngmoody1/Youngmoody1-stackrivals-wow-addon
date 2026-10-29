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

local Comm = { handlers = {}, queue = {}, enabled = false, stats = { sent = 0, received = 0, dropped = 0, rejected = 0 } }
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
  local okReg, res = pcall(api.RegisterAddonMessagePrefix, P.PREFIX)
  -- older clients return true/false, 12.x an Enum.RegisterAddonMessagePrefixResult
  -- (0 success, 1 duplicate = already ours, 2 invalid, 3 too many prefixes)
  if not okReg or res == false or res == 2 or res == 3 then Comm.unavailable = true; return end
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
      elseif msg:lower() == fmt:format(lname):lower() or msg:lower() == fmt:format((lname:match("^[^%-]+"))):lower() then
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
  if not m then Comm.stats.rejected = Comm.stats.rejected + 1; return end
  Comm.stats.received = Comm.stats.received + 1
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
    return false
  end
  if #Comm.queue >= MAX_QUEUE then
    Comm.stats.dropped = Comm.stats.dropped + 1
    if onFail then onFail("queue_full") end
    return false
  end
  Comm.queue[#Comm.queue + 1] = { text = text, channel = channel, target = target, onFail = onFail, tries = 0, notBefore = 0, key = opts and opts.key }
  Comm.flush()
  return true
end

local function refill(b, t)
  b.tokens = math.min(b.cap, b.tokens + (t - b.at) * b.rate)
  b.at = t
end

-- Enum.SendAddonMessageResult (12.x). Older clients return true/false or nothing.
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
      local okCall, res = pcall(C_ChatInfo.SendAddonMessage, P.PREFIX, q.text, q.channel, q.target)
      local code = okCall and ((type(res) == "number") and res or ((res == false) and 9 or 0)) or 9
      if code == 0 then
        table.remove(Comm.queue, i)
        Comm.stats.sent = Comm.stats.sent + 1
        if q.channel == "WHISPER" and q.target then recentTargets[q.target:lower()] = t end
      elseif RESULT_FAIL[code] or q.tries >= MAX_TRIES then
        table.remove(Comm.queue, i)
        Comm.stats.dropped = Comm.stats.dropped + 1
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
local KEEP = { DEC = true, BYE = true, END = true, LOG = true }
function Comm.purge(mid)
  for i = #Comm.queue, 1, -1 do
    local text = Comm.queue[i].text
    local kind, qmid = text:match("^%d+:(%u+):([^:]+)")
    if qmid == mid and not KEEP[kind] then table.remove(Comm.queue, i) end
  end
end

return Comm
