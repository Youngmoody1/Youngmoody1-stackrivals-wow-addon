-- Race My Best (Ghost Mode): Core/Ghost.lua + UI/GhostUI.lua. Complete addon instances in the mock client
-- (tests/netsim.lua): proof of the logic, not of a real WoW client.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local L = dofile(testdir .. "/layout.lua")
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local function client(seed, saved)
  local net = NS.new({ seed = seed or 1 })
  local c = net.add({ name = "Alice", saved = saved or { seenHelp = true } })
  net.step(2)
  return net, c, c.ns
end
local function kd(c, k) c.ns.UI.keys:GetScript("OnKeyDown")(c.ns.UI.keys, k) end
local function ku(c, k) c.ns.UI.keys:GetScript("OnKeyUp")(c.ns.UI.keys, k) end
local function sounds(c) local out = {} for _, p in ipairs(c.M.sounds) do out[#out + 1] = p:match("([%w]+)%.ogg$") end return out end
local function has(list, x) for _, v in ipairs(list) do if v == x then return true end end return false end

--- Play the current run to its end: style "weak" = a hard drop every 20 frames; "fast" = the test bot.
local function playOut(net, c, style, maxFrames)
  local bot = (style == "fast") and NS.autoplay(c, "fast") or nil
  for f = 1, maxFrames or 60 * 60 * 3 do
    local s = c.ns.App.session
    if not s or s.phase == "over" then break end
    if bot then bot() elseif s.phase == "playing" and f % 20 == 0 then kd(c, "SPACE"); ku(c, "SPACE") end
    net.step(1)
  end
  net.step(70)
end
--- A Time Trial best on record (weak or fast), through the real menu path.
local function blitzBest(net, c, style)
  c.env.SlashCmdList.STACKRIVALS("trial")
  playOut(net, c, style)
  local r = c.ns.db.records.blitz
  assert(r.best > 0 and r.bestLog, "a best with its log")
  return r
end

describe("Race My Best: the data", function()
  it("a saved best already holds everything a ghost needs: engine version, seed, start level, ticks, inputs", function()
    local net, c, ns = client(1)
    local r = blitzBest(net, c, "weak")
    local d = ns.Engine.deserializeLog(r.bestLog)
    eq(d.v, ns.Engine.ENGINE_VERSION); eq(d.startLevel, 1)
    ok(type(d.seed) == "string" and #d.seed > 0); ok(d.ticks > 0 and #d.log > 0)
    eq(ns.Engine.replay(d.seed, { startLevel = 1 }, d.log, d.ticks).score, r.best, "replays to the record's score")
  end)
  it("replay parity: the ghost advanced tick by tick (any frame sizes) equals Engine.replay at every point", function()
    local net, c, ns = client(2)
    local r = blitzBest(net, c, "fast")
    local G, E = ns.Ghost, ns.Engine
    local e = assert(G.source(ns.db, "blitz"))
    local d = assert(G.validate(e))
    local sess = { mode = ns.Session.MODES.ghost_blitz, state = { tick = 0, score = 0 } }
    G.attach(sess, e, d)
    local rnd, t, checks = 7, 0, 0
    while t < d.ticks do
      rnd = (rnd * 1103515245 + 12345) % 2147483648
      t = math.min(d.ticks, t + 1 + rnd % 90) -- 1..90 ticks per "frame" (a hitch, a slow PC)
      sess.state.tick = t
      local gs = G.update(sess)
      if checks < 40 or t == d.ticks then
        local ref = E.replay(d.seed, { startLevel = 1 }, d.log, t)
        eq(E.hashState(gs), E.hashState(ref), "tick " .. t)
        checks = checks + 1
      end
    end
    eq(sess.ghost.runner.s.score, r.best); eq(sess.ghost.runner.done, true)
  end)
  it("old or unusable records are never offered as a ghost (no log, other engine, other rules, edited score)", function()
    local net, c, ns = client(3)
    local r = blitzBest(net, c, "weak")
    local G = ns.Ghost
    local log, best = r.bestLog, r.best
    r.bestLog = nil
    local e, why = G.source(ns.db, "blitz"); eq(e, nil); eq(why, "no_log")
    r.bestLog = log:gsub("^%d+;", "9;", 1)
    e, why = G.source(ns.db, "blitz"); eq(e, nil); eq(why, "engine")
    r.bestLog = log:gsub("^(%d+;[^;]*;)%d+;", "%15;", 1)
    e, why = G.source(ns.db, "blitz"); eq(e, nil); eq(why, "rules")
    r.bestLog, r.best = log, best + 1 -- the file says a higher best than the run gives
    e = assert(G.source(ns.db, "blitz"))
    local d; d, why = G.validate(e); eq(d, nil); eq(why, "mismatch")
    eq(ns.App:StartGhost("blitz"), false, "not started")
    ok(not (ns.App.session and ns.App.session.mode.ghost))
    -- the menu: greyed, with the reason
    ns.UI:RefreshMenu()
    local b = ns.UI.modeButtons.blitz.race
    ok(b:IsShown() and not b:IsEnabled()); ok(b.tip:find("doesn't match", 1, true), b.tip)
    r.best = 0; r.bestLog = nil; ns.UI:RefreshMenu()
    ok(not b:IsShown(), "no record at all: no button")
  end)
end)

describe("Race My Best: the race", function()
  it("same seed, rules and start level as the best; panel + AHEAD / BEHIND; losing changes nothing", function()
    local net, c, ns = client(4)
    local r = blitzBest(net, c, "fast")
    local before = { best = r.best, games = r.games, log = r.bestLog }
    ns.UI:RefreshMenu()
    ns.UI.modeButtons.blitz.race:Click()
    local s = ns.App.session
    eq(s.mode.key, "ghost_blitz"); eq(s.mode.limitTicks, ns.Session.MODES.blitz.limitTicks)
    eq(s.seed, ns.Engine.deserializeLog(r.bestLog).seed); eq(s.state.config.startLevel, 1)
    net.step(185)
    ok(ns.UI.ghostPanel:IsShown()); ok(not ns.UI.nextPreviews[5]:IsShown(), "NEXT makes room as for a rival")
    net.step(60 * 20) -- idle 20 s: the best run is ahead
    eq(ns.UI.bestLabel:GetText(), "BEHIND")
    ok(ns.UI.bestText:GetText():match("^%-"), ns.UI.bestText:GetText())
    eq(ns.UI.ghostPanel.score:GetText(), ns.T.commas(s.ghost.runner.s.score))
    playOut(net, c, "weak")
    eq(r.best, before.best); eq(r.games, before.games); eq(r.bestLog, before.log)
    ok(ns.UI.overBadge:GetText():find("^OFFICIAL BEST"), ns.UI.overBadge:GetText())
    eq(ns.db.ghosts.blitz, nil)
  end)
  it("beating it: the big moment once, mid-run; the result; the win is the next ghost; records untouched", function()
    local net, c, ns = client(5)
    local r = blitzBest(net, c, "weak")
    local best = r.best
    ns.App:StartGhost("blitz"); net.step(185)
    c.M.sounds = {}
    local fired = 0
    local callout = ns.UI.Callout
    local words
    ns.UI.Callout = function(self, main, sub, c, p, tier, top)
      if main == "RACE BEST" then fired = fired + 1; words = { top = top, sub = sub } end
      return callout(self, main, sub, c, p, tier, top)
    end
    local bot = NS.autoplay(c, "fast")
    local burst
    for _ = 1, 60 * 130 do
      local s = ns.App.session
      if s.phase == "over" then break end
      bot(); net.step(1)
      if fired == 1 and burst == nil then burst = ns.UI.fx.burstAnim:IsPlaying() end
    end
    net.step(70)
    ns.UI.Callout = callout
    eq(fired, 1, "once"); eq(burst, true, "the gold burst")
    eq(words.top, "NEW"); eq(words.sub, "PAST YOUR GHOST") -- "NEW RACE BEST": never called a personal record
    ok(has(sounds(c), "record"), "the result fanfare")
    local s = ns.App.session
    ok(s.state.score > best)
    ok(ns.UI.overBadge:GetText():find("^NEW RACE BEST  %+"), ns.UI.overBadge:GetText())
    ok(ns.UI.overDetail:GetText():find("Official best stays " .. ns.T.commas(best), 1, true), ns.UI.overDetail:GetText())
    eq(r.best, best, "the normal record is not changed")
    local g = ns.db.ghosts.blitz
    eq(g.score, s.state.score)
    local e = ns.Ghost.source(ns.db, "blitz"); eq(e.from, "race"); eq(e.score, s.state.score)
    -- Play again: a race against the new ghost
    ns.UI:PlayAgain()
    eq(ns.App.session.mode.key, "ghost_blitz"); eq(ns.App.session.ghost.entry.score, g.score)
  end)
  it("Reduce effects: the text and sound stay, the burst doesn't play", function()
    local net, c, ns = client(6)
    blitzBest(net, c, "weak")
    ns.db.settings.reduceEffects = true
    ns.App:StartGhost("blitz"); net.step(185)
    local bot = NS.autoplay(c, "fast")
    local seen
    for _ = 1, 60 * 130 do
      if ns.App.session.phase == "over" then break end
      bot(); net.step(1)
      if ns.App.session.ghost.beaten and seen == nil then seen = { text = ns.UI.callout:GetText(), burst = ns.UI.fx.burstAnim:IsPlaying() } end
    end
    ok(seen, "beaten"); eq(seen.text, "RACE BEST"); eq(seen.burst, false)
  end)
  it("the panel can be hidden and shown again; the race goes on; the stats panel then shows the best's score", function()
    local net, c, ns = client(7)
    local r = blitzBest(net, c, "weak")
    ns.App:StartGhost("blitz"); net.step(185)
    ns.UI.ghostPanel.hide:Click(); net.step(2)
    eq(ns.db.settings.raceBestPanel, false)
    ok(not ns.UI.ghostPanel:IsShown()); ok(ns.UI.ghostShow:IsShown()); ok(ns.UI.nextPreviews[5]:IsShown())
    eq(ns.UI.bestLabel:GetText(), "OFFICIAL BEST"); eq(ns.UI.bestText:GetText(), ns.T.commas(r.best))
    net.step(60)
    ok(ns.App.session.ghost.runner.s.tick == ns.App.session.state.tick, "the ghost still runs")
    c.env.SlashCmdList.STACKRIVALS("best panel"); net.step(2)
    eq(ns.db.settings.raceBestPanel, true); ok(ns.UI.ghostPanel:IsShown())
    -- and a normal run afterwards shows the normal BEST again
    ns.App:Pause("manual"); ns.App:Quit(); net.step(2)
    c.env.SlashCmdList.STACKRIVALS("trial"); net.step(185)
    eq(ns.UI.bestLabel:GetText(), "BEST"); eq(ns.UI.bestText:GetText(), ns.T.commas(r.best))
    ok(not ns.UI.ghostPanel:IsShown())
  end)
  it("nothing is sent: a race is local", function()
    local net, c, ns = client(8, { seenHelp = true })
    blitzBest(net, c, "weak")
    local sent = ns.Comm.stats.sent
    ns.App:StartGhost("blitz"); net.step(185 + 600)
    eq(ns.Comm.stats.sent, sent); eq(#ns.Comm.queue, 0)
  end)
end)

describe("Race My Best: polish (Official Best vs Race Best, layout)", function()
  it("Official Best and Race Best are kept apart: a race updates Race Best (races, wins), never the records", function()
    local net, c, ns = client(20)
    local r = blitzBest(net, c, "weak")
    local official = r.best
    ns.App:StartGhost("blitz"); net.step(185)
    eq(ns.UI.ghostPanel.name:GetText(), "OFFICIAL BEST", "the ghost is the official record")
    playOut(net, c, "weak")                           -- race 1: lost
    local rr = ns.db.raceRecords.blitz
    eq(rr.races, 1); eq(rr.wins, 0); ok(rr.best > 0 and rr.best <= official)
    ns.UI:PlayAgain(); net.step(185); playOut(net, c, "fast") -- race 2: won
    rr = ns.db.raceRecords.blitz
    eq(rr.races, 2); eq(rr.wins, 1); eq(rr.best, ns.App.session.state.score)
    eq(ns.db.records.blitz.best, official, "official best unchanged")
    ns.UI:PlayAgain(); net.step(185)
    eq(ns.UI.ghostPanel.name:GetText(), "RACE BEST", "now racing the won race")
    -- Records: a separate Race best row; the menu tooltip names both
    ns.App:Pause("manual"); ns.UI:ShowSheet("records"); net.step(1)
    local card = ns.UI.records.cards[2]
    eq(card.key, "blitz"); eq(card.stats[6]:GetText(), ns.T.commas(rr.best)); eq(card.best:GetText(), ns.T.commas(official))
    ns.UI:HideSheets(); ns.App:Quit(); net.step(2); ns.UI:RefreshMenu()
    local tip = ns.UI.modeButtons.blitz.race.tip
    ok(tip:find("Official Best " .. ns.T.commas(official), 1, true) and tip:find("Race Best " .. ns.T.commas(rr.best), 1, true), tip)
    -- resetting the records starts Race My Best over too
    ns.DB.resetRecords(ns.db)
    eq(next(ns.db.ghosts), nil); eq(next(ns.db.raceRecords), nil)
  end)
  it("the ghost ends while you still play: its final score stays readable and marked final; you're compared with it", function()
    local net, c, ns = client(21)
    local r = blitzBest(net, c, "weak")               -- hard drops only: this best tops out before 2:00
    local d = ns.Engine.deserializeLog(r.bestLog)
    ok(d.ticks < 7200, "the best ended early (topped out at tick " .. d.ticks .. ")")
    ns.App:StartGhost("blitz"); net.step(185)
    local s = ns.App.session
    s.state.tick = d.ticks + 120; net.step(1)          -- two seconds after the ghost's end
    local gp = ns.UI.ghostPanel
    eq(s.ghost.runner.done, true)
    eq(gp.score:GetText(), ns.T.commas(r.best)); eq(gp.state:GetText(), "final score")
    eq(gp.state:IsTruncated(), false); eq(gp.name:IsTruncated(), false)
    eq(ns.UI.bestText:GetText(), "-" .. ns.T.commas(r.best - s.state.score), "compared with the final score")
  end)
  it("a Time Trial race that ends on time shows TIME! with 0:00 left (the preview's 1:39 was made-up test data)", function()
    local net, c, ns = client(22)
    blitzBest(net, c, "weak")
    ns.App:StartGhost("blitz"); net.step(185)
    local s = ns.App.session
    s.state.tick = s.mode.limitTicks - 30             -- jump to the last half second (the clock is the subject)
    for _ = 1, 120 do if s.phase ~= "playing" then break end; net.step(1) end
    net.step(70)
    eq(s.endReason, "time")
    eq(ns.UI.overTitle:GetText(), "TIME!"); eq(ns.UI.timeText:GetText(), "0:00")
  end)
  it("UI scale and small screens: the window is scaled as one piece, so the panel stays inside it and on screen", function()
    for _, case in ipairs({ { 1024, 768, 0.7 }, { 1024, 768, 1.4 }, { 1366, 768, 1.0 }, { 2560, 1440, 1.4 } }) do
      local net, c, ns = client(23)
      c.env.UIParent:SetSize(case[1], case[2])
      ns.db.settings.scale = case[3]
      blitzBest(net, c, "weak")
      ns.UI:ApplyScale()
      ns.App:StartGhost("blitz"); net.step(185)
      local F, gp = ns.UI.frame, ns.UI.ghostPanel
      local sc = F:GetScale()
      ok(F:GetHeight() * sc <= case[2] and F:GetWidth() * sc <= case[1], "window fits the screen " .. case[1] .. "x" .. case[2])
      ok(gp:IsShown())
      -- the panel is laid out inside the window (window units), so one scale moves it all together
      local cur = gp; while cur and cur ~= F do cur = cur._parent end
      eq(cur, F, "the panel belongs to the window")
      local R = L.new(F)
      local pr = R.rect(gp)
      ok(pr.l >= 0 and pr.r <= F._w and pr.b >= 0 and pr.t <= F._h, "panel inside the window")
      -- every text in the panel fits its width at its font (the long cases too)
      for _, t in ipairs({ { gp.name, "OFFICIAL BEST" }, { gp.state, "LV 20 - 999 lines" }, { gp.state, "1234 lines" }, { gp.state, "ghost changed" }, { gp.state, "final score" }, { gp.score, "1,234,567" } }) do
        local fs, txt = t[1], t[2]
        local w = L.textWidth(txt, fs._font[2], fs._font[1])
        local room = fs._w and fs._w > 0 and fs._w or (pr.r - R.rect(fs).l - 6)
        ok(w <= room, string.format("%q fits (%.0f <= %.0f)", txt, w, room))
      end
      -- the label row keeps clear of the hide button (at least 4 units apart)
      local nl = R.rect(gp.name).l + L.textWidth("OFFICIAL BEST", gp.name._font[2], gp.name._font[1])
      ok(nl + 4 <= R.rect(gp.hide).l, string.format("OFFICIAL BEST ends at %.0f, the - starts at %.0f", nl, R.rect(gp.hide).l))
    end
  end)
  it("old saves: no Race Best yet loads; garbage in it is dropped", function()
    local DBm = (select(3, client(24))).DB
    eq(next(DBm.sanitize({}).raceRecords), nil)
    local db = DBm.sanitize({ raceRecords = { blitz = { best = "x", races = -4 }, daily = { best = 5 }, classic = { best = 700, races = 3, wins = 1, date = "2026-11-14" } } })
    eq(db.raceRecords.blitz.best, 0); eq(db.raceRecords.blitz.races, 0); eq(db.raceRecords.daily, nil)
    eq(db.raceRecords.classic.best, 700); eq(db.raceRecords.classic.wins, 1)
  end)
end)

describe("Race My Best: /reload, saved data, records", function()
  it("an interrupted race (/reload) continues against the same ghost, at the same point", function()
    local net, c, ns = client(9)
    blitzBest(net, c, "fast")
    ns.App:StartGhost("blitz"); net.step(185 + 60 * 25)
    local tick, gscore = ns.App.session.state.tick, ns.App.session.ghost.runner.s.score
    c.M.fire("PLAYER_LOGOUT")
    local saved = c.env.StackRivalsDB
    ok(saved.suspended and saved.suspended.mode == "ghost_blitz" and saved.suspended.ghostId, "saved with its ghost id")
    local net2 = NS.new({ seed = 99 })
    local c2 = net2.add({ name = "Alice", saved = saved }); net2.step(2)
    c2.env.SlashCmdList.STACKRIVALS("")
    c2.ns.UI.continueBtn:Click(); net2.step(2)
    local s = c2.ns.App.session
    eq(s.mode.key, "ghost_blitz"); eq(s.state.tick, tick)
    ok(s.ghost and s.ghost.runner, "ghost attached"); eq(s.ghost.runner.s.tick, tick); eq(s.ghost.runner.s.score, gscore)
  end)
  it("if the best changed while the race was saved, it continues without a ghost (and says so), no error", function()
    local net, c, ns = client(10)
    blitzBest(net, c, "fast")
    ns.App:StartGhost("blitz"); net.step(185 + 600)
    c.M.fire("PLAYER_LOGOUT")
    local saved = c.env.StackRivalsDB
    saved.records.blitz.best = saved.records.blitz.best + 0 -- unchanged record, but another ghost slot:
    saved.ghosts = { blitz = { log = saved.records.blitz.bestLog:gsub(";%d+;([^;]*)$", ";1;%1"), score = 5, lines = 0, level = 1 } }
    local net2 = NS.new({ seed = 98 })
    local c2 = net2.add({ name = "Alice", saved = saved }); net2.step(2)
    c2.env.SlashCmdList.STACKRIVALS(""); c2.ns.UI.continueBtn:Click(); net2.step(200)
    local s = c2.ns.App.session
    eq(s.mode.key, "ghost_blitz"); eq(s.ghost.lost, true)
    eq(c2.ns.UI.ghostPanel.state:GetText(), "ghost changed")
    s:finish("time"); net2.step(70)
    eq(c2.ns.UI.overBadge:GetText(), "NO GHOST")
  end)
  it("old SavedVariables (no ghosts, no setting) load; garbage in the ghost slot is dropped", function()
    local DBm = (select(3, client(11))).DB
    local db = DBm.sanitize({ records = { blitz = { best = 100 } } })
    eq(db.settings.raceBestPanel, true); eq(next(db.ghosts), nil)
    db = DBm.sanitize({ ghosts = { blitz = { log = "not a log", score = 5 }, classic = { log = "1;s;1;10;", score = -3 },
      daily = { log = "1;s;1;10;", score = 5 }, junk = 4 } })
    eq(next(db.ghosts), nil)
    db = DBm.sanitize({ ghosts = { blitz = { log = "1;s;1;10;" .. string.rep("1,1 ", 80000), score = 5 } } })
    eq(db.ghosts.blitz, nil, "over the size cap")
    db = DBm.sanitize({ ghosts = { blitz = { log = "1;abc;1;10;0,6", score = 42, lines = 1, level = 1, date = "2026-11-14" } } })
    eq(db.ghosts.blitz.score, 42)
  end)
  it("a new normal record replaces a won race as the ghost only when it scores at least as high", function()
    local net, c, ns = client(12)
    local G = ns.Ghost
    ns.db.records.blitz.best = 1000
    ns.db.ghosts = { blitz = { log = "1;x;1;1;", score = 5000 } }
    G.onNewRecord(ns.db, "blitz"); ok(ns.db.ghosts.blitz ~= nil, "lower record: the race ghost stays")
    ns.db.records.blitz.best = 6000
    G.onNewRecord(ns.db, "blitz"); eq(ns.db.ghosts.blitz, nil, "higher record: it is the ghost")
  end)
  it("Classic (endless) can be raced too: the best that topped out is shown as topped out", function()
    local net, c, ns = client(14)
    c.env.SlashCmdList.STACKRIVALS("classic"); playOut(net, c, "weak", 60 * 60 * 10)
    local r = ns.db.records.classic
    ok(r.best > 0 and r.bestLog)
    ok(ns.App:StartGhost("classic")); net.step(185)
    local s = ns.App.session
    eq(s.mode.key, "ghost_classic"); eq(s.mode.limitTicks, nil)
    playOut(net, c, "fast", 60 * 60 * 6)
    eq(s.ghost.runner.done, true); eq(s.ghost.runner.s.gameOver, true)
    eq(r.best, ns.db.records.classic.best, "records untouched")
  end)
  it("cost: the full check at the start and the per-frame ghost are small (Lua 5.3 shim numbers in a note)", function()
    local net, c, ns = client(15)
    blitzBest(net, c, "fast")
    local clock = os.clock
    local e = ns.Ghost.source(ns.db, "blitz")
    local t0 = clock(); assert(ns.Ghost.validate(e)); local check = (clock() - t0) * 1000
    ns.App:StartGhost("blitz"); net.step(185)
    local s = ns.App.session
    -- the ghost's own work for a whole 2:00 race, measured alone
    local d = ns.Engine.deserializeLog(e.log)
    local sess = { mode = s.mode, state = { tick = 0, score = 0 } }
    ns.Ghost.attach(sess, e, d)
    t0 = clock()
    for t = 1, d.ticks do sess.state.tick = t; ns.Ghost.update(sess) end
    local perFrame = (clock() - t0) * 1e6 / d.ticks
    print(string.format("  note: Race My Best: full replay check %.1f ms once per ghost; ghost %.1f us per frame (%d ticks)", check, perFrame, d.ticks))
    ok(check < 500); ok(perFrame < 200)
  end)
  it("Daily, duels, Loot Duel and web challenges can't be raced; App:Start refuses ghost modes", function()
    local net, c, ns = client(13)
    local e, why = ns.Ghost.source(ns.db, "daily"); eq(e, nil); eq(why, "mode")
    ns.App:Start("ghost_blitz"); eq(ns.App.session, nil)
  end)
end)

return H
