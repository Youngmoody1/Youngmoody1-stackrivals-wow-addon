-- Spell Battle between two SIMULATED WoW clients (tests/netsim.lua): loadouts at Ready, spells
-- crossing as SP messages, the lockstep replay result on both PCs, lag, lost / duplicated /
-- forged messages, old clients. Simulated: two real WoW clients are still needed
-- (docs/MULTIPLAYER_TEST.md).
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local pure = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Engine/Verify.lua", "Engine/Spells.lua", "Net/Protocol.lua" })
local P, S = pure.Protocol, pure.Spells

describe("protocol: Spell Battle additions", function()
  it("SP, RDY + loadout, GO + loadout round-trip; s180 is a ruleset", function()
    local m = P.decode(P.encode("SP", "abc123", 3, P.b36(4321), S.INDEX.garbage))
    eq(m.kind, "SP"); eq(m.seq, 3); eq(m.tick, 4321); eq(m.spell, "garbage")
    eq(P.decode(P.encode("RDY", "abc123", "1057")).loadout, "1057")
    eq(P.decode(P.encode("RDY", "abc123")).loadout, nil, "classic Ready unchanged")
    eq(P.decode(P.encode("GO", "abc123", "n0nce123", "1057")).loadout, "1057")
    eq(P.encode("RDY", "abc123", nil), "1:RDY:abc123", "no trailing field when there is no loadout")
    ok(P.decode(P.encode("INV", "abc123", "s180", 1, "n0nce123")))
  end)
  it("rejects forged spell packets: self spells, unknown spells, bad loadouts, bad seq", function()
    for _, s in ipairs({
      "1:SP:abc123:1:5:0",        -- bomb is a self spell: never sent
      "1:SP:abc123:1:5:9",        -- no spell 9
      "1:SP:abc123:0:5:5",        -- seq starts at 1
      "1:SP:abc123:1:-5:5", "1:SP:abc123:1:5", "1:SP:abc123:1:5:5:x",
      "1:RDY:abc123:0012",        -- 3 self spells
      "1:RDY:abc123:105",         -- 3 spells
      "1:RDY:abc123:1057:x",
      "1:GO:abc123:n0nce123:9999",
    }) do ok(P.decode(s) == nil, "accepted " .. s) end
  end)
  it("the log codec carries casts (H..P) and old logs are unchanged", function()
    local log = { 0, 0, 3, 105, 3, 5, 10, 100, 250, 108, 251, 6 }
    local packed = P.packLog(log)
    eq(packed:match("[H-P]") ~= nil, true)
    local back = P.unpackLog(packed)
    eq(table.concat(back, ","), table.concat(log, ","))
    eq(P.packLog({ 1, 0, 2, 5 }), "1A1F", "classic logs pack exactly as in 0.4")
    for _, ch in ipairs(P.chunk(string.rep("1H", 150))) do ok(ch:sub(-1) == "H") end
  end)
  it("version gate: 0.4.x can't play s180, 0.5.0+ can", function()
    ok(not P.versionAtLeast("0.4.0", "0.5.0")); ok(P.versionAtLeast("0.5.0", "0.5.0")); ok(P.versionAtLeast("0.10.1", "0.5.0"))
    ok(not P.versionAtLeast("dev", "0.5.0"))
  end)
end)

------------------------------------------------------------------------------------------------
-- Full duels
------------------------------------------------------------------------------------------------
local function pair(opts)
  local net = NS.new(opts)
  local a = net.add({ name = "Alice", guild = "G" })
  local b = net.add({ name = "Bob", guild = "G" })
  return net, a, b
end

-- the web's spell bot plays each client through the real keys
local function spellPlayer(c, seed, diff)
  local bot
  return function()
    local s = c.ns.App.session
    if not (s and s.spell and s.phase == "playing") then return end
    bot = bot or c.ns.Bot.SpellBot.new(seed, diff or "elite")
    local m = s.duel
    local opp = { game = { score = m and m.rival_.score or 0 } }
    local code = bot:act(s.spell.me, opp)
    if not code then return end
    local spell = c.ns.Spells.spellOfCode(code)
    if spell then
      for i, x in ipairs(s.spell.me.loadout) do if x == spell then s:press("spell" .. i) end end
    else
      local a = c.ns.Engine.INPUT_ACTIONS[code + 1]
      s:press(a); s:release(a)
    end
  end
end

