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
      P.encode("GO", "abc123", "n0nce123"), P.encode("PNG", "abc123"), P.encode("SC", "abc123", P.b36(7200), P.b36(123456), P.b36(40), 1),
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
      "1:RDY:abc123:extra", "1:HI:v:1:yes", "1:GO:ABC123:nonce123", "1:GO:abc123", "1:BYE:abc123:whatever",
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
  ok(b.ns.Duel.current.nonceA == nil, "guest doesn't know the inviter's nonce (seed) before GO")
  ok(a.ns.UI.lobby:IsShown() and b.ns.UI.lobby:IsShown(), "lobby shown")
  a.ns.UI.lobby.ready:Click(); b.ns.UI.lobby.ready:Click()
  ok(until_(go, function() local sa, sb = a.ns.App.session, b.ns.App.session; return sa and sb and sa.duel and sb.duel end), "both runs started")
  eq(a.ns.App.session.duel, a.ns.Duel.current, "Alice's duel run started")
  eq(b.ns.App.session.duel, b.ns.Duel.current, "Bob's duel run started")
  eq(a.ns.Duel.current.seed, b.ns.Duel.current.seed, "same seed on both sides")
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
    -- the invite may queue for a moment behind the last chunks of the previous match's log
    ok(until_(go, function() return b.ns.Duel.current.state == "invited" end, 60 * 10), "Bob got the rematch invite")
    ok(b.ns.Duel.current.rematch, "shown as rematch")
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
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked")
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
    eq(b.ns.Duel.current, nil, "Bob's invite timed out and was forgotten")
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
  it("combat during a duel pauses BOTH runs; both resume together; the duel completes", function()
    local net, a, b = pair({ seed = 20 })
    local ma, mb = runDuel(net, a, b, { during = function(go)
      go(900)
      a.M.fire("PLAYER_REGEN_DISABLED"); a.M.combat = true
      eq(a.ns.App.session.phase, "paused"); ok(not a.ns.UI.keys._kb, "keys back to WoW")
      go(600)
      eq(b.ns.App.session.phase, "paused", "Bob's run waits for Alice")
      eq(b.ns.App.session.pauseReason, "rival")
      ok(not b.ns.UI.resumeBtn:IsEnabled(), "Bob can't resume alone")
      local bt = b.ns.App.session.state.tick
      go(300)
      eq(b.ns.App.session.state.tick, bt, "Bob's clock stands still")
      a.M.combat = false; a.M.fire("PLAYER_REGEN_ENABLED")
      a.ns.UI.resumeBtn:Click()
      go(300)
      ok(b.ns.App.session.state.tick > bt, "Bob goes on when Alice does")
    end })
    -- Alice lost 10 s of play time to the pause but still finishes her full 2:00
    for _ = 1, 40 do if ma.state == "done" and mb.state == "done" then break end net.step(60) end
    eq(ma.state, "done"); eq(mb.state, "done"); complementary(ma, mb)
    eq(#a.M.blocked + #b.M.blocked, 0, "no blocked actions")
  end)
  it("a tampered result (inflated END score) is caught by the peer check: the cheater's result is rejected", function()
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
    eq(ma.endReason, "check_failed"); eq(ma.outcome, "win"); eq(ma.basis, "rejected")
    eq(a.ns.UI.duelOutcomeOf(ma)[1], "WALKOVER", "a rejected rival is not a played-out VICTORY")
    -- never counted as a played-out win. Bob's own PC replayed both games: if it says Bob won, the
    -- verdicts don't match ("disputed", not counted); if it agrees Bob lost, it's a forfeit win.
    for _ = 1, 60 do if ma.agreement then break end net.step(30) end
    eq(a.ns.db.duels.wins, 0)
    if ma.agreement == "disputed" then
      eq(a.ns.db.duels.disputes, 1); eq(a.ns.db.duels.history[1].res, "disputed")
    else
      eq(ma.agreement, "agreed"); eq(ma.rivalVer.verdict, "l", "Bob's PC says he lost"); eq(a.ns.db.duels.fwins, 1)
    end
  end)

  it("a cheater whose own PC says it won against a rejected result: disputed, counted nowhere", function()
    local net, a, b = pair({ seed = 21 })
    local realSend = b.env.C_ChatInfo.SendAddonMessage
    b.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      local mid, rest = text:match("^1:END:(%w+):(.*)$")
      if mid then
        local f = {}
        for x in rest:gmatch("[^:]+") do f[#f + 1] = x end
        f[2] = P.b36(P.unb36(f[2]) + 50000)
        text = "1:END:" .. mid .. ":" .. table.concat(f, ":")
      end
      local vmid = text:match("^1:VER:(%w+):")
      if vmid then text = P.encode("VER", vmid, "w", P.b36(999999), P.b36(1), "r") end -- "I won"
      return realSend(prefix, text, ch, tgt)
    end
    local ma = runDuel(net, a, b)
    eq(ma.endReason, "check_failed")
    for _ = 1, 60 do if ma.agreement then break end net.step(30) end
    eq(ma.agreement, "disputed")
    eq(a.ns.db.duels.wins + a.ns.db.duels.fwins, 0); eq(a.ns.db.duels.disputes, 1)
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

------------------------------------------------------------------------------------------------
-- Regression tests for the findings of the independent review (0.4.0-dev)
------------------------------------------------------------------------------------------------
local function count(net, from, kind)
  local n = { v = 0 }
  local prev = net.tap
  net.tap = function(c, text, ...)
    if c == from and text:match("^1:" .. kind .. ":") then n.v = n.v + 1 end
    if prev then prev(c, text, ...) end
  end
  return n
end

-- challenge -> accept -> ready -> both runs started; returns a stepping function without autoplay
local function startDuel(net, a, b, rulesetId)
  local function go(n) net.step(n) end
  ok(a.ns.Duel.challenge("Bob", rulesetId or "b120"))
  for _ = 1, 40 do go(15); local m = b.ns.Duel.current; if m and m.state == "invited" then break end end
  b.ns.UI.invite.acc:Click()
  for _ = 1, 40 do go(15); if a.ns.Duel.current.state == "lobby" then break end end
  a.ns.UI.lobby.ready:Click(); b.ns.UI.lobby.ready:Click()
  for _ = 1, 40 do go(15); local sa, sb = a.ns.App.session, b.ns.App.session; if sa and sb and sa.duel and sb.duel then break end end
  ok(a.ns.App.session and a.ns.App.session.duel and b.ns.App.session and b.ns.App.session.duel, "both runs started")
  return go
end

-- Alice plays well, Bob hard-drops every few frames and tops out early
local function bobTopsOut(net, a, b, until_cond, maxFrames)
  local fa = NS.autoplay(a, "fast")
  for _ = 1, maxFrames or 60 * 60 * 8 do
    if until_cond() then return true end
    fa()
    local sb = b.ns.App.session
    if sb and sb.duel and sb.phase == "playing" and net.time * 60 % 6 < 1 then sb:press("hardDrop"); sb:release("hardDrop") end
    net.step(1)
  end
  return until_cond()
end

describe("review findings (regression tests, simulated clients)", function()
  it("#1 the player who finishes second streams their log unasked, even after going back to the menu", function()
    local net, a, b = pair({ seed = 31 })
    startDuel(net, a, b)
    local rq = count(net, b, "RQ")
    ok(bobTopsOut(net, a, b, function() return a.ns.Duel.current.state == "done" end), "Alice finished")
    eq(b.ns.Duel.current.state, "waiting", "Bob topped out first and waits")
    a.ns.App:ShowMenu() -- Alice clicks "Modes" right away: the match is cleared...
    eq(a.ns.Duel.current, nil)
    for _ = 1, 60 * 30 do if b.ns.Duel.current.state == "done" then break end net.step(1) end
    local mb = b.ns.Duel.current
    eq(mb.state, "done"); eq(mb.endReason, "checked", "...but her log still reached Bob")
    ok(rq.v == 0, "Bob didn't have to ask for chunks (" .. rq.v .. " RQ)")
  end)

  it("#2 log chunks that arrive before their END are kept", function()
    local net, a, b = pair({ seed = 32 })
    local realSend = b.env.C_ChatInfo.SendAddonMessage
    local sentLog, lostEnds = false, 0
    b.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      if text:match("^1:LOG:") then sentLog = true end
      if text:match("^1:END:") and (not sentLog or lostEnds < 1) then lostEnds = lostEnds + 1; return 0 end -- lost
      return realSend(prefix, text, ch, tgt)
    end
    local ma, mb = runDuel(net, a, b)
    ok(lostEnds >= 1, "Bob's first END got lost")
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked"); complementary(ma, mb)
  end)

  it("#3 challenging an offline player cancels the challenge; it is never a win", function()
    local net, a, b = pair({ seed = 33 })
    b.online = false
    a.ns.App:Start("classic"); net.step(120)
    ok(a.ns.Duel.challenge("Bob"))
    net.step(60 * 8) -- 6 s grace before an offline report ends anything
    local m = a.ns.Duel.current
    eq(m.state, "cancelled"); eq(m.endReason, "rival_offline")
    eq(a.ns.db.duels.wins, 0); eq(#a.ns.db.duels.history, 0)
    ok(a.ns.UI.lobby.status:GetText():find("offline") ~= nil, "Alice is told Bob is offline")
  end)

  it("#4 a rival who goes quiet for 40 s (loading screen, lockdown) and comes back is not a disconnect", function()
    local net, a, b = pair({ seed = 34 })
    local sawGone = false
    local ma, mb = runDuel(net, a, b, { during = function(go)
      go(600)
      b.lockdownUntil = net.time + 40
      for _ = 1, 40 do go(60); if a.ns.Duel.current.rivalGone then sawGone = true end end
      go(60 * 12) -- Comm's retry back-off (up to 8 s) after the lockdown lifts
      ok(not a.ns.Duel.current.rivalGone, "the mark clears when Bob is heard again")
    end })
    ok(sawGone, "Alice did notice the silence")
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked"); complementary(ma, mb)
  end)

  it("#5 challenging each other at the same moment starts one duel instead of two 'busy' refusals", function()
    local net, a, b = pair({ seed = 35 })
    ok(a.ns.Duel.challenge("Bob")); ok(b.ns.Duel.challenge("Alice"))
    net.step(120)
    local ma, mb = a.ns.Duel.current, b.ns.Duel.current
    eq(ma.state, "lobby"); eq(mb.state, "lobby"); eq(ma.mid, mb.mid, "the same match on both sides")
    ok(ma.role ~= mb.role, "one host, one guest")
    a.ns.UI.lobby.ready:Click(); b.ns.UI.lobby.ready:Click(); net.step(120)
    eq(a.ns.App.session.duel, ma); eq(b.ns.App.session.duel, mb)
    eq(ma.seed, mb.seed)
  end)

  it("#6 lobby race: a guest's cancel that crosses GO cancels the duel, nobody wins", function()
    local net, a, b = pair({ seed = 36 })
    a.ns.Duel.LOBBY_TIMEOUT = 60
    eq(b.ns.Duel.LOBBY_TIMEOUT + b.ns.Duel.GUEST_GRACE > a.ns.Duel.LOBBY_TIMEOUT, true, "the guest waits longer than the host")
    startDuel(net, a, b)
    local mid = a.ns.Duel.current.mid
    net.inject(a, "Bob-Realm", "1:DEC:" .. mid .. ":timeout")
    eq(a.ns.Duel.current.state, "cancelled")
    eq(a.ns.App.session, nil, "Alice's duel run was stopped")
    eq(a.ns.db.duels.wins, 0)
  end)

  it("#7 leaving after your own run ended: back to the menu, the duel is still decided (leaving never voids a loss)", function()
    local net, a, b = pair({ seed = 37 })
    startDuel(net, a, b)
    ok(bobTopsOut(net, a, b, function() return b.ns.Duel.current.state == "waiting" end), "Bob topped out")
    b.ns.Duel.leave()
    local mb = b.ns.Duel.current
    ok(mb.viewLeft, "Bob is back in the menu"); eq(b.ns.App.session, nil); eq(mb.state, "waiting")
    local okC, why = b.ns.Duel.challenge("Alice", "b120")
    eq(okC, false); eq(why, "deciding")
    ok(bobTopsOut(net, a, b, function() return a.ns.Duel.current.state == "done" and mb.state == "done" end), "both decided")
    local ma = a.ns.Duel.current
    eq(ma.endReason, "checked", "Bob's result reached Alice"); eq(mb.endReason, "checked", "and Alice's reached Bob")
    eq(mb.basis, "replay"); complementary(ma, mb)
    for _ = 1, 60 do if ma.agreement and mb.agreement then break end net.step(30) end
    eq(ma.agreement, "agreed"); eq(mb.agreement, "agreed")
    eq(b.ns.db.duels.voids, 0)
  end)

  it("#7b /reload after your own run ended: no verdict from you, so the rival's checked result stands (not disputed)", function()
    local net, a, b = pair({ seed = 47 })
    startDuel(net, a, b)
    ok(bobTopsOut(net, a, b, function() return b.ns.Duel.current.state == "waiting" end), "Bob topped out")
    net.step(60 * 6) -- his log has streamed
    local b2 = net.reload(b)
    eq(b2.ns.db.duels.voids, 1, "Bob's own PC can't follow the result any more: no result for him")
    ok(bobTopsOut(net, a, b2, function() return a.ns.Duel.current.state == "done" end), "Alice finished")
    local ma = a.ns.Duel.current
    eq(ma.endReason, "checked"); eq(ma.basis, "replay")
    for _ = 1, 80 do if ma.agreement then break end net.step(30) end
    eq(ma.agreement, "unconfirmed", "not disputed: Alice's result is counted")
    eq(a.ns.db.duels.disputes, 0)
  end)

  it("#8 a rival who keeps talking but withholds their log forfeits: a walkover, never a checked win", function()
    local net, a, b = pair({ seed = 38 })
    local realSend = b.env.C_ChatInfo.SendAddonMessage
    b.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      if text:match("^1:LOG:") then return 0 end -- "sent", never arrives
      return realSend(prefix, text, ch, tgt)
    end
    local ma, mb = runDuel(net, a, b)
    -- Bob still sends his END (and everything else) but never his log: whatever he claims, keeping
    -- the log back can't turn his loss into "no result"
    eq(ma.endReason, "rival_no_log"); eq(ma.outcome, "win"); eq(ma.basis, "forfeit")
    ok(ma.noLogTalking, "Bob was still talking")
    eq(a.ns.UI.duelOutcomeOf(ma)[1], "WALKOVER", "never shown as a VICTORY")
    for _ = 1, 60 do if ma.agreement then break end net.step(30) end
    -- Bob replayed Alice's game: if he says he won, the two verdicts disagree -> disputed
    eq(a.ns.db.duels.wins, 0, "not a played-out win")
    if ma.agreement == "disputed" then eq(a.ns.db.duels.disputes, 1); eq(a.ns.db.duels.fwins, 0)
    else eq(a.ns.db.duels.fwins, 1) end
    eq(mb.basis, "replay", "Bob had Alice's log: his result is a replay")
  end)

  it("#8b a rival who claims a high score, then goes silent without the log: no result for either side", function()
    local net, a, b = pair({ seed = 48 })
    local realSend = b.env.C_ChatInfo.SendAddonMessage
    local gone = false
    b.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      if gone or text:match("^1:LOG:") then return 0 end
      local mid, rest = text:match("^1:END:(%w+):(.*)$")
      if mid then
        local f = {}
        for x in rest:gmatch("[^:]+") do f[#f + 1] = x end
        f[2] = P.b36(P.unb36(f[2]) + 5000000) -- "I scored a lot more"
        text = "1:END:" .. mid .. ":" .. table.concat(f, ":")
        local r = realSend(prefix, text, ch, tgt)
        gone = true -- ...and nothing after that (like a client that drops right after its run)
        return r
      end
      return realSend(prefix, text, ch, tgt)
    end
    local ma = runDuel(net, a, b, { during = function(go)
      -- Bob stops playing at once, so his END comes first
      for _ = 1, 600 do
        local s = b.ns.App.session
        if s and s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end
        go(1)
        if b.ns.Duel.current.state ~= "playing" then break end
      end
    end })
    eq(ma.endReason, "unchecked"); eq(ma.outcome, "void"); eq(ma.basis, "void")
    eq(a.ns.db.duels.wins + a.ns.db.duels.fwins + a.ns.db.duels.losses + a.ns.db.duels.flosses, 0)
    eq(a.ns.db.duels.voids, 1)
  end)

  it("#9 seed commit-reveal: an inviter that reveals another nonce is caught", function()
    local net, a, b = pair({ seed = 39 })
    local realSend = a.env.C_ChatInfo.SendAddonMessage
    a.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      text = text:gsub("^(1:GO:%w+:)%w+$", "%1zzzzzzzz")
      return realSend(prefix, text, ch, tgt)
    end
    ok(a.ns.Duel.challenge("Bob")); net.step(60)
    b.ns.UI.invite.acc:Click(); net.step(60)
    a.ns.UI.lobby.ready:Click(); b.ns.UI.lobby.ready:Click(); net.step(120)
    eq(b.ns.Duel.current.state, "cancelled"); eq(b.ns.Duel.current.endReason, "rival_bad_seed")
    ok(not (b.ns.App.session and b.ns.App.session.duel), "Bob never started on the manipulated seed")
    eq(a.ns.Duel.current.state, "cancelled", "Alice's duel is cancelled too")
  end)

  it("#9 a final result that arrives faster than the game can be played is rejected", function()
    local net, a, b = pair({ seed = 40 })
    startDuel(net, a, b)
    net.step(60)
    local m = a.ns.Duel.current
    net.inject(a, "Bob-Realm", "1:END:" .. m.mid .. ":" .. P.b36(7200) .. ":" .. P.b36(999999) .. ":5:3:0a1b2c3d:1")
    ok(m.tooFast, "a 2:00 result 1 s after GO is flagged")
  end)

  it("#10 300 invites and hellos from a stranger during a duel don't starve it", function()
    local net, a, b = pair({ seed = 41 })
    local toMallory = { v = 0 }
    net.tap = function(c, text, ch, tgt) if c == a and tgt == "Mallory-Realm" then toMallory.v = toMallory.v + 1 end end
    local maxQueue = 0
    local ma, mb = runDuel(net, a, b, { during = function(go)
      for i = 1, 150 do
        net.inject(a, "Mallory-Realm", "1:INV:m" .. P.b36(1000 + i) .. ":b120:1:abcdef12")
        net.inject(a, "Mallory-Realm", "1:HEL:0.4.0:1")
        maxQueue = math.max(maxQueue, #a.ns.Comm.queue)
      end
      go(60)
    end })
    ok(maxQueue <= 17, "queue stayed small (" .. maxQueue .. ")")
    ok(toMallory.v <= 2, "at most a couple of replies to the spammer (" .. toMallory.v .. ")")
    eq(ma.endReason, "checked"); complementary(ma, mb)
  end)

  it("#11 realm names with hyphens or spaces match the name the server reports", function()
    local net, a = pair({ seed = 42 })
    local C = a.ns.Comm
    eq(C.fullName("Bob-Azjol-Nerub"), "Bob-AzjolNerub")
    eq(C.fullName("Bob-Azjol Nerub"), "Bob-AzjolNerub")
    eq(C.fullName("Bob"), "Bob-Realm")
    ok(C.same("bob-azjolnerub", "Bob-Azjol-Nerub"))
  end)

  it("#12 declining an invite during a solo run leaves the run visible and playable", function()
    local net, a, b = pair({ seed = 43 })
    b.ns.App:Start("classic"); net.step(300)
    ok(a.ns.Duel.challenge("Bob")); net.step(60)
    eq(b.ns.Duel.current.state, "invited")
    b.ns.UI.invite:GetScript("OnUpdate")(b.ns.UI.invite)
    b.ns.Duel.decline("no"); net.step(30)
    eq(b.ns.Duel.current, nil, "the declined invite is forgotten")
    ok(not b.ns.UI.lobby:IsShown(), "nothing covers Bob's board")
    eq(b.ns.App.session.phase, "playing"); eq(b.ns.UI.keys._kb, true, "Bob still has his keys")
    eq(a.ns.Duel.current.endReason, "rival_no")
  end)

  it("#13 'Quit to menu' in a duel is a labelled forfeit, never a stuck duel", function()
    local net, a, b = pair({ seed = 44 })
    startDuel(net, a, b)
    net.step(300)
    b.ns.App:Pause("manual")
    ok(not b.ns.UI.restartBtn:IsShown(), "no Restart in a duel")
    eq(b.ns.UI.quitBtn.fs:GetText(), "Forfeit duel")
    b.ns.UI.quitBtn:Click()
    eq(b.ns.Duel.current.state, "playing", "one click only arms the forfeit")
    eq(b.ns.UI.quitBtn.fs:GetText(), "Click again to forfeit")
    net.step(60 * 4)
    eq(b.ns.UI.quitBtn.fs:GetText(), "Forfeit duel", "the confirmation times out")
    b.ns.UI.quitBtn:Click(); net.step(30)
    b.ns.UI.quitBtn:Click()
    eq(b.ns.Duel.current.endReason, "you_forfeited"); ok(not b.ns.Duel.busy(), "Bob is free again")
    ok(bobTopsOut(net, a, b, function() return a.ns.Duel.current.state == "done" end))
    eq(a.ns.Duel.current.endReason, "rival_forfeited"); eq(a.ns.Duel.current.outcome, "win")
  end)

  it("#14 a duel that starts while you are in combat starts paused", function()
    local net, a, b = pair({ seed = 45 })
    ok(a.ns.Duel.challenge("Bob")); net.step(60)
    b.ns.UI.invite.acc:Click(); net.step(60)
    b.ns.UI.lobby.ready:Click(); net.step(30)
    b.M.fire("PLAYER_REGEN_DISABLED"); b.M.combat = true
    a.ns.UI.lobby.ready:Click(); net.step(60)
    local s = b.ns.App.session
    ok(s and s.duel, "Bob's duel run exists")
    eq(s.phase, "paused"); eq(s.pauseReason, "combat")
    eq(b.ns.UI.keys._kb, false); eq(#b.M.blocked, 0, "no blocked actions")
  end)
end)

------------------------------------------------------------------------------------------------
-- Delivery, WoW API results, budget, reload, version, diagnostics (multiplayer hardening round 2)
------------------------------------------------------------------------------------------------
describe("delivery, API results and budget (simulated clients)", function()
  it("result code is read from the LAST return value (deprecation wrapper) and booleans still work", function()
    local net, a = pair({ seed = 50 })
    local R = a.ns.Comm.result
    eq(R(true, 0), 0); eq(R(true, 3), 3); eq(R(true, true, 3), 3, "wrapper: boolean first, code last")
    eq(R(true, false, 11), 11); eq(R(true, true), 0); eq(R(true, false), 9); eq(R(true), 0)
    eq(R(false, "error"), 9, "a Lua error is retried, never counted as sent")
  end)

  it("a throttle reported in the second return position is retried, not counted as delivered", function()
    local net, a, b = pair({ seed = 51 })
    local realSend = a.env.C_ChatInfo.SendAddonMessage
    local refused = 0
    a.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      if text:match("^1:INV:") and refused < 2 then refused = refused + 1; return true, 3 end -- wrapper style
      return realSend(prefix, text, ch, tgt)
    end
    ok(a.ns.Duel.challenge("Bob"))
    for _ = 1, 60 * 6 do net.step(1); if b.ns.Duel.current then break end end
    eq(refused, 2); eq(b.ns.Duel.current and b.ns.Duel.current.state, "invited", "the invite arrived after the retries")
    eq(a.ns.Comm.stats.codes[3], 2)
  end)

  it("prefix registration: duplicate is fine, invalid or full disables duels cleanly; Trial accounts can't challenge", function()
    local net = NS.new({ seed = 52 })
    local dup = net.add({ name = "Dup", guild = "G", beforeLogin = function(env) env.C_ChatInfo.RegisterAddonMessagePrefix = function() return 1 end end })
    ok(dup.ns.Comm.enabled, "DuplicatePrefix (1) = already registered")
    local full = net.add({ name = "Full", guild = "G", beforeLogin = function(env) env.C_ChatInfo.RegisterAddonMessagePrefix = function() return 3 end end })
    ok(not full.ns.Comm.enabled, "MaxPrefixes (3) disables messaging")
    local okF, whyF = full.ns.Duel.challenge("Dup"); ok(not okF); eq(whyF, "unavailable")
    local old = net.add({ name = "Old", guild = "G", beforeLogin = function(env) env.C_ChatInfo.RegisterAddonMessagePrefix = function() return true end end })
    ok(old.ns.Comm.enabled, "old clients return a boolean")
    local trial = net.add({ name = "Trial", guild = "G", beforeLogin = function(env) env.IsTrialAccount = function() return true end end })
    local okT, whyT = trial.ns.Duel.challenge("Dup")
    ok(not okT); eq(whyT, "trial")
    ok(dup.ns.Duel.challenge("Trial")); net.step(60)
    eq(trial.ns.Duel.current, nil, "a Trial account can't answer, so the popup isn't shown")
  end)

  it("a lost DEC: the re-sent invite gets the decline again instead of re-opening the popup", function()
    local net, a, b = pair({ seed = 53 })
    local realSend = b.env.C_ChatInfo.SendAddonMessage
    local lost = 0
    b.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      if text:match("^1:DEC:") and lost == 0 then lost = 1; return 0 end -- accepted, never delivered
      return realSend(prefix, text, ch, tgt)
    end
    ok(a.ns.Duel.challenge("Bob")); net.step(60)
    b.ns.Duel.decline("no"); net.step(60 * 6)
    eq(lost, 1)
    eq(b.ns.Duel.current, nil); ok(not b.ns.UI.invite:IsShown(), "no second popup")
    eq(a.ns.Duel.current.state, "cancelled"); eq(a.ns.Duel.current.endReason, "rival_no")
  end)

  it("a cancel in the lobby whose DEC is lost still reaches the rival", function()
    local net, a, b = pair({ seed = 54 })
    ok(a.ns.Duel.challenge("Bob")); net.step(60)
    b.ns.UI.invite.acc:Click(); net.step(60)
    local realSend = a.env.C_ChatInfo.SendAddonMessage
    local lost = 0
    a.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      if text:match("^1:DEC:") and lost == 0 then lost = 1; return 0 end
      return realSend(prefix, text, ch, tgt)
    end
    a.ns.Duel.leave(); net.step(60 * 10)
    eq(lost, 1); eq(b.ns.Duel.current.state, "cancelled"); eq(b.ns.Duel.current.endReason, "rival_cancel")
  end)

  it("FIN: results are acknowledged, so nobody keeps re-sending for 60 s", function()
    local net, a, b = pair({ seed = 55 })
    local ma, mb = runDuel(net, a, b)
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked")
    for _ = 1, 60 * 5 do net.step(1) end
    ok(ma.rivalHasMine and mb.rivalHasMine, "both sides confirmed")
    local ends = count(net, a, "END")
    for _ = 1, 60 * 60 do net.step(1) end
    eq(ends.v, 0, "no END re-sends after FIN")
  end)

  it("message budget per player stays far below Blizzard's limits", function()
    local net, a, b = pair({ seed = 56 })
    local per = { [a] = {}, [b] = {} }
    net.tap = function(c, text) local s = math.floor(net.time); per[c][s] = (per[c][s] or 0) + 1 end
    local ma = runDuel(net, a, b)
    eq(ma.endReason, "checked")
    for c, secs in pairs(per) do
      local total, peak = 0, 0
      for _, n in pairs(secs) do total = total + n; if n > peak then peak = n end end
      print(string.format("    %s: %d messages per duel, peak %d in one second", c.name, total, peak))
      ok(total <= 110, c.name .. " total " .. total)
      ok(peak <= 8, c.name .. " peak " .. peak .. " per second")
    end
  end)

  it("/reload during a duel: the prefix is registered again, the rival wins by forfeit, the loss is saved", function()
    local net, a, b = pair({ seed = 57 })
    local ma = runDuel(net, a, b, { during = function(go)
      go(600)
      local b2 = net.reload(b)
      ok(b2.M.prefixes.StackRivals, "prefix registered again after /reload")
      ok(b2.ns.Comm.enabled)
      eq(b2.ns.Duel.current, nil, "a running duel can't survive a reload")
      eq(b2.ns.db.duels.flosses, 1, "Bob's forfeit was saved at logout (as a forfeit loss)")
      eq(b2.ns.db.duels.losses, 0, "not a played-out loss")
      go(30)
    end })
    eq(ma.endReason, "rival_forfeited"); eq(ma.outcome, "win"); eq(ma.basis, "forfeit")
    eq(a.ns.db.duels.fwins, 1); eq(a.ns.db.duels.wins, 0)
  end)

  it("a client on another protocol version answers in the inviter's version: 'different version'", function()
    local net = NS.new({ seed = 58 })
    local a = net.add({ name = "Alice", guild = "G" })
    local b = net.add({ name = "Bob", guild = "G", beforeLogin = function(env, M, ns) ns.Protocol.VERSION = 2 end })
    ok(a.ns.Duel.challenge("Bob")); net.step(60)
    ok(b.ns.Comm.stats.rejected >= 1, "Bob (v2) can't decode Alice's v1 invite")
    eq(b.ns.Duel.current, nil)
    eq(a.ns.Duel.current.state, "cancelled"); eq(a.ns.Duel.current.endReason, "rival_version", "Alice is told at once")
  end)

  it("GO while typing in chat starts the duel paused", function()
    local net, a, b = pair({ seed = 59 })
    ok(a.ns.Duel.challenge("Bob")); net.step(60)
    b.ns.UI.invite.acc:Click(); net.step(60)
    b.ns.UI.lobby.ready:Click(); net.step(30)
    b.env.GetCurrentKeyBoardFocus = function() return {} end -- chat edit box has focus
    a.ns.UI.lobby.ready:Click(); net.step(60)
    eq(b.ns.App.session.phase, "paused"); eq(b.ns.App.session.pauseReason, "chat")
  end)

  it("diagnostics: every duel leaves a compact, saved event log", function()
    local net, a, b = pair({ seed = 60, drop = 0.05 })
    local ma = runDuel(net, a, b)
    local r = a.ns.db.duelDiag[1]
    ok(r, "a record exists"); eq(r.mid, ma.mid); eq(r.rival, "Bob-Realm"); eq(r.result, ma.outcome)
    ok(r.sent.SC > 30 and r.recv.SC > 30, "score heartbeats counted")
    ok(r.codes["0"] > 0)
    ok(#r.lines > 5 and #r.lines < 120, #r.lines .. " lines")
    local joined = table.concat(r.lines, "\n")
    ok(joined:find(">INV") and joined:find("<ACC") and joined:find("~playing") and joined:find("=" .. ma.outcome), joined)
    ok(joined:find("<SC %d+/%d+"), "rival game state sampled")
    -- survives the SavedVariables round trip
    local db2 = a.ns.DB.sanitize(a.ns.db)
    eq(#db2.duelDiag, 1); eq(#db2.duelDiag[1].lines, #r.lines)
    local st = a.ns.DuelDiag.status()
    ok(#st >= 4 and st[3]:find("Bob"), table.concat(st, " | "))
    print("    diag sample: " .. table.concat({ r.lines[1], r.lines[2], r.lines[3], r.lines[#r.lines] }, " | "))
  end)
end)

------------------------------------------------------------------------------------------------
-- Regression tests for the second independent review (round 3)
------------------------------------------------------------------------------------------------
describe("second review findings (simulated clients)", function()
  local function dropSends(c, pred)
    local real = c.env.C_ChatInfo.SendAddonMessage
    c.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ch, tgt)
      if pred(text) then return 0 end -- accepted, never delivered
      return real(prefix, text, ch, tgt)
    end
  end
  local function toLobby(net, a, b)
    ok(a.ns.Duel.challenge("Bob", "b120"))
    for _ = 1, 40 do net.step(15); local m = b.ns.Duel.current; if m and m.state == "invited" then break end end
    b.ns.UI.invite.acc:Click()
    for _ = 1, 40 do net.step(15); if a.ns.Duel.current.state == "lobby" then break end end
  end
  local function runUntil(net, fns, cond, max)
    for _ = 1, max or 60 * 60 * 10 do
      if cond() then return true end
      for _, f in ipairs(fns) do f() end
      net.step(1)
    end
    return cond()
  end
  local function dropper(net, c, period)
    return function()
      local s = c.ns.App.session
      if s and s.duel and s.phase == "playing" and (math.floor(net.time * 60) % period) == 0 then s:press("hardDrop"); s:release("hardDrop") end
    end
  end

  it("H1 a GO that arrives 13 s late doesn't make the host's honest result look too fast", function()
    local net, a, b = pair({ seed = 101 })
    toLobby(net, a, b)
    local until_t
    dropSends(a, function(text)
      if text:match("^1:GO:") then until_t = until_t or (net.time + 13); return net.time < until_t end
      return false
    end)
    b.ns.UI.lobby.ready:Click(); net.step(30); a.ns.UI.lobby.ready:Click()
    runUntil(net, { NS.autoplay(a, "fast"), NS.autoplay(b, "slow") }, function()
      return a.ns.Duel.current.state == "done" and b.ns.Duel.current.state == "done" end)
    local ma, mb = a.ns.Duel.current, b.ns.Duel.current
    ok(mb.goAt - ma.goAt > 12, "the guest really started late")
    eq(ma.endReason, "checked"); eq(mb.endReason, "checked"); complementary(ma, mb)
  end)

  it("M1 a BYE 'left' that overtakes a lost END never gives the waiting player a win", function()
    local net, a, b = pair({ seed = 102 })
    toLobby(net, a, b)
    a.ns.UI.lobby.ready:Click(); b.ns.UI.lobby.ready:Click(); net.step(120)
    local lost = false
    dropSends(a, function(text) if text:match("^1:END:") and not lost then lost = true; return true end return false end)
    dropSends(b, function(text) return text:match("^1:LOG:") ~= nil end)
    runUntil(net, { dropper(net, b, 6) }, function() return b.ns.Duel.current.state == "waiting" end)
    runUntil(net, { NS.autoplay(a, "fast") }, function() return false end, 60 * 30)
    runUntil(net, { dropper(net, a, 6) }, function() return a.ns.Duel.current.state == "waiting" end)
    a.ns.Duel.leave()
    runUntil(net, {}, function() return b.ns.Duel.current.state == "done" end, 60 * 120)
    local mb = b.ns.Duel.current
    ok(mb.outcome ~= "win", "Bob (lower score) must not win: " .. tostring(mb.endReason))
    ok(mb.endReason == "checked" or mb.endReason == "unchecked", mb.endReason)
  end)

  it("L1 a guest that never played can't hand the host a timeout win through late DEC replies", function()
    local net, a, b = pair({ seed = 103 })
    toLobby(net, a, b)
    dropSends(a, function(text) return text:match("^1:GO:") ~= nil end)
    local first
    dropSends(b, function(text)
      if text:match("^1:DEC:") then first = first or net.time; return net.time < first + 6 end
      return false
    end)
    b.ns.UI.lobby.ready:Click(); net.step(30)
    local tg = b.ns.Duel.current.lobbyAt
    while net.time - tg < 57 do net.step(30) end
    a.ns.UI.lobby.ready:Click()
    runUntil(net, { NS.autoplay(a, "fast") }, function() local m = a.ns.Duel.current; return m.state == "done" or m.state == "cancelled" end, 60 * 60 * 3)
    eq(a.ns.Duel.current.state, "cancelled"); eq(a.ns.db.duels.wins, 0)
  end)

  it("L2 offline line: only the rival's full name counts, and one stray line doesn't end a duel", function()
    local net = NS.new({ seed = 104 })
    local filt
    local a = net.add({ name = "Alice", guild = "G", beforeLogin = function(env)
      env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
      env.ChatFrame_AddMessageEventFilter = function(ev, fn) filt = fn end
    end })
    local b = net.add({ name = "Bob-Other", guild = "G" })
    ok(filt, "chat filter installed")
    ok(a.ns.Duel.challenge("Bob-Other", "b120"))
    for _ = 1, 40 do net.step(15); local m = b.ns.Duel.current; if m and m.state == "invited" then break end end
    b.ns.UI.invite.acc:Click(); for _ = 1, 40 do net.step(15); if a.ns.Duel.current.state == "lobby" then break end end
    a.ns.UI.lobby.ready:Click(); b.ns.UI.lobby.ready:Click(); net.step(600)
    -- a different, offline "Bob" on Alice's own realm
    eq(filt(nil, "CHAT_MSG_SYSTEM", "No player named 'Bob' is currently playing."), false, "not ours: shown, ignored")
    -- the real rival's line, but Bob is still sending scores: grace keeps the duel alive
    eq(filt(nil, "CHAT_MSG_SYSTEM", "No player named 'Bob-Other' is currently playing."), true, "ours: hidden")
    net.step(60 * 10)
    eq(a.ns.Duel.current.state, "playing", "Bob is still heard, so the duel goes on")
    -- now Bob really goes offline
    b.online = false
    for _ = 1, 20 do net.step(60); if a.ns.Duel.current.state == "done" then break end; filt(nil, "CHAT_MSG_SYSTEM", "No player named 'Bob-Other' is currently playing.") end
    eq(a.ns.Duel.current.state, "done"); ok(a.ns.Duel.current.endReason == "rival_offline" or a.ns.Duel.current.endReason == "rival_disconnected")
  end)

  it("L9 a stranger's invites don't push real duels out of the saved diagnostics", function()
    local net, a, b = pair({ seed = 105 })
    local ma = runDuel(net, a, b)
    for i = 1, 8 do
      net.inject(a, "Mallory-Realm", "1:INV:mal" .. P.b36(100 + i) .. ":b120:1:abcdef12"); net.step(60)
      a.ns.Duel.decline("no"); net.step(30)
    end
    eq(a.ns.db.duelDiag[1].mid, ma.mid, "the real duel is still the newest record")
  end)
end)

return H
