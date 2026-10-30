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
  it("spell duel log = moves + casts + where the rival's spells landed; garbage is refused", function()
    local log = { 0, 0, 3, 105, 400, 5 }
    local land = { { tick = 95, castTick = 2, spell = "garbage" }, { tick = 300, castTick = 200, spell = "scramble" } }
    local packed = P.packSpellLog(log, land)
    local back, l2 = P.unpackSpellLog(packed)
    eq(table.concat(back, ","), table.concat(log, ","))
    eq(#l2, 2); eq(l2[2].tick, 300); eq(l2[2].castTick, 200); eq(l2[2].spell, "scramble")
    local b2, l3 = P.unpackSpellLog(P.packSpellLog(log, {}))
    eq(#b2, #log); eq(#l3, 0)
    for _, bad in ipairs({ packed .. "x", "1AZ5.3Q5.3", "1AZ5.3H", "1AZ9.1Q5.1Q", "1A" }) do
      ok(P.unpackSpellLog(bad) == nil, "accepted " .. bad)
    end
    for _, ch in ipairs(P.chunk(string.rep("1H", 120) .. "Z" .. string.rep("3k.2Q", 60))) do ok(ch:sub(-1):match("[A-Z]"), ch:sub(-3)) end
  end)
  it("SR1 codes stay classic-only: a log with casts is never encoded or accepted as SR1", function()
    local ns = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Engine/Verify.lua", "Engine/Spells.lua", "Net/Protocol.lua", "Net/Codes.lua" })
    local C = ns.Codes
    local r = { platform = "wow-forever", ruleset = "b120", seed = "abc123", ticks = 100, score = 10, lines = 0, level = 1,
      hash = "0011aabb", player = "Alice-Realm", log = { 1, 0, 5, 105 } }
    ok(not pcall(C.result, r), "a spell log can't become an SR1 code")
    r.log = { 1, 0, 5, 5 }
    local okC, code = pcall(C.result, r)
    ok(okC, tostring(code))
    local spellCode = code:gsub("1A4F", "1A4M") -- swap a hard drop for a cast letter
    local parsed, why = C.parseResult(spellCode)
    eq(parsed, nil); ok(why == "log" or why == "check", tostring(why))
  end)
  it("PSE carries the pause tick (optional); VER carries what the verdict rests on", function()
    local m = P.decode(P.encode("PSE", "abc123", 2, "combat", P.b36(4321)))
    eq(m.n, 2); eq(m.reason, "combat"); eq(m.tick, 4321)
    eq(P.decode(P.encode("PSE", "abc123", 2, "combat")).tick, nil, "without the tick (older build)")
    ok(P.decode("1:PSE:abc123:2:combat:!") == nil and P.decode("1:PSE:abc123:2:combat:1:2") == nil)
    for code, basis in pairs({ r = "replay", x = "rejected", f = "forfeit", t = "timeout", v = "void", ["1"] = "replay", ["0"] = "rejected" }) do
      eq(P.decode(P.encode("VER", "abc123", "w", P.b36(10), P.b36(20), code)).basis, basis, code)
    end
    ok(P.decode("1:VER:abc123:w:a:k:z") == nil, "unknown basis")
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
    -- (a whisper's sender can't be faked in WoW, so this models Alice's own client cheating;
    -- what Alice's PC concludes doesn't matter)
  end)

  it("withheld casts (a client that never sends its SP) can't hurt the rival: the replay lands spells only where they landed live", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    a.ns.Duel.sendCast = function() end
    play(net, a, b, 10800 + 400, spellPlayer(a, "pa", "rival"), spellPlayer(b, "pb", "elite"))
    finishBoth(net, a, b)
    ok(#a.ns.App.session.spell.me.casts > 0, "Alice cast spells")
    eq(mb.spell.diverged, false, "Bob's replay = what Bob saw")
    eq(mb.myScore, mb.spell.myLive, "Bob keeps his live score")
    eq(mb.endReason, "checked")
  end)

  it("unpaid casts (logged and sent without the mana) are caught", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local real = a.ns.Spells.canCast
    a.ns.Spells.canCast = function(side, spell, t) if side == a.ns.App.session.spell.me then return true end return real(side, spell, t) end
    net.step(300)
    a.ns.App.session:press("spell3"); net.step(400); a.ns.App.session:press("spell3")
    play(net, a, b, 10800 + 400, spellPlayer(a, "pa", "elite"), spellPlayer(b, "pb", "elite"))
    finishBoth(net, a, b)
    eq(mb.endReason, "check_failed", "Bob rejects the free garbage"); eq(mb.outcome, "win")
  end)

  it("an honest pause (combat, chat) mid-duel: spells land late, nobody is flagged, both replays = live", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local pa, pb = spellPlayer(a, "pa", "rival"), spellPlayer(b, "pb", "rival")
    play(net, a, b, 3000, pa, pb)
    a.ns.App:Pause("combat")
    play(net, a, b, 600, pa, pb)
    a.ns.App:Resume()
    play(net, a, b, 10800, pa, pb)
    finishBoth(net, a, b)
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked")
    eq(ma.spell.diverged, false); eq(mb.spell.diverged, false)
    eq(ma.myScore, mb.theirScore); eq(ma.theirScore, mb.myScore)
  end)

  it("a client that ignores incoming spells is caught by the sender", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    b.ns.SpellBattle.incoming = function() end -- Bob "never receives" anything
    play(net, a, b, 10800 + 400, spellPlayer(a, "pa", "rival"), spellPlayer(b, "pb", "elite"))
    finishBoth(net, a, b)
    local sent = 0
    for _, c in ipairs(a.ns.App.session.spell.me.casts) do if S.INFO[c.spell].target == "opponent" then sent = sent + 1 end end
    ok(sent > 1, "the test needs casts: " .. sent)
    eq(ma.endReason, "check_failed", sent .. " spells sent, none applied")
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

  it("disconnect right after casting (spell still on its way): the one who stays wins, nothing breaks", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    play(net, a, b, 2400)
    -- Bob casts, then his connection dies before the spell lands
    local sb = b.ns.App.session
    sb.spell.me.mana = 20
    sb:press("spell3"); net.step(2)
    b.online = false
    play(net, a, b, 10800, nil, function() end)
    finishBoth(net, a, b)
    eq(ma.state, "done")
    ok(ma.endReason == "rival_disconnected" or ma.endReason == "rival_offline" or ma.endReason == "unchecked", ma.endReason)
    ok(ma.outcome == "win" or ma.outcome == "void", ma.outcome)
  end)

  it("both PCs confirm the same result (verdict exchange): agreed", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    play(net, a, b, 10800 + 400)
    finishBoth(net, a, b)
    for _ = 1, 60 do if ma.agreement and mb.agreement then break end net.step(30) end
    eq(ma.agreement, "agreed"); eq(mb.agreement, "agreed")
  end)

  it("a pause (combat) pauses both runs; the rival can't resume alone; both go on together", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local pa, pb = spellPlayer(a, "pa", "elite"), spellPlayer(b, "pb", "elite")
    play(net, a, b, 1200, pa, pb)
    a.M.combat = true; a.M.fire("PLAYER_REGEN_DISABLED")
    play(net, a, b, 120, pa, pb)
    local sb = b.ns.App.session
    eq(sb.phase, "paused"); eq(sb.pauseReason, "rival")
    local tb, ta = sb.state.tick, a.ns.App.session.state.tick
    b.ns.App:Resume()
    play(net, a, b, 600, pa, pb)
    eq(sb.state.tick, tb, "Bob waits"); eq(a.ns.App.session.state.tick, ta, "Alice is paused")
    a.M.combat = false; a.M.fire("PLAYER_REGEN_ENABLED"); a.ns.App:Resume()
    play(net, a, b, 600, pa, pb)
    ok(sb.state.tick > tb and a.ns.App.session.state.tick > ta, "both run again")
    ok(math.abs(sb.state.tick - a.ns.App.session.state.tick) < 200, "clocks still together")
    play(net, a, b, 10800, pa, pb)
    finishBoth(net, a, b)
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked")
    eq(ma.myScore, mb.theirScore)
  end)

  it("pausing for more than 60 s in total forfeits the duel (never a free 'no result')", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    play(net, a, b, 600)
    a.ns.App:Pause("manual")
    play(net, a, b, 60 * 62)
    eq(ma.state, "done"); eq(ma.endReason, "you_pause_limit"); eq(ma.outcome, "loss")
    for _ = 1, 60 do if mb.state == "done" then break end; play(net, a, b, 300) end
    eq(mb.endReason, "rival_forfeited"); eq(mb.outcome, "win")
  end)

  it("a client that pauses without telling (and ignores the limit) is rejected by the clock check", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    a.ns.Duel.PAUSE_BUDGET = 1e9 -- modified client: no limit...
    local realSend = a.env.C_ChatInfo.SendAddonMessage
    a.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      if text:match("^1:PSE:") or text:match("^1:RSM:") then return 0 end -- ...and silent pauses
      return realSend(prefix, text, ch, tgt)
    end
    mb.rival05 = true
    local pa, pb = spellPlayer(a, "pa", "contender"), spellPlayer(b, "pb", "elite")
    play(net, a, b, 600, pa, pb)
    a.ns.App:Pause("manual")
    play(net, a, b, 60 * 95, pa, pb) -- keeps "talking" (scores) so it doesn't look disconnected
    eq(ma.state, "playing", "no self-forfeit: the client ignores the limit")
    a.ns.App:Resume()
    play(net, a, b, 10800, pa, pb)
    finishBoth(net, a, b)
    eq(mb.endReason, "check_failed"); eq(mb.check.reasons[1], "pause_limit")
  end)

  it("a client that holds back incoming spells is caught (landing far after it could arrive)", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local held = {}
    local real = b.ns.SpellBattle.incoming
    b.ns.SpellBattle.incoming = function(sess, castTick, spell) held[#held + 1] = { at = net.time + 15, sess = sess, castTick = castTick, spell = spell } end
    local pa, pb = spellPlayer(a, "pa", "rival"), spellPlayer(b, "pb", "elite")
    for _ = 1, 10800 + 600 do
      pa(); pb(); net.step(1)
      for i = #held, 1, -1 do if net.time >= held[i].at then local h = table.remove(held, i); real(h.sess, h.castTick, h.spell) end end
    end
    finishBoth(net, a, b)
    local sent = 0
    for _, c in ipairs(a.ns.App.session.spell.me.casts) do if S.INFO[c.spell].target == "opponent" then sent = sent + 1 end end
    ok(sent > 0, "Alice cast spells")
    eq(ma.endReason, "check_failed")
    ok(ma.check.reasons[1] == "late_landing" or ma.check.reasons[1] == "spells_not_applied", tostring(ma.check.reasons[1]))
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


------------------------------------------------------------------------------------------------
-- Hardening: result classes, pauses, clocks and sync under bad conditions. Each test is a
-- documented risk (docs/SPELL_BATTLE.md "Result classes" and "Pauses"). Simulated clients only.
------------------------------------------------------------------------------------------------
local function agree(net, ma, mb)
  for _ = 1, 120 do if ma.agreement and mb.agreement then break end; net.step(30) end
end
local function dropper(c) return function() local s = c.ns.App.session; if s and s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end end end
local function idle() end
-- the web's spell bot plays the moves only (no casts): mana builds up for a scripted cast
local function mover(c, seed, diff)
  local bot, last
  return function()
    local s = c.ns.App.session
    if not (s and s.spell and s.phase == "playing") or s.state.tick == last then return end
    last = s.state.tick -- one decision per game tick (a slow client gets fewer, not doubled, keys)
    bot = bot or c.ns.Bot.SpellBot.new(seed, diff)
    local code = bot:act(s.spell.me, { game = { score = 0 } })
    if code and not c.ns.Spells.spellOfCode(code) then
      local a = c.ns.Engine.INPUT_ACTIONS[code + 1]
      s:press(a); s:release(a)
    end
  end
end
local function blockSends(c, pattern)
  local real = c.env.C_ChatInfo.SendAddonMessage
  c.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
    if text:match(pattern) then return 0 end
    return real(prefix, text, ch, tgt)
  end
end
-- everything that moves with time on a spell side
local function snap(c)
  local s = c.ns.App.session
  local me = s.spell.me
  local pend = {}
  for _, p in ipairs(s.spell.pendingMe) do pend[#pend + 1] = p.spell .. "@" .. p.at end
  return table.concat({ me.game.tick, me.mana, me.freezeUntil, me.speedUntil, me.blackoutUntil, S.cooldownLeft(me),
    c.ns.Engine.hashState(me.game), table.concat(pend, ","), #me.hits }, "|")
end

describe("hardening: result classes, pauses, clocks and sync (simulated clients)", function()
  it("a forfeit is a forfeit on both PCs: labelled, counted apart, and the verdicts agree", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    play(net, a, b, 1200)
    a.ns.Duel.leave()
    play(net, a, b, 10800, idle)
    finishBoth(net, a, b)
    agree(net, ma, mb)
    eq(ma.endReason, "you_forfeited"); eq(ma.basis, "forfeit"); eq(ma.outcome, "loss")
    eq(mb.endReason, "rival_forfeited"); eq(mb.basis, "forfeit"); eq(mb.outcome, "win")
    -- live scores of a forfeit can't match exactly on both PCs: only the outcome is compared
    eq(ma.agreement, "agreed", "the forfeiter waited for the rival's verdict"); eq(mb.agreement, "agreed")
    eq(b.ns.db.duels.wins, 0); eq(b.ns.db.duels.fwins, 1); eq(a.ns.db.duels.losses, 0); eq(a.ns.db.duels.flosses, 1)
    eq(b.ns.UI.duelOutcomeOf(mb)[1], "WALKOVER"); eq(a.ns.UI.duelOutcomeOf(ma)[1], "FORFEIT")
    eq(b.ns.db.duels.history[1].b, "forfeit")
  end)

  it("a played-out duel is the only VICTORY / DEFEAT, and only it counts as won / lost", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    play(net, a, b, 2000, dropper(a), dropper(b))
    finishBoth(net, a, b)
    agree(net, ma, mb)
    eq(ma.basis, "replay"); eq(mb.basis, "replay"); eq(ma.agreement, "agreed")
    local d = a.ns.db.duels
    eq(d.wins + d.losses + d.draws, 1); eq(d.fwins + d.flosses, 0)
    local t = a.ns.UI.duelOutcomeOf(ma)[1]
    ok(t == "VICTORY" or t == "DEFEAT" or t == "DRAW", t)
  end)

  it("a dispute takes the result out of the counter it was in (forfeit counters too)", function()
    local net, a = pair()
    local DB = a.ns.DB
    local db = a.ns.db
    local m = { outcome = "win", basis = "forfeit", endReason = "rival_no_log", rival = "Bob-Realm", myScore = 1, theirScore = 0, rulesetId = "s180" }
    m.historyRef = DB.recordDuel(db, m, "2026-11-05")
    eq(db.duels.fwins, 1)
    DB.disputeDuel(db, m)
    eq(db.duels.fwins, 0); eq(db.duels.disputes, 1); eq(db.duels.history[1].res, "disputed")
    local m2 = { outcome = "loss", basis = "replay", endReason = "checked", rival = "Bob-Realm", rulesetId = "s180" }
    m2.historyRef = DB.recordDuel(db, m2, "2026-11-05")
    eq(db.duels.losses, 1); DB.disputeDuel(db, m2); eq(db.duels.losses, 0); eq(db.duels.disputes, 2)
  end)

  it("all RSM copies lost: the rival's score heartbeat (clock moving again) still ends my wait", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    blockSends(a, "^1:RSM:")
    local pa, pb = spellPlayer(a, "pa", "elite"), spellPlayer(b, "pb", "elite")
    play(net, a, b, 1200, pa, pb)
    a.ns.App:Pause("manual")
    play(net, a, b, 300, pa, pb)
    local sb = b.ns.App.session
    eq(sb.phase, "paused"); eq(sb.pauseReason, "rival")
    a.ns.App:Resume()
    play(net, a, b, 60 * 6, pa, pb) -- 2 s resume countdown + one heartbeat (2 s) + latency
    ok(sb.phase == "playing" or sb.phase == "countdown", "Bob runs again: " .. sb.phase)
    play(net, a, b, 10800, pa, pb)
    finishBoth(net, a, b)
    agree(net, ma, mb)
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked"); eq(ma.agreement, "agreed")
  end)

  it("a rival that never comes back from a pause (ignores the limit): I stop waiting and win by forfeit", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    a.ns.Duel.PAUSE_BUDGET = 1e9 -- modified client
    local pb = spellPlayer(b, "pb", "elite")
    play(net, a, b, 900, nil, pb)
    a.ns.App:Pause("manual")
    play(net, a, b, 60 * 50, idle, pb)
    local sb = b.ns.App.session
    eq(sb.phase, "paused", "Bob waits while it's within the limit")
    play(net, a, b, 60 * 25, idle, pb)
    ok(mb.rivalPauseLimit, "Bob saw the pause go far past the limit")
    ok(sb.phase == "playing" or sb.phase == "countdown" or sb.phase == "over", "Bob plays on: " .. sb.phase)
    play(net, a, b, 10800, idle, pb)
    for _ = 1, 400 do if mb.state == "done" then break end; net.step(30) end
    eq(mb.endReason, "rival_pause_limit"); eq(mb.outcome, "win"); eq(mb.basis, "forfeit")
  end)

  it("micro-pauses cost at least 3 s each: a rival can't break your rhythm for free", function()
    local net, a, b = pair()
    local ma = startSpellDuel(net, a, b)
    play(net, a, b, 600)
    for i = 1, 25 do
      if ma.state ~= "playing" then break end
      a.ns.App:Pause("manual"); net.step(6); a.ns.App:Resume(); net.step(130)
      if i == 10 then ok(ma.myPaused >= 30, "10 short pauses = " .. ma.myPaused .. " s of the budget") end
    end
    eq(ma.endReason, "you_pause_limit", "the 21st pause goes over 60 s")
    ok(ma.myPauses <= 21, tostring(ma.myPauses))
  end)

  it("a shared pause freezes everything that runs on time: clock, mana, cooldowns, spells on their way, effects", function()
    local net, a, b = pair({ latency = { 0.05, 0.1 } })
    local ma, mb = startSpellDuel(net, a, b)
    local sa, sb = a.ns.App.session, b.ns.App.session
    -- both play (moves only) until they have earned the mana: Bob for Freeze, Alice for Garbage
    local pa, pb = mover(a, "pa", "elite"), mover(b, "pb", "elite")
    for _ = 1, 60 * 150 do
      if S.canCast(sa.spell.me, "garbage") and S.canCast(sb.spell.me, "freeze") then break end
      pa(); pb(); net.step(1)
    end
    ok(S.canCast(sa.spell.me, "garbage") and S.canCast(sb.spell.me, "freeze"), "mana earned")
    sb:press("spell1") -- Bob: Freeze on himself (5 s)
    sa:press("spell3") -- Alice: Garbage at Bob (lands 90 ticks later on his clock)
    net.step(20)
    eq(#sb.spell.pendingMe, 1, "the garbage is on its way to Bob")
    ok(sb.spell.me.freezeUntil > sb.state.tick, "Bob is frozen")
    local castTick = sb.spell.pendingMe[1].castTick
    b.M.combat = true; b.M.fire("PLAYER_REGEN_DISABLED")
    net.step(30)
    eq(sa.phase, "paused"); eq(sb.phase, "paused")
    local before = { snap(a), snap(b) }
    net.step(60 * 10)
    eq(snap(a), before[1], "Alice's side did not move"); eq(snap(b), before[2], "Bob's side did not move")
    b.M.combat = false; b.M.fire("PLAYER_REGEN_ENABLED"); b.ns.App:Resume()
    play(net, a, b, 600, idle, idle)
    eq(#sb.spell.landings, 1)
    eq(sb.spell.landings[1].tick, castTick + S.DELIVERY_TICKS, "landed exactly at its tick, after the pause")
    play(net, a, b, 10800, dropper(a), dropper(b))
    finishBoth(net, a, b)
    local why = function(m) return table.concat(m.check and m.check.reasons or {}, ",") .. (m.stall and (" stall " .. m.stall.stall .. "/" .. m.stall.allowed) or "") end
    eq(ma.endReason, "checked", why(ma)); eq(mb.endReason, "checked", why(mb))
    eq(ma.spell.diverged, false); eq(mb.spell.diverged, false)
  end)

  it("my run is over, the rival's isn't: their pause is still measured, no false clock rejection", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local pa = spellPlayer(a, "pa", "elite")
    play(net, a, b, 2400, pa, dropper(b))
    eq(mb.state, "waiting", "Bob topped out")
    a.M.combat = true; a.M.fire("PLAYER_REGEN_DISABLED")
    play(net, a, b, 60 * 40, pa, idle)
    a.M.combat = false; a.M.fire("PLAYER_REGEN_ENABLED"); a.ns.App:Resume()
    play(net, a, b, 10800, pa, idle)
    finishBoth(net, a, b)
    ok((mb.rivalPausedSeen or 0) > 35, "Bob measured Alice's pause: " .. tostring(mb.rivalPausedSeen))
    eq(mb.endReason, "checked", "honest pause after Bob's run: accepted")
  end)

  it("a slowed-down game (75 % speed, no pauses: easier to play) is caught by the clock check", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local sa = a.ns.App.session
    local real = sa.update
    sa.update = function(self, dt) return real(self, dt * 0.75) end -- modified client: slow motion
    -- Bob tops out at once (no spells to sink Alice); Alice plays on in slow motion
    play(net, a, b, 10800 / 0.75 + 900, NS.autoplay(a, "fast"), dropper(b))
    finishBoth(net, a, b)
    print(string.format("    slow motion: Alice's run %d ticks, extra time %d s, allowed %d s", sa.state.tick, mb.stall.stall, mb.stall.allowed))
    ok(sa.state.tick > 4000, "a run long enough to tell: " .. sa.state.tick)
    eq(mb.endReason, "check_failed", mb.stall.stall .. " / " .. mb.stall.allowed)
    eq(mb.check.reasons[1], "pause_limit")
  end)

  it("an honest slow PC (5 FPS, two 3 s freezes) on a bad network: both PCs check and agree", function()
    local net, a, b = pair({ latency = { 0.3, 0.8 }, drop = 0.05, dup = 0.1 })
    local ma, mb = startSpellDuel(net, a, b)
    if ma.state ~= "playing" then return end -- a lost GO is covered by the duel tests
    a.frameDt = 1 / 5
    local pa, pb = spellPlayer(a, "pa", "contender"), spellPlayer(b, "pb", "contender")
    play(net, a, b, 3000, pa, pb)
    a.hangUntil = net.time + 3
    play(net, a, b, 3000, pa, pb)
    a.hangUntil = net.time + 3
    play(net, a, b, 10800, pa, pb)
    finishBoth(net, a, b)
    agree(net, ma, mb)
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked", "Alice's slow PC is not a cheat")
    eq(ma.myScore, mb.theirScore); eq(ma.theirScore, mb.myScore)
    eq(ma.agreement, "agreed"); eq(mb.agreement, "agreed")
    ok(mb.stall.stall <= mb.stall.allowed, mb.stall.stall .. " <= " .. mb.stall.allowed)
  end)

  it("pause messages 2-2.5 s late and both players in combat, overlapping: same result, checked, agreed", function()
    local net, a, b = pair({ latency = { 2.0, 2.5 } })
    local ma, mb = startSpellDuel(net, a, b)
    -- decent players without spells: nobody is sunk before the pauses this test is about
    local pa, pb = NS.autoplay(a, "fast"), NS.autoplay(b, "fast")
    play(net, a, b, 1800, pa, pb)
    eq(a.ns.App.session.phase, "playing"); eq(b.ns.App.session.phase, "playing")
    a.M.combat = true; a.M.fire("PLAYER_REGEN_DISABLED")
    play(net, a, b, 300, pa, pb)
    b.M.combat = true; b.M.fire("PLAYER_REGEN_DISABLED")
    play(net, a, b, 600, pa, pb)
    a.M.combat = false; a.M.fire("PLAYER_REGEN_ENABLED"); a.ns.App:Resume()
    play(net, a, b, 300, pa, pb)
    eq(a.ns.App.session.phase, "paused", "Alice waits for Bob"); eq(a.ns.App.session.pauseReason, "rival")
    b.M.combat = false; b.M.fire("PLAYER_REGEN_ENABLED"); b.ns.App:Resume()
    play(net, a, b, 10800, pa, pb)
    finishBoth(net, a, b)
    agree(net, ma, mb)
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked")
    eq(ma.myScore, mb.theirScore); eq(ma.agreement, "agreed"); eq(mb.agreement, "agreed")
  end)

  it("an old pause message that arrives after the resume does not pause the game again", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    play(net, a, b, 900)
    local tick = a.ns.App.session.state.tick
    a.ns.App:Pause("manual"); play(net, a, b, 120); a.ns.App:Resume(); play(net, a, b, 300)
    local sb = b.ns.App.session
    eq(sb.phase, "playing")
    net.inject(b, "Alice-Realm", P.encode("PSE", ma.mid, 1, "manual", P.b36(tick)))
    play(net, a, b, 30)
    eq(sb.phase, "playing", "pause #1 is over: a late copy is ignored")
  end)

  it("the rival pauses, then goes silent: after 35 s I play on; lost contact, not a replay result", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local pb = spellPlayer(b, "pb", "elite")
    play(net, a, b, 900, nil, pb)
    a.ns.App:Pause("manual")
    play(net, a, b, 120, idle, pb)
    eq(b.ns.App.session.pauseReason, "rival")
    a.hangUntil = net.time + 3600 -- Alice's client freezes for good: no more messages (still "online")
    play(net, a, b, 60 * 30, idle, pb)
    eq(b.ns.App.session.phase, "paused", "within 35 s Bob still waits")
    play(net, a, b, 60 * 10, idle, pb)
    local sb = b.ns.App.session
    ok(sb.phase == "playing" or sb.phase == "countdown", "Bob plays on: " .. sb.phase)
    play(net, a, b, 10800, idle, pb)
    for _ = 1, 400 do if mb.state == "done" then break end; net.step(30) end
    ok(mb.endReason == "rival_disconnected" or mb.endReason == "rival_offline", mb.endReason)
    eq(mb.basis, "timeout"); eq(b.ns.UI.duelOutcomeOf(mb)[1], "WALKOVER")
  end)
end)


describe("hardening, review round: fake pauses, loading screens, leaving, verdicts (simulated clients)", function()
  it("fake micro-pauses can't buy clock allowance: a slowed-down client that fakes 35 pauses is still stopped", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local sa = a.ns.App.session
    local real = sa.update
    sa.update = function(self, dt) return real(self, dt * 0.6) end -- slow motion...
    local pa = NS.autoplay(a, "fast")
    local n = 0
    for f = 1, math.floor(10800 / 0.6 + 900) do
      pa(); dropper(b)()
      -- ...and once Bob waits, a fake PSE / RSM pair every 1.2 s (each "pause" 0.6 s long)
      if mb.state == "waiting" and n < 35 and f % 72 == 0 then
        n = n + 1
        a.ns.Comm.send(P.encode("PSE", ma.mid, n, "manual", P.b36(sa.state.tick)), "WHISPER", "Bob-Realm")
      end
      if n > 0 and f % 72 == 36 then a.ns.Comm.send(P.encode("RSM", ma.mid, n), "WHISPER", "Bob-Realm") end
      net.step(1)
    end
    for _ = 1, 400 do if mb.state == "done" then break end; net.step(30) end
    -- each fake pause costs the 3 s minimum on Bob's PC too: past 70 s Bob stops counting them
    ok(mb.rivalPauseLimit, "Bob saw the pause budget used up")
    ok(mb.endReason == "rival_pause_limit" or (mb.endReason == "check_failed" and mb.check.reasons[1] == "pause_limit"), mb.endReason)
    eq(mb.outcome, "win"); ok(mb.basis ~= "replay")
  end)

  it("an honest loading screen of 28 s (its pause message can only leave afterwards) is measured from its start", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local pa, pb = NS.autoplay(a, "fast"), NS.autoplay(b, "fast")
    play(net, a, b, 2400, pa, pb)
    a.M.fire("LOADING_SCREEN_ENABLED") -- pauses Alice's run ("loading")...
    a.hangUntil = net.time + 28         -- ...and no Lua runs until the loading screen is over
    play(net, a, b, 28 * 60 + 30, idle, pb)
    a.hangUntil = nil
    a.ns.App:Resume()
    play(net, a, b, 10800, pa, pb)
    finishBoth(net, a, b)
    ok((mb.rivalPausedSeen or 0) > 25, "Bob counted the whole pause: " .. tostring(mb.rivalPausedSeen))
    eq(mb.endReason, "checked", mb.stall and (mb.stall.stall .. " / " .. mb.stall.allowed) or "")
    eq(ma.endReason, "checked")
  end)

  it("an honest 28 s freeze without any pause event: announced as a pause ('frozen'), the rival accepts the run", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local pa, pb = NS.autoplay(a, "fast"), NS.autoplay(b, "fast")
    play(net, a, b, 2400, pa, pb)
    a.hangUntil = net.time + 28
    play(net, a, b, 28 * 60 + 30, idle, pb)
    a.hangUntil = nil
    eq(ma.myPauses, 1, "the freeze counts as one pause"); ok(ma.myPaused >= 26, "and uses the budget: " .. ma.myPaused)
    eq(b.ns.App.session.phase, "playing", "Bob is not paused by a freeze that is already over")
    play(net, a, b, 10800, pa, pb)
    finishBoth(net, a, b)
    eq(mb.endReason, "checked", mb.stall and (mb.stall.stall .. " / " .. mb.stall.allowed) or "")
  end)

  it("pausing after the rival forfeited costs nothing: still a walkover, never a draw or a loss", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    play(net, a, b, 1200)
    b.ns.Duel.leave() -- Bob forfeits
    play(net, a, b, 120, nil, idle)
    a.M.combat = true; a.M.fire("PLAYER_REGEN_DISABLED")
    play(net, a, b, 60 * 70, idle, idle) -- 70 s in combat
    a.M.combat = false; a.M.fire("PLAYER_REGEN_ENABLED"); a.ns.App:Resume()
    play(net, a, b, 10800, nil, idle)
    for _ = 1, 400 do if ma.state == "done" then break end; net.step(30) end
    eq(ma.endReason, "rival_forfeited"); eq(ma.outcome, "win")
    agree(net, ma, mb)
    eq(ma.agreement, "agreed")
  end)

  it("both wait for each other and every RSM copy is lost for a while: the repeated 'ready' gets both going", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    local pa, pb = NS.autoplay(a, "fast"), NS.autoplay(b, "fast")
    play(net, a, b, 1500, pa, pb)
    local blocked = true
    for _, c in ipairs({ a, b }) do
      local real = c.env.C_ChatInfo.SendAddonMessage
      c.env.C_ChatInfo.SendAddonMessage = function(p1, text, ch, tg) if blocked and text:match("^1:RSM:") then return 0 end return real(p1, text, ch, tg) end
    end
    a.M.combat = true; a.M.fire("PLAYER_REGEN_DISABLED")
    b.M.combat = true; b.M.fire("PLAYER_REGEN_DISABLED")
    play(net, a, b, 300, pa, pb)
    a.M.combat = false; a.M.fire("PLAYER_REGEN_ENABLED"); a.ns.App:Resume()
    b.M.combat = false; b.M.fire("PLAYER_REGEN_ENABLED"); b.ns.App:Resume()
    play(net, a, b, 300, pa, pb)
    eq(a.ns.App.session.pauseReason, "rival"); eq(b.ns.App.session.pauseReason, "rival") -- deadlock while RSM is lost
    blocked = false
    play(net, a, b, 60 * 6, pa, pb)
    ok(a.ns.App.session.phase ~= "paused" and b.ns.App.session.phase ~= "paused", "both run again")
    play(net, a, b, 10800, pa, pb)
    finishBoth(net, a, b)
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked")
  end)

  it("verdicts: the first copies lost both ways, still both 'agreed' (VER carries an ack)", function()
    local net, a, b = pair()
    local ma, mb = startSpellDuel(net, a, b)
    for _, c in ipairs({ a, b }) do
      local real, dropped = c.env.C_ChatInfo.SendAddonMessage, 0
      c.env.C_ChatInfo.SendAddonMessage = function(p1, text, ch, tg)
        if text:match("^1:VER:") and dropped < 2 then dropped = dropped + 1; return 0 end
        return real(p1, text, ch, tg)
      end
    end
    play(net, a, b, 2000, dropper(a), dropper(b))
    finishBoth(net, a, b)
    agree(net, ma, mb)
    eq(ma.agreement, "agreed"); eq(mb.agreement, "agreed")
  end)
end)

return H
