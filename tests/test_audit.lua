-- 0.9.1 quality audit (Nov 2026): one regression test per confirmed finding. Simulated clients (tests/netsim.lua):
-- these prove the logic, not behaviour in a real WoW client.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local function solo(seed)
  local net = NS.new({ seed = seed or 1 })
  local c = net.add({ name = "Alice", saved = { seenHelp = true } })
  return net, c, c.ns
end
local function kd(c, k) c.ns.UI.keys:GetScript("OnKeyDown")(c.ns.UI.keys, k) end
local function ku(c, k) c.ns.UI.keys:GetScript("OnKeyUp")(c.ns.UI.keys, k) end
local function key(c, k) kd(c, k); ku(c, k) end
local function sounds(c) local out = {} for _, p in ipairs(c.M.sounds) do out[#out + 1] = p:match("([%w]+)%.ogg$") end return out end
local function count(list, name) local n = 0 for _, x in ipairs(list) do if x == name then n = n + 1 end end return n end

local function pair(seed)
  local net = NS.new({ seed = seed or 7 })
  local a = net.add({ name = "Alice", guild = "G", saved = { seenHelp = true } })
  local b = net.add({ name = "Bob", guild = "G", saved = { seenHelp = true } })
  return net, a, b
end
local function startDuel(net, a, b, rs)
  assert(a.ns.Duel.challenge("Bob", rs or "b120"))
  for _ = 1, 80 do net.step(15); local m = b.ns.Duel.current; if m and m.state == "invited" then break end end
  b.ns.UI.invite.acc:Click()
  for _ = 1, 80 do net.step(15); if a.ns.Duel.current.state == "lobby" then break end end
  a.ns.UI.lobby.ready:Click(); b.ns.UI.lobby.ready:Click()
  for _ = 1, 80 do net.step(15); local sa, sb = a.ns.App.session, b.ns.App.session; if sa and sb and sa.duel and sb.duel then break end end
  assert(a.ns.App.session and a.ns.App.session.duel and b.ns.App.session and b.ns.App.session.duel, "both runs started")
end

describe("audit: run lifecycle and keys", function()
  it("/sr spell during a solo run: the run goes to 'Continue last run', it is never orphaned", function()
    local net, c, ns = solo(1)
    c.env.SlashCmdList.STACKRIVALS("classic"); net.step(185)
    for _ = 1, 5 do key(c, "SPACE"); net.step(3) end
    local score = ns.App.session.state.score
    ok(score > 0)
    c.env.SlashCmdList.STACKRIVALS("spell")
    eq(ns.App.session, nil, "no hidden session behind the menu")
    ok(ns.db.suspended ~= nil, "saved for Continue")
    ns.UI.spellBack:Click()
    ok(ns.UI.continueBtn:IsShown(), "Continue is offered")
    ns.App:ContinueSuspended()
    eq(ns.App.session.state.score, score); eq(ns.App.session.phase, "paused")
  end)
  it("Quit to menu clears the landing preview's outline; nothing of it shows in the next run", function()
    local net, c, ns = solo(2)
    c.env.SlashCmdList.STACKRIVALS("classic"); net.step(185)
    local function outlined() local n = 0 for _, cell in ipairs(ns.UI.field.cells) do if cell.gl:IsShown() or cell.gr:IsShown() then n = n + 1 end end return n end
    ok(outlined() > 0, "a ghost is on the board while playing")
    ns.App:Pause("manual"); ns.App:Quit(); net.step(2)
    eq(outlined(), 0)
  end)
  it("a web challenge: Restart on the pause screen and the play-again key both restart that challenge", function()
    local net, c, ns = solo(3)
    local code = ns.Codes.challenge("b120", "00c0ffee")
    ok(ns.App:StartChallenge(code)); net.step(185)
    local first = ns.App.session
    ns.App:Pause("manual")
    ns.UI.restartBtn:Click()
    ok(ns.App.session ~= first and ns.App.session.challenge ~= nil, "restarted as the same challenge")
    eq(ns.App.session.seed, first.seed)
    net.step(185); ns.App.session:finish("time"); net.step(70)
    local over = ns.App.session
    kd(c, "SPACE")
    ok(ns.App.session ~= over and ns.App.session.challenge ~= nil, "Space after the result plays it again")
  end)
  it("a key that was down when the run paused isn't stuck: its next press works", function()
    local net, c, ns = solo(4)
    c.env.SlashCmdList.STACKRIVALS("classic"); net.step(185)
    kd(c, "LEFT")                 -- held
    kd(c, "ENTER")                -- chat opens: pause; the release goes to the chat box, not to us
    eq(ns.App.session.phase, "paused")
    eq(ns.UI.down.LEFT, nil, "not marked as held any more")
    ns.App:Resume()
    for _ = 1, 400 do net.step(1); if ns.App.session.phase == "playing" then break end end
    local x = ns.App.session.state.active.x
    kd(c, "LEFT"); net.step(2)
    ok(ns.App.session.state.active.x < x, "LEFT moved the piece: " .. x .. " -> " .. ns.App.session.state.active.x)
  end)
  it("the second after a duel ends: game keys are swallowed, not handed to WoW", function()
    local net, a, b = pair(5)
    startDuel(net, a, b)
    net.step(60 * 8)
    a.ns.App.session:finish("time"); net.step(1)
    eq(a.ns.UI.keys._kb, true)
    kd(a, "SPACE"); eq(a.ns.UI.keys._prop, false, "Space swallowed")
    net.step(70)
    eq(a.ns.UI.keys._kb, false, "after the grace second the keyboard is WoW's again (a duel needs a click)")
  end)
end)

describe("audit: feedback", function()
  it("a clear that reaches a new level keeps its callout; the level goes on the top line", function()
    local net, c, ns = solo(6)
    c.env.SlashCmdList.STACKRIVALS("classic"); net.step(185)
    local UI = ns.UI
    UI:OnEvent({ kind = "clear", a = 4, b = { lines = 4, points = 800, combo = 0, backToBack = true } })
    UI:OnEvent({ kind = "level", a = 3 })
    eq(UI.callout:GetText(), "QUAD")
    ok(UI.calloutTop:GetText():find("BACK-TO-BACK", 1, true) and UI.calloutTop:GetText():find("LEVEL 3", 1, true), UI.calloutTop:GetText())
    net.step(120)
    UI:OnEvent({ kind = "level", a = 4 }) -- a level-up on its own still gets its callout
    eq(UI.callout:GetText(), "LEVEL 4")
  end)
  it("one frame, one impact sound and one melodic sound: hard drop + clear + combo + level-up isn't four files", function()
    local net, c, ns = solo(7)
    c.env.SlashCmdList.STACKRIVALS("classic"); net.step(185)
    c.M.sounds = {}
    local s = ns.App.session
    s:emit("harddrop"); s:emit("clear", 1, { lines = 1, points = 100, combo = 2 }); s:emit("level", 2)
    net.step(1)
    local got = sounds(c)
    eq(#got, 1, table.concat(got, ","))
    eq(got[1], "levelup")
    c.M.sounds = {}
    s:emit("harddrop"); s:emit("lock"); net.step(1)
    got = sounds(c)
    eq(#got, 1, table.concat(got, ",")); eq(got[1], "harddrop")
  end)
  it("Spell Battle vs Bot: exactly one end sound (victory or defeat), never both", function()
    local net, c, ns = solo(8)
    c.env.SlashCmdList.STACKRIVALS("")
    ns.App:Start("spellbot"); net.step(241) -- 4 s countdown
    c.M.sounds = {}
    local sess = ns.App.session
    for _ = 1, 400 do
      if sess.phase ~= "playing" then break end
      sess:press("hardDrop"); net.step(1); sess:release("hardDrop")
    end
    for _ = 1, 600 do net.step(1); if sess.spell.result then break end end
    net.step(5)
    ok(ns.App.session.spell.result, "result in")
    local got = sounds(c)
    eq(count(got, "gameover") + count(got, "record"), 1, table.concat(got, ","))
    eq(count(got, sess.spell.result.outcome == "win" and "record" or "gameover"), 1, "the one that fits the result")
  end)
  it("effects of one run never play over the next: Restart right after a clear", function()
    local net, c, ns = solo(9)
    c.env.SlashCmdList.STACKRIVALS("classic"); net.step(185)
    ns.UI:OnEvent({ kind = "clear", a = 4, b = { lines = 4, points = 800, combo = 0 } })
    ok(ns.UI.field.flash:GetAlpha() > 0)
    ns.App:Pause("manual"); ns.UI.restartBtn:Click()
    eq(ns.UI.field.flash:GetAlpha(), 0)
    eq(ns.UI.calloutBox:GetAlpha(), 0)
  end)
  it("sound off means off: the window-open and invite sounds follow the setting", function()
    local net, c, ns = solo(10)
    local played = 0
    c.env.PlaySound = function() played = played + 1; return true end
    c.env.SOUNDKIT = c.env.SOUNDKIT or { IG_MAINMENU_OPEN = 850, READY_CHECK = 8960 }
    ns.Sound.enabled = false
    c.env.SlashCmdList.STACKRIVALS(""); net.step(2)
    net.inject(c, "Bob-Realm", ns.Protocol.encode("INV", "abc123", "b120", ns.Engine.ENGINE_VERSION, "abcd1234")); net.step(6)
    eq(played, 0)
  end)
end)

describe("audit: text", function()
  it("names outside Latin (Cyrillic, Hangul, CJK) are shown in WoW's own font, never in the Latin-only display font", function()
    local net, c, ns = solo(40)
    c.env.SlashCmdList.STACKRIVALS(""); net.step(2)
    local T = ns.T
    local fs = T.display(ns.UI.frame, 15)
    local own = fs:GetFont()
    fs:SetText("Alice"); eq(fs:GetFont(), own)
    fs:SetText("Søren"); eq(fs:GetFont(), own, "æøå are in the display font")
    fs:SetText("\208\144\208\187\208\184\209\129\208\176"); eq(fs:GetFont(), T.FONT, "Cyrillic")
    fs:SetText("\237\149\156\234\184\128"); eq(fs:GetFont(), T.FONT, "Hangul")
    fs:SetText("Bob"); eq(fs:GetFont(), own, "and back")
    -- a cut never splits a character
    eq(T.cut("\208\144\208\187\208\184", 3), "\208\144")
    eq(T.cut("abc\237\149\156", 5), "abc")
    eq(T.cut("abcdef", 4), "abcd"); eq(T.cut("ab", 4), "ab")
  end)
  it("the side panels (live standings, match chat) flip to the left when the right side is off screen", function()
    local net, c, ns = solo(42)
    c.env.SlashCmdList.STACKRIVALS(""); net.step(2)
    local UI, F = ns.UI, ns.UI.frame
    local p = c.env.CreateFrame("Frame", nil, F); p:SetSize(200, 300)
    local W = c.env.UIParent:GetWidth()
    F._left, F._right = (W - 500) / F:GetScale(), (W - 20) / F:GetScale() -- 20 units of room on the right
    UI:PlaceSidePanel(p); eq(p.sideLeft, true)
    F._left, F._right = 100 / F:GetScale(), 600 / F:GetScale()             -- plenty of room
    UI:PlaceSidePanel(p); eq(p.sideLeft, false)
    F._left, F._right = 10 / F:GetScale(), (W - 20) / F:GetScale()         -- no room on either side: stay right
    UI:PlaceSidePanel(p); eq(p.sideLeft, false)
  end)
  it("duel result: the explanation never runs behind the Rematch button; the agreement line always shows", function()
    local net, a, b = pair(41)
    startDuel(net, a, b)
    net.step(60 * 5); b.ns.Duel.leave(); net.step(60 * 3)
    a.ns.App.session:finish("time"); net.step(60 * 3)
    local m, UI = a.ns.Duel.current, a.ns.UI
    eq(m.state, "done")
    local L = dofile(testdir .. "/layout.lua")
    for _, case in ipairs({
      { endReason = "check_failed", check = { reasons = { "pause_limit" } }, agreement = "disputed", noClock = true, basis = "forfeit" },
      { endReason = "rival_no_log", agreement = "unconfirmed", basis = "forfeit" },
      { endReason = "checked", agreement = "agreed", basis = "replay" },
      { endReason = "timeout", agreement = "unconfirmed", noClock = true },
    }) do
      for k, v in pairs(case) do m[k] = v end
      UI:ShowDuelOver(m)
      local lines = L.textLines(UI.overDetail)
      ok(#lines <= 4, case.endReason .. ": " .. #lines .. " lines")
      local last = lines[#lines] or ""
      ok(#last > 0, "agreement line shown")
      m.noClock, m.check = nil, nil
    end
  end)
end)

describe("audit: multiplayer", function()
  it("comm-test pings can't fill another player's send queue (whispered, from outside the group, or repeated)", function()
    local net = NS.new({ seed = 21 })
    local lead = net.add({ name = "Lead", group = "P", lead = true, saved = { seenHelp = true } })
    local ann = net.add({ name = "Ann", group = "P", saved = { seenHelp = true } })
    net.step(30)
    local P = ann.ns.Protocol
    local before = ann.ns.Comm.stats.sent
    -- 200 whispered pings with fresh ids (the reported attack), and 200 over the group channel from a stranger
    for i = 1, 200 do
      net.inject(ann, "Lead-Realm", P.encode("CTP", string.format("x%05d", i)), "WHISPER")
      net.inject(ann, "Mallory-Realm", P.encode("CTP", string.format("y%05d", i)), "PARTY")
    end
    eq(#ann.ns.Comm.queue, 0, "nothing queued")
    -- from a real group member over the group channel: answered, but one answer per PING_GAP, low priority, one key
    for i = 1, 200 do net.inject(ann, "Lead-Realm", P.encode("CTP", string.format("z%05d", i)), "PARTY") end
    ok(#ann.ns.Comm.queue <= 1, "queue " .. #ann.ns.Comm.queue)
    net.step(120)
    ok(ann.ns.Comm.stats.sent - before <= 2, "answers sent: " .. (ann.ns.Comm.stats.sent - before))
    -- the real comm test still works
    net.step(60 * 6)
    lead.env.SlashCmdList.STACKRIVALS("commtest"); net.step(60 * 4)
    eq(lead.ns.Report.cur.answers, 1)
  end)
  it("nobody can push a 'Quickplay match' on a player who isn't searching, and Quickplay never errors per frame", function()
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
    -- and even from a broken state the frame loop survives
    QP.state, QP.started = "searching", nil
    for _ = 1, 120 do net.step(1) end
    ok(QP.state ~= "searching", "a search without a start time ends: " .. QP.state)
  end)
  it("the rival forfeits, then I leave too: I keep the win and both PCs agree", function()
    local net, a, b = pair(7)
    startDuel(net, a, b)
    net.step(60 * 10)
    b.ns.Duel.leave(); net.step(60 * 3)
    a.ns.Duel.leave(); net.step(60 * 40)
    local ma, mb = a.ns.Duel.current or a.ns.Duel.past, b.ns.Duel.current or b.ns.Duel.past
    eq(ma.endReason, "rival_forfeited"); eq(ma.outcome, "win")
    eq(mb.outcome, "loss")
    ok(ma.agreement ~= "disputed" and mb.agreement ~= "disputed", tostring(ma.agreement) .. " / " .. tostring(mb.agreement))
  end)
  it("invites right after a decline get a quiet 'busy', not another popup; challenging them clears it", function()
    local net = NS.new({ seed = 3 })
    local v = net.add({ name = "Victim", saved = { seenHelp = true } })
    net.step(30)
    local P = v.ns.Protocol
    local popups = 0
    v.ns.Duel.on("invite", function() popups = popups + 1 end)
    for i = 1, 40 do
      net.inject(v, "Griefer-Realm", P.encode("INV", string.format("m%05d", i), "b120", v.ns.Engine.ENGINE_VERSION, "abcd1234"))
      net.step(6)
      local m = v.ns.Duel.current
      if m and m.state == "invited" then v.ns.Duel.decline("no") end
      net.step(6)
    end
    eq(popups, 1)
    -- someone else is not affected
    net.inject(v, "Friend-Realm", P.encode("INV", "f00001", "b120", v.ns.Engine.ENGINE_VERSION, "abcd1234")); net.step(6)
    eq(popups, 2)
    v.ns.Duel.decline("no")
    -- the cooldown ends (30 s the first time)
    net.step(60 * 31)
    net.inject(v, "Griefer-Realm", P.encode("INV", "m99999", "b120", v.ns.Engine.ENGINE_VERSION, "abcd1234")); net.step(6)
    eq(popups, 3)
  end)
  it("a long log that is still arriving is not 'withheld': the wait counts from the last chunk, with a hard cap", function()
    local net, a, b = pair(11)
    startDuel(net, a, b)
    net.step(60 * 5)
    local m = a.ns.Duel.current
    a.ns.App.session:finish("time"); net.step(2)
    local D = a.ns.Duel
    -- Bob's END is in, 60 chunks announced, they keep arriving one every 20 s (slower than any real client)
    m.rivalEnd = m.rivalEnd or { ticks = 7200, score = 99999, lines = 1, level = 1, hash = "00000000", chunks = 60, at = net.time }
    m.rivalEnd.chunks, m.chunksN, m.chunks = 60, 60, {}
    b.online = false
    for i = 1, 4 do
      net.step(60 * 20)
      if m.state ~= "done" then m.chunks[i] = "x"; m.lastChunkIn = net.time end
    end
    ok(m.state ~= "done", "still waiting after 80 s while chunks arrive (was a forfeit at 60 s): " .. tostring(m.endReason))
    -- the hard cap (LOG_WAIT + 1.5 s per chunk = 150 s) ends it even if chunks keep trickling
    for i = 5, 12 do
      net.step(60 * 20)
      if m.state ~= "done" then m.chunks[i] = "x"; m.lastChunkIn = net.time end
    end
    eq(m.state, "done")
  end)
  it("Announce never posts a result this PC knows is disputed, and claims only what this PC checked", function()
    local net = NS.new({ seed = 31 })
    local cs = {}
    for i, n in ipairs({ "Lead", "Ann", "Ben" }) do cs[n] = net.add({ name = n, group = "P", lead = (i == 1), saved = { seenHelp = true } }) end
    net.step(30)
    local function LD(c) return c.ns.LootDuel end
    assert(LD(cs.Lead).create(19019, "l060", { "Lead-Realm", "Ann-Realm", "Ben-Realm" })); net.step(60)
    LD(cs.Ann).answer(true); LD(cs.Ben).answer(true); net.step(120)
    assert(LD(cs.Lead).start()); net.step(60 * 8)
    for f = 1, 60 * 60 * 4 do
      for _, c in pairs(cs) do
        local s = c.ns.App.session
        if s and s.loot and s.phase == "playing" and f % 20 == 0 then s:press("hardDrop"); s:release("hardDrop") end
      end
      net.step(1)
      local all = true
      for _, c in pairs(cs) do if LD(c).current.state ~= "done" then all = false end end
      if all then break end
    end
    local ben = cs.Ben
    local d = LD(ben).current
    eq(d.state, "done")
    local posted = {}
    ben.env.C_ChatInfo.SendChatMessage = function(msg, ch) posted[#posted + 1] = msg end
    ben.env.SendChatMessage = ben.env.C_ChatInfo.SendChatMessage
    ben.ns.UI:AnnounceLoot()
    ok(posted[1] and not posted[1]:find("Every PC replayed", 1, true), tostring(posted[1]))
    d.agreement = "disputed"
    ben.ns.UI:AnnounceLoot()
    ok(posted[2] and posted[2]:find("don't agree", 1, true) and not posted[2]:find(" wins ", 1, true), tostring(posted[2]))
  end)
  it("a finished duel's panels are cleared when a Loot Duel run starts", function()
    local net, a, b = pair(13)
    startDuel(net, a, b)
    net.step(60 * 5); b.ns.Duel.leave(); net.step(60 * 3)
    a.ns.App.session:finish("time"); net.step(60 * 3)
    ok(a.ns.Duel.current ~= nil and a.ns.Duel.current.state == "done")
    a.ns.App:StartLoot({ rs = "l060", seed = "00c0ffee" })
    eq(a.ns.Duel.current, nil)
  end)
end)

return H
