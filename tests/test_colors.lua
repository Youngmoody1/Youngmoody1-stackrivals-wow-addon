-- WoW's own colours: class colours from the client API (C_ClassColor, then RAID_CLASS_COLORS) with
-- the warcraft.wiki.gg values as fallback; item quality colours; Alliance blue / Horde red themes.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local function boot(extra)
  local net = NS.new({ seed = 1 })
  local o = { name = "Alice", guild = "G", saved = { seenHelp = true } }
  for k, v in pairs(extra or {}) do o[k] = v end
  local c = net.add(o)
  return net, c, c.ns.T
end
local function lum(r, g, b)
  local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
  return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
end
local function contrast(a, b)
  local l1, l2 = lum(a[1], a[2], a[3]), lum(b[1], b[2], b[3])
  if l1 < l2 then l1, l2 = l2, l1 end
  return (l1 + 0.05) / (l2 + 0.05)
end

describe("class colours", function()
  it("fallback table = WoW's official class colours (warcraft.wiki.gg), incl. the newer classes", function()
    local _, _, T = boot()
    local want = { WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372", ROGUE = "FFF468", PRIEST = "FFFFFF", SHAMAN = "0070DD",
      MAGE = "3FC7EB", WARLOCK = "8788EE", DRUID = "FF7C0A", DEATHKNIGHT = "C41E3A", MONK = "00FF98", DEMONHUNTER = "A330C9", EVOKER = "33937F" }
    for k, v in pairs(want) do eq(T.CLASS_HEX[k], v, k) end
    local n = 0
    for _ in pairs(T.CLASS_HEX) do n = n + 1 end
    eq(n, 13)
    eq(T.classText("SHAMAN", "Shaman"), "|cff0070ddShaman|r")
    eq(T.classText("WARRIOR", "Warrior"), "|cffc69b6dWarrior|r")
    eq(T.classText(nil, "Bob"), "Bob", "unknown class: plain text")
    eq(T.classText("NOTACLASS", "Bob"), "Bob")
  end)
  it("the client's own colours win: C_ClassColor first, then RAID_CLASS_COLORS", function()
    local _, _, T = boot({ beforeLogin = function(env)
      env.RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } } -- Classic's 0070DE
    end })
    eq(T.classText("SHAMAN", "x"), "|cff0070dex|r", "RAID_CLASS_COLORS used")
    local _, _, T2 = boot({ beforeLogin = function(env)
      env.RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
      env.C_ClassColor = { GetClassColor = function(t) if t == "SHAMAN" then return { r = 0, g = 0.4392, b = 0.8667 } end end }
    end })
    eq(T2.classText("SHAMAN", "x"), "|cff0070ddx|r", "C_ClassColor preferred")
  end)
  it("every class colour reads at >= 3:1 on the Alliance, Horde and neutral card fills", function()
    local _, _, T = boot()
    for faction, th in pairs(T.FACTION_THEME) do
      for token in pairs(T.CLASS_HEX) do
        local r, g, b = T.classColor(token)
        local cr = contrast({ r, g, b }, th.fill)
        ok(cr >= 3, string.format("%s on %s: %.2f", token, faction, cr))
      end
      ok(contrast(th.text, th.fill) >= 4.5, faction .. " faction label contrast")
    end
  end)
  it("item quality colours: client first, WoW's values as fallback", function()
    local _, _, T = boot()
    local r, g, b = T.qualityColor(4)
    eq(string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)), "a335ee", "epic")
    r, g, b = T.qualityColor(5)
    eq(string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)), "ff8000", "legendary")
    eq(T.qualityColor(99), nil)
  end)
  it("localised class names map back to tokens (lists that only give a name)", function()
    local _, _, T = boot()
    eq(T.classToken("Shaman"), "SHAMAN"); eq(T.classToken("WARLOCK"), "WARLOCK"); eq(T.classToken("Tinker"), nil)
  end)
end)

describe("class and faction on screens", function()
  local function lobby(fa, fb)
    local net = NS.new({ seed = 3 })
    local a = net.add({ name = "Alice", guild = "G", faction = fa.faction, race = fa.race, class = fa.class, level = 42, saved = { seenHelp = true } })
    local b = net.add({ name = "Bob", guild = "G", faction = fb.faction, race = fb.race, class = fb.class, level = 38, saved = { seenHelp = true } })
    net.step(30)
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.Duel.challenge("Bob-Realm", "b120"); net.step(60); b.ns.Duel.accept(); net.step(120)
    a.ns.UI:RefreshPhase()
    return net, a, b
  end
  it("lobby cards: Alliance blue, Horde red; class name in its class colour", function()
    local _, a = lobby({ faction = "Alliance", race = "Human", class = "WARRIOR" }, { faction = "Horde", race = "Orc", class = "SHAMAN" })
    local T, o = a.ns.T, a.ns.UI.lobby
    local me, them = o.meCard, o.themCard
    local ae, he = T.FACTION_THEME.Alliance.edge, T.FACTION_THEME.Horde.edge
    eq(me.edge._r, ae[1]); eq(me.edge._b, ae[3])
    eq(them.edge._r, he[1]); eq(them.edge._g, he[2])
    eq(them.bg._r, T.FACTION_THEME.Horde.fill[1])
    eq(me.line2:GetText(), "Human |cffc69b6dWarrior|r  -  Level 42")
    eq(them.faction:GetText(), "HORDE")
    ok(me.cIcon._tex == "portrait:player" or me.cIcon._tex ~= nil, "your card shows your portrait (or class icon)")
  end)
  it("the guild list colours names by class; the chat colours the rival's name", function()
    local net, a, b = lobby({ faction = "Horde", class = "SHAMAN" }, { faction = "Horde", race = "Troll", class = "MAGE" })
    a.ns.Chat.mode(a.ns.Duel.current)
    b.ns.Chat.quick(b.ns.Duel.current, 1); net.step(60)
    a.ns.UI:RefreshChat()
    local found
    for _, fs in ipairs(a.ns.UI.chat.lines) do if (fs:GetText() or ""):find("|cff3fc7ebBob|r: Good luck!", 1, true) then found = true end end
    ok(found, "Bob (Mage) in mage blue")
    a.ns.Duel.leave(); net.step(30); a.ns.Duel.clear()
    a.ns.UI:ShowSheet("duel"); a.ns.UI.duelSheet.refresh:Click(); net.step(60); a.ns.UI:RefreshDuelSheet()
    local named
    for _, row in ipairs(a.ns.UI.duelSheet.rows) do if row:IsShown() and (row.name:GetText() or ""):find("|cff3fc7ebBob|r", 1, true) then named = true end end
    ok(named, "guild roster class (Mage) colours the name")
  end)
end)

return H