local function startSpellDuel(net, a, b, loA, loB)
  a.ns.db.spell.loadout = S.encodeLoadout(loA or { "lineBlast", "bomb", "garbage", "speedUp" })
  b.ns.db.spell.loadout = S.encodeLoadout(loB or { "freeze", "clearBoard", "garbage", "blackout" })
  ok(a.ns.Duel.challenge("Bob", "s180"))
  local function wait(cond) for _ = 1, 600 do if cond() then return end; net.step(5) end end
  wait(function() return b.ns.Duel.current and b.ns.Duel.current.state == "invited" end)
  b.ns.Duel.accept()
  wait(function() return a.ns.Duel.current.state == "lobby" end)
  a.ns.Duel.ready(); b.ns.Duel.ready()
  wait(function() return a.ns.Duel.current.state == "playing" and b.ns.Duel.current.state == "playing" end)
  return a.ns.Duel.current, b.ns.Duel.current
end

local function play(net, a, b, frames, pa, pb)
  pa = pa or spellPlayer(a, "pa", "elite")
  pb = pb or spellPlayer(b, "pb", "contender")
  for _ = 1, frames do pa(); pb(); net.step(1) end
end

local function finishBoth(net, a, b)
  local n = 0
  while n < 60 * 120 and not (a.ns.Duel.current.state == "done" and b.ns.Duel.current.state == "done") do net.step(30); n = n + 30 end
end

