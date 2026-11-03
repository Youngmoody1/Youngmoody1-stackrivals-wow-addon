--[[
  StackRivals - Battle.net transport: duels, presence, cards and chat with Battle.net friends on
  realms a normal addon whisper can't reach (not your realm, not a connected realm).

  Documented APIs only (warcraft.wiki.gg, checked Nov 2026):
    * C_BattleNet.SendGameData(gameAccountID, prefix, data) -> Enum.SendAddonMessageResult
      (Retail 12.0.0+, Forever 1.60.1, Classic Era 1.15.9, TBC 2.5.6, Mists 5.5.4);
    * BNSendGameData(gameAccountID, prefix, text) (older clients; deprecated in 12.0.0; max 4078 bytes);
    * event BN_CHAT_MSG_ADDON(prefix, text, channel "WHISPER", senderID = the sender's game account ID).
  Both deliver only between Battle.net friends: nobody else can reach you this way.

  gameAccountIDs are temporary (one session): they live in memory only, are re-read from the
  friend list, are never saved, never shown and never used as an identity. Everyone is identified
  by "Name-Realm" as the friend list reports it; a message from an ID that isn't a current
  Battle.net friend on WoW is dropped.
  NOT TESTED in a real client (delivery, order, throttling, cross-flavour behaviour).
]]
local _, ns = ...
ns = ns or {}

local BNet = { byName = {}, byId = {}, at = -99, stats = { sent = 0, received = 0, unknown = 0 } }
ns.BNet = BNet

BNet.REFRESH = 10 -- s between friend-list re-reads (also on BN_FRIEND_INFO_CHANGED)

local function now() return GetTime and GetTime() or 0 end

function BNet.sendFn()
  if C_BattleNet and type(C_BattleNet.SendGameData) == "function" then return C_BattleNet.SendGameData end
  if type(BNSendGameData) == "function" then return BNSendGameData end
  return nil
end

--- Is the transport there at all (API present, addon messages work)?
function BNet.available()
  return BNet.sendFn() ~= nil and ns.Comm and ns.Comm.enabled and not ns.Comm.trial or false
end

--- Re-read the Battle.net friend list: online friends on WoW, same WoW version (project).
function BNet.refresh(force)
  local t = now()
  if not force and t - BNet.at < BNet.REFRESH then return end
  BNet.at = t
  local byName, byId = {}, {}
  local B = C_BattleNet
  if BNGetNumFriends and B and B.GetFriendAccountInfo then
    local total = BNGetNumFriends() or 0
    for i = 1, math.min(total, 200) do
      local ok, acc = pcall(B.GetFriendAccountInfo, i)
      local g = ok and type(acc) == "table" and acc.gameAccountInfo or nil
      if g and g.isOnline and g.clientProgram == (BNET_CLIENT_WOW or "WoW") and type(g.gameAccountID) == "number"
        and type(g.characterName) == "string" and g.characterName ~= ""
        and not (WOW_PROJECT_ID and g.wowProjectID and g.wowProjectID ~= WOW_PROJECT_ID) then
        local name = ns.Social and ns.Social.full(g.characterName, (type(g.realmName) == "string" and g.realmName ~= "") and g.realmName or nil)
        if name then byName[name:lower()] = g.gameAccountID; byId[g.gameAccountID] = name end
      end
    end
  end
  BNet.byName, BNet.byId = byName, byId
end

--- The friend's current game account ID for "Name-Realm" (nil if not a Battle.net friend on WoW now).
function BNet.idFor(name)
  if type(name) ~= "string" then return nil end
  BNet.refresh()
  return BNet.byName[name:lower()]
end

--- Should a whisper to `target` go over Battle.net? Only when the normal whisper can't reach the
--- realm and the target is a Battle.net friend on WoW (same version) right now.
function BNet.route(target)
  if not BNet.available() or type(target) ~= "string" then return nil end
  local realm = target:match("%-(.+)$")
  if not realm or (ns.Social and ns.Social.whisperable(realm)) then return nil end
  return BNet.idFor(target)
end

--- Send one already-encoded message (Comm.flush calls this). Returns an Enum.SendAddonMessageResult code.
function BNet.send(id, text)
  local fn = BNet.sendFn()
  if not fn then return 7 end
  local code = ns.Comm.result(pcall(fn, id, ns.Protocol.PREFIX, text))
  if code == 0 then BNet.stats.sent = BNet.stats.sent + 1 end
  return code
end

--- BN_CHAT_MSG_ADDON: map the temporary ID back to the friend's character, then the normal path.
function BNet.onEvent(prefix, text, _, senderID)
  if prefix ~= ns.Protocol.PREFIX then return end
  local name = BNet.byId[senderID]
  if not name then BNet.refresh(true); name = BNet.byId[senderID] end
  if not name then
    BNet.stats.unknown = BNet.stats.unknown + 1 -- not a current Battle.net friend on WoW: dropped
    return
  end
  BNet.stats.received = BNet.stats.received + 1
  BNet.lastVia = BNet.lastVia or {}
  BNet.lastVia[name:lower()] = now()
  ns.Comm.receive(prefix, text, "WHISPER", name)
end

--- Did this player's messages come over Battle.net (we're Battle.net friends)?
function BNet.isFriendRoute(name)
  return type(name) == "string" and BNet.route(name) ~= nil
end

function BNet.init()
  if BNet.frame or not CreateFrame then return end
  local f = CreateFrame("Frame")
  BNet.frame = f
  pcall(f.RegisterEvent, f, "BN_CHAT_MSG_ADDON")
  pcall(f.RegisterEvent, f, "BN_FRIEND_INFO_CHANGED")
  f:SetScript("OnEvent", function(_, ev, ...)
    if ev == "BN_FRIEND_INFO_CHANGED" then BNet.at = -99 -- re-read on next use
    else BNet.onEvent(...) end
  end)
end

return BNet
