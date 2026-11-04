-- Loot Duel between SIMULATED WoW clients in one party (tests/netsim.lua). Real raid behaviour
-- (RAID channel throttling, 40 players, loot windows) needs a real test: docs/LOOT_DUEL.md.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local pure = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Engine/Verify.lua", "Net/Protocol.lua" })
local P = pure.Protocol

--- A party: Lead (leader) + players. opts[name] = extra client options.
local function party(seed, names, opts, netOpts)
  netOpts = netOpts or {}
  netOpts.seed = seed
  local net = NS.new(netOpts)
  local cs = {}
  local classes = { "WARRIOR", "SHAMAN", "MAGE", "ROGUE", "PRIEST", "DRUID" }
  for i, n in ipairs(names) do
    local o = { name = n, group = "P", lead = (i == 1), class = classes[i], saved = { seenHelp = true } }
    for k, v in pairs((opts or {})[n] or {}) do o[k] = v end
    cs[n] = net.add(o)
  end
  net.step(30)
  return net, cs
end
local function LD(c) return c.ns.LootDuel end
--- Play every running loot race to its end (hard drops), then let results travel.
local function raceToEnd(net, cs, skip)
  -- the race starts once every seed share is in (a few seconds on the group channel)
  for _ = 1, 60 * 20 do
    local started = false
    for _, c in pairs(cs) do local s = c.ns.App.session; if s and s.loot then started = true end end
    if started then break end
    net.step(1)
  end
  for _ = 1, 6000 do
    local running = false
    for n, c in pairs(cs) do
      local s = c.ns.App.session
      if s and s.loot and not s.recorded and not (skip and skip[n]) then
        running = true
        if s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end
      end
    end
    net.step(1)
    if not running then break end
  end
  net.step(60 * 20)
end

