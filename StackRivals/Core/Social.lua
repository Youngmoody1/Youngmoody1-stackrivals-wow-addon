--[[
  StackRivals - who you can challenge: guild members, WoW friends, Battle.net friends who are on
  WoW, your party / raid, and recent rivals. Read-only lists from the WoW client; nothing is sent
  here. Whether someone has StackRivals is NEVER assumed from these lists: only their addon's own
  answer (HI to our HEL, Core/Duel.lua) makes them "ready to challenge".

  Every WoW API is optional and guarded (names checked against warcraft.wiki.gg docs, not yet in a
  real client): a missing API just gives an empty list. Battle.net game account IDs are temporary
  and are never stored; a Battle.net friend is reached by their character name (same WoW version
  and a realm we can whisper), the same whisper transport as every duel.
]]
local _, ns = ...
ns = ns or {}

local Social = {}
ns.Social = Social

local function myRealm()
  local r = GetNormalizedRealmName and GetNormalizedRealmName()
  if not r or r == "" then r = GetRealmName and GetRealmName() or "" end
  return (r:gsub("[%s%-]", ""))
end

--- "Name" or "Name-Realm" (any spacing) -> "Name-Realm".
function Social.full(name, realm)
  if type(name) ~= "string" or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  realm = (realm and realm ~= "") and realm:gsub("[%s%-]", "") or myRealm()
  return name .. "-" .. realm
end

--- Realms we can whisper: our own and the connected ones.
local function reachableRealms()
  local t = { [myRealm():lower()] = true }
  if GetAutoCompleteRealms then
    local ok, list = pcall(GetAutoCompleteRealms)
    if ok and type(list) == "table" then for _, r in ipairs(list) do t[(tostring(r):gsub("[%s%-]", "")):lower()] = true end end
  end
  return t
end

--- On your ignore list: never shown, never asked, never answered.
function Social.isIgnored(name)
  local F = C_FriendList
  if not (F and F.IsIgnored) or type(name) ~= "string" then return false end
  local ok, v = pcall(F.IsIgnored, name)
  if ok and v then return true end
  local short = name:match("^([^%-]+)%-")
  if short and name:sub(#short + 2):lower() == myRealm():lower() then
    ok, v = pcall(F.IsIgnored, short)
    return ok and v or false
  end
  return false
end

local function me() return ns.Comm and ns.Comm.me and ns.Comm.me() end

local function add(out, seen, e)
  if not e.name or seen[e.name:lower()] then return end
  local my = me()
  if my and my:lower() == e.name:lower() then return end
  if Social.isIgnored(e.name) then return end
  seen[e.name:lower()] = true
  out[#out + 1] = e
end

--- Ask the client to refresh the guild roster (it answers with GUILD_ROSTER_UPDATE).
function Social.requestGuild()
  if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
  elseif GuildRoster then pcall(GuildRoster) end
end

function Social.guild()
  local out, seen = {}, {}
  if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return out end
  local total = GetNumGuildMembers() or 0
  for i = 1, math.min(total, 1000) do
    local name, _, _, _, className, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
    local cls = (type(classFile) == "string" and classFile ~= "" and classFile) or (ns.T and ns.T.classToken(className)) or nil
    add(out, seen, { name = Social.full(name), online = online and true or false, reach = true, source = "guild", class = cls })
  end
  return out
end

function Social.friends()
  local out, seen = {}, {}
  local F = C_FriendList
  if not (F and F.GetNumFriends and F.GetFriendInfoByIndex) then return out end
  for i = 1, math.min(F.GetNumFriends() or 0, 200) do
    local info = F.GetFriendInfoByIndex(i)
    if type(info) == "table" then
      add(out, seen, { name = Social.full(info.name), online = info.connected and true or false, reach = true, source = "friends",
        class = ns.T and ns.T.classToken(info.className) or nil })
    end
  end
  return out
end

--- Can a normal addon whisper reach this realm (ours or a connected one)?
function Social.whisperable(realm)
  return type(realm) == "string" and reachableRealms()[(realm:gsub("[%s%-]", "")):lower()] or false
end

--- Battle.net friends who are on WoW now. Reachable = the same WoW version (project) and a realm
--- we can whisper, or any realm through the Battle.net transport (Net/BNet.lua) when the client
--- has it; others are listed with the reason.
function Social.bnet()
  local out, seen = {}, {}
  local B = C_BattleNet
  if not (BNGetNumFriends and B and B.GetFriendAccountInfo) then return out end
  local total = BNGetNumFriends() or 0
  local realms = reachableRealms()
  local project = WOW_PROJECT_ID
  for i = 1, math.min(total, 200) do
    local ok, acc = pcall(B.GetFriendAccountInfo, i)
    local g = ok and type(acc) == "table" and acc.gameAccountInfo or nil
    if g and g.isOnline and g.clientProgram == (BNET_CLIENT_WOW or "WoW") and type(g.characterName) == "string" and g.characterName ~= "" then
      local realm = type(g.realmName) == "string" and g.realmName or ""
      local e = { name = Social.full(g.characterName, realm ~= "" and realm or nil), online = true, source = "bnet", reach = true,
        class = ns.T and ns.T.classToken(g.className) or nil }
      if project and g.wowProjectID and g.wowProjectID ~= project then
        e.reach, e.why = false, "other WoW version"
      elseif realm ~= "" and not realms[(realm:gsub("[%s%-]", "")):lower()] then
        if ns.BNet and ns.BNet.available() then e.via = "bnet" -- other realm: over Battle.net
        else e.reach, e.why = false, "other realm" end
      end
      add(out, seen, e)
    end
  end
  return out
end

function Social.group()
  local out, seen = {}, {}
  if not (GetNumGroupMembers and UnitName) then return out end
  local raid = IsInRaid and IsInRaid()
  local n = GetNumGroupMembers() or 0
  if not raid then n = n - 1 end -- party1..party(n-1): the player is not a "party" unit
  for i = 1, math.min(n, 40) do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    local name, realm = UnitName(unit)
    if name then add(out, seen, { name = Social.full(name, realm), online = true, reach = true, source = "group" }) end
  end
  return out
end

--- Rivals from your duel history (newest first). Online status unknown until they answer.
function Social.recent()
  local out, seen = {}, {}
  local h = ns.db and ns.db.duels and ns.db.duels.history or {}
  for _, e in ipairs(h) do
    if #out >= 12 then break end
    add(out, seen, { name = e.rival, online = nil, reach = true, source = "recent" })
  end
  return out
end

Social.SOURCES = { "guild", "friends", "bnet", "group", "recent" }
function Social.list(source) return (Social[source] or Social.guild)() end

--- Refresh the open list when the client's rosters change (events guarded: unknown -> ignored).
function Social.init(onChange)
  if Social.frame or not CreateFrame then return end
  local f = CreateFrame("Frame")
  Social.frame = f
  for _, ev in ipairs({ "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "GROUP_ROSTER_UPDATE" }) do
    pcall(f.RegisterEvent, f, ev)
  end
  f:SetScript("OnEvent", function() if onChange then onChange() end end)
end

return Social
