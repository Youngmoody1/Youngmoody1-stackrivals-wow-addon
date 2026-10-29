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
local MAX_TRIES = 6

local function now() return GetTime and GetTime() or 0 end

--- "Name" or "Name-Realm" -> "Name-Realm" (realm without spaces, like the client reports it).
function Comm.fullName(name)
  if type(name) ~= "string" or name == "" then return nil end
  if name:find("-", 1, true) then return name end
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
  local okReg = pcall(api.RegisterAddonMessagePrefix, P.PREFIX)
  if not okReg then Comm.unavailable = true; return end
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
function Comm.send(text, channel, target, onFail)
  if not Comm.enabled then if onFail then onFail("unavailable") end return false end
  if #Comm.queue >= MAX_QUEUE then
    Comm.stats.dropped = Comm.stats.dropped + 1
    if onFail then onFail("queue_full") end
    return false
  end
  Comm.queue[#Comm.queue + 1] = { text = text, channel = channel, target = target, onFail = onFail, tries = 0, notBefore = 0 }
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

--- Drop queued messages for a finished match (e.g. no point retrying old scores).
function Comm.purge(mid)
  for i = #Comm.queue, 1, -1 do
    if Comm.queue[i].text:find(":" .. mid .. ":", 1, true) or Comm.queue[i].text:sub(-#mid - 1) == ":" .. mid then
      table.remove(Comm.queue, i)
    end
  end
end

return Comm
