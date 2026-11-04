--[[
  StackRivals - which WoW client is this, and what can it do?

  One code base for every official client. Nothing here guesses from the interface number alone:
  WOW_PROJECT_ID decides the client type, the interface number only fills in when the constant is
  missing, and every feature is checked by looking for the API itself (feature detection).

  Client types (warcraft.wiki.gg "WOW_PROJECT_ID" and "TOC format", Oct 2026):
    1  retail   Retail / Midnight 12.x           family mainline   TOC _Standard, then _Mainline
    18 forever  WoW Forever 1.60.x (WOW_PROJECT_CAMELOT) mainline  TOC _Forever / _Camelot, then _Mainline
    19 mists    Mists of Pandaria Classic 5.5.x  family classic    TOC _Mists, then _Classic
    5  tbc      Burning Crusade Classic (the Anniversary realms) 2.5.x   TOC _TBC
    11 wrath    Wrath game type (Titan Reforged, China) 3.80.x        TOC _Wrath
    14 cata     Cataclysm Classic (ended 2025; kept so it is named, not misread)
    2  vanilla  Classic Era 1.15.x, with Hardcore and Season of Discovery realms   TOC _Vanilla
  Forever shares Retail's ("Mainline") UI code and its addon restrictions (Blizzard, 15 Sep 2026):
  it is NOT Classic Era, even though it plays like 2004.

  Restrictions handled here (read only, never worked around):
    * Addon chat lockdown (Retail and Forever): during a boss encounter, a Mythic+ run or a PvP match
      WoW refuses addon messages (SendAddonMessage result 11, AddOnMessageLockdown).
      C_ChatInfo.InChatMessagingLockdown() says when; C_RestrictedActions.IsAddOnRestrictionActive()
      says why. Classic clients have the API but the restrictions are off there (Blizzard, Apr 2026).
    * Trial and Veteran accounts can't send addon messages on Forever and modern clients.
]]
local _, ns = ...
ns = ns or {}

local Client = {}
ns.Client = Client

Client.TYPES = {
  [1] = { key = "retail", name = "Retail (Midnight)", family = "mainline" },
  [18] = { key = "forever", name = "WoW Forever", family = "mainline" },
  [19] = { key = "mists", name = "Mists of Pandaria Classic", family = "classic" },
  [14] = { key = "cata", name = "Cataclysm Classic", family = "classic" },
  [11] = { key = "wrath", name = "Wrath Classic (Titan Reforged)", family = "classic" },
  [5] = { key = "tbc", name = "Burning Crusade Classic (Anniversary)", family = "classic" },
  [2] = { key = "vanilla", name = "Classic Era", family = "classic" },
}
local BY_KEY = {}
for id, t in pairs(Client.TYPES) do t.project = id; BY_KEY[t.key] = t end

--- Only when WOW_PROJECT_ID is missing or unknown: the interface number's range.
local function fromInterface(iface)
  iface = tonumber(iface) or 0
  if iface >= 100000 then return BY_KEY.retail end
  if iface >= 16000 and iface < 17000 then return BY_KEY.forever end
  if iface >= 50000 and iface < 60000 then return BY_KEY.mists end
  if iface >= 40000 and iface < 50000 then return BY_KEY.cata end
  if iface >= 30000 and iface < 40000 then return BY_KEY.wrath end
  if iface >= 20000 and iface < 30000 then return BY_KEY.tbc end
  if iface >= 10000 and iface < 16000 then return BY_KEY.vanilla end
  return nil
end

local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
end
--- A secret value (Retail / Forever) is never compared: treat it as "unknown".
local function plain(v)
  if issecretvalue and call(issecretvalue, v) then return nil end
  return v
end