describe("Loot Duel protocol", function()
  it("all messages round-trip and stay within 255 bytes; bad ones are refused", function()
    local h = P.hexName("Ann-Realm")
    local c16 = "0a1b2c3d4e5f6071"
    local msgs = {
      P.encode("LDO", "lid123", "l060", 1, 19019, c16, 3), P.encode("LDI", "lid123", 1, h .. "," .. P.hexName("Ben-Realm")),
      P.encode("LDA", "lid123", "a", c16), P.encode("LDA", "lid123", "d", "-"),
      P.encode("LDP", "lid123", 1, 1, h .. "-" .. c16), P.encode("LDS", "lid123", "0a1b2c3d", 2),
      P.encode("LDN", "lid123", "n0nce123"), P.encode("LDV", "lid123", 1, 1, h .. "-n0nce123"), P.encode("LDG", "lid123", "n0nce999", "0a1b2c3d"),
      P.encode("LDC", "lid123", P.b36(600), P.b36(12345)), P.encode("LDE", "lid123", P.b36(3600), P.b36(9000), P.b36(12), P.b36(2), "0a1b2c3d", 2),
      P.encode("LDL", "lid123", 1, 2, "3A0B5F"), P.encode("LDX", "lid123", "cancel"), P.encode("LDR", "lid123", h, 0),
    }
    for _, s in ipairs(msgs) do ok(#s <= 255, s); ok(P.decode(s), "decode " .. s) end
    eq(P.decode(msgs[2]).names[2], "Ben-Realm")
    local bad = {
      "1:LDO:lid123:x999:1:19019:0a1b2c3d4e5f6071:3", "1:LDO:lid123:l060:1:19019:0a1b2c3d4e5f6071:9", "1:LDO:lid123:l060:1:0:0a1b2c3d4e5f6071:3",
      "1:LDO:lid123:l060:1:19019:0a1b2c3d:3", "1:LDA:lid123:a:n0nce123", "1:LDP:lid123:1:1:" .. h .. "-n0nce123",
      "1:LDI:lid123:1:zz", "1:LDI:lid123:1:" .. P.hexName("Bad|cName-Realm"), "1:LDA:lid123:a:-", "1:LDA:lid123:x:0a1b2c3d4e5f6071",
      "1:LDP:lid123:2:1:" .. h .. "-0a1b2c3d4e5f6071", "1:LDS:lid123:nothex!:2", "1:LDE:lid123:1:1:1:1:xyz:1", "1:LDL:lid123:1:1:3AH",
      "1:LDN:lid123:-", "1:LDG:lid123:n0nce:xyz", "1:LDV:lid123:1:1:" .. h .. "-BAD!",
      "1:LDX:lid123:whatever", "1:LDR:lid123:" .. h .. ":2",
    }
    for _, s in ipairs(bad) do ok(P.decode(s) == nil, "accepted: " .. s) end
  end)
  it("standings: replay-checked first, score then lines; a tie at the top stays a tie; nobody checked = no winner", function()
    local _, cs = party(1, { "Lead" })
    local L = LD(cs.Lead)
    local parts = { { name = "Ann-Realm" }, { name = "Ben-Realm" }, { name = "Cid-Realm" } }
    local list, w, tied = L.standings(parts, {
      ["ann-realm"] = { status = "verified", score = 900, lines = 9 }, ["ben-realm"] = { status = "verified", score = 900, lines = 10 },
      ["cid-realm"] = { status = "rejected", score = 99999, lines = 99 } })
    eq(w, "Ben-Realm", "lines break the score tie"); eq(list[3].name, "Cid-Realm", "a rejected run is last, whatever it claimed")
    list, w, tied = L.standings(parts, { ["ann-realm"] = { status = "verified", score = 900, lines = 9 }, ["ben-realm"] = { status = "verified", score = 900, lines = 9 } })
    eq(w, nil); eq(#tied, 2, "same score and lines: tie -> roll off")
    list, w = L.standings(parts, { ["ann-realm"] = { status = "missing" } })
    eq(w, nil, "no checked result: no winner")
  end)
  it("the group roster carries each member's class (names in class colours)", function()
    local _, cs = party(3, { "Lead", "Ann", "Ben" })
    local L = LD(cs.Lead)
    eq(L.classOf("Ann-Realm"), "SHAMAN"); eq(L.classOf("Ben-Realm"), "MAGE"); eq(L.classOf("Lead-Realm"), "WARRIOR")
    eq(cs.Lead.ns.T.classText("SHAMAN", "Ann"), "|cff0070ddAnn|r", "Shaman blue #0070DD")
  end)
  it("item links: link, item:ID or a number; quality from the item", function()
    local _, cs = party(2, { "Lead" })
    local L = LD(cs.Lead)
    eq(L.itemIdFrom("|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"), 19019)
    eq(L.itemIdFrom("item:17076"), 17076); eq(L.itemIdFrom(" 17076 "), 17076); eq(L.itemIdFrom("Thunderfury"), nil); eq(L.itemIdFrom("0"), nil)
    local name, _, q, icon = L.itemInfo(19019)
    eq(name, "Thunderfury, Blessed Blade of the Windseeker"); eq(q, 5); ok(icon)
    ok(cs.Lead.ns.UI.lootItemText({ itemId = 19019 }):find("^|cffff8000Thunderfury"), "legendary orange")
  end)
end)

describe("Loot Duel between simulated clients", function()
  it("leader invites 3, two join, one passes: same pieces, every PC replays every run, same winner everywhere, no loot API", function()
    local net, cs = party(10, { "Lead", "Ann", "Ben", "Cid" })
    ok(LD(cs.Lead).create(19019, "l060", { "Ann-Realm", "Ben-Realm", "Cid-Realm" }))
    net.step(60)
    for _, n in ipairs({ "Ann", "Ben", "Cid" }) do
      local d = LD(cs[n]).current
      ok(d and d.state == "inviting" and d.itemId == 19019, n .. " got the offer")
      ok(cs[n].ns.UI.lootPopup:IsShown(), n .. " sees the popup")
    end
    LD(cs.Ann).answer(true); LD(cs.Ben).answer(true); LD(cs.Cid).answer(false)
    net.step(120)
    eq(#LD(cs.Lead).accepted(LD(cs.Lead).current), 2)
    ok(LD(cs.Lead).start())
    net.step(60 * 10)
    local seed = LD(cs.Lead).current.seed
    eq(LD(cs.Ann).current.seed, seed); eq(LD(cs.Ben).current.seed, seed); eq(LD(cs.Cid).current.seed, seed, "watchers know it too")
    eq(cs.Ann.ns.App.session.seed, seed); eq(cs.Ben.ns.App.session.seed, seed)
    eq(cs.Cid.ns.App.session, nil, "who passed doesn't play")
    raceToEnd(net, cs)
    local winner
    for _, n in ipairs({ "Lead", "Ann", "Ben", "Cid" }) do
      local d = LD(cs[n]).current
      eq(d.state, "done", n)
      for _, r in ipairs(d.standings) do eq(r.status, "verified", n .. " checked " .. r.name) end
      winner = winner or d.winner or "tie"
      eq(d.winner or "tie", winner, n .. " computes the same winner")
    end
    eq(LD(cs.Ann).history[1].agreement, "agreed", "the leader's announcement matches")
    for _, c in pairs(cs) do eq(c.M.lootGiven, nil); eq(c.M.lootChanged, nil); eq(c.M.chat[1], nil, "nothing posted without a click") end
  end)

  it("a forged result (score not matching the log) is rejected on every PC", function()
    local net, cs = party(11, { "Lead", "Ann", "Ben" })
    LD(cs.Lead).create(19019, "l060", { "Ann-Realm", "Ben-Realm" }); net.step(60)
    LD(cs.Ann).answer(true); LD(cs.Ben).answer(true); net.step(120)
    LD(cs.Lead).start(); net.step(120)
    -- Ben's addon lies: after his real run, the result message claims a huge score
    local realSend = cs.Ben.env.C_ChatInfo.SendAddonMessage
    cs.Ben.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      local lid, ticks, score, rest = text:match("^1:LDE:([^:]+):([^:]+):([^:]+):(.*)$")
      if lid then text = "1:LDE:" .. lid .. ":" .. ticks .. ":" .. P.b36(9999999) .. ":" .. rest end
      return realSend(prefix, text, ch, tgt)
    end
    raceToEnd(net, cs)
    for _, n in ipairs({ "Lead", "Ann" }) do
      local d = LD(cs[n]).current
      local ben
      for _, r in ipairs(d.standings) do if r.name == "Ben-Realm" then ben = r end end
      eq(ben.status, "rejected", n .. " rejects Ben's claim")
      eq(d.winner, "Ann-Realm")
    end
  end)

  it("a player who disconnects is out after the deadline; the race still has a winner", function()
    local net, cs = party(12, { "Lead", "Ann", "Ben" })
    LD(cs.Lead).create(17076, "l060", { "Lead-Realm", "Ann-Realm", "Ben-Realm" }); net.step(60)
    eq(LD(cs.Lead).current.answers["lead-realm"].accept, true, "the leader can play too")
    LD(cs.Ann).answer(true); LD(cs.Ben).answer(true); net.step(120)
    LD(cs.Lead).start(); net.step(240)
    cs.Ben.online = false
    raceToEnd(net, cs, { Ben = true })
    net.step(60 * 130) -- past the deadline: time limit + countdown + GRACE
    local d = LD(cs.Lead).current
    eq(d.state, "done")
    local ben
    for _, r in ipairs(d.standings) do if r.name == "Ben-Realm" then ben = r end end
    eq(ben.status, "missing"); ok(d.winner == "Lead-Realm" or d.winner == "Ann-Realm" or #d.tied > 1)
  end)

  it("only the leader / assistant / master looter may offer; members' fake offers are ignored", function()
    local net, cs = party(13, { "Lead", "Ann", "Ben" })
    local okA, why = LD(cs.Ann).create(19019, "l060", { "Ann-Realm", "Ben-Realm" })
    ok(not okA); eq(why, "not_leader")
    net.inject(cs.Ben, "Ann-Realm", P.encode("LDO", "fake01", "l060", 1, 19019, "0a1b2c3d", 2), "PARTY")
    net.step(30)
    eq(LD(cs.Ben).current, nil)
    local solo = NS.new({ seed = 14 }).add({ name = "Zed" })
    local okS, whyS = solo.ns.LootDuel.create(19019, "l060", { "Zed-Realm", "Ann-Realm" })
    ok(not okS); eq(whyS, "not_in_group")
  end)

  it("the master looter (not the leader) may run it; read through C_PartyInfo.GetLootMethod, never changed", function()
    local ml = function(env)
      -- Enum.LootMethod 2 = master looter; Ann is it: 0 on her PC, her party index elsewhere
      env.C_PartyInfo = { GetLootMethod = function()
        if env.UnitName("player") == "Ann" then return 2, 0, nil end
        for i = 1, 4 do if env.UnitName("party" .. i) == "Ann" then return 2, i, nil end end
        return 2, nil, nil
      end }
    end
    local net, cs = party(19, { "Lead", "Ann", "Ben" }, { Lead = { beforeLogin = ml }, Ann = { beforeLogin = ml }, Ben = { beforeLogin = ml } })
    ok(LD(cs.Ann).create(19019, "l060", { "Lead-Realm", "Ben-Realm" }), "Ann (master looter) may offer")
    net.step(60)
    ok(LD(cs.Ben).current and LD(cs.Ben).current.state == "inviting", "Ben accepts the master looter's offer")
    local okB, why = LD(cs.Ben).create(19019, "l060", { "Lead-Realm", "Ann-Realm" })
    ok(not okB); ok(why == "not_leader" or why == "busy", why)
    for _, c in pairs(cs) do eq(c.M.lootChanged, nil) end
  end)

  it("no answer (no StackRivals) is shown as such; the leader can start with those who joined", function()
    local net, cs = party(15, { "Lead", "Ann", "Ben" }, { Ben = { beforeLogin = function(_, _, ns) ns.LootDuel.init = function() end end } })
    LD(cs.Lead).create(19019, "l060", { "Ann-Realm", "Ben-Realm", "Lead-Realm" }); net.step(60)
    LD(cs.Ann).answer(true); net.step(60 * 65)
    cs.Lead.env.SlashCmdList.STACKRIVALS("")
    cs.Lead.ns.UI:ShowSheet("loot")
    local found
    for _, row in ipairs(cs.Lead.ns.UI.lootSheet.rows) do
      if row:IsShown() and (row.status:GetText() or ""):find("no StackRivals", 1, true) then found = true end
    end
    ok(found, "Ben: no answer -> /roll instead")
    ok(LD(cs.Lead).start(), "Lead + Ann can race")
  end)

  it("the start can't change the list: a start that doesn't match the accepted list is refused", function()
    local net, cs = party(16, { "Lead", "Ann", "Ben" })
    LD(cs.Lead).create(19019, "l060", { "Ann-Realm", "Ben-Realm" }); net.step(60)
    LD(cs.Ann).answer(true); net.step(60)
    local d = LD(cs.Ann).current
    -- a start naming Ann plus an uninvited player, with a hash that matches that list
    local mal = "0123456789abcdef"
    local entries = { { name = "Ann-Realm", commit = d.myCommit }, { name = "Mal-Realm", commit = mal } }
    local hash = LD(cs.Ann).listHash(d.lid, d.rs, d.itemId, entries)
    net.inject(cs.Ann, "Lead-Realm", P.encode("LDP", d.lid, 1, 1, P.hexName("Ann-Realm") .. "-" .. d.myCommit .. "," .. P.hexName("Mal-Realm") .. "-" .. mal), "PARTY")
    net.inject(cs.Ann, "Lead-Realm", P.encode("LDS", d.lid, hash, 2), "PARTY")
    net.step(10)
    eq(LD(cs.Ann).current.state, "cancelled")
    ok(LD(cs.Ann).current.endReason:find("bad_start"), LD(cs.Ann).current.endReason)
    eq(cs.Ann.ns.App.session, nil, "no run started")
  end)

  it("a player in a duel can't join (answered as a pass)", function()
    local net, cs = party(17, { "Lead", "Ann", "Ben" })
    cs.Ann.ns.Duel.challenge("Ben-Realm", "b120"); net.step(60); cs.Ben.ns.Duel.accept(); net.step(60)
    LD(cs.Lead).create(19019, "l060", { "Ann-Realm", "Ben-Realm" }); net.step(60)
    LD(cs.Ann).answer(true); net.step(60)
    eq(LD(cs.Lead).current.answers["ann-realm"].accept, false)
  end)

  -- regression tests for the independent review of Loot Duel (0.7.0)
  local function joined(seed, names)
    local net, cs = party(seed, names)
    local others = {}
    for i = 2, #names do others[#others + 1] = names[i] .. "-Realm" end
    ok(LD(cs[names[1]]).create(19019, "l060", others)); net.step(60)
    for i = 2, #names do LD(cs[names[i]]).answer(true) end
    net.step(120)
    return net, cs
  end

  it("R1 commit-reveal: nobody knows the seed before every share is in; a swapped share is refused", function()
    local net, cs = joined(30, { "Lead", "Ann", "Ben" })
    local L = LD(cs.Lead).current
    ok(LD(cs.Lead).start()); net.step(2)
    -- after the list is fixed but before the reveals arrive, nobody has a seed
    eq(LD(cs.Ann).current.seed, nil)
    net.step(240)
    local seed = L.seed
    ok(seed and LD(cs.Ann).current.seed == seed and LD(cs.Ben).current.seed == seed, "same seed once everything is revealed")
    -- a modified leader swaps Ben's share in the list after Ben joined: Ann (who saw Ben's answer) refuses
    local net2, cs2 = joined(31, { "Lead", "Ann", "Ben" })
    local d = LD(cs2.Ann).current
    local entries = {}
    for _, p in ipairs(LD(cs2.Lead).accepted(LD(cs2.Lead).current)) do
      entries[#entries + 1] = { name = p.name, commit = (p.name == "Ben-Realm") and "ffffffffffffffff" or p.commit }
    end
    local items = {}
    for _, e in ipairs(entries) do items[#items + 1] = P.hexName(e.name) .. "-" .. e.commit end
    net2.inject(cs2.Ann, "Lead-Realm", P.encode("LDP", d.lid, 1, 1, table.concat(items, ",")), "PARTY")
    net2.inject(cs2.Ann, "Lead-Realm", P.encode("LDS", d.lid, LD(cs2.Ann).listHash(d.lid, d.rs, d.itemId, entries), 2), "PARTY")
    net2.step(5)
    eq(LD(cs2.Ann).current.state, "cancelled"); eq(LD(cs2.Ann).current.endReason, "bad_start_commit_swap")
  end)

  it("R1b a player who joined but was left out of the list is told so", function()
    local net, cs = joined(32, { "Lead", "Ann", "Ben", "Cid" })
    local d = LD(cs.Cid).current
    local list = {}
    for _, p in ipairs(LD(cs.Lead).accepted(LD(cs.Lead).current)) do if p.name ~= "Cid-Realm" then list[#list + 1] = p end end
    local items = {}
    for _, e in ipairs(list) do items[#items + 1] = P.hexName(e.name) .. "-" .. e.commit end
    net.inject(cs.Cid, "Lead-Realm", P.encode("LDP", d.lid, 1, 1, table.concat(items, ",")), "PARTY")
    net.inject(cs.Cid, "Lead-Realm", P.encode("LDS", d.lid, LD(cs.Cid).listHash(d.lid, d.rs, d.itemId, list), #list), "PARTY")
    net.step(5)
    ok(LD(cs.Cid).current.leftOut, "Cid sees that he was left out")
    eq(LD(cs.Cid).busy(), false, "and is free again")
  end)

  it("R1c a missing reveal cancels the whole race (no re-roll by leaving someone out)", function()
    local net, cs = joined(33, { "Lead", "Ann", "Ben" })
    cs.Ben.online = false
    ok(LD(cs.Lead).start())
    net.step(60 * 30)
    eq(LD(cs.Lead).current.state, "cancelled"); eq(LD(cs.Lead).current.endReason, "noreveal")
    eq(LD(cs.Ann).current.state, "cancelled")
    eq(cs.Ann.ns.App.session, nil, "nobody raced")
  end)

  it("R2 the leader can't start after the invite expired (members stopped waiting)", function()
    local net, cs = joined(34, { "Lead", "Ann", "Ben" })
    net.step(60 * 80) -- past START_LIMIT after the offer
    local okS, why = LD(cs.Lead).start()
    ok(not okS); eq(why, "expired")
  end)

  it("R3 the last finisher gets the result at once, and agrees with the leader", function()
    local net, cs = joined(35, { "Lead", "Ann", "Ben" })
    LD(cs.Lead).start(); net.step(240)
    -- Ben plays on a little longer than Ann
    raceToEnd(net, cs, { Ben = true })
    local s = cs.Ben.ns.App.session
    for _ = 1, 400 do if s.recorded then break end; if s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end; net.step(1) end
    net.step(60 * 3)
    eq(LD(cs.Ben).current.state, "done", "Ben's PC finished right after his own run")
    net.step(60 * 15)
    eq(LD(cs.Ben).history[1].agreement, "agreed")
  end)

  it("R4 a low frame rate doesn't slow the race down (real-time stepping)", function()
    local net, cs = joined(36, { "Lead", "Ann", "Ben" })
    cs.Ann.frameDt = 1 / 5
    LD(cs.Lead).start(); net.step(60 * 5)
    local t0a, t0b = cs.Ann.ns.App.session.state.tick, cs.Ben.ns.App.session.state.tick
    net.step(60 * 20)
    local da, db = cs.Ann.ns.App.session.state.tick - t0a, cs.Ben.ns.App.session.state.tick - t0b
    ok(math.abs(da - db) <= 15, "Ann at 5 fps: " .. da .. " ticks, Ben: " .. db)
  end)

  it("R5 a running Loot Duel is busy: no duels, no Quickplay, no solo start, and invites are declined", function()
    local net, cs = joined(37, { "Lead", "Ann", "Ben" })
    eq(LD(cs.Ann).busy(), true, "joined = busy")
    local okC, why = cs.Ann.ns.Duel.challenge("Ben-Realm", "b120"); ok(not okC); eq(why, "loot")
    LD(cs.Lead).start(); net.step(240)
    cs.Lead.ns.Duel.challenge("Ann-Realm", "b120"); net.step(60)
    eq(cs.Ann.ns.Duel.current, nil, "Ann's addon declined as busy")
    ok(not cs.Ann.ns.Quickplay.start("b120"))
    local loot = cs.Ann.ns.App.session
    cs.Ann.ns.App:Start("classic")
    eq(cs.Ann.ns.App.session, loot, "the loot run wasn't thrown away")
  end)

  it("R6 a log with inhuman input (6 hard drops in one tick) is rejected", function()
    local net, cs = joined(38, { "Lead", "Ann", "Ben" })
    LD(cs.Lead).start(); net.step(240)
    local d = LD(cs.Lead).current
    local E = cs.Lead.ns.Engine
    local log = { 10, 5, 10, 5, 10, 5, 10, 5, 10, 5, 10, 5 }
    local st = E.replay(d.seed, { startLevel = 1 }, log, 100)
    local packed = P.packLog(log)
    net.inject(cs.Lead, "Ben-Realm", P.encode("LDE", d.lid, P.b36(100), P.b36(st.score), P.b36(st.lines), P.b36(st.level), E.hashState(st), 1), "PARTY")
    net.inject(cs.Lead, "Ben-Realm", P.encode("LDL", d.lid, 1, 1, packed), "PARTY")
    net.step(2)
    local r = d.results["ben-realm"]
    eq(r.status, "rejected"); eq(r.why, "inhuman_input_rate")
  end)

  it("R7 a leader who /reloads during the invite can offer again; the group sees the new one", function()
    local net, cs = party(39, { "Lead", "Ann", "Ben" })
    LD(cs.Lead).create(19019, "l060", { "Ann-Realm", "Ben-Realm" }); net.step(60)
    LD(cs.Ann).answer(true); net.step(30)
    local lead = net.reload(cs.Lead) -- logout tells the group; the old invite is gone
    net.step(60)
    eq(LD(cs.Ann).current.state, "cancelled")
    ok(lead.ns.LootDuel.create(19019, "l060", { "Ann-Realm", "Ben-Realm" })); net.step(60)
    eq(LD(cs.Ann).current.lid, lead.ns.LootDuel.current.lid)
    -- even without the goodbye (a crash): the same leader's new offer replaces the open one
    local net2, cs2 = party(40, { "Lead", "Ann", "Ben" })
    LD(cs2.Lead).create(19019, "l060", { "Ann-Realm", "Ben-Realm" }); net2.step(60)
    LD(cs2.Lead).current = nil
    ok(LD(cs2.Lead).create(17076, "l060", { "Ann-Realm", "Ben-Realm" })); net2.step(60)
    eq(LD(cs2.Ann).current.itemId, 17076)
  end)

  it("R8 pauses are limited: past the budget the run ends where it is (and still counts)", function()
    local net, cs = joined(41, { "Lead", "Ann", "Ben" })
    LD(cs.Lead).start(); net.step(60 * 6)
    local s = cs.Ann.ns.App.session
    s:pause("manual")
    net.step(60 * (cs.Ann.ns.LootDuel.PAUSE_BUDGET + 3))
    ok(s.recorded, "Ann's run ended at the pause limit")
    ok(LD(cs.Ann).current.pauseLimit)
    raceToEnd(net, cs)
    local ann
    for _, r in ipairs(LD(cs.Lead).current.standings) do if r.name == "Ann-Realm" then ann = r end end
    eq(ann.status, "verified")
  end)

  it("R9 out of order, duplicated and 5% lost messages: the same winner everywhere", function()
    local net, cs = party(42, { "Lead", "Ann", "Ben", "Cid" }, nil, { latency = { 0.05, 2.5 }, dup = 0.2, drop = 0.05 })
    ok(LD(cs.Lead).create(19019, "l060", { "Ann-Realm", "Ben-Realm", "Cid-Realm" })); net.step(60 * 15)
    for _, n in ipairs({ "Ann", "Ben", "Cid" }) do LD(cs[n]).answer(true) end
    net.step(60 * 15)
    ok(LD(cs.Lead).start())
    raceToEnd(net, cs)
    net.step(60 * 30)
    local w
    for _, n in ipairs({ "Lead", "Ann", "Ben", "Cid" }) do
      local d = LD(cs[n]).history[1]
      ok(d, n .. " has a result")
      w = w or (d.winner or "tie")
      eq(d.winner or "tie", w, n)
    end
  end)

  it("the sheet: pick players, invite, join from the popup, start, result banner, announce only on click", function()
    local net, cs = party(18, { "Lead", "Ann", "Ben" })
    local UI = cs.Lead.ns.UI
    cs.Lead.env.SlashCmdList.STACKRIVALS("")
    UI.lootBtn:Click()
    local s = UI.lootSheet
    ok(s:IsShown())
    s.input:SetText("|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"); s.setItem:Click()
    ok(s.item.name:GetText():find("Thunderfury", 1, true))
    for _, row in ipairs(s.rows) do
      if row:IsShown() and ((row.name:GetText() or ""):find("Ann", 1, true) or (row.name:GetText() or ""):find("Ben", 1, true)) then row:Click() end
    end
    eq(s.go.fs:GetText(), "Invite 2")
    s.go:Click(); net.step(60)
    cs.Ann.ns.UI.lootPopup.acc:Click(); cs.Ben.ns.UI.lootPopup.acc:Click(); net.step(120)
    UI:RefreshLootDuel()
    eq(s.go.fs:GetText(), "Start (2)")
    s.go:Click(); net.step(240)
    raceToEnd(net, cs)
    UI:ShowSheet("loot")
    local b = s.banner:GetText() or ""
    ok(b:find("WINNER", 1, true) or b:find("TIE", 1, true), b)
    eq(cs.Lead.M.chat[1], nil)
    s.announce:Click()
    ok(cs.Lead.M.chat[1] and cs.Lead.M.chat[1][2] == "PARTY" and cs.Lead.M.chat[1][1]:find("Loot Duel", 1, true), "posted once, by click")
  end)
end)

return H
