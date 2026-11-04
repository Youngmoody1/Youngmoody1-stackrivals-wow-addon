-- Regression tests for the independent review of 0.6.1 (each test = one finding, fixed in 0.7.0).
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe
local T0 = 1793000000

local function pair(seed, oa, ob)
  local net = NS.new({ seed = seed })
  oa = oa or {}; ob = ob or {}
  oa.name = oa.name or "Alice"; ob.name = ob.name or "Bob"
  oa.guild = oa.guild or "G"; ob.guild = ob.guild or "G"
  oa.saved = oa.saved or { seenHelp = true }; ob.saved = ob.saved or { seenHelp = true }
  local a, b = net.add(oa), net.add(ob)
  net.step(30)
  return net, a, b
end
local function finish(net, c)
  for _ = 1, 3000 do
    local s = c.ns.App.session
    if s.recorded then return s end
    if s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end
    net.step(1)
  end
end

describe("0.6.1 review findings (fixed)", function()
  it("1. a rival can't smuggle colour codes into chat through line wrapping", function()
    local net, a, b = pair(1)
    a.ns.Quickplay.start("b120"); b.ns.Quickplay.start("b120"); net.step(300)
    net.inject(a, b.name, a.ns.Protocol.encode("CH", a.ns.Duel.current.mid, 77, a.ns.Codes.hex(string.rep("a", 29) .. "|cffff0000FAKE SYSTEM MESSAGE|r")))
    net.step(10)
    a.env.SlashCmdList.STACKRIVALS(""); a.ns.UI:RefreshPhase(); a.ns.UI:RefreshChat()
    local saw = 0
    for i, fs in ipairs(a.ns.UI.chat.lines) do
      local t = fs:GetText() or ""
      if t:find("aaaa", 1, true) or t:find("FAKE", 1, true) then
        saw = saw + 1
        -- drop our own name tag on the first line, then every "|" must be part of an escaped "||"
        local rest = t:gsub("^|cff%x%x%x%x%x%x[^|]*|r", ""):gsub("||", "")
        ok(not rest:find("|", 1, true), "live escape on line " .. i .. ": " .. t)
      end
    end
    ok(saw >= 2, "the long line wrapped")
  end)

  it("2. a web challenge restored after /reload stays that challenge; App:Start can't start challenge modes", function()
    local net, c = pair(2)
    local ns = c.ns
    ok(ns.App:StartChallenge(ns.Codes.challenge("b120", "srchal-reloadme01")))
    for _ = 1, 400 do net.step(1) end
    ns.App.session:press("hardDrop"); ns.App.session:release("hardDrop"); net.step(5)
    local c2 = net.reload(c)
    c2.ns.App:ContinueSuspended()
    eq(c2.ns.App.session.seed, "srchal-reloadme01")
    finish(net, c2)
    c2.ns.UI:PlayAgain()
    eq(c2.ns.App.session.seed, "srchal-reloadme01", "Play again = the same challenge")
    local before = c2.ns.App.session
    c2.ns.App:Start("chal_b120")
    eq(c2.ns.App.session, before, "App:Start refuses challenge modes")
    for _, r in ipairs(c2.ns.db.sync.results) do eq(r.seed, "srchal-reloadme01", "only the real challenge is exportable") end
  end)

  it("3. accepting a normal duel stops a running Quickplay search (no more QS)", function()
    local net, a, b = pair(3)
    local carol = net.add({ name = "Carol", guild = "G", saved = { seenHelp = true } })
    net.step(30)
    ok(b.ns.Quickplay.start("b120")); net.step(60)
    carol.ns.Duel.challenge(b.name, "b120"); net.step(60)
    b.ns.Duel.accept(); net.step(60)
    eq(b.ns.Quickplay.state, "idle"); eq(b.ns.Quickplay.note, "busy")
    local qs = 0
    net.tap = function(cl, text) if cl == b and text:find(":QS:", 1, true) then qs = qs + 1 end end
    net.step(60 * 45)
    eq(qs, 0, "no Quickplay announcements while in the duel")
    ok(a)
  end)

  it("4. the platform comes from the client: 16001 = Forever, 11509 = Classic Era, project 1 = Retail", function()
    local _, a = pair(4)
    eq(a.ns.Account.platform(), "wow-forever")
    local _, c = pair(5, { beforeLogin = function(env) env.GetBuildInfo = function() return "1.15.9", "1", "Nov 2026", 11509 end end })
    eq(c.ns.Account.platform(), "wow-classic")
    local _, r = pair(6, { beforeLogin = function(env) env.WOW_PROJECT_ID = 1; env.GetBuildInfo = function() return "12.1.5", "1", "x", 120105 end end })
    eq(r.ns.Account.platform(), "wow-retail")
  end)

  it("5. 'Share my card' off: the rival sees Unknown for the record too", function()
    local net, a, b = pair(7, nil, { saved = { seenHelp = true, social = { shareCard = false }, duels = { wins = 9, losses = 1 } } })
    a.ns.Duel.challenge(b.name, "b120"); net.step(60); b.ns.Duel.accept(); net.step(120)
    a.env.SlashCmdList.STACKRIVALS(""); a.ns.UI:RefreshPhase()
    local card = a.ns.UI.lobby.themCard
    eq(card.faction:GetText(), "UNKNOWN FACTION")
    ok(card.line4:GetText():find("Record: Unknown", 1, true), card.line4:GetText())
  end)

  it("6. every kept result can be reached on the Sync tab (pages)", function()
    local net, c = pair(8)
    local ns = c.ns
    for i = 1, 10 do ok(ns.App:StartChallenge(ns.Codes.challenge("b120", "srchal-page" .. i))); finish(net, c) end
    ns.App:ShowMenu()
    ns.UI:ShowSheet("account"); ns.UI.accountSheet.tabs.sync:Click()
    local y = ns.UI.accountSheet.sync
    ok(y.next:IsShown() and y.next:IsEnabled(), "more pages")
    for _ = 1, 3 do y.next:Click() end
    eq(y.page:GetText(), "4 / 4")
    ok(y.rows[1]:IsShown(), "the 10th result is on the last page")
  end)

  it("7. a Quickplay invite from someone who never announced a search is ignored, even while searching", function()
    local net, a = pair(9)
    ok(a.ns.Quickplay.start("b120")); net.step(30)
    local P = a.ns.Protocol
    net.inject(a, "Mallory-Realm", P.encode("INV", "abc123", "b120", 1, P.commit("abc123", "n0nce123"), "q"))
    net.step(30)
    eq(a.ns.Duel.current, nil)
    eq(a.ns.Quickplay.state, "searching")
  end)

  it("8. an expired one-time web code is not kept in SavedVariables", function()
    local net = NS.new({ seed = 10 })
    local c = net.add({ name = "Alice", saved = { accounts = { ["Alice-Realm"] = { pending = { code = "A7K9P2XJ", linkId = "abcdefghij12", at = 1000 } } } } })
    eq(c.ns.db.accounts["Alice-Realm"], nil)
    ok(net)
  end)

  it("9. a Battle.net friend without a realm is never guessed onto your realm", function()
    local net = NS.new({ seed = 11 })
    local a = net.add({ name = "Alice", beforeLogin = function(env)
      env.BNGetNumFriends = function() return 1 end
      env.C_BattleNet.GetFriendAccountInfo = function() return { gameAccountInfo = { isOnline = true, clientProgram = "WoW", characterName = "Ghost", realmName = "", wowProjectID = 2, gameAccountID = 7001 } } end
    end })
    net.step(5)
    a.ns.BNet.refresh(true)
    eq(a.ns.BNet.byId[7001], nil)
  end)

  it("10. a Loot Duel run is never saved for 'Continue' (it can't be resumed)", function()
    local net, a = pair(12)
    local s = a.ns.Session.new("loot_l060", "srloot-test-1", a.ns.App:Today())
    s.loot = {}
    s.state.tick = 50
    eq(s:suspendData(), nil)
    ok(net)
  end)
end)

return H
