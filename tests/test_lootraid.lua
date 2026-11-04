-- Loot Duel with up to 10 players at once, in parties and raids of 5-40 (SIMULATED clients,
-- tests/netsim.lua with WoW's per-prefix throttle: 10 messages, +1 per second). Real raids need a
-- real test: docs/LOOT_DUEL.md, "Test with 10 real players".
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local CLS = { "WARRIOR", "SHAMAN", "MAGE", "ROGUE", "PRIEST", "DRUID", "HUNTER", "WARLOCK", "PALADIN" }
local LONG = { "Aaaaaaaaaaab", "Bbbbbbbbbbbc", "Cccccccccccd", "Ddddddddddde", "Eeeeeeeeeeef", "Fffffffffffg",
  "Ggggggggggga", "Hhhhhhhhhhhb", "Iiiiiiiiiiic", "Jjjjjjjjjjjd", "Kkkkkkkkkkke", "Lllllllllllf" }

--- A group of `size` (raid when > 5); the first `n` have long 12-letter names on a long realm.
local function group(seed, size, netOpts)
  netOpts = netOpts or {}; netOpts.seed = seed
  local net = NS.new(netOpts)
  local cs, names = {}, {}
  for i = 1, size do
    local n = LONG[i] or ("Px" .. string.char(96 + (i % 26) + 1) .. i)
    names[i] = n
    cs[n] = net.add({ name = n, realm = "ZandalarTribe", group = "G", raid = size > 5, lead = (i == 1), class = CLS[(i - 1) % #CLS + 1], saved = { seenHelp = true } })
  end
  net.step(30)
  return net, cs, names
end
local function LD(c) return c.ns.LootDuel end
local function full(n) return n .. "-ZandalarTribe" end
local P = (function()
  local pure = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Engine/Verify.lua", "Net/Protocol.lua" })
  return pure.Protocol
end)()

local function race(net, cs)
  for _ = 1, 6000 do
    local running = false
    for _, c in pairs(cs) do
      local s = c.ns.App.session
      if s and s.loot and not s.recorded then
        running = true
        if s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end
      end
    end
    net.step(1)
    if not running then break end
  end
end

--- Invite the first n (leader included), everyone joins; returns seconds from Start to the last
--- client's run start, and the result of the whole race.
local function run(seed, size, n, netOpts)
  local net, cs, names = group(seed, size, netOpts)
  local lead = cs[names[1]]
  local inv = {}
  for i = 1, n do inv[i] = full(names[i]) end
  ok(LD(lead).create(19019, "l060", inv))
  net.step(60 * 5)
  for i = 2, n do ok(LD(cs[names[i]]).answer(true), names[i] .. " joins") end
  net.step(60 * 10)
  eq(#LD(lead).accepted(LD(lead).current), n, "everyone joined")
  local t0 = net.time
  if os.getenv("SR_TRACE") then
    net.tap = function(c, text) print(string.format("%6.2f %-14s %s", net.time - t0, c.name:sub(1, 12), text:sub(1, 60))) end
  end
  ok(LD(lead).start())
  local started = {}
  for _ = 1, 60 * 60 do
    net.step(1)
    local all = true
    for i = 1, n do
      local c = cs[names[i]]
      if not started[i] and c.ns.App.session and c.ns.App.session.loot then started[i] = net.time - t0 end
      if not started[i] then all = false end
    end
    if all then break end
  end
  net.tap = nil
  local last = 0
  for i = 1, n do ok(started[i], names[i] .. " started"); last = math.max(last, started[i] or 999) end
  race(net, cs)
  net.step(60 * 150)
  return net, cs, names, last
end

describe("Loot Duel: up to 10 players at once (simulated)", function()
  for _, case in ipairs({ { 2, 5 }, { 3, 5 }, { 5, 5 }, { 8, 10 }, { 10, 10 }, { 10, 40 } }) do
    local n, size = case[1], case[2]
    it(n .. " players in a group of " .. size .. ": same pieces, same winner on every PC, within WoW's message limits", function()
      local net, cs, names, last = run(100 + n + size, size, n)
      H.note(string.format("start took %.1f s for %d players; %d messages sent, %d refused by the throttle", last, n, net.sent, net.throttled))
      ok(last < 20, "everyone starts within 20 s of Start (was " .. last .. ")")
      eq(net.throttled, 0, "no message over WoW's per-prefix limit")
      local seed, w = LD(cs[names[1]]).history[1].seed, nil
      for i = 1, size do
        local d = LD(cs[names[i]]).history[1]
        ok(d, names[i] .. " has the result")
        eq(d.seed, seed, "same pieces")
        w = w or (d.winner or "tie")
        eq(d.winner or "tie", w, names[i] .. " same winner")
        if i <= n then for _, r in ipairs(d.standings) do eq(r.status, "verified", names[i] .. " replayed " .. r.name) end end
      end
      eq(#LD(cs[names[1]]).history[1].standings, n)
    end)
  end
end)

describe("Loot Duel for dungeons and raids: inviting, leaders, trouble (simulated)", function()
  it("party of 5: Invite Party invites all 5 with one click; nobody else is entered; 3 join, 1 passes, 1 never answers -> 4 race", function()
    local net, cs, names = group(201, 5)
    local lead = cs[names[1]]
    local UI = lead.ns.UI
    lead.env.SlashCmdList.STACKRIVALS("")
    UI:ShowSheet("loot")
    local s = UI.lootSheet
    s.input:SetText("19019"); s.setItem:Click()
    eq(s.all.fs:GetText(), "Invite Party (5)")
    s.all:Click(); net.step(60 * 3)
    local d = LD(lead).current
    eq(#d.inviteOrder, 5, "all five invited")
    eq(#LD(lead).accepted(d), 1, "only the leader (his own click) has joined")
    for i = 2, 5 do ok(cs[names[i]].ns.UI.lootPopup:IsShown(), names[i] .. " sees the popup") end
    LD(cs[names[2]]).answer(true); LD(cs[names[3]]).answer(true); LD(cs[names[4]]).answer(false)
    net.step(60 * 5)
    eq(#LD(lead).accepted(d), 3)
    LD(cs[names[5]]).answer(true); net.step(60 * 5)
    ok(LD(lead).start())
    race(net, cs); net.step(60 * 150)
    eq(#LD(lead).history[1].standings, 4)
    eq(cs[names[4]].ns.App.session, nil, "who passed didn't play")
  end)

  it("raid of 10: Invite All asks to confirm, then invites all 10; over 10 online it is off", function()
    local net, cs, names = group(202, 10)
    local lead = cs[names[1]]
    local UI = lead.ns.UI
    lead.env.SlashCmdList.STACKRIVALS("")
    UI:ShowSheet("loot")
    local s = UI.lootSheet
    s.input:SetText("19019"); s.setItem:Click()
    eq(s.all.fs:GetText(), "Invite All (10)")
    s.all:Click(); net.step(5)
    eq(LD(lead).current, nil, "first click only asks")
    ok(UI.lootNote:find("Click again", 1, true), UI.lootNote)
    eq(s.all.fs:GetText(), "Confirm: 10")
    s.all:Click(); net.step(60 * 3)
    eq(#LD(lead).current.inviteOrder, 10)
    for i = 2, 10 do eq(LD(cs[names[i]]).current.state, "inviting", names[i]) end
  end)

  it("party leader, raid leader and raid assistant may run it; an ordinary member may not", function()
    local net, cs, names = group(203, 5)
    ok(LD(cs[names[1]]).mayLead(), "party leader")
    local okM, why = LD(cs[names[2]]).mayLead(); ok(not okM); eq(why, "not_leader")
    local net2 = NS.new({ seed = 204 })
    local rc = {}
    for i = 1, 12 do
      local n = LONG[i]
      rc[n] = net2.add({ name = n, realm = "ZandalarTribe", group = "R", raid = true, lead = i == 1, assist = i == 2, class = CLS[i % #CLS + 1], saved = { seenHelp = true } })
    end
    net2.step(30)
    ok(rc[LONG[1]].ns.LootDuel.mayLead(), "raid leader")
    ok(rc[LONG[2]].ns.LootDuel.mayLead(), "raid assistant")
    ok(not rc[LONG[3]].ns.LootDuel.mayLead(), "raid member")
  end)

  it("10 players, one disconnects mid-race: out after the deadline, shown as disconnected; the rest still get one winner", function()
    local net, cs, names = group(205, 10)
    local lead = cs[names[1]]
    local inv = {}
    for i = 1, 10 do inv[i] = full(names[i]) end
    LD(lead).create(19019, "l060", inv); net.step(60 * 5)
    for i = 2, 10 do LD(cs[names[i]]).answer(true) end
    net.step(60 * 10)
    ok(LD(lead).start()); net.step(60 * 8)
    cs[names[7]].online = false
    net.step(60 * 25)
    local board = LD(lead).liveBoard(LD(lead).current)
    local st
    for _, r in ipairs(board) do if r.name == full(names[7]) then st = r.status end end
    eq(st, "disconnected", "the leader's list shows it")
    race(net, cs); net.step(60 * 150)
    local w
    for i = 1, 10 do
      if i ~= 7 then
        local d = LD(cs[names[i]]).history[1]
        ok(d, names[i]); w = w or (d.winner or "tie"); eq(d.winner or "tie", w, names[i])
        for _, r in ipairs(d.standings) do if r.name == full(names[7]) then eq(r.status, "missing") end end
      end
    end
    ok(w ~= full(names[7]), "nobody wins by being gone")
  end)

  it("10 players over a bad network (latency up to 2.5 s, 20% duplicates, 5% lost) and one at 5 fps: same winner everywhere", function()
    local net, cs, names = group(206, 10, { latency = { 0.05, 2.5 }, dup = 0.2, drop = 0.05 })
    cs[names[4]].frameDt = 1 / 5
    local lead = cs[names[1]]
    local inv = {}
    for i = 1, 10 do inv[i] = full(names[i]) end
    LD(lead).create(19019, "l060", inv); net.step(60 * 15)
    for i = 2, 10 do LD(cs[names[i]]).answer(true) end
    net.step(60 * 20)
    ok(LD(lead).start())
    race(net, cs); net.step(60 * 160)
    local w, cancelled = nil, 0
    for i = 1, 10 do
      local d = LD(cs[names[i]]).history[1] or LD(cs[names[i]]).current
      ok(d, names[i])
      if d.state == "cancelled" then cancelled = cancelled + 1
      else w = w or (d.winner or "tie"); eq(d.winner or "tie", w, names[i] .. " same winner") end
    end
    eq(cancelled, 0, "the start survived the bad network")
  end)

  it("identical play by all 10: a 10-way tie at the top (roll off), the same on every PC", function()
    local net, cs, names, last = run(207, 10, 10)
    for i = 1, 10 do
      local d = LD(cs[names[i]]).history[1]
      eq(d.winner, nil, names[i]); eq(#d.tied, 10, names[i] .. " sees the tie")
    end
  end)

  it("a forged result and a log that never arrives: rejected / missing on every PC, shown apart, never the winner", function()
    local net, cs, names = group(208, 5)
    local lead = cs[names[1]]
    local inv = {}
    for i = 1, 5 do inv[i] = full(names[i]) end
    LD(lead).create(19019, "l060", inv); net.step(60 * 5)
    for i = 2, 5 do LD(cs[names[i]]).answer(true) end
    net.step(60 * 10)
    ok(LD(lead).start()); net.step(60 * 6)
    -- player 3 is a modified client: claims a huge score; player 5's log is lost on the way
    local d3 = LD(cs[names[3]]).current
    cs[names[3]].ns.LootDuel.onLocalEnd = function(sess)
      local st = sess.state
      local packed = P.packLog(st.inputLog)
      for _, c in pairs(cs) do
        net.inject(c, full(names[3]), P.encode("LDE", d3.lid, P.b36(st.tick), P.b36(999999), P.b36(st.lines), P.b36(st.level), cs[names[3]].ns.Engine.hashState(st), 1), "PARTY")
        net.inject(c, full(names[3]), P.encode("LDL", d3.lid, 1, 1, packed), "PARTY")
      end
    end
    local realSend = net.send
    net.send = function(c, prefix, text, channel, target)
      if c.name == full(names[5]) and text:find(":LDL:", 1, true) then return 0 end -- lost
      return realSend(c, prefix, text, channel, target)
    end
    race(net, cs); net.step(60 * 160)
    net.send = realSend
    for i = 1, 4 do
      local d = LD(cs[names[i]]).history[1]
      ok(d, names[i])
      local by = {}
      for _, r in ipairs(d.standings) do by[r.name] = r.status end
      if i ~= 3 then eq(by[full(names[3])], "rejected", names[i] .. " rejects the forged score") end
      eq(by[full(names[5])], "missing", names[i] .. ": no log, no result")
      ok(d.winner ~= full(names[3]) and d.winner ~= full(names[5]), "never the winner")
    end
    -- on the sheet, results that don't count are listed apart
    local UI = lead.ns.UI
    lead.env.SlashCmdList.STACKRIVALS(""); UI:ShowSheet("loot")
    local seen
    for _, row in ipairs(UI.lootSheet.rows) do if row:IsShown() and (row.name:GetText() or ""):find("NOT COUNTED", 1, true) then seen = true end end
    ok(seen, "a NOT COUNTED divider")
  end)

  it("the live board beside the window: 10 rows in class colours, your row marked, outside the board area", function()
    local net, cs, names = group(209, 10)
    local lead = cs[names[1]]
    local inv = {}
    for i = 1, 10 do inv[i] = full(names[i]) end
    LD(lead).create(19019, "l060", inv); net.step(60 * 5)
    for i = 2, 10 do LD(cs[names[i]]).answer(true) end
    net.step(60 * 10)
    LD(lead).start(); net.step(60 * 12)
    local c2 = cs[names[2]]
    if not c2.ns.UI.frame:IsShown() then c2.env.SlashCmdList.STACKRIVALS("") end
    c2.ns.UI:RefreshPhase()
    net.step(60 * 6)
    local b = c2.ns.UI.lootBoard
    ok(b:IsShown(), "shown while racing")
    local shown, mine = 0, 0
    for _, r in ipairs(b.rows) do
      if r:IsShown() then
        shown = shown + 1
        ok((r.name:GetText() or ""):find("^|cff"), "class colour: " .. tostring(r.name:GetText()))
        if r.me:IsShown() then mine = mine + 1 end
      end
    end
    eq(shown, 10); eq(mine, 1)
    local pt, rel, relPt, x = b:GetPoint(1)
    ok(pt == "TOPLEFT" and rel == c2.ns.UI.frame and relPt == "TOPRIGHT" and x > 0, "beside the window, never over the board")
    ok((b.foot:GetText() or ""):find("provisional", 1, true))
  end)

  it("loot window: the leader can pick an item from the open loot window (read only); nothing is looted", function()
    local net, cs, names = group(210, 5)
    local lead = cs[names[1]]
    lead.env.GetNumLootItems = function() return 3 end
    local links = { "|cff9d9d9d|Hitem:2934::::::::60:::::|h[Ruined Leather Scraps]|h|r", "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r", "|cff0070dd|Hitem:17076::::::::60:::::|h[Bonereaver's Edge]|h|r" }
    lead.env.GetLootSlotLink = function(i) return links[i] end
    lead.env.GetLootSlotInfo = function(i) return nil, nil, 1, nil, ({ 0, 4, 3 })[i] end
    local looted = false
    lead.env.LootSlot = function() looted = true end
    lead.env.SlashCmdList.STACKRIVALS("")
    lead.ns.UI:ShowSheet("loot")
    local s = lead.ns.UI.lootSheet
    ok(s.item.fromLoot:IsShown()); eq(s.item.fromLoot.fs:GetText(), "From loot 2", "grey junk is left out")
    s.item.fromLoot:Click(); eq(lead.ns.UI.lootItemId, 19019)
    s.item.fromLoot:Click(); eq(lead.ns.UI.lootItemId, 17076)
    eq(looted, false)
  end)
end)

describe("main menu: Loot Duel is a main card (Daily Challenge kept)", function()
  it("order: Classic, Time Trial, LOOT DUEL, Quickplay, Spell Battle | Guild Duels; Daily Challenge in the button row and still playable", function()
    local net = NS.new({ seed = 220 })
    local c = net.add({ name = "Solo", saved = { seenHelp = true } }) -- not in a group
    net.step(30)
    c.env.SlashCmdList.STACKRIVALS("")
    local UI = c.ns.UI
    local function y(b) return select(5, b:GetPoint(1)) end
    ok(y(UI.modeButtons.classic) > y(UI.modeButtons.blitz) and y(UI.modeButtons.blitz) > y(UI.lootCard) and y(UI.lootCard) > y(UI.qpBar), "card order")
    eq(UI.lootCard.fs:GetText(), "LOOT DUEL"); eq(UI.lootCard.desc:GetText(), "Compete for raid loot")
    ok(UI.lootCard.icon:GetTexture():find("lootduel", 1, true), "own gem icon")
    eq(UI.lootCard.cta:GetText(), "Create Loot Duel")
    eq(UI.lootCard.side:GetText(), "For parties and raids")
    UI.lootCard:Click()
    ok(UI.lootSheet:IsShown(), "opens the lobby")
    eq(c.ns.LootDuel.current, nil, "a click sends no invite")
    UI.lootSheet:Hide(); UI:RefreshPhase()
    eq(UI.dailyBtn.fs:GetText(), "Daily Challenge")
    UI.dailyBtn:Click()
    eq(c.ns.App.session.mode.key, "daily", "Daily Challenge still plays")
  end)
  it("the card's call to action follows the group: leader of a party, member, invited", function()
    local net, cs, names = group(221, 5)
    local lead, mem = cs[names[1]], cs[names[2]]
    lead.env.SlashCmdList.STACKRIVALS(""); mem.env.SlashCmdList.STACKRIVALS("")
    lead.ns.UI:RefreshMenu(); mem.ns.UI:RefreshMenu()
    eq(lead.ns.UI.lootCard.cta:GetText(), "Create Loot Duel"); eq(lead.ns.UI.lootCard.side:GetText(), "Party of 5")
    eq(mem.ns.UI.lootCard.cta:GetText(), "Open"); eq(mem.ns.UI.lootCard.side:GetText(), "Your leader starts it")
    LD(lead).create(19019, "l060", { full(names[1]), full(names[2]) }); net.step(60 * 3)
    mem.ns.UI:RefreshMenu()
    eq(mem.ns.UI.lootCard.cta:GetText(), "Join now")
  end)
end)

describe("Loot Duel quick-access button near the group frames", function()
  local function solo(seed) local net = NS.new({ seed = seed }); local c = net.add({ name = "Solo", saved = { seenHelp = true } }); net.step(30); return net, c end
  it("hidden solo; shown in a party and in a raid; hidden again after leaving the group", function()
    local net, c = solo(230)
    local b = c.ns.LootButton.button
    ok(b, "created at login"); ok(not b:IsShown(), "solo: hidden")
    local net2, cs, names = group(231, 5)
    ok(cs[names[1]].ns.LootButton.button:IsShown(), "party leader")
    ok(cs[names[3]].ns.LootButton.button:IsShown(), "party member (opens the lobby to join or watch)")
    local net3, rs, rn = group(232, 12)
    ok(rs[rn[1]].ns.LootButton.button:IsShown(), "raid")
    local m = cs[names[2]]
    m.o.group = nil; m.M.fire("GROUP_ROSTER_UPDATE")
    ok(not m.ns.LootButton.button:IsShown(), "left the group: hidden")
  end)
  it("a click opens the Loot Duel lobby and sends nothing; in combat it stays hidden and opens nothing", function()
    local net, cs, names = group(233, 5)
    local c = cs[names[1]]
    local sent = 0
    net.tap = function(from) if from == c then sent = sent + 1 end end
    local before = sent
    c.ns.LootButton.button:Click("LeftButton")
    net.step(60)
    ok(c.ns.UI.frame:IsShown() and c.ns.UI.lootSheet:IsShown(), "the lobby is open")
    eq(c.ns.LootDuel.current, nil, "no Loot Duel created")
    local loot = 0
    net.tap = function(from, text) if from == c and text:find(":LD[FIAQW]:") then loot = loot + 1 end end
    net.step(60 * 5)
    eq(loot, 0, "no invite or Loot Duel message")
    net.tap = nil
    c.ns.UI.lootSheet:Hide(); c.ns.UI.frame:Hide()
    c.M.combat = true; c.M.fire("PLAYER_REGEN_DISABLED")
    ok(not c.ns.LootButton.button:IsShown(), "hidden in combat")
    c.ns.LootButton:Open()
    ok(not c.ns.UI.frame:IsShown(), "opens nothing in combat")
    c.M.combat = false; c.M.fire("PLAYER_REGEN_ENABLED")
    ok(c.ns.LootButton.button:IsShown(), "back after combat")
  end)
  it("right-click hides it (saved); Settings and /sr lootbutton show it again; Shift-drag saves its place across a reload", function()
    local net, cs, names = group(234, 5)
    local c = cs[names[1]]
    local b = c.ns.LootButton.button
    b:Click("RightButton")
    ok(not b:IsShown()); eq(c.ns.db.settings.lootButton, false)
    c.env.SlashCmdList.STACKRIVALS("lootbutton")
    ok(b:IsShown()); eq(c.ns.db.settings.lootButton, true)
    -- the settings switch
    c.ns.UI:ShowSettings(true)
    local tg
    for _, t in ipairs(c.ns.UI.toggles) do if t.key == "lootButton" then tg = t end end
    ok(tg, "a switch in Settings"); tg:Click()
    ok(not b:IsShown(), "switched off in Settings")
    tg:Click(); ok(b:IsShown())
    -- move: without Shift nothing moves; with Shift the place is saved
    c.env.IsShiftKeyDown = function() return false end
    b:GetScript("OnDragStart")(b); b:SetPoint("TOPLEFT", c.env.UIParent, "TOPLEFT", 300, -400); b:GetScript("OnDragStop")(b)
    eq(c.ns.db.settings.lootButtonPos, nil, "no Shift: not moved")
    c.env.IsShiftKeyDown = function() return true end
    b:GetScript("OnDragStart")(b); b:ClearAllPoints(); b:SetPoint("TOPLEFT", c.env.UIParent, "TOPLEFT", 300, -400); b:GetScript("OnDragStop")(b)
    eq(c.ns.db.settings.lootButtonPos.x, 300); eq(c.ns.db.settings.lootButtonPos.y, -400)
    local c2 = net.reload(c)
    local _, _, _, x, y = c2.ns.LootButton.button:GetPoint(1)
    eq(x, 300); eq(y, -400)
    c2.env.SlashCmdList.STACKRIVALS("lootbutton reset")
    local _, _, _, x2 = c2.ns.LootButton.button:GetPoint(1)
    eq(x2, c2.ns.LootButton.DEFAULT.x)
  end)
  it("a broken saved place is ignored (SavedVariables are cleaned)", function()
    local net = NS.new({ seed = 235 })
    local c = net.add({ name = "Solo", saved = { seenHelp = true, settings = { lootButton = "yes", lootButtonPos = { point = "NOPE", x = 1e9, y = "a" } } } })
    net.step(30)
    eq(c.ns.db.settings.lootButton, true); eq(c.ns.db.settings.lootButtonPos, nil)
  end)
end)

return H
