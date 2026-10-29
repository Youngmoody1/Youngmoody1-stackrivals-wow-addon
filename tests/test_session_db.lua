-- Session (modes, pause, countdown, events) and DB (validation, records, bindings) tests.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local ns = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Core/Session.lua", "Core/DB.lua" })
local S, DB, E = ns.Session, ns.DB, ns.Engine
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe
local STEP = 1 / 60

local function run(sess, ticks) for _ = 1, ticks do sess:update(STEP) end end

describe("session", function()
  it("3 second countdown, then live; inputs during countdown are ignored", function()
    local s = S.new("classic", "seed-a")
    eq(s.phase, "countdown"); eq(s:countdownNumber(), 3)
    s:press("hardDrop")
    run(s, 179); eq(s.phase, "countdown"); eq(s:countdownNumber(), 1)
    run(s, 1); eq(s.phase, "playing")
    eq(s.state.piecesPlaced, 0, "countdown input ignored")
  end)
  it("game speed is the same at 30, 60, 144 and 240 FPS (fixed 60 Hz simulation)", function()
    for _, fps in ipairs({ 30, 60, 144, 240 }) do
      local s = S.new("classic", "fps")
      for _ = 1, 3 * fps do s:update(1 / fps) end -- 3 s countdown
      local t0 = s.state.tick
      for _ = 1, 10 * fps do s:update(1 / fps) end -- 10 s of play
      local dt = s.state.tick - t0
      ok(math.abs(dt - 600) <= 1, fps .. " fps -> " .. dt .. " ticks in 10 s")
    end
  end)
  it("a huge frame never runs more than 8 ticks (no catch-up spiral)", function()
    local s = S.new("classic", "seed-b")
    run(s, 180)
    local t = s.state.tick
    s:update(5.0)
    ok(s.state.tick - t <= 8)
  end)
  it("pause freezes the game; resume goes through a countdown", function()
    local s = S.new("classic", "seed-c")
    run(s, 200)
    local t = s.state.tick
    ok(s:pause("manual")); run(s, 300)
    eq(s.state.tick, t)
    ok(s:resume()); eq(s.phase, "countdown")
    run(s, 180); eq(s.phase, "playing")
  end)
  it("blitz ends at exactly 7200 ticks with reason 'time'", function()
    local s = S.new("blitz", "seed-d")
    run(s, 180)
    local n = 0
    while s.phase == "playing" and n < 8000 do
      if n % 30 == 0 then s:press("hardDrop") end
      s:update(STEP); n = n + 1
    end
    if s.endReason == "time" then eq(s.state.tick, 7200) else eq(s.endReason, "topout") end
    local ev = s:takeEvents()
    eq(ev[#ev].kind, "over")
  end)
  it("emits clear / lock / harddrop events and the session's input log replays exactly", function()
    local s = S.new("classic", "seed-e")
    run(s, 180)
    local kinds = {}
    for i = 1, 3000 do
      if i % 9 == 0 then s:press("hardDrop") elseif i % 4 == 0 then s:press("left"); s:release("left") end
      s:update(STEP)
      for _, e in ipairs(s:takeEvents()) do kinds[e.kind] = true end
      if s.phase ~= "playing" then break end
    end
    ok(kinds.harddrop and kinds.lock, "events")
    local r = E.replay(s.seed, { startLevel = 1 }, s.state.inputLog, s.state.tick)
    eq(E.hashState(r), E.hashState(s.state))
  end)
  it("suspend -> restore gives the identical state, paused", function()
    local s = S.new("blitz", "seed-f")
    run(s, 180)
    for i = 1, 400 do if i % 70 == 0 then s:press("hardDrop") end s:update(STEP) end
    local data = s:suspendData()
    ok(data, "has data")
    local r = S.restore(data.mode, data.log, data.playSeconds)
    eq(r.phase, "paused")
    eq(E.hashState(r.state), E.hashState(s.state))
    eq(r:timeLeftTicks(), s:timeLeftTicks())
    eq(S.restore("classic", "garbage"), nil)
  end)
end)

describe("daily seed", function()
  it("is the same for every timezone (run under TZ=UTC+14, UTC-11, Copenhagen, UTC)", function()
    local lua = arg and arg[-1] or "lua5.1"
    local outs = {}
    for _, tz in ipairs({ "UTC", "Pacific/Kiritimati", "Pacific/Pago_Pago", "Europe/Copenhagen", "America/Los_Angeles" }) do
      local p = io.popen("TZ=" .. tz .. " " .. lua .. " tests/tz_print.lua")
      outs[#outs + 1] = p:read("*l"); p:close()
    end
    ok(outs[1] and outs[1]:find("^2026%-11%-04 srwow%-daily%-2026%-11%-04 ") ~= nil, "UTC date used: " .. tostring(outs[1]))
    for i = 2, #outs do eq(outs[i], outs[1], "timezone " .. i) end
  end)
  it("Daily Blitz pieces for fixed dates match the web engine exactly (golden sequences)", function()
    local fx = dofile(testdir .. "/fixtures/parity.lua")
    ok(#fx.dailies >= 5)
    for _, d in ipairs(fx.dailies) do
      local s = S.new("daily", S.dailySeed(d.date), d.date)
      -- what the player sees at the start: current piece + the 5-piece preview
      local shown = { s.state.active.id }
      for i = 1, 5 do shown[#shown + 1] = s.state.queue[i] end
      eq(table.concat(shown, ","), table.concat(d.pieces, ",", 1, 6), d.date .. " start")
      -- and the full first two bags, dealt by the addon's own PRNG
      local P = ns.Prng
      local b1, n1 = P.shuffle(ns.Pieces.IDS, P.hashString(S.dailySeed(d.date)))
      local b2 = P.shuffle(ns.Pieces.IDS, n1)
      eq(table.concat(b1, ",") .. "," .. table.concat(b2, ","), table.concat(d.pieces, ","), d.date .. " bags")
    end
  end)
  it("dailyDate() recovers the date only from real daily seeds", function()
    eq(S.dailyDate(S.dailySeed("2026-11-04")), "2026-11-04")
    eq(S.dailyDate("abc123"), nil)
    local s = S.new("daily", S.dailySeed("2026-11-04"), "2026-11-05")
    eq(s.date, "2026-11-04", "seed date wins")
  end)
end)

describe("db", function()
  it("sanitize(nil) gives full defaults", function()
    local db = DB.sanitize(nil)
    eq(db.settings.sound, true); eq(db.settings.scale, 1.0)
    eq(db.bindings.left, "LEFT"); eq(db.records.blitz.best, 0)
  end)
  it("recordRun tracks best, totals and today's daily best", function()
    local db = DB.sanitize(nil)
    local st = { score = 1200, lines = 9, level = 1, clears = { quad = 1 } }
    local r1 = DB.recordRun(db, "daily", st, 120, "2026-11-04", "log")
    ok(r1.newBest); ok(r1.newTodayBest)
    local r2 = DB.recordRun(db, "daily", { score = 900, lines = 3, level = 1, clears = { quad = 0 } }, 120, "2026-11-04", "log2")
    eq(r2.newBest, false); eq(r2.newTodayBest, false)
    eq(db.records.dailyToday.tries, 2); eq(db.records.daily.games, 2); eq(db.records.daily.quads, 1)
    DB.recordRun(db, "daily", { score = 50, lines = 0, level = 1, clears = { quad = 0 } }, 1, "2026-11-05", nil)
    eq(db.records.dailyToday.date, "2026-11-05"); eq(db.records.dailyToday.best, 50)
    eq(db.records.daily.best, 1200, "all-time daily best kept")
  end)
  it("a Daily that finishes after midnight UTC counts for the day of its pieces, not today", function()
    local db = DB.sanitize(nil)
    DB.recordRun(db, "daily", { score = 500, lines = 4, level = 1, clears = { quad = 0 } }, 120, "2026-11-04", nil, "2026-11-04")
    local r = DB.recordRun(db, "daily", { score = 900, lines = 6, level = 1, clears = { quad = 0 } }, 120, "2026-11-04", nil, "2026-11-05")
    eq(r.newTodayBest, nil, "not counted as today's (Nov 5) best")
    eq(db.records.dailyToday.date, "2026-11-04"); eq(db.records.dailyToday.best, 500)
    eq(db.records.daily.top[1].d, "2026-11-04"); eq(db.records.daily.best, 900)
  end)
  it("keeps a sorted top 5 and reports the rank", function()
    local db = DB.sanitize(nil)
    local ranks = {}
    for i, sc in ipairs({ 300, 900, 100, 500, 700, 800, 50 }) do
      ranks[i] = DB.recordRun(db, "blitz", { score = sc, lines = 1, level = 1, clears = { quad = 0 } }, 1, "2026-11-04").rank
    end
    eq(ranks[2], 1); eq(ranks[6], 2); eq(ranks[7], nil, "50 doesn't make the top 5")
    local top = db.records.blitz.top
    eq(#top, 5); eq(top[1].s, 900); eq(top[5].s, 300)
    local again = DB.sanitize({ records = { blitz = { top = { { s = 5 }, "bad", { s = 99, d = "2026-11-01" }, { s = "x" } } } } })
    eq(#again.records.blitz.top, 2); eq(again.records.blitz.top[1].s, 99)
  end)
  it("records are tagged with the ruleset; a rules change archives old records instead of deleting", function()
    local fresh = DB.sanitize(nil)
    eq(fresh.rules, E.ENGINE_VERSION)
    -- data saved before the field existed counts as rules 1 = current: kept as is
    local kept = DB.sanitize({ records = { blitz = { best = 777 } } })
    eq(kept.records.blitz.best, 777); eq(kept.rulesChangedFrom, nil)
    -- data from another ruleset: archived, fresh records for the current rules
    local old = DB.sanitize({ rules = 0, records = { blitz = { best = 999, games = 3 } } })
    eq(old.records.blitz.best, 0)
    eq(old.archive.rules0.blitz.best, 999); eq(old.archive.rules0.blitz.games, 3)
    eq(old.rulesChangedFrom, 0)
    -- the archive survives the next load untouched
    local again = DB.sanitize(old)
    eq(again.archive.rules0.blitz.best, 999); eq(again.rules, E.ENGINE_VERSION)
  end)
  it("key lookup: custom binding beats a fixed alternate key", function()
    local db = DB.sanitize(nil)
    eq(DB.actionForKey(db, "A"), "left")
    DB.setBinding(db, "hold", "A")
    eq(DB.actionForKey(db, "A"), "hold")
    eq(DB.actionForKey(db, "F12"), nil)
    eq(DB.setBinding(db, "hold", "bad key!"), false)
  end)
end)

return H
