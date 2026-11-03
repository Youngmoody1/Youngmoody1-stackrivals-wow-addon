-- Battle.net transport (Net/BNet.lua): duels, presence, Quickplay and chat with Battle.net friends on
-- realms a normal whisper can't reach. SIMULATED: tests/netsim.lua models C_BattleNet.SendGameData /
-- BN_CHAT_MSG_ADDON from their documentation; real delivery, order and throttling need a WoW test.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local function pair(seed, oa, of)
  local net = NS.new({ seed = seed })
  oa = oa or {}; of = of or {}
  oa.name = "Alice"; oa.bnet = oa.bnet or { { name = "Bob" }, { name = "Frank", realm = "Faraway" } }
  of.name = "Frank"; of.realm = "Faraway"; of.bnet = of.bnet or { { name = "Alice" } }
  local a = net.add(oa)
  local f = net.add(of)
  net.step(30)
  return net, a, f
end
local function rowFor(c, name)
  for _, row in ipairs(c.ns.UI.duelSheet.rows) do if row:IsShown() and (row.name:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) == name then return row end end
end
local function scan(t, seen, hit)
  seen = seen or {}
  if seen[t] then return end
  seen[t] = true
  for k, v in pairs(t) do
    if type(k) == "number" and k >= 7000 and k < 8000 then hit[#hit + 1] = "key " .. k end
    if type(v) == "number" and v >= 7000 and v < 8000 then hit[#hit + 1] = tostring(k) .. "=" .. v end
    if type(v) == "table" then scan(v, seen, hit) end
  end
end

describe("Battle.net transport (simulated clients)", function()
  it("a friend on a realm whispers can't reach: listed via Battle.net, answers, and a full duel runs over it", function()
    local net, a, f = pair(1)
    eq(a.ns.Social.whisperable("Faraway"), false, "not a connected realm")
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.UI:ShowSheet("duel"); a.ns.UI.duelSource = "bnet"; a.ns.UI:RefreshDuelSheet()
    a.ns.UI.duelSheet.refresh:Click()
    net.step(60)
    ok((net.bnetSent or 0) >= 2, "HEL and HI went over Battle.net: " .. tostring(net.bnetSent))
    local row = rowFor(a, "Frank-Faraway")
    ok(row and row.btn:IsEnabled(), "Frank is ready: " .. (row and row.info:GetText() or "not listed"))
    row.btn:Click(); net.step(60)
    eq(f.ns.Duel.current and f.ns.Duel.current.state, "invited")
    eq(f.ns.Duel.current.rival, "Alice-Realm", "Frank sees Alice by name, never by a game account ID")
    f.ns.Duel.accept(); net.step(60)
    a.ns.Duel.ready(); f.ns.Duel.ready(); net.step(60)
    eq(a.ns.Duel.current.state, "playing")
    -- both top out fast: END, LOG chunks, VER all over Battle.net
    for _ = 1, 4000 do
      for _, c in ipairs({ a, f }) do
        local s = c.ns.App.session
        if s and s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end
      end
      net.step(1)
      if a.ns.Duel.current.state == "done" and f.ns.Duel.current.state == "done" and a.ns.Duel.current.agreement then break end
    end
    net.step(600)
    eq(a.ns.Duel.current.state, "done"); eq(f.ns.Duel.current.state, "done")
    eq(a.ns.Duel.current.basis, "replay", "peer-checked by replay over Battle.net")
    eq(a.ns.Duel.current.agreement, "agreed")
    eq(net.unreachable or 0, 0, "nothing tried the plain whisper to Faraway")
  end)

  it("same-realm Battle.net friends keep using the normal whisper", function()
    local net = NS.new({ seed = 2 })
    local a = net.add({ name = "Alice", bnet = { { name = "Bob" } } })
    local b = net.add({ name = "Bob", bnet = { { name = "Alice" } } })
    net.step(30)
    a.ns.Duel.pingPresence({ "Bob-Realm" }); net.step(60)
    eq(net.bnetSent or 0, 0)
    ok(a.ns.Duel.presence("Bob-Realm"), "Bob answered by whisper")
    ok(b)
  end)

  it("without the API (older client) the other-realm friend is 'other realm'", function()
    local net, a = pair(3, { noBnetApi = true })
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.UI:ShowSheet("duel"); a.ns.UI.duelSource = "bnet"; a.ns.UI:RefreshDuelSheet()
    a.ns.UI.duelSheet.refresh:Click(); net.step(60)
    local row = rowFor(a, "Frank-Faraway")
    ok(row and not row.btn:IsShown() and row.info:GetText() == "other realm", row and row.info:GetText() or "not listed")
  end)

  it("a message from a game account that isn't a Battle.net friend on WoW is dropped", function()
    local net, a = pair(4)
    local before = a.ns.Comm.stats.received
    a.M.fire("BN_CHAT_MSG_ADDON", "StackRivals", a.ns.Protocol.encode("HEL", "0.6.1", 1), "WHISPER", 9999)
    net.step(5)
    eq(a.ns.Comm.stats.received, before)
    eq(a.ns.BNet.stats.unknown, 1)
  end)

  it("not mutual friends: Battle.net doesn't deliver, nothing breaks", function()
    local net, a, f = pair(5, nil, { bnet = {} })
    a.ns.Duel.pingPresence({ "Frank-Faraway" })
    net.step(600)
    eq(a.ns.Duel.presence("Frank-Faraway"), nil)
    eq(f.ns.Comm.stats.received, 0)
  end)

  it("temporary game account IDs are never saved or used as names", function()
    local net, a, f = pair(6)
    a.ns.Duel.pingPresence({ "Frank-Faraway" }); net.step(60)
    ok(a.ns.Duel.presence("Frank-Faraway"))
    a.M.fire("PLAYER_LOGOUT")
    local hits = {}
    scan(a.env.StackRivalsDB, nil, hits)
    eq(#hits, 0, "SavedVariables hold no game account IDs: " .. table.concat(hits, ", "))
    for k in pairs(a.ns.Duel.players) do ok(type(k) == "string" and k:find("-", 1, true), "players by name: " .. tostring(k)) end
    ok(f)
  end)

  it("Quickplay finds a Battle.net friend on another realm", function()
    local net, a, f = pair(7)
    ok(a.ns.Quickplay.start("b120")); ok(f.ns.Quickplay.start("b120"))
    net.step(60 * 50)
    local m = a.ns.Duel.current
    ok(m and m.state == "lobby" and m.quickplay, "matched over Battle.net")
    eq(f.ns.Duel.current.rival, "Alice-Realm")
  end)

  it("match chat between Battle.net friends works across factions (as Battle.net whispers do)", function()
    local net, a, f = pair(8, { faction = "Alliance" }, { faction = "Horde" })
    a.ns.Duel.challenge("Frank-Faraway", "b120"); net.step(60)
    f.ns.Duel.accept(); net.step(120)
    eq(a.ns.Chat.mode(a.ns.Duel.current), "free")
    ok(a.ns.Chat.send(a.ns.Duel.current, "gl from the other side")); net.step(60)
    local l = f.ns.Duel.current.chat
    eq(l and l[#l].text, "gl from the other side")
  end)

  it("Trial / Veteran accounts: no Battle.net transport either", function()
    local net = NS.new({ seed = 9 })
    local a = net.add({ name = "Alice", bnet = { { name = "Frank", realm = "Faraway" } }, beforeLogin = function(env) env.IsTrialAccount = function() return true end end })
    net.step(10)
    eq(a.ns.BNet.available(), false)
  end)
end)

return H