--- Detect once per load (the client can't change while running).
function Client.detect()
  local version, build, _, iface = call(GetBuildInfo)
  local project = tonumber(plain(WOW_PROJECT_ID))
  local t = (project and Client.TYPES[project]) or fromInterface(iface)
  local info = {
    key = t and t.key or "unknown", name = t and t.name or "Unknown WoW client", family = t and t.family or "unknown",
    project = project, interface = tonumber(iface) or 0, version = tostring(version or "?"), build = tostring(build or "?"),
    byInterface = (t ~= nil and not (project and Client.TYPES[project])) or nil,
  }
  -- realm rules on the same client (Classic Era: Hardcore, Season of Discovery)
  if C_GameRules and C_GameRules.IsHardcoreActive and call(C_GameRules.IsHardcoreActive) == true then info.hardcore = true end
  if C_Seasons and C_Seasons.HasActiveSeason and call(C_Seasons.HasActiveSeason) == true then
    local season = call(C_Seasons.GetActiveSeason)
    local sod = Enum and Enum.SeasonID and Enum.SeasonID.SeasonOfDiscovery
    if sod and season == sod then info.sod = true end
  end
  info.trial = ((IsTrialAccount and call(IsTrialAccount)) or (IsVeteranTrialAccount and call(IsVeteranTrialAccount))) and true or false
  Client.info = info
  return info
end

function Client.get() return Client.info or Client.detect() end
function Client.is(key) return Client.get().key == key end
function Client.mainline() return Client.get().family == "mainline" end

--- Short label for diagnostics and the help line: "WoW Forever 1.60.1 (16001)".
function Client.label()
  local i = Client.get()
  local extra = (i.hardcore and ", Hardcore") or (i.sod and ", Season of Discovery") or ""
  return i.name .. extra .. " " .. i.version .. " (" .. i.interface .. ")"
end

--- Feature checks: the API exists here (says nothing about whether WoW lets us use it right now).
function Client.features()
  local ci, bn = C_ChatInfo, C_BattleNet
  return {
    addonMessages = (ci and ci.SendAddonMessage) and true or false,
    bnetGameData = ((bn and bn.SendGameData) or BNSendGameData) and true or false,
    chatLockdownApi = (ci and ci.InChatMessagingLockdown) and true or false,
    restrictionApi = (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive) and true or false,
    lootMethodApi = ((C_PartyInfo and C_PartyInfo.GetLootMethod) or GetLootMethod) and true or false,
    secretValues = issecretvalue ~= nil,
    compartment = AddonCompartmentFrame ~= nil,
    itemInfo = ((C_Item and C_Item.GetItemInfo) or GetItemInfo) and true or false,
  }
end

--- Is WoW refusing addon messages right now (boss encounter, Mythic+, PvP match)? A secret or
--- missing answer counts as "not locked": the send result (11) still catches a lockdown.
function Client.messagingLocked()
  local ci = C_ChatInfo
  if not (ci and ci.InChatMessagingLockdown) then return false end
  return plain(call(ci.InChatMessagingLockdown)) == true
end

--- Why (when the client says): "encounter", "challengeMode", "pvpMatch", "map", "chat" or nil.
local REASONS = { { "Encounter", "encounter" }, { "ChallengeMode", "challengeMode" }, { "PvPMatch", "pvpMatch" }, { "Map", "map" }, { "Chat", "chat" } }
function Client.lockdownReason()
  local R, E = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
  if not (R and R.IsAddOnRestrictionActive and E) then return nil end
  for _, r in ipairs(REASONS) do
    local v = E[r[1]]
    if v ~= nil and plain(call(R.IsAddOnRestrictionActive, v)) == true then return r[2] end
  end
  return nil
end

--- The group's loot method, read only: "master", "group", "needbeforegreed", "personal",
--- "freeforall", "roundrobin" or nil (unknown / not in a group). Never changed by StackRivals.
local LM = { [0] = "freeforall", [1] = "roundrobin", [2] = "master", [3] = "group", [4] = "needbeforegreed", [5] = "personal" }
local LM_OLD = { freeforall = "freeforall", roundrobin = "roundrobin", master = "master", group = "group", needbeforegreed = "needbeforegreed", personalloot = "personal", personal = "personal" }
function Client.lootMethod()
  if C_PartyInfo and C_PartyInfo.GetLootMethod then
    local m = plain(call(C_PartyInfo.GetLootMethod))
    return LM[m] or (type(m) == "string" and LM_OLD[m:lower()]) or nil
  end
  if GetLootMethod then
    local m = plain(call(GetLootMethod))
    return type(m) == "string" and LM_OLD[m:lower()] or nil
  end
  return nil
end

--- In a dungeon / raid instance? ("party", "raid", "pvp", "arena", "scenario" or nil)
function Client.instanceType()
  if not IsInInstance then return nil end
  local inside, kind = call(IsInInstance)
  if plain(inside) ~= true then return nil end
  return plain(kind)
end
