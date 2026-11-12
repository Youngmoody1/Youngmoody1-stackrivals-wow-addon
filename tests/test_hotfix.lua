-- 0.9.0.1 security hotfix: every result-changing scenario of the November 2026 audit, as a regression test.
-- Several COMPLETE addon instances on a simulated bus (tests/netsim.lua): proof of the logic, not of a real
-- WoW client. The attacks need no modified addon: net.inject is what a "/run C_ChatInfo.SendAddonMessage(...)"
-- macro does.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local function LD(c) return c.ns.LootDuel end
local function drop(c, f) -- a weak player: one hard drop every third of a second
  local s = c.ns.App.session
  if s and (s.loot or s.duel) and s.phase == "playing" and f % 20 == 0 then s:press("hardDrop"); s:release("hardDrop") end
end

--- A 3-player Loot Duel (Lead, Ann, Ben): Ann plays well, the others drop pieces. opts.each(f, cs, net, d).
local function lootRace(opts)
  opts = opts or {}
  local net = NS.new({ seed = opts.seed or 21 })
  local cs = {}
  for i, n in ipairs({ "Lead", "Ann", "Ben" }) do cs[n] = net.add({ name = n, group = "P", lead = (i == 1), saved = { seenHelp = true } }) end
  net.step(30)
  assert(LD(cs.Lead).create(19019, "l060", { "Lead-Realm", "Ann-Realm", "Ben-Realm" }))
  net.step(60)
  LD(cs.Ann).answer(true); LD(cs.Ben).answer(true); net.step(120)
  assert(LD(cs.Lead).start())
  net.step(60 * 8)
  if opts.before then opts.before(cs, net) end
  local ann = NS.autoplay(cs.Ann, "fast")
  for f = 1, 60 * 60 * 6 do
    ann(); drop(cs.Lead, f); drop(cs.Ben, f)
    if opts.each then opts.each(f, cs, net, LD(cs.Lead).current) end
    net.step(1)
    local all = true
    for _, c in pairs(cs) do if c.online and LD(c).current.state ~= "done" then all = false end end
    if all then break end
  end
  net.step(60 * 20)
  return cs, net
end
local function winnerOf(c) return LD(c).current.winner end

local function duelPair(opts)
  local net = NS.new(opts)
  local a = net.add({ name = "Alice", guild = "G", group = "P", lead = true, saved = { seenHelp = true } })
  local b = net.add({ name = "Bob", guild = "G", saved = { seenHelp = true } })
  local c = net.add({ name = "Carl", group = "P", saved = { seenHelp = true } }) -- Alice's party: she has a group channel
  net.step(30)
  assert(a.ns.Duel.challenge("Bob", opts.rs or "b120"))
  for _ = 1, 80 do net.step(15); local m = b.ns.Duel.current; if m and m.state == "invited" then break end end
  b.ns.UI.invite.acc:Click()
  for _ = 1, 80 do net.step(15); if a.ns.Duel.current.state == "lobby" then break end end
  a.ns.UI.lobby.ready:Click(); b.ns.UI.lobby.ready:Click()
  for _ = 1, 80 do net.step(15); local sa, sb = a.ns.App.session, b.ns.App.session; if sa and sb and sa.duel and sb.duel then break end end
  assert(a.ns.App.session and a.ns.App.session.duel and b.ns.App.session and b.ns.App.session.duel, "both runs started")
  return net, a, b, c
end

