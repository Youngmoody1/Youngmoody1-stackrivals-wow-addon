-- Account > Sync: SR1 challenge codes in, SR1 result codes out (simulated client; the website's
-- import is simulated with the addon's own decoder + engine replay, as in tests/sr1_vectors.lua).
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local T0 = 1793000000

local function client(seed, o)
  local net = NS.new({ seed = seed })
  o = o or {}; o.name = o.name or "Alice"; o.saved = o.saved or { seenHelp = true }
  local c = net.add(o)
  c.M.serverTime = T0
  c.env.SlashCmdList.STACKRIVALS("")
  return net, c
end
--- Play the current run to its end fast (hard drops until top-out).
local function finish(net, c)
  for _ = 1, 3000 do
    local s = c.ns.App.session
    if s.recorded then return s end
    if s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end
    net.step(1)
  end
  error("run didn't end")
end
--- The website's SR1 import, simulated: decode, then replay the log with the engine.
local function serverCheck(ns, code)
  local r = assert(ns.Codes.parseResult(code))
  local E = ns.Engine
  local s = E.replay(r.seed, { startLevel = 1 }, r.log, r.ticks)
  return r, s.score == r.score and s.lines == r.lines and s.level == r.level and E.hashState(s) == r.hash
end

describe("Sync: challenge codes", function()
  it("a pasted SR1 challenge starts that exact challenge (ruleset + seed), not a record run", function()
    local net, c = client(1)
    local ns = c.ns
    local code = ns.Codes.challenge("b120", "srchal-7f3k2p9d01")
    ns.UI:ShowSheet("account"); ns.UI.accountSheet.tabs.sync:Click()
    local y = ns.UI.accountSheet.sync
    ok(y:IsShown(), "Sync tab")
    y.code:SetText(code); y.play:Click()
    local s = ns.App.session
    eq(s.mode.key, "chal_b120"); eq(s.seed, "srchal-7f3k2p9d01"); eq(s.mode.limitTicks, 7200)
    ok(not ns.UI.accountSheet:IsShown(), "the sheet closes, the run starts")
    local gamesBefore = ns.db.records.blitz.games
    finish(net, c)
    eq(ns.db.records.blitz.games, gamesBefore, "never a local record")
    eq(#ns.db.sync.results, 1, "kept for export")
    eq(ns.UI.overBadge:GetText(), "RESULT CODE READY")
    -- Play again = the same challenge again
    ns.UI:PlayAgain()
    eq(ns.App.session.seed, "srchal-7f3k2p9d01"); eq(ns.App.session.mode.key, "chal_b120")
  end)
  it("r180 and daily120 codes use their own time caps", function()
    local _, c = client(2)
    local ns = c.ns
    ok(ns.App:StartChallenge(ns.Codes.challenge("r180", "srchal-aaaaaaaaaa")))
    eq(ns.App.session.mode.limitTicks, 10800)
    ok(ns.App:StartChallenge(ns.Codes.challenge("daily120", "srwow-daily-2026-11-05")))
    eq(ns.App.session.mode.key, "chal_daily120"); eq(ns.App.session.seed, "srwow-daily-2026-11-05")
  end)
  it("bad codes are refused with a clear reason and nothing starts", function()
    local _, c = client(3)
    local ns = c.ns
    local good = ns.Codes.challenge("b120", "srchal-7f3k2p9d01")
    local cases = {
      { good:sub(1, -2) .. (good:sub(-1) == "0" and "1" or "0"), "check" },
      { good:sub(1, 12), "fields" },
      { "", "format" },
      { "hello world", "format" },
      { good:gsub("%.e1%.", ".e2."), "check" },
    }
    for _, cs in ipairs(cases) do
      local okP, why = ns.App:StartChallenge(cs[1])
      ok(not okP, "accepted: " .. cs[1])
      ok(ns.Sync.ERRORS[why], "a message for " .. tostring(why))
    end
    -- a correctly signed code for another engine version
    local body = "SR1C.b120.e2.srchal-7f3k2p9d01"
    local other = body .. "." .. string.format("%08x", ns.Prng.hashString(body))
    local okP, why = ns.App:StartChallenge(other)
    ok(not okP); eq(why, "engine")
    eq(ns.App.session, nil, "nothing started")
  end)
end)

describe("Sync: result codes", function()
  it("a finished challenge exports an SR1 result the website's replay accepts", function()
    local net, c = client(4)
    local ns = c.ns
    ok(ns.App:StartChallenge(ns.Codes.challenge("b120", "srchal-7f3k2p9d01")))
    local s = finish(net, c)
    local list = ns.Sync.exportable(ns.App:Today())
    eq(#list, 1)
    local code = assert(ns.Sync.resultCode(list[1].r))
    local r, replayOk = serverCheck(ns, code)
    ok(replayOk, "server replay reproduces score, lines, level and hash")
    eq(r.score, s.state.score); eq(r.player, "Alice-Realm"); eq(r.platform, "wow-forever", "the mock runs interface 16001 = WoW Forever"); eq(r.link, nil, "not linked: no link")
    ok(#code <= ns.Codes.MAX_CODE)
    ok(list[1].r.exported)
  end)
  it("when linked, the result carries this character's linkId", function()
    local net, c = client(5)
    local ns = c.ns
    local AC = ns.AccountCodes
    local req = AC.parseLinkRequest(ns.Account.startLink(AC.makeWebCode("SYNC123")))
    c.M.serverTime = T0 + 60
    ok(ns.Account.import(AC.profile({ linkId = req.linkId, player = req.player, accountId = "acc_1", name = "Alice", issued = T0 + 30, expires = T0 + 86400, history = {} })))
    ok(ns.App:StartChallenge(ns.Codes.challenge("b120", "srchal-linkedrun1")))
    finish(net, c)
    local r = serverCheck(ns, assert(ns.Sync.resultCode(ns.Sync.exportable(ns.App:Today())[1].r)))
    eq(r.link, req.linkId:upper())
  end)
  it("today's best Daily Challenge run is exportable (daily120); Time Trial and Classic are not", function()
    local net, c = client(6)
    local ns = c.ns
    ns.App:Start("blitz"); finish(net, c)
    ns.App:Start("classic"); finish(net, c)
    eq(#ns.Sync.exportable(ns.App:Today()), 0, "private seeds can't be checked by the website")
    ns.App:Start("daily"); finish(net, c)
    local list = ns.Sync.exportable(ns.App:Today())
    eq(#list, 1); eq(list[1].kind, "daily")
    local r, replayOk = serverCheck(ns, assert(ns.Sync.resultCode(list[1].r)))
    ok(replayOk); eq(r.ruleset, "daily120"); eq(r.seed, "srwow-daily-" .. ns.App:Today())
  end)
  it("keeps the last 10 results, newest first", function()
    local net, c = client(7)
    local ns = c.ns
    for i = 1, 12 do ok(ns.App:StartChallenge(ns.Codes.challenge("b120", "srchal-run" .. i))); finish(net, c) end
    eq(#ns.db.sync.results, 10)
    eq(ns.db.sync.results[1].seed, "srchal-run12")
  end)
  it("the Sync tab: Copy code puts the result code in the copy box", function()
    local net, c = client(8)
    local ns = c.ns
    ok(ns.App:StartChallenge(ns.Codes.challenge("b120", "srchal-uiexport1")))
    finish(net, c)
    ns.App:ShowMenu()
    ns.UI:ShowSheet("account"); ns.UI.accountSheet.tabs.sync:Click()
    local y = ns.UI.accountSheet.sync
    ok(y.rows[1]:IsShown())
    eq(y.rows[1].name:GetText(), "Web Challenge 2:00")
    y.rows[1].btn:Click()
    local code = y.out:GetText()
    ok(code:match("^SR1R%."), code:sub(1, 20))
    local _, replayOk = serverCheck(ns, code)
    ok(replayOk)
    ok(ns.UI.syncNote:find("replays it"), ns.UI.syncNote)
  end)
  it("manipulated saved results are dropped on load", function()
    local net = NS.new({ seed = 9 })
    local c = net.add({ name = "Alice", saved = { sync = { results = {
      { ruleset = "b120", seed = "srchal-ok", hash = "0a0b0c0d", log = "", player = "Alice-Realm", engine = 1, ticks = 10, score = 0, lines = 0, level = 1 },
      { ruleset = "zz99", seed = "x", hash = "0a0b0c0d", log = "", player = "Alice-Realm", engine = 1, ticks = 1, score = 0, lines = 0, level = 1 },
      { ruleset = "b120", seed = "BAD SEED", hash = "0a0b0c0d", log = "", player = "Alice-Realm", engine = 1, ticks = 1, score = 0, lines = 0, level = 1 },
      { ruleset = "b120", seed = "srchal-ok", hash = "nothex!!", log = "", player = "Alice-Realm", engine = 1, ticks = 1, score = 0, lines = 0, level = 1 },
      { ruleset = "b120", seed = "srchal-ok", hash = "0a0b0c0d", log = "", player = "|cffBad-Realm", engine = 1, ticks = 1, score = 0, lines = 0, level = 1 },
      "junk",
    }, daily = { ruleset = "b120", seed = "srchal-ok" } } } })
    eq(#c.ns.db.sync.results, 1)
    eq(c.ns.db.sync.daily, nil)
  end)
end)

return H
