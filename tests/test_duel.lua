-- Multiplayer: protocol, verification and full duels between SIMULATED WoW clients
-- (tests/netsim.lua). None of this proves real-client behaviour; see docs/CROSS_PLATFORM_MULTIPLAYER.md.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local pure = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Engine/Verify.lua", "Net/Protocol.lua" })
local P, E, V = pure.Protocol, pure.Engine, pure.Verify

describe("protocol", function()
  it("every message type round-trips and stays within 255 bytes", function()
    local msgs = {
      P.encode("HEL", "0.4.0", 1), P.encode("HI", "0.4.0", 1, 0), P.encode("INV", "abc123", "b120", 1, "n0nce123"),
      P.encode("ACC", "abc123", "zz99zz99"), P.encode("DEC", "abc123", "busy"), P.encode("RDY", "abc123"),
      P.encode("GO", "abc123"), P.encode("PNG", "abc123"), P.encode("SC", "abc123", P.b36(7200), P.b36(123456), P.b36(40), 1),
      P.encode("END", "abc123", P.b36(7200), P.b36(123456), P.b36(40), P.b36(5), "0a1b2c3d", 3),
      P.encode("LOG", "abc123", 2, 3, "3A0Bc"), P.encode("RQ", "abc123", 2), P.encode("BYE", "abc123", "forfeit"),
    }
    for _, s in ipairs(msgs) do
      ok(#s <= 255, s)
      local m, why = P.decode(s)
      ok(m, "decode " .. s .. " " .. tostring(why))
    end
    local m = P.decode(msgs[9])
    eq(m.tick, 7200); eq(m.score, 123456); eq(m.over, true)
  end)
  it("rejects malformed, oversized, unknown and hostile packets", function()
    local bad = {
      "", "2:HEL:1:1", "1:XXX:a", "1:INV:abc123:b120:1", "1:INV:ab:b120:1:nonce123", "1:INV:abc123:zz:1:nonce123",
      "1:SC:abc123:-1:2:3:0", "1:SC:abc123:1:2:3:2", "1:END:abc123:1:2:3:4:nothex!!:1", "1:LOG:abc123:3:2:AA",
      "1:LOG:abc123:1:1:" .. string.rep("1A", 101), "1:DEC:abc123:because", "1:HEL:|cff:1", string.rep("x", 256),
      "1:RDY:abc123:extra", "1:HI:v:1:yes", "1:GO:ABC123",
    }
    for _, s in ipairs(bad) do ok(P.decode(s) == nil, "accepted bad packet: " .. s) end
  end)
  it("compact log codec round-trips real games and chunks never split an input", function()
    local fx = dofile(testdir .. "/fixtures/parity.lua")
    for k = 1, 10 do
      local log = fx.cases[k].log
      local packed = P.packLog(log)
      local back = P.unpackLog(packed)
      eq(#back, #log)
      for i = 1, #log do eq(back[i], log[i]) end
      local chunks = P.chunk(packed)
      for _, ch in ipairs(chunks) do ok(#ch <= P.CHUNK_PAYLOAD); ok(ch == "" or ch:sub(-1):match("[A-G]"), "chunk ends on an action") end
      eq(table.concat(chunks), packed)
      ok(#packed / math.max(1, #log / 2) < 4, "about 3 bytes per input")
    end
    ok(P.unpackLog("3A0Z") == nil); ok(P.unpackLog("3A0") == nil)
  end)
end)

describe("peer verification (port of the web verifyLog)", function()
  local function play(seed, ticks)
    local s = E.createGame(seed)
    local acts = { "left", "right", "rotateCW", "hardDrop" }
    for t = 0, ticks - 1 do
      if t % 11 == 0 then E.applyInput(s, acts[(t / 11) % 4 + 1]) end
      if s.gameOver then break end
      E.tick(s)
    end
    return s
  end
  it("an honest log verifies to the claimed score and hash", function()
    local s = play("srduel-x", 3000)
    local r = V.verify(s.inputLog, s.seed, s.tick, { seed = s.seed, capTicks = 7200, claimed = { score = s.score, lines = s.lines, hash = E.hashState(s) } })
    ok(r.ok, table.concat(r.reasons, ",")); eq(r.score, s.score)
  end)
  it("flags inflated scores, wrong seeds, over-time logs and inhuman input", function()
    local s = play("srduel-y", 3000)
    local r1 = V.verify(s.inputLog, s.seed, s.tick, { seed = s.seed, capTicks = 7200, claimed = { score = s.score + 500, lines = s.lines } })
    ok(not r1.ok and r1.reasons[1] == "claim_mismatch")
    local r2 = V.verify(s.inputLog, "srduel-other", s.tick, { seed = s.seed, capTicks = 7200 })
    eq(r2.reasons[1], "seed_mismatch")
    local r3 = V.verify(s.inputLog, s.seed, 9000, { seed = s.seed, capTicks = 7200 })
    ok(not r3.ok and r3.reasons[1] == "over_time_cap")
    local spam = {}
    for i = 0, 99 do spam[#spam + 1] = 10 + math.floor(i / 2); spam[#spam + 1] = i % 2 end
    local r4 = V.verify(spam, "z", 200, { seed = "z", capTicks = 7200 })
    ok(not r4.ok, "100 inputs in under a second must be flagged")
    local burst = { 5, 0, 5, 1, 5, 0, 5, 1, 5, 0 }
    local r5 = V.verify(burst, "z", 10, { seed = "z", capTicks = 7200 })
    eq(r5.reasons[1], "inhuman_input_rate")
  end)
  it("limits match the web's match rules (fingerprint)", function()
    local R = dofile(testdir .. "/fixtures/parity.lua").rules.match
    eq(V.MAX_INPUTS_PER_TICK, R.maxInputsPerTick); eq(V.MAX_INPUTS_PER_SECOND, R.maxInputsPerSecond)
    eq(V.TIME_CAP_MS, R.timeCapMs); eq(V.COUNTDOWN_MS, R.countdownMs); eq(V.RECONNECT_GRACE_MS, R.reconnectGraceMs)
    eq(P.RULESETS.r180.limitTicks, R.timeCapMs / 1000 * 60, "3:00 web-rules duel = web time cap")
    eq(P.RULESETS.r180.countdownTicks, R.countdownMs / 1000 * 60, "web countdown")
  end)
end)

------------------------------------------------------------------------------------------------
-- Full duels between simulated clients
------------------------------------------------------------------------------------------------
local function pair(opts)
  local net = NS.new(opts)
  local a = net.add({ name = "Alice", guild = "G" })
  local b = net.add({ name = "Bob", guild = "G", engine = opts and opts.bobEngine })
  return net, a, b
end

local function players(net, list)
  local fns = {}
  for _, c in ipairs(list) do fns[#fns + 1] = NS.autoplay(c, c == list[1] and "fast" or "slow") end
  return function(n)
    for _ = 1, n do
      for _, f in ipairs(fns) do f() end
      net.step(1)
    end
  end
end

local function until_(go, cond, maxFrames)
  local n = 0
  while not cond() and n < (maxFrames or 60 * 40) do go(15); n = n + 15 end
  return cond()
end

local function runDuel(net, a, b, opts)
  opts = opts or {}
  local go = players(net, { a, b })
  for _ = 1, 4 do -- a broadcast can get lost on a bad network: ask again after the cooldown
    a.ns.Duel.findPlayers()
    go(60)
    if a.ns.Duel.players["Bob-Realm"] then break end
    go(60 * 21)
  end
  ok(a.ns.Duel.players["Bob-Realm"], "Bob answered the guild hello")
  local okC, why = a.ns.Duel.challenge("Bob", opts.ruleset or "b120")
  ok(okC, tostring(why))
  ok(until_(go, function() local m = b.ns.Duel.current; return m and m.state == "invited" end), "Bob got the invite")
  ok(b.ns.UI.invite and b.ns.UI.invite:IsShown(), "invite popup visible")
  b.ns.UI.invite.acc:Click()
  ok(until_(go, function() return a.ns.Duel.current.state == "lobby" end), "Alice in the lobby")
  eq(b.ns.Duel.current.state, "lobby")
  eq(a.ns.Duel.current.seed, b.ns.Duel.current.seed, "same seed on both sides")
  ok(a.ns.UI.lobby:IsShown() and b.ns.UI.lobby:IsShown(), "lobby shown")
  a.ns.UI.lobby.ready:Click(); b.ns.UI.lobby.ready:Click()
  ok(until_(go, function() local sa, sb = a.ns.App.session, b.ns.App.session; return sa and sb and sa.duel and sb.duel end), "both runs started")
  eq(a.ns.App.session.duel, a.ns.Duel.current, "Alice's duel run started")
  eq(b.ns.App.session.duel, b.ns.Duel.current, "Bob's duel run started")
  eq(table.concat(a.ns.App.session.state.queue, ","), table.concat(b.ns.App.session.state.queue, ","), "same pieces")
  if opts.during then opts.during(go) end
  until_(go, function() return a.ns.Duel.current.state == "done" and b.ns.Duel.current.state == "done" end, 60 * 60 * 6)
  return a.ns.Duel.current, b.ns.Duel.current
end

local function complementary(ma, mb)
  local opp = { win = "loss", loss = "win", draw = "draw" }
  eq(mb.outcome, opp[ma.outcome], "outcomes mirror each other")
end

describe("duels between two simulated clients", function()
  it("full Blitz 2:00 duel: find, challenge, accept, ready, play, live scores, peer check, winner", function()
    local net, a, b = pair({ seed = 11 })
    local sawLive = false
    local ma, mb = runDuel(net, a, b, { during = function(go)
      go(600)
      sawLive = (a.ns.Duel.current.rival_.score or -1) >= 0 and a.ns.UI.rivalPanel:IsShown()
    end })
    ok(sawLive, "live rival score shown during the match")
    eq(ma.state, "done"); eq(mb.state, "done")
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked")
    eq(ma.theirScore, b.ns.App.session.state.score, "Alice saw Bob's real score")
    eq(mb.theirScore, a.ns.App.session.state.score, "Bob saw Alice's real score")
    complementary(ma, mb)
    ok(a.ns.UI.over:IsShown(), "result screen")
    ok(a.ns.UI.overTitle:GetText() == "VICTORY" or a.ns.UI.overTitle:GetText() == "DEFEAT" or a.ns.UI.overTitle:GetText() == "DRAW")
    eq(a.ns.db.duels.history[1].rival, "Bob-Realm"); eq(b.ns.db.duels.history[1].rival, "Alice-Realm")
    eq(a.ns.db.records.blitz.games, 0, "duels don't count as solo records")
    print(string.format("    duel: Alice %d vs Bob %d -> %s; %d messages, max %d bytes", ma.myScore, ma.theirScore, ma.outcome, net.sent, 255))
  end)
  it("rematch: same rival, new seed, a second full duel", function()
    local net, a, b = pair({ seed = 12 })
    local ma1 = runDuel(net, a, b)
    local seed1 = ma1.seed
    local go = players(net, { a, b })
    a.ns.UI.againBtn:Click() -- "Rematch"
    go(30)
    eq(b.ns.Duel.current.state, "invited"); ok(b.ns.Duel.current.rematch, "shown as rematch")
    b.ns.UI.invite.acc:Click(); go(30)
    a.ns.UI.lobby.ready:Click(); b.ns.UI.lobby.ready:Click(); go(7200 + 400)
    for _ = 1, 60 do if a.ns.Duel.current.state == "done" and b.ns.Duel.current.state == "done" then break end go(30) end
    eq(a.ns.Duel.current.state, "done"); ok(a.ns.Duel.current.seed ~= seed1, "new seed")
    eq(#a.ns.db.duels.history, 2)
  end)
  it("3:00 duel with the web's rules (time cap and countdown)", function()
    local net, a, b = pair({ seed = 13 })
    local ma, mb = runDuel(net, a, b, { ruleset = "r180" })
    eq(ma.state, "done"); eq(ma.endReason, "checked"); complementary(ma, mb)
    eq(a.ns.App.session.state.tick <= 10800, true)
  end)
  it("survives a bad network: 15% loss, 10% duplicates, 50-900 ms latency (reordering)", function()
    local net, a, b = pair({ seed = 14, drop = 0.15, dup = 0.10, latency = { 0.05, 0.9 } })
    local ma, mb = runDuel(net, a, b)
    eq(ma.state, "done"); eq(mb.state, "done")
    ok(ma.endReason == "checked" or ma.endReason == "unchecked", ma.endReason)
    complementary(ma, mb)
  end)
  it("works inside instances where whispers are throttled (10 msgs, +1/s)", function()
    local net, a, b = pair({ seed = 15, instance = true })
    local ma, mb = runDuel(net, a, b)
    eq(ma.endReason, "checked"); complementary(ma, mb)
    ok(net.throttled == 0, "our own pacing stays under Blizzard's limit (throttled " .. net.throttled .. ")")
  end)
  it("decline, no answer, busy rival and version mismatch", function()
    local net, a, b = pair({ seed = 16 })
    local go = players(net, { a, b })
    a.ns.Duel.challenge("Bob"); go(30)
    b.ns.UI.invite:GetScript("OnUpdate")(b.ns.UI.invite)
    b.ns.Duel.decline("no"); go(30)
    eq(a.ns.Duel.current.state, "cancelled"); eq(a.ns.Duel.current.endReason, "rival_no")
    ok(a.ns.UI.lobby:IsShown() and a.ns.UI.lobby.status:GetText():find("declined") ~= nil, "Alice sees the decline")
    a.ns.Duel.clear(); b.ns.Duel.clear()
    -- no answer
    a.ns.Duel.challenge("Bob"); go(60 * 36)
    eq(a.ns.Duel.current.state, "cancelled")
    eq(b.ns.Duel.current.state, "cancelled", "Bob's invite timed out")
    a.ns.Duel.clear(); b.ns.Duel.clear()
    -- busy: Carol challenges Bob while Bob is in a duel with Alice
    local c = net.add({ name = "Carol", guild = "G" })
    local go3 = players(net, { a, b, c })
    a.ns.Duel.challenge("Bob"); go3(30); b.ns.Duel.accept(); go3(30)
    c.ns.Duel.challenge("Bob"); go3(30)
    eq(c.ns.Duel.current.state, "cancelled"); eq(c.ns.Duel.current.endReason, "rival_busy")
    eq(b.ns.Duel.current.rival, "Alice-Realm", "Bob's duel untouched")
    -- version mismatch
    local net2, a2, b2 = pair({ seed = 17, bobEngine = 2 })
    local go2 = players(net2, { a2, b2 })
    a2.ns.Duel.challenge("Bob"); go2(30)
    eq(a2.ns.Duel.current.endReason, "rival_version")
  end)
  it("rival disconnects mid-match: you play on and win by disconnect", function()
    local net, a, b = pair({ seed = 18 })
    local ma = runDuel(net, a, b, { during = function(go) go(1200); b.online = false end })
    eq(ma.state, "done")
    ok(ma.endReason == "rival_disconnected" or ma.endReason == "rival_offline", ma.endReason)
    eq(ma.outcome, "win")
  end)
  it("rival forfeits (/sr leave): you win, they lose", function()
    local net, a, b = pair({ seed = 19 })
    local ma, mb = runDuel(net, a, b, { during = function(go) go(600); b.ns.Duel.leave() end })
    eq(mb.outcome, "loss"); eq(mb.endReason, "you_forfeited")
    eq(ma.outcome, "win"); eq(ma.endReason, "rival_forfeited")
  end)
  it("combat during a duel pauses only your run; the duel still completes", function()
    local net, a, b = pair({ seed = 20 })
    local ma, mb = runDuel(net, a, b, { during = function(go)
      go(900)
      a.M.fire("PLAYER_REGEN_DISABLED"); a.M.combat = true
      eq(a.ns.App.session.phase, "paused"); ok(not a.ns.UI.keys._kb, "keys back to WoW")
      go(600)
      eq(b.ns.App.session.phase, "playing", "Bob keeps playing")
      a.M.combat = false; a.M.fire("PLAYER_REGEN_ENABLED")
      a.ns.UI.resumeBtn:Click()
    end })
    -- Alice lost 10 s of play time to the pause but still finishes her full 2:00
    for _ = 1, 40 do if ma.state == "done" and mb.state == "done" then break end net.step(60) end
    eq(ma.state, "done"); eq(mb.state, "done"); complementary(ma, mb)
    eq(#a.M.blocked + #b.M.blocked, 0, "no blocked actions")
  end)
  it("a tampered result (inflated END score) is caught by the peer check: no winner", function()
    local net, a, b = pair({ seed = 21 })
    -- Bob's client lies about his final score
    local realSend = b.env.C_ChatInfo.SendAddonMessage
    b.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      local mid, rest = text:match("^1:END:(%w+):(.*)$")
      if mid then
        local f = {}
        for x in rest:gmatch("[^:]+") do f[#f + 1] = x end
        f[2] = P.b36(P.unb36(f[2]) + 50000)
        text = "1:END:" .. mid .. ":" .. table.concat(f, ":")
      end
      return realSend(prefix, text, ch, tgt)
    end
    local ma = runDuel(net, a, b)
    eq(ma.endReason, "check_failed"); eq(ma.outcome, "void")
    eq(a.ns.db.duels.voids, 1)
  end)
  it("garbage and spoofed packets are ignored; nothing crashes", function()
    local net, a, b = pair({ seed = 22 })
    local ma = runDuel(net, a, b, { during = function(go)
      local mid = a.ns.Duel.current.mid
      for _, junk in ipairs({ "hello", "1:SC:" .. mid .. ":zz:zz:zz:0", "1:END:" .. mid .. ":1:1:1:1:00000000:0", "1:BYE:" .. mid .. ":forfeit", string.rep("A", 255) }) do
        net.inject(a, "Mallory-Realm", junk) -- not Alice's rival: must be ignored
      end
      net.inject(a, "Bob-Realm", "1:SC:" .. mid .. ":-5:1:1:0") -- malformed from the real rival
      go(30)
      eq(a.ns.Duel.current.state, "playing", "spoofed BYE/END from a stranger ignored")
    end })
    eq(ma.state, "done"); eq(ma.endReason, "checked")
    ok(a.ns.Comm.stats.rejected >= 2)
  end)
  it("addon-message lockdown (12.x code 11) is retried until it lifts", function()
    local net, a, b = pair({ seed = 23 })
    local ma = runDuel(net, a, b, { during = function(go) a.lockdownUntil = net.time + 8; go(60 * 12) end })
    eq(ma.state, "done"); eq(ma.endReason, "checked")
  end)
end)

return H