describe("hotfix 0.9.0.1: message spam can't change a result", function()
  it("baseline: a normal Loot Duel - the best player wins on every PC, and all agree", function()
    local cs = lootRace()
    for _, n in ipairs({ "Lead", "Ann", "Ben" }) do eq(winnerOf(cs[n]), "Ann-Realm", n) end
    eq(LD(cs.Ann).current.agreement, "agreed"); eq(LD(cs.Ben).current.agreement, "agreed")
    eq(LD(cs.Lead).current.unconfirmed, nil)
  end)
  it("Loot Duel: comm-test pings whispered at the best player (4 per second) don't touch the result", function()
    local pings = 0
    local cs = lootRace({ each = function(f, cs, net, d)
      if d.state == "playing" and net.time - d.startAt > 43 and f % 15 == 0 then
        pings = pings + 1
        net.inject(cs.Ann, "Ben-Realm", cs.Ann.ns.Protocol.encode("CTP", string.format("x%05d", pings)), "WHISPER")
      end
    end })
    ok(pings > 50, "the attack ran: " .. pings .. " pings")
    for _, n in ipairs({ "Lead", "Ann", "Ben" }) do eq(winnerOf(cs[n]), "Ann-Realm", n) end
    eq(cs.Ann.ns.Comm.stats.dropped, 0, "nothing of Ann's was dropped")
  end)
  it("Loot Duel: a malicious GROUP MEMBER pinging over the group channel (10 per second) can't do it either", function()
    local pings = 0
    local cs = lootRace({ each = function(f, cs, net, d)
      if d.state == "playing" and net.time - d.startAt > 30 and f % 6 == 0 then
        pings = pings + 1
        local msg = cs.Ann.ns.Protocol.encode("CTP", string.format("y%05d", pings))
        net.inject(cs.Ann, "Ben-Realm", msg, "PARTY"); net.inject(cs.Lead, "Ben-Realm", msg, "PARTY")
      end
    end })
    ok(pings > 200, pings .. " pings")
    for _, n in ipairs({ "Lead", "Ann", "Ben" }) do eq(winnerOf(cs[n]), "Ann-Realm", n) end
    ok(cs.Ann.ns.Comm.stats.maxQueue < 32, "Ann's queue stayed short: " .. cs.Ann.ns.Comm.stats.maxQueue)
    eq(cs.Ann.ns.Comm.stats.dropped, 0)
  end)
  it("the answer limit is global and tiny: any number of senders together get one low-priority answer per 5 s", function()
    local net = NS.new({ seed = 2 })
    local cs = {}
    for i = 1, 8 do cs[i] = net.add({ name = "P" .. i, group = "R", lead = (i == 1), saved = { seenHelp = true } }) end
    net.step(30)
    local v = cs[1]
    local sent0 = v.ns.Comm.stats.sent
    for round = 1, 60 do -- 6 s: seven members ping ten times a second with fresh ids
      for i = 2, 8 do net.inject(v, "P" .. i .. "-Realm", v.ns.Protocol.encode("CTP", string.format("%d%05d", i, round)), "RAID") end
      ok(#v.ns.Comm.queue <= 1, "queue " .. #v.ns.Comm.queue)
      net.step(6)
    end
    ok(v.ns.Comm.stats.sent - sent0 <= 3, "answers in 6 s: " .. (v.ns.Comm.stats.sent - sent0))
    -- pings from outside the group, or whispered, get nothing at all
    net.step(60 * 6)
    local s1 = v.ns.Comm.stats.sent
    net.inject(v, "Stranger-Realm", v.ns.Protocol.encode("CTP", "s00001"), "RAID")
    net.inject(v, "P2-Realm", v.ns.Protocol.encode("CTP", "w00001"), "WHISPER")
    net.step(60)
    eq(v.ns.Comm.stats.sent, s1)
  end)
  it("a duel: pings at the winner don't turn her win into 'rival sent no log'", function()
    local net, a, b = duelPair({ seed = 31 })
    local fa = NS.autoplay(a, "fast")
    local pings, tDone = 0, nil
    for f = 1, 60 * 60 * 9 do
      fa(); drop(b, f)
      local mb = b.ns.Duel.current
      if mb and (mb.state == "playing" or mb.state == "waiting") and net.time - mb.goAt > 60 and f % 15 == 0 then
        pings = pings + 1
        net.inject(a, "Bob-Realm", a.ns.Protocol.encode("CTP", string.format("x%05d", pings)), "WHISPER")
      end
      net.step(1)
      if a.ns.Duel.current.state == "done" and mb.state == "done" then tDone = tDone or f; if f - tDone > 60 * 40 then break end end
    end
    ok(pings > 100, pings .. " pings")
    local ma, mb = a.ns.Duel.current, b.ns.Duel.current
    eq(ma.outcome, "win"); eq(mb.outcome, "loss")
    eq(mb.endReason, "checked", "Bob's PC replayed Alice's run")
    eq(ma.agreement, "agreed"); eq(mb.agreement, "agreed")
    eq(a.ns.db.duels.wins, 1); eq(b.ns.db.duels.losses, 1)
  end)
  it("the real comm test still works: every group member answers once", function()
    local net = NS.new({ seed = 4 })
    local cs = {}
    for i, n in ipairs({ "Lead", "Ann", "Ben", "Cid" }) do cs[n] = net.add({ name = n, group = "P", lead = (i == 1), saved = { seenHelp = true } }) end
    net.step(60 * 6)
    cs.Lead.env.SlashCmdList.STACKRIVALS("commtest"); net.step(60 * 5)
    eq(cs.Lead.ns.Report.cur.answers, 3)
    -- and again a little later (a new test id is answered again)
    net.step(60 * 6)
    cs.Ann.env.SlashCmdList.STACKRIVALS("commtest"); net.step(60 * 5)
    eq(cs.Ann.ns.Report.cur.answers, 3)
  end)
end)

describe("hotfix 0.9.0.1: a result that can't be checked is never shown as a confirmed winner", function()
  it("missing replay parts on EVERY PC: no winner is named, the sheet and the chat line say UNVERIFIED", function()
    local cs, net = lootRace({ before = function(cs, net)
      -- Ann's log never arrives anywhere (her claim does)
      net.dropIf = function(to, from, text) return from.name == "Ann-Realm" and text:match("^1:LDL:") ~= nil end
    end })
    for _, n in ipairs({ "Lead", "Ben" }) do
      local d = LD(cs[n]).current
      eq(d.winner, nil, n .. ": the next best run is NOT the winner")
      ok(d.unconfirmed and d.unconfirmed.name == "Ann-Realm", n .. ": says whose run is missing")
    end
    eq(LD(cs.Ben).current.agreement, "agreed", "all PCs agree that there is no confirmed winner")
    local ui = cs.Lead.ns.UI
    cs.Lead.M.chat = {}
    ui:AnnounceLoot()
    local msg = cs.Lead.M.chat[1] and cs.Lead.M.chat[1][1] or ""
    ok(msg:find("UNVERIFIED", 1, true) and not msg:find(" wins ", 1, true), msg)
    cs.Lead.env.SlashCmdList.STACKRIVALS(""); ui:ShowSheet("loot"); ui:RefreshLootDuel()
    eq(ui.lootSheet.final.big:GetText(), "UNVERIFIED")
  end)
  it("a missing log of a run that couldn't have won changes nothing", function()
    local cs = lootRace({ before = function(cs, net)
      net.dropIf = function(to, from, text) return from.name == "Ben-Realm" and text:match("^1:LDL:") ~= nil end
    end })
    eq(winnerOf(cs.Lead), "Ann-Realm"); eq(LD(cs.Lead).current.unconfirmed, nil)
  end)
  it("disagreeing PCs: the PC that missed the best run shows DISPUTED and never announces a winner", function()
    local cs = lootRace({ before = function(cs, net)
      net.dropIf = function(to, from, text) return to.name == "Ben-Realm" and from.name == "Ann-Realm" and text:match("^1:LDL:") ~= nil end
    end })
    eq(winnerOf(cs.Lead), "Ann-Realm")
    local d = LD(cs.Ben).current
    eq(d.winner, nil); eq(d.agreement, "disputed")
    cs.Ben.M.chat = {}
    cs.Ben.ns.UI:AnnounceLoot()
    local msg = cs.Ben.M.chat[1] and cs.Ben.M.chat[1][1] or ""
    ok(msg:find("DISPUTED", 1, true) and not msg:find(" wins ", 1, true), msg)
    -- the leader's own announcement doesn't over-claim either
    cs.Lead.M.chat = {}
    cs.Lead.ns.UI:AnnounceLoot()
    msg = cs.Lead.M.chat[1][1]
    ok(msg:find("Ann wins", 1, true) and not msg:find("Every PC", 1, true), msg)
  end)
  it("delayed messages (2-6 s latency, 10 % loss, duplicates): same winner everywhere", function()
    local cs = lootRace({ seed = 5, before = function(cs, net) net.latency, net.drop, net.dup = { 2, 6 }, 0.10, 0.10 end })
    for _, n in ipairs({ "Lead", "Ann", "Ben" }) do eq(winnerOf(cs[n]), "Ann-Realm", n) end
  end)
  it("a disconnect during the result exchange: the run that was sent is checked; no invented winner", function()
    local cut
    local cs = lootRace({ each = function(f, cs, net, d)
      -- Ben's PC goes offline two seconds after the race ended, while results are still coming in
      if not cut and d.state == "playing" and net.time > d.deadline + 2 then cut = true; cs.Ben.online = false end
    end })
    for _, n in ipairs({ "Lead", "Ann" }) do
      local d = LD(cs[n]).current
      eq(d.state, "done", n)
      ok(d.winner == "Ann-Realm" or d.winner == nil, n .. ": " .. tostring(d.winner))
      ok(d.winner ~= "Ben-Realm" and d.winner ~= "Lead-Realm")
    end
    eq(winnerOf(cs.Lead), winnerOf(cs.Ann))
  end)
end)

describe("hotfix 0.9.0.1: Quickplay and the log wait", function()
  it("nobody can push a 'Quickplay match' on a player who isn't searching; no per-frame Lua error afterwards", function()
    local net = NS.new({ seed = 9 })
    local v = net.add({ name = "Victim", saved = { seenHelp = true } })
    net.step(30)
    local P, D, QP = v.ns.Protocol, v.ns.Duel, v.ns.Quickplay
    local eng = v.ns.Engine.ENGINE_VERSION
    net.inject(v, "Gone-Realm", P.encode("INV", "grief1", "b120", eng, "abcd1234")); net.step(6)
    net.inject(v, "Gone-Realm", P.encode("DEC", "grief1", "cancel")); net.step(6)
    net.inject(v, "Gtwo-Realm", P.encode("INV", "grief1", "b120", eng, "abcd1234", "q")); net.step(6)
    ok(not (D.current and D.current.state == "lobby"), "no forced lobby")
    ok(QP.state ~= "matched", QP.state)
    net.inject(v, "Gtwo-Realm", P.encode("DEC", "grief1", "cancel"))
    local errors = 0
    for _ = 1, 600 do if not pcall(net.step, 1) then errors = errors + 1 end end
    eq(errors, 0)
    -- even from the broken state itself, the frame loop survives
    QP.state, QP.started = "searching", nil
    for _ = 1, 120 do net.step(1) end
    ok(QP.state ~= "searching", QP.state)
  end)
  it("normal Quickplay still matches two searching players", function()
    local net = NS.new({ seed = 12 })
    local a = net.add({ name = "Alice", guild = "G", saved = { seenHelp = true } })
    local b = net.add({ name = "Bob", guild = "G", saved = { seenHelp = true } })
    net.step(30)
    ok(a.ns.Quickplay.start("b120")); ok(b.ns.Quickplay.start("b120"))
    for _ = 1, 60 * 20 do net.step(1); if a.ns.Quickplay.state == "matched" and b.ns.Quickplay.state == "matched" then break end end
    eq(a.ns.Quickplay.state, "matched"); eq(b.ns.Quickplay.state, "matched")
    ok(a.ns.Duel.current and b.ns.Duel.current and a.ns.Duel.current.mid == b.ns.Duel.current.mid)
  end)
  it("inside an instance, a long honest log is waited for: the real winner wins (was: forfeited after 60 s)", function()
    local net, a, b = duelPair({ seed = 5, instance = true, rs = "r180" })
    local fa = NS.autoplay(a, "fast")
    -- Bob holds soft drop all game (30 logged inputs per second) and steers: a very long, valid log
    local fbase = NS.autoplay(b, "fast")
    local orig = b.ns.UI.keys:GetScript("OnKeyDown")
    b.ns.UI.keys:SetScript("OnKeyDown", function(self, key) if key ~= "SPACE" then orig(self, key) end end)
    local pressed
    local tDone
    for i = 1, 60 * 60 * 9 do
      local s = b.ns.App.session
      if s and s.phase == "playing" and pressed ~= s then s:press("softDrop"); pressed = s end
      fa(); fbase(); net.step(1)
      local ma, mb = a.ns.Duel.current, b.ns.Duel.current
      if ma.state == "done" and mb.state == "done" then tDone = tDone or i; if i - tDone > 60 * 45 then break end end
    end
    local ma, mb = a.ns.Duel.current, b.ns.Duel.current
    ok(mb.outChunks and #mb.outChunks > 45, "Bob's log is long: " .. tostring(mb.outChunks and #mb.outChunks) .. " chunks")
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked")
    ok((ma.outcome == "win" and mb.outcome == "loss") or (ma.outcome == "loss" and mb.outcome == "win"), ma.outcome .. " / " .. mb.outcome)
    eq(ma.agreement, "agreed"); eq(mb.agreement, "agreed")
  end)
  it("a log that never completes still ends the match (hard cap), as DISPUTED and uncounted - not as a clean win", function()
    local net, a, b = duelPair({ seed = 11 })
    net.step(60 * 5)
    local m = a.ns.Duel.current
    a.ns.App.session:finish("time"); b.ns.App.session:finish("time")
    net.dropIf = function(to, from, text) return from.name == "Bob-Realm" and text:match("^1:LOG:") ~= nil end
    for _ = 1, 60 * 200 do net.step(1); if m.state == "done" then break end end
    eq(m.state, "done"); eq(m.endReason, "rival_no_log")
    net.step(60 * 40)
    ok(m.agreement ~= "agreed", tostring(m.agreement))
    eq(a.ns.db.duels.wins, 0, "not counted as a win")
  end)
end)

return H
