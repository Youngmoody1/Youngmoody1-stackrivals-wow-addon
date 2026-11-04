-- Every official WoW client type, modelled from the documentation (tests/clients.lua): the whole
-- addon loads, detects the client correctly, plays every solo mode, opens every screen, keeps its
-- saved data, reads the loot method, and handles each client's restrictions (addon chat lockdown,
-- trial accounts) without faking anything. MOCK TESTS: they prove the logic and the fallbacks for
-- APIs a client lacks - NOT that the addon works in that client (docs/COMPATIBILITY.md).
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local CL = dofile(testdir .. "/clients.lua")
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local function tocFiles()
  local files = {}
  for line in io.lines(root .. "/StackRivals.toc") do
    if line ~= "" and not line:match("^##") then files[#files + 1] = (line:gsub("\\", "/")) end
  end
  return files
end

local function boot(profile, saved, before)
  local M = dofile(testdir .. "/wowmock.lua")
  M.install()
  CL.apply(profile, _G, M)
  if before then before(_G, M) end
  _G.StackRivalsDB = saved
  local ns = {}
  for _, f in ipairs(tocFiles()) do assert(loadfile(root .. "/" .. f))("StackRivals", ns) end
  M.fire("ADDON_LOADED", "StackRivals")
  M.fire("PLAYER_LOGIN")
  return M, ns
end
local function key(ns, k) ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, k); ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, k) end
local SPREAD = { { "LEFT", 4 }, { "RIGHT", 4 }, { "LEFT", 2 }, { "RIGHT", 2 }, { "LEFT", 0 }, { "RIGHT", 1 } }
local function playSome(M, ns, drops)
  for i = 1, drops do
    local d = SPREAD[(i - 1) % #SPREAD + 1]
    for _ = 1, d[2] do key(ns, d[1]); M.frames_step(2) end
    key(ns, "SPACE"); M.frames_step(3)
  end
end

local PLATFORM = { forever = "wow-forever", retail = "wow-retail", future = "wow-retail" }

for _, name in ipairs(CL.ORDER) do
  local prof = CL.PROFILES[name]
  describe("client: " .. prof.label .. " (mock of " .. prof.interface .. ", project " .. prof.project .. ")", function()
    it("loads every file, detects the client type, platform and realm rules correctly", function()
      local M, ns = boot(name)
      local info = ns.Client.get()
      eq(info.key, CL.EXPECT_KEY[name], "client type")
      eq(info.interface, prof.interface)
      if name == "forever" then ok(ns.Client.mainline(), "Forever is a Mainline-family client, not Classic Era") end
      if name == "vanilla" or name == "tbc" or name == "mists" then ok(not ns.Client.mainline()) end
      eq(info.hardcore, name == "hardcore" or nil, "Hardcore realm rules")
      eq(info.sod, name == "sod" or nil, "Season of Discovery")
      if name == "future" then ok(info.byInterface, "unknown project id: named from the interface range, and marked so") end
      eq(ns.Account.platform(), PLATFORM[name] or "wow-classic", "SR1 platform")
      SlashCmdList.STACKRIVALS("version")
      ok(M.log[#M.log]:find(prof.version, 1, true), "/sr version names the client: " .. M.log[#M.log])
      eq(StackRivalsDB.diag.clients[tostring(prof.interface)].client, CL.EXPECT_KEY[name], "diagnostics in SavedVariables")
    end)

    it("plays Classic, Time Trial, Daily and Spell Battle vs Bot; records survive a reload", function()
      local M, ns = boot(name)
      SlashCmdList.STACKRIVALS("")
      for _, mode in ipairs({ "classic", "blitz", "daily", "spellbot" }) do
        ns.App:Start(mode); M.frames_step(250)
        eq(ns.App.session.phase, "playing", mode .. " is playing")
        playSome(M, ns, 12)
        ok(ns.App.session.state.tick > 0, mode .. " ticks")
        ns.App:Quit(); M.frames_step(2)
      end
      -- a full Classic game to game over (hard drops in one column), so a record is saved
      ns.App:Start("classic"); M.frames_step(250)
      for _ = 1, 60 do if ns.App.session.phase == "over" then break end key(ns, "SPACE"); M.frames_step(3) end
      eq(ns.App.session.phase, "over", "Classic game over")
      ok((ns.db.records.classic.games or 0) >= 1, "Classic game recorded")
      local saved = StackRivalsDB
      local M2, ns2 = boot(name, saved)
      ok((ns2.db.records.classic.games or 0) >= 1, "records kept after a reload")
    end)

    it("opens every screen without a Lua error", function()
      local M, ns = boot(name)
      SlashCmdList.STACKRIVALS("")
      for _, sheet in ipairs({ "help", "records", "duel", "quickplay", "account", "loot", "spell" }) do
        local okS, err = pcall(ns.UI.ShowSheet, ns.UI, sheet)
        ok(okS, sheet .. ": " .. tostring(err))
        M.frames_step(2)
      end
      ok(ns.UI.frame:IsShown())
    end)

    it("reads the loot method (never changes it) and finds its APIs by feature, not by name", function()
      local M, ns = boot(name)
      M.lootMethod, M.lootMethodOld = 2, "master"
      eq(ns.Client.lootMethod(), "master")
      M.lootMethod, M.lootMethodOld = 3, "group"
      eq(ns.Client.lootMethod(), "group")
      local f = ns.Client.features()
      ok(f.addonMessages and f.itemInfo, "addon messages and item info available")
      eq(f.secretValues, name == "forever" or name == "retail" or name == "future", "secret values only on Mainline")
      eq(M.lootGiven, nil, "never hands out loot"); eq(M.lootChanged, nil, "never changes the loot method")
      -- the item box works without the removed global GetItemInfo (Mainline 12.1.5)
      eq((ns.LootDuel.itemInfo(19019)), "Thunderfury, Blessed Blade of the Windseeker")
    end)

    it("addon chat lockdown: on Mainline clients Loot Duel can't start and messages wait; Classic clients never lock", function()
      local M, ns = boot(name)
      eq(ns.LootDuel.commState(), true, "free to use outside a lockdown")
      M.chatLocked = true
      M.restriction = 1 -- Enum.AddOnRestrictionType.Encounter
      local mainline = (name == "forever" or name == "retail" or name == "future")
      local okC, why = ns.LootDuel.commState()
      if mainline then
        eq(okC, false); eq(why, "locked", "says why (boss fight / M+ / PvP)")
        eq(ns.Client.lockdownReason(), "encounter")
        local okCreate, whyCreate = ns.LootDuel.create(19019, "l060", { "A-Realm", "B-Realm" })
        eq(okCreate, false); eq(whyCreate, "locked")
        -- a message sent now waits (it is not lost and not counted as a failed try)
        local sent0 = #M.addonOut
        ns.Comm.send("1:HEL:0.7.3:1", "PARTY", nil, nil, {})
        M.frames_step(5)
        eq(#M.addonOut, sent0, "held during the lockdown")
        M.chatLocked = false; M.restriction = nil
        M.frames_step(5)
        eq(#M.addonOut, sent0 + 1, "sent once it lifts")
        -- a whole map locked (if the client reports it that way): said differently, still refused
        M.chatLocked = true; M.restriction = 4 -- Enum.AddOnRestrictionType.Map
        local okM, whyM = ns.LootDuel.commState()
        eq(okM, false); eq(whyM, "locked_map")
        ok(ns.LootDuel.WHY.locked_map:find("zone", 1, true))
        M.chatLocked = false; M.restriction = nil
      else
        eq(okC, true, "Classic clients have no addon chat lockdown (Blizzard: off in Classic)")
        eq(ns.Client.messagingLocked(), false)
      end
    end)

    it("/sr report: one copyable line that names this client and its abilities, with no names or chat", function()
      local M, ns = boot(name)
      SlashCmdList.STACKRIVALS("report")
      local w = ns.UI.reportFrame
      ok(w and w:IsShown(), "report window shown")
      local txt = w.box:GetText()
      ok(txt:find("^SRDIAG1;"), "starts with SRDIAG1")
      local kv = {}
      for k, v in txt:gmatch("([%w]+)=([^;]*)") do kv[k] = v end
      eq(kv.client, CL.EXPECT_KEY[name]); eq(kv.iface, tostring(prof.interface)); eq(kv.v, ns.VERSION)
      eq(kv.hc, name == "hardcore" and "1" or "0"); eq(kv.sod, name == "sod" and "1" or "0")
      ok(kv.api and kv.api:find("am1", 1, true), "addon messages API listed")
      ok(kv.api:find("bn1", 1, true), "Battle.net game data API listed")
      ok(not txt:find(ns.Comm.me() or "Player", 1, true), "no character name")
      ok(not txt:find(GetRealmName(), 1, true), "no realm name")
      ok(#txt < 1000, "short enough to paste anywhere: " .. #txt)
    end)

    it("a trial / veteran account: no Loot Duel or duels, said plainly", function()
      local M, ns = boot(name, nil, function(G) G.IsTrialAccount = function() return true end end)
      local okC, why = ns.LootDuel.commState()
      eq(okC, false); eq(why, "trial")
      ok(ns.LootDuel.WHY.trial:find("Trial", 1, true))
      ok(ns.Client.get().trial)
    end)
  end)
end

-- Loot Duel between simulated clients of one type (netsim: WoW's throttle enforced). Instances are
-- modelled by the client reporting a lockdown; whether Forever locks a whole dungeon map (not only
-- encounters) is UNVERIFIED and needs the real client (docs/FOREVER.md).
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local function lootGroup(seed, client, n, raid)
  local net = NS.new({ seed = seed, instance = true })
  local list = {}
  local cls = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER", "DRUID", "SHAMAN", "WARLOCK", "PALADIN", "MAGE" }
  for i = 1, n do
    list[i] = net.add({ name = "P" .. i, group = "G", raid = raid, lead = (i == 1), class = cls[i], client = client, saved = { seenHelp = true } })
  end
  net.step(30)
  return net, list
end
local function raceAll(net, list, frames)
  for f = 1, frames do
    local running = false
    for i, c in ipairs(list) do
      local s = c.ns.App.session
      if s and s.loot and not s.recorded then
        running = true
        if s.phase == "playing" and f % (5 + i) == 0 then s:press("hardDrop"); s:release("hardDrop") end
      end
    end
    net.step(1)
    if not running then break end
  end
end

for _, client in ipairs({ "forever", "vanilla", "retail", "tbc", "mists" }) do
  local mainline = client == "forever" or client == "retail"
  describe("Loot Duel on " .. CL.PROFILES[client].label .. " (simulated clients" .. (mainline and ", addon chat lockdown modelled" or "") .. ")", function()
    it("5 in a dungeon party: invite, join, race, one result everywhere", function()
      local net, list = lootGroup(600, client, 5, false)
      local L = list[1].ns.LootDuel
      local names = {}
      for i = 1, 5 do names[i] = list[i].name end
      ok(L.create(19019, "l060", names), "offer")
      net.step(60 * 4)
      for i = 2, 5 do ok(list[i].ns.LootDuel.answer(true), "join " .. i) end
      net.step(60 * 6)
      ok(L.start(), "start")
      net.step(60 * 3)
      for i = 1, 5 do ok(list[i].ns.App.session and list[i].ns.App.session.loot, "P" .. i .. " races") end
      raceAll(net, list, 7000)
      net.step(60 * 20)
      local w
      for i = 1, 5 do
        local d = list[i].ns.LootDuel.history[1]
        ok(d, "result on P" .. i)
        local x = d and (d.winner or ("tie:" .. table.concat(d.tied or {}, ",")))
        w = w or x
        eq(x, w, "same result on P" .. i)
      end
    end)

    if mainline then
      it("a boss is pulled mid-race (addon messages locked 25 s): runs go on, nothing is lost, one result everywhere", function()
        local net, list = lootGroup(601, client, 10, true)
        local L = list[1].ns.LootDuel
        local names = {}
        for i = 1, 10 do names[i] = list[i].name end
        L.create(19019, "l060", names); net.step(60 * 4)
        for i = 2, 10 do list[i].ns.LootDuel.answer(true) end
        net.step(60 * 6)
        ok(L.start()); net.step(60 * 3)
        -- lockdown for everyone from now on for 25 s (an encounter)
        for _, c in ipairs(list) do c.lockdownUntil = net.time + 25 end
        net.step(60 * 2)
        local d1 = list[2].ns.LootDuel.current
        ok(d1.lockedNow, "the client says: locked")
        eq(list[2].ns.LootDuel.commState(), false)
        raceAll(net, list, 7000)
        net.step(60 * 60)
        local w
        for i = 1, 10 do
          local d = list[i].ns.LootDuel.history[1]
          ok(d, "result on P" .. i)
          if d then
            for _, r in ipairs(d.standings) do ok(r.status ~= "missing", "nobody is out because WoW held the messages: " .. r.name .. " " .. r.status) end
            local x = d.winner or ("tie:" .. table.concat(d.tied or {}, ","))
            w = w or x
            eq(x, w, "same result on P" .. i)
          end
        end
      end)

      it("Start during a lockdown is refused with the reason; after it, the same Loot Duel starts", function()
        local net, list = lootGroup(602, client, 5, false)
        local L = list[1].ns.LootDuel
        local names = {}
        for i = 1, 5 do names[i] = list[i].name end
        L.create(19019, "l060", names); net.step(60 * 4)
        for i = 2, 5 do list[i].ns.LootDuel.answer(true) end
        net.step(60 * 6)
        for _, c in ipairs(list) do c.lockdownUntil = net.time + 10 end
        local okS, why = L.start()
        eq(okS, false); eq(why, "locked")
        ok(L.WHY.locked:find("boss fight", 1, true))
        net.step(60 * 11)
        ok(L.start(), "starts once WoW allows addon messages again")
        net.step(60 * 4)
        for i = 1, 5 do ok(list[i].ns.App.session and list[i].ns.App.session.loot, "P" .. i .. " races") end
      end)
    end
  end)
end

describe("/sr commtest: proof that addon messages arrive (simulated clients)", function()
  for _, client in ipairs({ "forever", "vanilla" }) do
    it(CL.PROFILES[client].label .. ": a party of 5 - every other StackRivals answers, the chat line says who", function()
      local net, list = lootGroup(610, client, 5, false)
      local a = list[1]
      a.env.SlashCmdList.STACKRIVALS("commtest")
      net.step(60 * 7)
      local c = a.ns.Report.last
      eq(c.code, 0, "send accepted"); eq(c.answers, 4, "4 answers = delivered both ways")
      ok(a.M.log[#a.M.log]:find("4 of 4", 1, true), a.M.log[#a.M.log])
      ok(a.ns.Report.text():find("ct=PARTY,code0,ans4/4", 1, true), "in the report")
      -- a second test right away is refused (no spam)
      local okT, why = a.ns.Report.commTest()
      eq(okT, false); eq(why, "cooldown")
    end)
  end
  it("WoW Forever during a boss fight (lockdown): the test says so - result 11, no answers - instead of pretending", function()
    local net, list = lootGroup(611, "forever", 5, false)
    for _, c in ipairs(list) do c.lockdownUntil = net.time + 30 end
    local a = list[1]
    a.env.SlashCmdList.STACKRIVALS("commtest")
    net.step(60 * 7)
    local c = a.ns.Report.last
    eq(c.answers, 0); ok(c.locked, "lockdown reported by the client")
    ok(a.M.log[#a.M.log]:find("lockdown", 1, true), a.M.log[#a.M.log])
  end)
end)

describe("upgrade: a save written by 0.7.0 itself (your installed version) loads in this build", function()
  local function load070()
    local chunk = assert(loadfile(testdir .. "/fixtures/sv_0.7.0_classic_era.lua"))
    local env = {}
    setfenv(chunk, env); chunk()
    return env.StackRivalsDB
  end
  for _, client in ipairs({ "vanilla", "forever" }) do
    it(CL.PROFILES[client].label .. ": records, Spell Battle stats, settings, keys, Daily export and the pending account link are all kept", function()
      local saved = load070()
      local M, ns = boot(client, saved)
      eq(ns.db.records.classic.games, 1, "Classic"); eq(ns.db.records.blitz.games, 1, "Time Trial"); eq(ns.db.records.daily.games, 1, "Daily")
      eq(ns.db.spell.stats.challenger.losses, 1, "Spell Battle stats"); eq(ns.db.spell.loadout, "1057"); eq(ns.db.spell.difficulty, "challenger")
      eq(ns.db.settings.sound, false); eq(ns.db.settings.scale, 0.9)
      eq(ns.db.bindings.spell1, "Q"); eq(ns.db.bindings.hardDrop, "SPACE")
      eq(ns.db.sync.daily.score, 248, "Daily export kept")
      eq((ns.Account.state()), "pending", "the account link is still pending")
      eq(ns.db.settings.lootButton, true, "new setting added with its default")
      -- play, log out, load again: nothing lost
      SlashCmdList.STACKRIVALS(""); ns.App:Start("classic"); M.frames_step(250)
      for _ = 1, 80 do if ns.App.session.phase == "over" then break end
        ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, "SPACE"); ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, "SPACE"); M.frames_step(3) end
      M.fire("PLAYER_LOGOUT")
      local _, ns2 = boot(client, StackRivalsDB)
      eq(ns2.db.records.classic.games, 2, "the new game is added to the old ones")
      eq(ns2.db.spell.stats.challenger.losses, 1)
    end)
  end
end)

describe("client detection edge cases", function()
  it("an unreadable WOW_PROJECT_ID (secret) and an unknown interface never break loading", function()
    local M, ns = boot("forever", nil, function(G) G.WOW_PROJECT_ID = "SECRET"; G.GetBuildInfo = function() return "?", "?", "?", 0 end end)
    local info = ns.Client.get()
    eq(info.key, "unknown", "nothing to go on: unknown, not a guess")
    ok(ns.UI and ns.App, "loaded")
  end)
  it("WOW_PROJECT_ID decides over the interface number (Forever is not read as Classic Era)", function()
    local M, ns = boot("forever", nil, function(G) G.GetBuildInfo = function() return "1.60.2", "1", "x", 11509 end end)
    eq(ns.Client.get().key, "forever")
  end)
end)

return H
