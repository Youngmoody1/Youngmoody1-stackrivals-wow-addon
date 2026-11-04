-- Quickplay, character cards and match chat between SIMULATED WoW clients (tests/netsim.lua).
-- None of this proves real-client behaviour (delivery, throttling, cross-faction / cross-realm
-- whispers, keyboard focus): see docs/WOW_QUICKPLAY_HANDOFF.md, "needs a real WoW test".
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local pure = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Engine/Verify.lua", "Net/Protocol.lua" })
local P = pure.Protocol

local function hex(s) return (s:gsub(".", function(ch) return string.format("%02x", ch:byte()) end)) end
local function sec(net, s) net.step(math.floor(s * 60)) end
local function qp(c) return c.ns.Quickplay end
local function cur(c) return c.ns.Duel.current end
local function tap(net)
  local seen = {}
  net.tap = function(c, text, channel, target) seen[#seen + 1] = { from = c.name, text = text, channel = channel, target = target } end
  return seen
end
--- Two guild mates who both press Search (Blitz) and get matched into the lobby.
local function matched(oa, ob, seed)
  local net = NS.new({ seed = seed or 1 })
  oa = oa or {}; ob = ob or {}
  oa.name = oa.name or "Alice"; ob.name = ob.name or "Bob"
  oa.guild = oa.guild or "G"; ob.guild = ob.guild or "G"
  local a, b = net.add(oa), net.add(ob)
  sec(net, 1)
  ok(qp(a).start("b120")); ok(qp(b).start("b120"))
  sec(net, 5)
  return net, a, b
end

describe("protocol: Quickplay, cards, chat", function()
  it("QS / PRF / CH / QM round-trip, fit 255 bytes, and INV carries the Quickplay flag", function()
    local msgs = {
      P.encode("QS", "q1w2e3", "b120", "0.6.1"),
      P.encode("PRF", "abc123", "H", "Orc", "SHAMAN", 38, P.b36(12), P.b36(8), 1),
      P.encode("PRF", "abc123", "-", "-", "-", 0, P.b36(0), P.b36(0), 0),
      P.encode("CH", "abc123", 1, hex(string.rep("x", 80))),
      P.encode("QM", "abc123", 2, 4),
      P.encode("INV", "abc123", "s180", 1, "n0nce123", "q"),
    }
    for _, s in ipairs(msgs) do ok(#s <= 255, s); ok(P.decode(s), "decode " .. s) end
    local m = P.decode(msgs[2])
    eq(m.faction, "Horde"); eq(m.race, "Orc"); eq(m.class, "SHAMAN"); eq(m.level, 38); eq(m.wins, 12); eq(m.losses, 8); eq(m.chat, true)
    m = P.decode(msgs[3])
    ok(m.faction == nil and m.race == nil and m.class == nil, "'-' = not shared"); eq(m.level, 0)
    eq(P.decode(msgs[4]).text, string.rep("x", 80))
    eq(P.decode(msgs[6]).quickplay, true)
    ok(not P.decode(P.encode("INV", "abc123", "b120", 1, "n0nce123")).quickplay)
  end)
  it("manipulated cards and chat packets are rejected", function()
    local bad = {
      "1:PRF:abc123:X:Orc:SHAMAN:38:c:8:1",          -- unknown faction
      "1:PRF:abc123:H:Orc:SHAMAN:999:c:8:1",         -- level out of range
      "1:PRF:abc123:H:Orc:SHAMAN:-1:c:8:1",
      "1:PRF:abc123:H:Orc1:SHAMAN:38:c:8:1",         -- race not a token
      "1:PRF:abc123:H:" .. string.rep("A", 17) .. ":SHAMAN:38:c:8:1",
      "1:PRF:abc123:H:Orc:SHAMAN:38:zzzzzzz:8:1",    -- 78 billion wins
      "1:PRF:abc123:H:Orc:SHAMAN:38:c:8:2",          -- chat flag
      "1:PRF:abc123:H:Orc:SHAMAN:38:c:8",            -- missing field
      "1:CH:abc123:1:abc",                           -- odd hex
      "1:CH:abc123:1:ZZ",                            -- not hex
      "1:CH:abc123:1:" .. string.rep("ab", 81),      -- 81 bytes
      "1:CH:abc123:0:6869",                          -- n = 0
      "1:QM:abc123:1:5",                             -- no quick message 5
      "1:QM:abc123:1:0",
      "1:QS:q1w2e3:zz99:0.6.1",                      -- unknown ruleset
      "2:QS:q1w2e3:b120:0.6.1",                      -- other protocol version
      "1:INV:abc123:b120:1:n0nce123:x",              -- unknown flag
      "1:INV:abc123:b120:1:n0nce123:q:q",
    }
    for _, s in ipairs(bad) do ok(P.decode(s) == nil, "accepted bad packet: " .. s) end
  end)
end)

describe("game mode names (display only; ids, protocol and saved data unchanged)", function()
  it("WoW-style names on the menu, sheets and lobby; the internal ids are the same as before", function()
    local net = NS.new({ seed = 40 })
    local a = net.add({ name = "Alice", guild = "G", saved = { seenHelp = true } })
    sec(net, 1)
    local ns = a.ns
    -- ids (saved records, protocol, SR1 / SR2) unchanged
    ok(ns.Session.MODES.blitz and ns.Session.MODES.daily and ns.Session.MODES.classic and ns.Session.MODES.spellbot)
    ok(ns.Protocol.RULESETS.b120 and ns.Protocol.RULESETS.r180 and ns.Protocol.RULESETS.s180)
    eq(ns.Session.MODES.blitz.limitTicks, 7200); eq(ns.Protocol.RULESETS.r180.limitTicks, 10800)
    -- names
    eq(ns.Session.MODES.classic.name, "Classic")
    eq(ns.Session.MODES.blitz.name, "Time Trial")
    eq(ns.Session.MODES.daily.name, "Daily Challenge")
    eq(ns.Session.MODES.spellbot.name, "Spell Battle")
    eq(ns.Protocol.RULESETS.b120.name, "Duel 2:00")
    eq(ns.Protocol.RULESETS.r180.name, "Duel 3:00")
    eq(ns.Protocol.RULESETS.s180.name, "Spell Duel 3:00")
    a.env.SlashCmdList.STACKRIVALS("")
    local UI = ns.UI
    eq(UI.modeButtons.blitz.fs:GetText(), "Time Trial")
    eq(UI.modeButtons.daily.fs:GetText(), "Daily Challenge")
    eq(UI.qpBar.fs:GetText(), "QUICKPLAY")
    ok(UI.qpBar.desc:GetText():find("Quick Duel"), UI.qpBar.desc:GetText())
    eq(UI.duelBtn.fs:GetText(), "Guild Duel")
    eq(UI.spellCard.fs:GetText(), "Spell Battle")
    UI:ShowSheet("duel")
    eq(UI.duelSheet.b120.fs:GetText(), "Duel 2:00"); eq(UI.duelSheet.r180.fs:GetText(), "Duel 3:00"); eq(UI.duelSheet.s180.fs:GetText(), "Spell Duel")
    UI:ShowSheet("quickplay")
    eq(UI.qpSheet.b120.fs:GetText(), "Duel 2:00"); eq(UI.qpSheet.s180.fs:GetText(), "Spell Duel 3:00")
    -- /sr trial = Time Trial (the old /sr blitz still works)
    a.env.SlashCmdList.STACKRIVALS("trial")
    eq(ns.App.session.mode.key, "blitz")
  end)
end)

describe("Quickplay (simulated clients)", function()
  it("two players searching Blitz in one guild are matched, the lower name invites, no popup, lobby = ready check", function()
    local net, a, b = matched()
    local ma, mb = cur(a), cur(b)
    ok(ma and mb, "both have the match")
    eq(ma.mid, mb.mid)
    eq(ma.state, "lobby"); eq(mb.state, "lobby")
    eq(ma.role, "host", "Alice < Bob: Alice invites")
    ok(ma.quickplay and mb.quickplay, "flagged as Quickplay on both PCs")
    eq(qp(a).state, "matched"); eq(qp(b).state, "matched")
    ok(not b.ns.UI.invite:IsShown(), "no invite popup: Bob was searching for exactly this")
    eq(ma.rulesetId, "b120")
    a.ns.Duel.ready(); b.ns.Duel.ready()
    sec(net, 2)
    eq(cur(a).state, "playing"); eq(cur(b).state, "playing")
    eq(qp(a).state, "idle", "the duel took over")
  end)

  it("the lobby shows MATCH FOUND and both character cards (rival's marked unverified)", function()
    local net, a, b = matched({ faction = "Alliance", race = "Human", class = "WARRIOR", level = 42 },
      { faction = "Horde", race = "Orc", class = "SHAMAN", level = 38 })
    sec(net, 1)
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.UI:RefreshPhase()
    local o = a.ns.UI.lobby
    ok(o:IsShown(), "lobby shown")
    ok(o.rules:GetText():find("MATCH FOUND"), o.rules:GetText())
    local rc = cur(a).rivalCard
    ok(rc and rc.selfReported, "Bob's card arrived")
    eq(rc.faction, "Horde"); eq(rc.race, "Orc"); eq(rc.class, "SHAMAN"); eq(rc.level, 38)
    eq(o.themCard.faction:GetText(), "HORDE")
    eq(o.themCard.line2:GetText(), "Orc |cff0070ddShaman|r  -  Level 38", "class name in WoW's class colour")
    ok(o.themCard.line4:GetText():find("unverified"), o.themCard.line4:GetText())
    eq(o.meCard.faction:GetText(), "ALLIANCE")
    ok(not o.meCard.line4:GetText():find("unverified"), "your own card comes from WoW")
    eq(a.M.chat[1], nil, "nothing posted to a WoW chat channel")
  end)

  it("nobody else searching: 'no opponent' after 5 minutes, few messages, no duel", function()
    local net = NS.new({ seed = 2 })
    local a = net.add({ name = "Alice", guild = "G" })
    net.add({ name = "Bob", guild = "G" }) -- has StackRivals but isn't searching
    sec(net, 1)
    local before = net.sent
    ok(qp(a).start("b120"))
    sec(net, qp(a).SEARCH_MAX + 2)
    eq(qp(a).state, "none"); eq(qp(a).note, "no_opponent")
    eq(cur(a), nil, "no duel")
    ok(net.sent - before <= 20, "one guild announcement per 20 s: " .. (net.sent - before))
  end)

  it("Cancel stops the search: a later searcher doesn't find you", function()
    local net = NS.new({ seed = 3 })
    local a = net.add({ name = "Alice", guild = "G" })
    local b = net.add({ name = "Bob", guild = "G" })
    sec(net, 1)
    qp(a).start("b120"); sec(net, 2)
    qp(a).cancel("cancelled")
    eq(qp(a).state, "idle")
    qp(b).start("b120"); sec(net, 45)
    eq(cur(a), nil); eq(cur(b), nil)
    eq(qp(b).state, "searching")
  end)

  it("different modes never match (Blitz vs Spell Battle)", function()
    local net = NS.new({ seed = 4 })
    local a = net.add({ name = "Alice", guild = "G" })
    local b = net.add({ name = "Bob", guild = "G" })
    sec(net, 1)
    qp(a).start("b120"); qp(b).start("s180")
    sec(net, 45)
    eq(cur(a), nil); eq(cur(b), nil)
  end)

  it("Spell Battle 3:00 Quickplay matches into an s180 lobby", function()
    local net = NS.new({ seed = 5 })
    local a = net.add({ name = "Alice", guild = "G" })
    local b = net.add({ name = "Bob", guild = "G" })
    sec(net, 1)
    qp(a).start("s180"); qp(b).start("s180")
    sec(net, 5)
    ok(cur(a) and cur(a).rulesetId == "s180" and cur(a).state == "lobby", "s180 lobby")
  end)

  it("three searchers: two are paired, the third keeps searching (no double booking)", function()
    local net = NS.new({ seed = 6 })
    local cs = { net.add({ name = "Alice", guild = "G" }), net.add({ name = "Bob", guild = "G" }), net.add({ name = "Carol", guild = "G" }) }
    sec(net, 1)
    for _, c in ipairs(cs) do qp(c).start("b120") end
    sec(net, 45)
    local inLobby, searching = {}, 0
    for _, c in ipairs(cs) do
      local m = cur(c)
      if m and m.state == "lobby" then inLobby[#inLobby + 1] = c end
      if qp(c).state == "searching" then searching = searching + 1 end
    end
    eq(#inLobby, 2, "exactly one pair")
    eq(searching, 1, "the third is still searching")
    local x, y = inLobby[1], inLobby[2]
    ok(x.ns.Comm.same(cur(x).rival, y.name) and y.ns.Comm.same(cur(y).rival, x.name), "paired with each other")
  end)

  it("a matched player who never presses Ready: the other searches again and skips them; the AFK one stops", function()
    local net, a, b = matched(nil, nil, 7)
    a.ns.Duel.ready()
    sec(net, a.ns.Duel.LOBBY_TIMEOUT + a.ns.Duel.GUEST_GRACE + 5)
    eq(qp(a).state, "searching"); eq(qp(a).note, "fell_through")
    eq(qp(b).state, "idle"); eq(qp(b).note, "you_not_ready")
    qp(b).start("b120")
    sec(net, 30)
    eq(cur(a), nil, "Bob is skipped for 2 minutes")
  end)

  it("Cancel in the Quickplay lobby: back to idle, the rival searches on", function()
    local net, a, b = matched(nil, nil, 8)
    a.ns.Duel.leave()
    sec(net, 3)
    eq(qp(a).state, "idle"); eq(qp(a).note, "cancelled")
    eq(qp(b).state, "searching"); eq(qp(b).note, "fell_through")
  end)

  it("an unsolicited Quickplay invite is ignored: no duel, no popup, no answer", function()
    local net = NS.new({ seed = 9 })
    local a = net.add({ name = "Alice", guild = "G" })
    sec(net, 1)
    local seen = tap(net)
    local commit = a.ns.Protocol.commit("abc123", "n0nce123")
    net.inject(a, "Mallory-Realm", P.encode("INV", "abc123", "b120", 1, commit, "q"))
    sec(net, 2)
    eq(cur(a), nil); ok(not a.ns.UI.invite:IsShown())
    eq(#seen, 0, "not even a decline")
    -- searching for Spell Battle: a Blitz Quickplay invite is still not for you
    qp(a).start("s180"); sec(net, 1)
    net.inject(a, "Mallory-Realm", P.encode("INV", "abd123", "b120", 1, a.ns.Protocol.commit("abd123", "n0nce123"), "q"))
    sec(net, 2)
    eq(cur(a), nil)
  end)

  it("an ignored player is never matched", function()
    local net = NS.new({ seed = 10 })
    local a = net.add({ name = "Alice", guild = "G", ignored = { Bob = true } })
    local b = net.add({ name = "Bob", guild = "G" })
    sec(net, 1)
    qp(a).start("b120"); qp(b).start("b120")
    sec(net, 60)
    eq(cur(a), nil)
    ok(not (cur(b) and cur(b).state == "lobby"), "Bob's invite goes unanswered")
  end)

  it("different realms: a friend on another realm is found through their answered presence", function()
    local net = NS.new({ seed = 11 })
    local a = net.add({ name = "Alice", friends = { "Dan-Faraway" }, connected = { "Faraway" } })
    local d = net.add({ name = "Dan", realm = "Faraway", friends = { "Alice-Realm" }, connected = { "Realm" } })
    sec(net, 1)
    qp(a).start("b120"); qp(d).start("b120")
    sec(net, 50)
    local m = cur(a)
    ok(m and m.state == "lobby", "matched across realms (simulated: real delivery needs connected realms)")
    a.env.SlashCmdList.STACKRIVALS(""); a.ns.UI:RefreshPhase()
    eq(a.ns.UI.lobby.themCard.line3:GetText(), "Faraway")
    eq(a.ns.UI.lobby.themCard.name:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), "Dan")
  end)

  it("an older StackRivals (no Quickplay) is never matched and nothing breaks", function()
    local net = NS.new({ seed = 12 })
    local a = net.add({ name = "Alice", guild = "G" })
    local old = net.add({ name = "Bob", guild = "G", beforeLogin = function(_, _, ns)
      -- 0.6.0 behaviour on the wire: QS / PRF / CH / QM are unknown kinds (not handled), no card sent
      ns.Quickplay.init, ns.Card.init, ns.Chat.init = function() end, function() end, function() end
      ns.Card.send = function() end
    end })
    sec(net, 1)
    qp(a).start("b120")
    sec(net, 60)
    eq(cur(a), nil); eq(old.ns.Duel.current, nil)
    -- and a normal challenge between them still works (old client: no cards, no chat)
    a.ns.Duel.challenge(old.name, "b120"); sec(net, 2)
    old.ns.Duel.accept(); sec(net, 2)
    eq(cur(a).state, "lobby")
    eq(cur(a).rivalCard, nil, "no card from an older client")
    eq(a.ns.Chat.mode(cur(a)), "off")
  end)

  it("rematch after a Quickplay match is a normal invite the rival must accept", function()
    local net, a, b = matched(nil, nil, 13)
    a.ns.Duel.ready(); b.ns.Duel.ready()
    sec(net, 5)
    -- both top out fast (hard drops): the match is decided in seconds
    for _ = 1, 2400 do
      for _, c in ipairs({ a, b }) do
        local s = c.ns.App.session
        if s and s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end
      end
      net.step(1)
      if cur(a).state == "done" and cur(b).state == "done" then break end
    end
    eq(cur(a).state, "done")
    sec(net, 3)
    ok(a.ns.Duel.rematch(), "rematch sent")
    sec(net, 2)
    eq(cur(b).state, "invited", "Bob gets a normal invite")
    ok(b.ns.UI.invite:IsShown(), "with the popup")
    ok(not cur(b).quickplay, "not a Quickplay invite")
    b.ns.Duel.accept(); sec(net, 2)
    eq(cur(a).state, "lobby")
  end)
end)

describe("match chat (simulated clients)", function()
  local function lastLine(c) local l = cur(c).chat; return l and l[#l] end

  it("same faction: text both ways, escaped, never on a WoW channel", function()
    local net, a, b = matched(nil, nil, 20)
    sec(net, 1)
    local seen = tap(net)
    eq(a.ns.Chat.mode(cur(a)), "free")
    ok(a.ns.Chat.send(cur(a), "Good luck |cffff0000|Hitem:1|h[x]|h|r!"))
    sec(net, 1)
    local l = lastLine(b)
    ok(l and not l.me, "Bob got it")
    ok(not l.text:find("|c", 1, true) or l.text:find("||c", 1, true), "escape codes neutralised: " .. l.text)
    ok(l.text:find("||Hitem", 1, true), "links can't be injected")
    for _, s in ipairs(seen) do ok(s.channel == "WHISPER", "chat only whispers the rival: " .. s.channel) end
    eq(a.M.chat[1], nil); eq(b.M.chat[1], nil)
    ok(b.ns.Chat.send(cur(b), "you too"))
    sec(net, 1)
    eq(lastLine(a).text, "you too")
  end)

  it("quick messages GL / GG / WP / Rematch? arrive as their text", function()
    local net, a, b = matched(nil, nil, 21)
    sec(net, 1)
    ok(a.ns.Chat.quick(cur(a), 1)); sec(net, 2)
    ok(a.ns.Chat.quick(cur(a), 4)); sec(net, 1)
    eq(lastLine(b).text, "Rematch?"); ok(lastLine(b).quick)
  end)

  it("rate limits: 1 line per 1.5 s and 8 per 30 s when sending; a flood from the rival is cut at 10", function()
    local net, a, b = matched(nil, nil, 22)
    sec(net, 1)
    ok(a.ns.Chat.send(cur(a), "one"))
    local okS, why = a.ns.Chat.send(cur(a), "two")
    ok(not okS and why == "slow down", "second line in the same moment is refused")
    local sent = 1
    for _ = 1, 12 do sec(net, 1.6); if a.ns.Chat.send(cur(a), "x") then sent = sent + 1 end end
    ok(sent <= 9 and sent >= 8, "at most 8 per 30 s (+1 after the window moved): " .. sent)
    -- a hostile rival floods 20 lines at once (bypassing their own limiter)
    local mid = cur(a).mid
    for n = 100, 119 do net.inject(a, b.name, P.encode("CH", mid, n, hex("spam " .. n))) end
    sec(net, 1)
    local fromBob = 0
    for _, l in ipairs(cur(a).chat) do if not l.me then fromBob = fromBob + 1 end end
    ok(fromBob <= 10, "flood cut: " .. fromBob)
    ok((cur(a).chatDropped or 0) >= 10, "dropped counted")
  end)

  it("mute hides that player's lines and is remembered; they are not told", function()
    local net, a, b = matched(nil, nil, 23)
    sec(net, 1)
    local seen = tap(net)
    a.ns.Chat.mute(cur(a), true)
    eq(#seen, 0, "muting sends nothing")
    ok(a.ns.db.chat.muted[b.name:lower()], "saved")
    b.ns.Chat.send(cur(b), "hello?"); sec(net, 1)
    eq(cur(a).chat, nil, "nothing shown")
    a.ns.Chat.mute(cur(a), false)
    sec(net, 2)
    b.ns.Chat.send(cur(b), "hello again"); sec(net, 1)
    eq(lastLine(a).text, "hello again")
  end)

  it("chat off: the rival's card says so, nothing can be sent either way", function()
    local net, a, b = matched(nil, nil, 24)
    sec(net, 1)
    b.env.SlashCmdList.STACKRIVALS(""); b.ns.UI:RefreshPhase()
    b.ns.UI.chat.onoff:Click() -- Bob turns match chat off
    sec(net, 1)
    eq(b.ns.db.chat.enabled, false)
    local mode, why = a.ns.Chat.mode(cur(a))
    eq(mode, "off"); ok(why:find("rival has match chat off"), why)
    ok(not a.ns.Chat.send(cur(a), "hi")); ok(not a.ns.Chat.quick(cur(a), 1))
    net.inject(b, a.name, P.encode("QM", cur(b).mid, 50, 2)); sec(net, 1)
    eq(cur(b).chat, nil, "Bob sees nothing while chat is off")
  end)

  it("different factions: quick messages only (free text refused and dropped)", function()
    local net, a, b = matched({ faction = "Alliance" }, { faction = "Horde" }, 25)
    sec(net, 1)
    eq(a.ns.Chat.mode(cur(a)), "quick")
    ok(not a.ns.Chat.send(cur(a), "hello"))
    net.inject(a, b.name, P.encode("CH", cur(a).mid, 7, hex("sneaky text"))); sec(net, 1)
    eq(cur(a).chat, nil, "free text across factions is dropped")
    ok(a.ns.Chat.quick(cur(a), 2)); sec(net, 1)
    eq(lastLine(b).text, "GG!")
  end)

  it("lines from someone who is not your rival, or for another match, are ignored", function()
    local net, a = matched(nil, nil, 26)
    sec(net, 1)
    net.inject(a, "Mallory-Realm", P.encode("CH", cur(a).mid, 1, hex("hi from mallory")))
    net.inject(a, "Mallory-Realm", P.encode("PRF", cur(a).mid, "H", "Orc", "WARRIOR", 60, P.b36(999), P.b36(0), 1))
    sec(net, 1)
    eq(cur(a).chat, nil)
    ok(cur(a).rivalCard.wins ~= 999, "a third party can't overwrite the rival's card")
  end)

  it("a forged card can't change anyone's results", function()
    local net, a, b = matched(nil, nil, 27)
    sec(net, 1)
    local before = a.ns.db.duels.wins
    net.inject(a, b.name, P.encode("PRF", cur(a).mid, "H", "Orc", "WARRIOR", 60, P.b36(1e7), P.b36(0), 1))
    net.inject(a, b.name, P.encode("PRF", cur(a).mid, "H", "Orc", "WARRIOR", 999, P.b36(5), P.b36(0), 1)) -- rejected
    sec(net, 1)
    eq(cur(a).rivalCard.wins, 1e7, "shown as the rival's own claim")
    eq(cur(a).rivalCard.level, 60, "the out-of-range card was rejected")
    ok(cur(a).rivalCard.selfReported)
    eq(a.ns.db.duels.wins, before, "your records are untouched")
  end)

  it("rival disconnects during the match: chat turns off with a reason", function()
    local net, a, b = matched(nil, nil, 28)
    a.ns.Duel.ready(); b.ns.Duel.ready()
    sec(net, 10)
    b.online = false
    sec(net, 90)
    local m = cur(a)
    local mode, why = a.ns.Chat.mode(m)
    eq(mode, "off"); ok(why:find("lost contact"), why .. " / " .. tostring(m.endReason))
  end)

  it("the chat panel: shows in the lobby, folds into a tab with unread count, sends with Enter", function()
    local net, a, b = matched(nil, nil, 29)
    sec(net, 1)
    a.env.SlashCmdList.STACKRIVALS(""); a.ns.UI:RefreshPhase()
    local p = a.ns.UI.chat
    ok(p:IsShown(), "panel shown in the lobby")
    p.input:SetText("hello bob")
    p.input:GetScript("OnEnterPressed")(p.input)
    sec(net, 1)
    eq(lastLine(b).text, "hello bob")
    eq(p.input:GetText(), "")
    p.close:Click()
    ok(not p:IsShown() and a.ns.UI.chatTab:IsShown(), "folded")
    b.ns.Chat.quick(cur(b), 2); sec(net, 2)
    eq(a.ns.UI.chatTab.fs:GetText(), "Chat (1)")
    a.ns.UI.chatTab:Click()
    ok(p:IsShown())
    local found = false
    for _, fs in ipairs(p.lines) do if (fs:GetText() or ""):find("GG!", 1, true) then found = true end end
    ok(found, "GG! shown")
  end)
end)

return H
