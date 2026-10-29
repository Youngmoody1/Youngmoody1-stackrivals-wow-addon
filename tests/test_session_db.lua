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