describe("Spell Battle duel between two simulated clients", function()
  it("loadouts lock at Ready, spells cross, both PCs replay to the same result", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    eq(ma.state, "playing"); eq(mb.state, "playing")
    eq(ma.rivalLoadout, b.ns.db.spell.loadout); eq(mb.rivalLoadout, a.ns.db.spell.loadout)
    local sa, sb = a.ns.App.session, b.ns.App.session
    ok(sa.spell and sa.spell.remote and sb.spell and sb.spell.remote, "both in a remote Spell Battle")
    -- changing your saved spells after Ready does not change this match
    a.ns.db.spell.loadout = S.encodeLoadout(S.DEFAULT_LOADOUT)
    play(net, a, b, 10800 + 400)
    finishBoth(net, a, b)
    eq(ma.state, "done"); eq(mb.state, "done")
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked")
    -- the same two numbers on both PCs, mirrored
    eq(ma.myScore, mb.theirScore); eq(ma.theirScore, mb.myScore)
    local opposite = { win = "loss", loss = "win", draw = "draw" }
    eq(mb.outcome, opposite[ma.outcome])
    local castA, castB = #sa.spell.me.casts, #sb.spell.me.casts
    ok(castA + castB > 2, "spells were cast: " .. castA .. " / " .. castB)
    local hitsB = 0
    for _, h in ipairs(sb.spell.me.hits) do if not h.fromSelf then hitsB = hitsB + 1 end end
    ok(hitsB > 0 or castA == 0, "Alice's spells landed on Bob's board")
    -- low latency: every spell arrived before its landing tick, so the live games ARE the replay
    eq(ma.spell.diverged, false, "Alice's live view = replay"); eq(mb.spell.diverged, false, "Bob's live view = replay")
    eq(ma.myScore, ma.spell.myLive)
  end)

  it("heavy lag (2-2.5 s): spells land late live, the replay still decides the same result on both PCs", function()
    local net, a, b = pair({ latency = { 2.0, 2.5 } })
    local ma, mb = startSpellDuel(net, a, b, nil, { "lineBlast", "bomb", "garbage", "speedUp" })
    play(net, a, b, 10800 + 400, spellPlayer(a, "pa", "elite"), spellPlayer(b, "pb", "rival"))
    finishBoth(net, a, b)
    eq(ma.state, "done"); eq(mb.state, "done")
    ok(ma.endReason == "checked" and mb.endReason == "checked", ma.endReason .. " / " .. mb.endReason)
    eq(ma.myScore, mb.theirScore); eq(ma.theirScore, mb.myScore)
    local late = ma.spell.late + mb.spell.late
    -- Bob starts ~2 s after Alice (GO travels 2 s), so Bob's spells reach Alice after their landing tick
    local bobOpp = 0
    for _, c in ipairs(b.ns.App.session.spell.me.casts) do if S.INFO[c.spell].target == "opponent" then bobOpp = bobOpp + 1 end end
    ok(bobOpp == 0 or late > 0, "Bob cast " .. bobOpp .. " spells at Alice; late: " .. late)
    print(string.format("    lag: %d + %d casts, %d late, live view differed: Alice %s, Bob %s; replay %d - %d",
      #a.ns.App.session.spell.me.casts, #b.ns.App.session.spell.me.casts, late, tostring(ma.spell.diverged), tostring(mb.spell.diverged), ma.myScore, ma.theirScore))
  end)

  it("lost and duplicated messages: each spell lands once; the result still agrees", function()
    local net, a, b = pair({ drop = 0.15, dup = 0.3 })
    local ma, mb = startSpellDuel(net, a, b)
    if ma.state ~= "playing" then return end -- a lost GO is covered by the duel tests
    play(net, a, b, 10800 + 400)
    finishBoth(net, a, b)
    eq(ma.myScore, mb.theirScore); eq(ma.theirScore, mb.myScore)
    -- no spell was applied twice: Bob's incoming hits <= Alice's sent casts
    local sentA = #(ma.outCasts or {})
    local hitsB = 0
    for _, h in ipairs(b.ns.App.session.spell.me.hits) do if not h.fromSelf then hitsB = hitsB + 1 end end
    ok(hitsB <= sentA, hitsB .. " hits from " .. sentA .. " casts")
  end)

  it("a forged spell (not in the sender's log) is caught: the forger's result is rejected", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    -- "Alice" sends Bob a garbage that her game never cast
    net.step(300)
    local tick = a.ns.App.session.state.tick
    net.inject(b, "Alice-Realm", P.encode("SP", ma.mid, 77, P.b36(tick), S.INDEX.garbage))
    play(net, a, b, 10800 + 400)
    finishBoth(net, a, b)
    eq(mb.endReason, "check_failed", "Bob rejects Alice's result"); eq(mb.outcome, "win")
    eq(ma.endReason, "checked", "Alice (who didn't forge in her own log) still checks Bob fine")
  end)

  it("spells that break the live rules are refused at once (not in the loadout, cooldown, after 3:00)", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b, nil, nil)
    net.step(400)
    local sb = b.ns.App.session
    local before = #sb.spell.pendingMe
    -- Alice's loadout is lineBlast, bomb, garbage, speedUp: blackout is not in it
    net.inject(b, "Alice-Realm", P.encode("SP", ma.mid, 50, P.b36(100), S.INDEX.blackout))
    net.inject(b, "Alice-Realm", P.encode("SP", ma.mid, 51, P.b36(200), S.INDEX.garbage))
    net.inject(b, "Alice-Realm", P.encode("SP", ma.mid, 52, P.b36(250), S.INDEX.speedUp)) -- 50 ticks later: cooldown
    net.inject(b, "Alice-Realm", P.encode("SP", ma.mid, 53, P.b36(11000), S.INDEX.speedUp))
    net.inject(b, "Alice-Realm", P.encode("SP", ma.mid, 51, P.b36(200), S.INDEX.garbage)) -- repeat
    eq(#sb.spell.pendingMe - before, 1, "only the valid garbage was accepted, once")
    eq(mb.spRejected, 3)
  end)

  it("old addon (0.4) in the player list: Spell Battle can't be offered; classic duels still work", function()
    local net, a, b = pair()
    a.ns.Duel.players["Bob-Realm"] = { name = "Bob-Realm", addon = "0.4.0", engine = 1, compatible = true, at = 0 }
    local okC, why = a.ns.Duel.challenge("Bob", "s180")
    eq(okC, false); eq(why, "old")
    ok(a.ns.Duel.challenge("Bob", "b120"), "score race is still offered")
  end)

  it("both top out early: replay ends both runs, results agree", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local function dropper(c) return function() local s = c.ns.App.session; if s and s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end end end
    play(net, a, b, 2000, dropper(a), dropper(b))
    finishBoth(net, a, b)
    eq(ma.state, "done"); eq(mb.state, "done")
    eq(ma.myScore, mb.theirScore); eq(ma.theirScore, mb.myScore)
  end)

  it("rematch keeps the Spell Battle rules and asks for spells again", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local function dropper(c) return function() local s = c.ns.App.session; if s and s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end end end
    play(net, a, b, 2000, dropper(a), dropper(b))
    finishBoth(net, a, b)
    ok(a.ns.Duel.rematch())
    net.step(30)
    eq(a.ns.Duel.current.rulesetId, "s180"); eq(b.ns.Duel.current.rulesetId, "s180")
    eq(a.ns.Duel.current.myLoadout, nil, "spells are chosen again at Ready")
  end)
end)

return H
