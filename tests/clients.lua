-- Client profiles for the WoW API mock: one per official client type (warcraft.wiki.gg, Oct 2026).
-- Each profile changes a mocked WoW API (tests/wowmock.lua) so it has what that client has - and,
-- more important, LACKS what that client lacks (removed globals, missing C_ namespaces). These are
-- models from the documentation, not the clients: passing here is NOT a real client test.
--
--   local CL = dofile("tests/clients.lua"); CL.apply("forever", G, M)
local CL = {}

local ENUMS = {
  AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
  LootMethod = { Freeforall = 0, Roundrobin = 1, Masterlooter = 2, Group = 3, Needbeforegreed = 4, Personal = 5 },
  SeasonID = { NoSeason = 0, SeasonOfMastery = 1, SeasonOfDiscovery = 2, Hardcore = 3, Fresh = 11 },
}

local function mainline(G, M)
  -- Midnight's addon restrictions: secret values, chat lockdown (encounter / M+ / PvP)
  G.issecretvalue = function(v) return v == "SECRET" end
  G.UnitAffectingCombat = function() return M.combat and "SECRET" or false end
  G.C_ChatInfo.InChatMessagingLockdown = function() return M.chatLocked and true or false end
  G.C_RestrictedActions = { IsAddOnRestrictionActive = function(kind) return M.restriction ~= nil and M.restriction == kind end }
  -- removed on 11.x / 12.x Mainline (and Forever, which shares that code)
  G.GetItemInfo, G.GetSpellInfo, G.UnitAura, G.GetLootMethod, G.BNSendGameData = nil, nil, nil, nil, nil
  G.C_Item = { GetItemInfo = M.GetItemInfoImpl, GetItemInfoInstant = function(id) return tonumber(id) end }
  G.AddonCompartmentFrame = { RegisterAddon = function() end }
end
local function classicApi(G, M, opts)
  -- the Classic clients have the lockdown API, but the restrictions are off there (Blizzard, Apr 2026)
  G.issecretvalue = nil
  G.UnitAffectingCombat = function() return M.combat end
  if opts.modern ~= false then
    G.C_ChatInfo.InChatMessagingLockdown = function() return false end
    G.C_RestrictedActions = { IsAddOnRestrictionActive = function() return false end }
    G.GetLootMethod = nil -- removed where C_PartyInfo.GetLootMethod came (1.15.8, 2.5.5, 5.5.1)
    G.GetSpellInfo = function(id) return "Spell " .. tostring(id) end
    G.UnitAura = nil
  else
    -- an older Classic-family client (Titan Reforged's Wrath game type is not documented as having
    -- the 12.x-era APIs): no lockdown API, the old global loot call
    G.C_ChatInfo.InChatMessagingLockdown = nil
    G.C_RestrictedActions = nil
    G.GetLootMethod = function() return M.lootMethodOld or "group", 0, nil end
  end
  G.AddonCompartmentFrame = nil
end

CL.PROFILES = {
  forever = { project = 18, version = "1.60.1", build = "70532", interface = 16001, apply = mainline, label = "WoW Forever" },
  retail = { project = 1, version = "12.1.5", build = "70575", interface = 120105, apply = mainline, label = "Retail (Midnight)" },
  vanilla = { project = 2, version = "1.15.9", build = "70411", interface = 11509, apply = function(G, M) classicApi(G, M, {}) end, label = "Classic Era" },
  hardcore = { project = 2, version = "1.15.9", build = "70411", interface = 11509, label = "Classic Era Hardcore",
    apply = function(G, M) classicApi(G, M, {}); G.C_GameRules = { IsHardcoreActive = function() return true end } end },
  sod = { project = 2, version = "1.15.9", build = "70411", interface = 11509, label = "Season of Discovery",
    apply = function(G, M) classicApi(G, M, {}); G.C_Seasons = { HasActiveSeason = function() return true end, GetActiveSeason = function() return 2 end } end },
  tbc = { project = 5, version = "2.5.6", build = "70400", interface = 20506, apply = function(G, M) classicApi(G, M, {}) end, label = "TBC Anniversary" },
  mists = { project = 19, version = "5.5.4", build = "70579", interface = 50504, apply = function(G, M) classicApi(G, M, {}) end, label = "Mists Classic" },
  titan = { project = 11, version = "3.80.2", build = "65000", interface = 38002, apply = function(G, M) classicApi(G, M, { modern = false }) end, label = "Titan Reforged" },
  -- a future client type we don't know yet: must still load, named "unknown", nothing faked
  future = { project = 99, version = "13.0.0", build = "1", interface = 130000, apply = mainline, label = "unknown future client" },
}
CL.ORDER = { "forever", "vanilla", "hardcore", "sod", "retail", "tbc", "mists", "titan", "future" }
CL.EXPECT_KEY = { forever = "forever", vanilla = "vanilla", hardcore = "vanilla", sod = "vanilla", retail = "retail", tbc = "tbc", mists = "mists", titan = "wrath", future = "retail" }

--- Apply profile `name` to the mocked globals G (and the mock module M).
-- optional globals a profile (or an earlier test in the same Lua state) may have set
CL.OPTIONAL = { "C_GameRules", "C_Seasons", "C_RestrictedActions", "IsTrialAccount", "IsVeteranTrialAccount", "AddonCompartmentFrame",
  "issecretvalue", "GetSpellInfo", "UnitAura", "GetLootMethod", "BNSendGameData", "C_Item", "C_PartyInfo" }

function CL.apply(name, G, M)
  local p = assert(CL.PROFILES[name], "unknown client profile " .. tostring(name))
  for _, k in ipairs(CL.OPTIONAL) do G[k] = nil end
  G.WOW_PROJECT_ID = p.project
  G.GetBuildInfo = function() return p.version, p.build, "Oct 2026", p.interface end
  G.Enum = G.Enum or {}
  for k, v in pairs(ENUMS) do G.Enum[k] = v end
  M.GetItemInfoImpl = M.GetItemInfoImpl or G.GetItemInfo
  G.C_PartyInfo = G.C_PartyInfo or {}
  G.C_PartyInfo.GetLootMethod = function() return M.lootMethod or 3, 0, nil end
  p.apply(G, M)
  if name == "titan" then G.C_PartyInfo.GetLootMethod = nil end
  M.client = name
  return p
end

return CL
