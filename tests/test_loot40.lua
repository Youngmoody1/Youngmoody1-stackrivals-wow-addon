-- Loot Duel for 2-40 players at once: load and performance in SIMULATED WoW clients
-- (tests/netsim.lua: every client runs the real addon; WoW's per-prefix throttle of 10 messages
-- +1/s per sender is enforced; latency, loss and duplicates on request). NOT real clients: real
-- raids are in docs/LOOT_DUEL.md ("Test with 40 real players").
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local CLS = { "WARRIOR", "SHAMAN", "MAGE", "ROGUE", "PRIEST", "DRUID", "HUNTER", "WARLOCK", "PALADIN" }
local function nameOf(i)
  -- realistic names: 4-12 letters, one realm for the raid (+ a few from a connected realm)
  local base = { "Thrall", "Jaina", "Arthas", "Sylvanas", "Varian", "Anduin", "Tyrande", "Malfurion", "Illidan", "Garrosh" }
  local b = base[(i - 1) % #base + 1]
  return (b .. string.char(96 + math.floor((i - 1) / #base) + 1)):sub(1, 12)
end

--- A group of `size` (raid when > 5); returns net, clients (in order), names.
local function group(seed, size, netOpts)
  netOpts = netOpts or {}; netOpts.seed = seed
  local net = NS.new(netOpts)
  local list, names = {}, {}
  for i = 1, size do
    local n = nameOf(i)
    names[i] = n
    list[i] = net.add({ name = n, realm = (i % 7 == 0) and "Firemaw" or "ZandalarTribe", group = "G", raid = size > 5, lead = (i == 1),
      class = CLS[(i - 1) % #CLS + 1], saved = { seenHelp = true } })
  end
  net.step(30)
  return net, list, names
end
local function LDc(c) return c.ns.LootDuel end

--- Play the race: each player drops on its own pace (different scores; nobody plays perfectly).
local function race(net, list, skip, maxFrames)
  for f = 1, maxFrames or 7000 do
    local running = false
    for i, c in ipairs(list) do
      local s = c.ns.App.session
      if s and s.loot and not s.recorded and not (skip and skip[i]) then
        running = true
        if s.phase == "playing" and f % (3 + (i * 7) % 11) == 0 then
          if (f + i) % 4 == 0 then s:press("left"); s:release("left") end
          s:press("hardDrop"); s:release("hardDrop")
        end
      end
    end
    net.step(1)
    if not running then break end
  end
end

--- Invite n of the group, everyone joins, start, race, wait for the result. Measures everything.
local function run(seed, size, n, netOpts, hooks)
  hooks = hooks or {}
  local net, list, names = group(seed, size, netOpts)
  local lead = list[1]
  local inv = {}
  for i = 1, n do inv[i] = list[i].name end
  -- traffic: per sender per second, and bytes
  local perSec, bytes, sent0 = {}, 0, net.sent
  net.tap = function(c, text)
    local sec = math.floor(net.time)
    perSec[sec] = (perSec[sec] or 0) + 1
    bytes = bytes + #text
    c.sentBySec = c.sentBySec or {}
    c.sentBySec[sec] = (c.sentBySec[sec] or 0) + 1
  end
  for _, c in ipairs(list) do local st = LDc(c).stats; st.checks, st.checkMs, st.maxCheckMs = 0, 0, 0 end
  collectgarbage("collect")
  local mem0 = collectgarbage("count")
  ok(LDc(lead).create(19019, "l060", inv), "create")
  net.step(60 * 5)
  -- everyone clicks Join when the invite shows up (on a bad network some get it on a repeat)
  local answered = {}
  for _ = 1, 60 * 40 do
    net.step(1)
    for i = 2, n do if not answered[i] and LDc(list[i]).answer(true) then answered[i] = true end end
    if #LDc(lead).accepted(LDc(lead).current) == n then break end
  end
  net.step(60 * 2)
  eq(#LDc(lead).accepted(LDc(lead).current), n, "everyone joined")
  if hooks.beforeStart then hooks.beforeStart(net, list) end
  local t0 = net.time
  ok(LDc(lead).start(), "start")
  local started, lastStart = {}, 0
  for _ = 1, 60 * 90 do
    net.step(1)
    local all = true
    for i = 1, n do
      local c = list[i]
      if not started[i] and c.ns.App.session and c.ns.App.session.loot then started[i] = net.time - t0; lastStart = math.max(lastStart, started[i]) end
      if not started[i] and not (hooks.skip and hooks.skip[i]) then all = false end
    end
    if all then break end
    local d = LDc(lead).current
    if d and d.state == "cancelled" then break end
  end
  -- when the leader had every share (its go), and how late the latest go reached a player
  local ld = LDc(lead).current
  local leaderGo = ld and ld.startAt and (ld.startAt - t0) or -1
  local maxLate = 0
  for i = 1, n do local x = LDc(list[i]).current; if x and x.lateBy and x.lateBy > maxLate then maxLate = x.lateBy end end
  if hooks.duringRace then hooks.duringRace(net, list) end
  race(net, list, hooks.skip)
  local tEnd = net.time
  -- the result: every PC done
  local doneAt
  for _ = 1, 60 * 400 do
    net.step(1)
    local all = true
    for i = 1, size do local d = LDc(list[i]).history[1]; if not d and list[i].online then all = false end end -- a PC that went offline doesn't count
    if all then doneAt = net.time; break end
  end
  net.tap = nil
  collectgarbage("collect")
  local m = {
    n = n, size = size, startS = lastStart, raceEndS = tEnd - t0, resultS = doneAt and (doneAt - t0) or nil,
    afterRaceS = doneAt and (doneAt - tEnd) or nil, messages = net.sent - sent0, bytes = bytes, throttled = net.throttled,
    memKB = collectgarbage("count") - mem0, leaderGo = leaderGo, maxLate = maxLate, checks = 0, checkMs = 0, maxCheckMs = 0, peakChannel = 0, peakSender10 = 0,
  }
  for _, v in pairs(perSec) do if v > m.peakChannel then m.peakChannel = v end end
  for _, c in ipairs(list) do
    local st = LDc(c).stats
    m.checks, m.checkMs = m.checks + st.checks, m.checkMs + st.checkMs
    if st.maxCheckMs > m.maxCheckMs then m.maxCheckMs = st.maxCheckMs end
    -- the most one sender sent in any 10 s (WoW allows 10 + 1/s = 19 per 10 s per prefix)
    local secs = c.sentBySec or {}
    for s0 in pairs(secs) do
      local w = 0
      for s1 = s0, s0 + 9 do w = w + (secs[s1] or 0) end
      if w > m.peakSender10 then m.peakSender10 = w end
    end
  end
  return net, list, names, m
end

local function fmt(m)
  return string.format("%2d players (group %2d): start %.1f s (leader's go %.1f s, latest go %d s late) | result %.1f s after the race (%.0f s total) | %d messages (%.1f KB) | peak %d msg/s on the channel, %d per sender in 10 s | %d replays, %.0f ms total, max %.1f ms | +%.0f KB memory | throttled %d",
    m.n, m.size, m.startS, m.leaderGo, m.maxLate, m.afterRaceS or -1, m.resultS or -1, m.messages, m.bytes / 1024, m.peakChannel, m.peakSender10, m.checks, m.checkMs, m.maxCheckMs, m.memKB, m.throttled)
end

local function sameResult(list, n, size)
  local w, tie
  for i = 1, size do
    local d = LDc(list[i]).history[1]
    ok(d, list[i].name .. " has a result")
    local x = d.winner or ("tie:" .. table.concat(d.tied or {}, ","))
    w = w or x
    eq(x, w, list[i].name .. " same result")
  end
  return w
end

describe("Loot Duel 2-40 at once: load (simulated clients, WoW's throttle enforced)", function()
  for _, case in ipairs({ { 2, 5 }, { 5, 5 }, { 10, 10 }, { 15, 20 }, { 20, 20 }, { 25, 25 }, { 40, 40 } }) do
    local n, size = case[1], case[2]
    it(n .. " players: same pieces, one result on every PC, within WoW's message limit, replays bounded", function()
      local net, list, names, m = run(400 + n, size, n)
      H.note(fmt(m))
      eq(m.throttled, 0, "no message over WoW's per-prefix limit")
      ok(m.peakSender10 <= 19, "per sender within 10 + 1/s (" .. m.peakSender10 .. ")")
      ok(m.startS < 30, "everyone starts within 30 s (" .. m.startS .. ")")
      ok(m.resultS, "a result")
      local seed = LDc(list[1]).history[1].seed
      for i = 1, size do eq(LDc(list[i]).history[1].seed, seed, "same pieces") end
      local w = sameResult(list, n, size)
      ok(not w:find("^tie:$"), "a winner or a real tie")
      -- replays: at most the best 10 (+ ties) per PC, not 40 x 40
      local d = LDc(list[1]).history[1]
      local verified, unchecked = 0, 0
      for _, r in ipairs(d.standings) do
        if r.status == "verified" then verified = verified + 1 elseif r.status == "unchecked" then unchecked = unchecked + 1 end
      end
      eq(verified + unchecked, n, "every honest player counted")
      -- the best 10 claims plus everyone tied with the 10th (score and lines): those and only those
      local sc = {}
      for _, r in ipairs(d.standings) do sc[#sc + 1] = r end
      table.sort(sc, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.lines > b.lines end)
      local cut = sc[math.min(10, #sc)]
      local want = 0
      for _, r in ipairs(sc) do if r.score > cut.score or (r.score == cut.score and r.lines >= cut.lines) then want = want + 1 end end
      eq(verified, want, "replayed = the best 10 + ties with the 10th (" .. want .. ")")
      for i = 1, size do
        local st = LDc(list[i]).stats
        ok(st.checks <= want, list[i].name .. " replayed " .. st.checks .. " runs (best 10 + ties: " .. want .. ")")
      end
      if n <= 10 then eq(verified, n, "up to 10: every run replayed") end
      ok(m.maxCheckMs < 120, "one replay stays short (" .. m.maxCheckMs .. " ms)")
    end)
  end
end)

describe("Loot Duel with 40: trouble", function()
  it("40 over a bad network (latency up to 2.5 s, 20% duplicates, 5% loss) and 5 players at 5 fps: one result everywhere", function()
    local net, list, names, m = run(470, 40, 40, { latency = { 0.05, 2.5 }, dup = 0.2, drop = 0.05 }, {
      beforeStart = function(_, l) for i = 3, 7 do l[i].frameDt = 1 / 5 end end,
    })
    H.note("bad network: " .. fmt(m))
    eq(m.throttled, 0)
    sameResult(list, 40, 40)
    eq(LDc(list[1]).history[1].state, "done")
  end)

  it("40, three disconnect mid-race: disconnected live, no result for them, nobody wins by their absence", function()
    local gone = { [9] = true, [20] = true, [33] = true }
    local net, list, names, m = run(471, 40, 40, nil, {
      skip = gone,
      duringRace = function(n2, l)
        n2.step(60 * 8)
        for i in pairs(gone) do l[i].online = false end
        n2.step(60 * 30)
        local board = LDc(l[1]).liveBoard(LDc(l[1]).current)
        local disc = 0
        for _, r in ipairs(board) do if r.status == "disconnected" or r.status == "no_signal" then disc = disc + 1 end end
        ok(disc >= 3, "shown as disconnected / no signal: " .. disc)
      end,
    })
    H.note("3 disconnects: " .. fmt(m))
    local d = LDc(list[1]).history[1]
    for _, r in ipairs(d.standings) do
      for i in pairs(gone) do if r.name == list[i].name then eq(r.status, "missing", r.name) end end
    end
    for i = 1, 40 do if not gone[i] then ok(LDc(list[i]).history[1], list[i].name) end end
    ok(not gone[(function() for i, c in ipairs(list) do if c.name == d.winner then return i end end end)() or 0], "a player who left can't win")
  end)

  it("40, a modified client claims the top score with a forged log: rejected on every PC, the next best are promoted and win", function()
    local net, list, names, m = run(472, 40, 40, nil, {
      beforeStart = function(n2, l)
        -- player 17 lies: claims 999,999 with a log that doesn't produce it
        local c = l[17]
        local P = c.ns.Protocol
        local LDm = c.ns.LootDuel
        local realSend = LDm.sendFinal
        LDm.sendFinal = function(d)
          local s = c.ns.App.session
          if d.myFinal and not d.forged and s then
            d.forged = true
            d.results[c.name:lower()].score = 999999 -- its own PC believes the lie too, so it sends the log
            d.myFinal.msg = P.encode("LDE", d.lid, P.b36(s.state.tick), P.b36(999999), P.b36(s.state.lines), P.b36(s.state.level), c.ns.Engine.hashState(s.state), #d.myFinal.chunks)
          end
          return realSend(d)
        end
      end,
    })
    H.note("forged top claim: " .. fmt(m))
    local w = sameResult(list, 40, 40)
    ok(w ~= list[17].name, "the liar doesn't win")
    for i = 1, 40 do
      if i ~= 17 then
        local d = LDc(list[i]).history[1]
        for _, r in ipairs(d.standings) do if r.name == list[17].name then eq(r.status, "rejected", list[i].name) end end
      end
    end
  end)

  for _, case in ipairs({ { 12, "12 forged claims above everyone (more than the best 10)" }, { 25, "25 forged claims, 15 honest players" } }) do
    local nForged, title = case[1], case[2]
    it("40, " .. title .. ": every forged claim is rejected, checking goes on down the list, the best honest run wins on every PC", function()
      local liars = {}
      for i = 2, nForged + 1 do liars[i] = true end
      local net, list, names, m = run(480 + nForged, 40, 40, nil, {
        beforeStart = function(n2, l)
          for i in pairs(liars) do
            local c = l[i]
            local P = c.ns.Protocol
            local LDm = c.ns.LootDuel
            local realSend = LDm.sendFinal
            local fake = 900000 + i * 1000 -- all different, all above any honest score
            LDm.sendFinal = function(d)
              local s = c.ns.App.session
              if d.myFinal and not d.forged and s then
                d.forged = true
                d.results[c.name:lower()].score = fake
                d.myFinal.msg = P.encode("LDE", d.lid, P.b36(s.state.tick), P.b36(fake), P.b36(s.state.lines), P.b36(s.state.level), c.ns.Engine.hashState(s.state), #d.myFinal.chunks)
              end
              return realSend(d)
            end
          end
        end,
      })
      H.note(nForged .. " forged: " .. fmt(m))
      local w = sameResult(list, 40, 40)
      for i in pairs(liars) do ok(w ~= list[i].name, "a liar doesn't win") end
      -- the winner (or the tie) is the best honest run, replay-checked
      local d = LDc(list[1]).history[1]
      local bestHonest = -1
      for _, r in ipairs(d.standings) do
        local liar = false
        -- out either way: "rejected" (its log was replayed) or "missing" (a cheat that withholds its log)
        for i in pairs(liars) do if r.name == list[i].name then liar = true; ok(r.status == "rejected" or r.status == "missing", r.name .. " out: " .. r.status) end end
        if not liar and r.status ~= "missing" then bestHonest = math.max(bestHonest, r.score) end
      end
      local top = d.standings[1]
      eq(top.status, "verified", "the top of the list is replay-checked")
      eq(top.score, bestHonest, "the best honest score is on top")
    end)
  end

  it("40, a modified client reveals a seed share that doesn't match its commitment: the whole race is cancelled (no re-roll)", function()
    local net, list = group(473, 40)
    local lead = list[1]
    local inv = {}
    for i = 1, 40 do inv[i] = list[i].name end
    LDc(lead).create(19019, "l060", inv); net.step(60 * 5)
    for i = 2, 40 do LDc(list[i]).answer(true) end
    net.step(60 * 12)
    -- player 25 swaps its share after committing
    local cheat = LDc(list[25])
    local realReveal = cheat.sendReveal
    cheat.sendReveal = function(d) d.myNonce = "fakefake11"; realReveal(d) end
    ok(LDc(lead).start())
    net.step(60 * 90)
    eq(LDc(lead).current.state, "cancelled"); eq(LDc(lead).current.endReason, "noreveal")
    for i = 2, 40 do eq(list[i].ns.App.session, nil, list[i].name .. " never raced on a steerable seed") end
  end)

  it("20: a member who missed one join (LDA) and the one-message go still starts, from the full list and go (same pieces)", function()
    local net, list = group(475, 20)
    local lead, deaf = list[1], list[9]
    -- player 9 never hears player 5's answer, nor the one-message list / go (LDS / LDG)
    net.dropIf = function(to, from, text)
      if to ~= deaf then return false end
      return (from == list[5] and text:find(":LDA:", 1, true)) or text:find(":LDS:", 1, true) or text:find(":LDG:", 1, true)
    end
    local inv = {}
    for i = 1, 20 do inv[i] = list[i].name end
    LDc(lead).create(19019, "l060", inv); net.step(60 * 5)
    for i = 2, 20 do LDc(list[i]).answer(true) end
    net.step(60 * 12)
    eq(#LDc(lead).accepted(LDc(lead).current), 20)
    ok(LDc(lead).start())
    local t0 = net.time
    for _ = 1, 60 * 40 do net.step(1); if deaf.ns.App.session and deaf.ns.App.session.loot then break end end
    ok(deaf.ns.App.session and deaf.ns.App.session.loot, "player 9 races")
    H.note(string.format("player 9 started %.1f s after the start (full list + go on the repeats)", net.time - t0))
    eq(LDc(deaf).current.seed, LDc(lead).current.seed, "same pieces")
    eq(list[2].ns.App.session and list[2].ns.App.session.loot ~= nil, true, "the others race too")
  end)

  it("20: a member whose first go is lost starts from a repeat, plays the rest of the time and finishes with everyone", function()
    local net, list = group(476, 20)
    local lead, late = list[1], list[12]
    local inv = {}
    for i = 1, 20 do inv[i] = list[i].name end
    LDc(lead).create(19019, "l060", inv); net.step(60 * 5)
    for i = 2, 20 do LDc(list[i]).answer(true) end
    net.step(60 * 12)
    local t0
    -- the first go (LDG + LDW) and its first one-message repeat never reach player 12
    net.dropIf = function(to, from, text)
      return to == late and t0 and net.time < t0 + 6 and (text:find(":LDG:", 1, true) or text:find(":LDW:", 1, true)) and true or false
    end
    ok(LDc(lead).start()); t0 = net.time
    for _ = 1, 60 * 40 do net.step(1); if late.ns.App.session and late.ns.App.session.loot then break end end
    local d = LDc(late).current
    ok(late.ns.App.session and late.ns.App.session.loot, "player 12 races")
    ok((d.lateBy or 0) >= 2, "started late: " .. tostring(d.lateBy))
    eq(late.ns.App.session.mode.limitTicks, 3600 - d.lateBy * 60, "plays the rest of the minute")
    eq(d.seed, LDc(lead).current.seed, "same pieces")
    -- every run ends at about the same moment (the late one isn't 'behind' the others)
    local endAt = {}
    for _ = 1, 60 * 90 do
      net.step(1)
      for i, c in ipairs(list) do local s = c.ns.App.session; if not endAt[i] and s and s.loot and (s.recorded or s.phase == "over") then endAt[i] = net.time end end
      if endAt[1] and endAt[12] then break end
    end
    ok(endAt[1] and endAt[12], "both runs ended")
    ok(math.abs(endAt[12] - endAt[1]) < 3, string.format("ends together (%.1f s apart)", math.abs((endAt[12] or 0) - (endAt[1] or 0))))
    H.note(string.format("player 12 got the go %d s late; its run ended %.1f s from the leader's", d.lateBy or -1, math.abs((endAt[12] or 0) - (endAt[1] or 0))))
  end)

  it("one player who never answers or leaves the lobby can't block anyone: no answer = not in, the rest start", function()
    local net, list = group(474, 20)
    local lead = list[1]
    local inv = {}
    for i = 1, 20 do inv[i] = list[i].name end
    LDc(lead).create(19019, "l060", inv); net.step(60 * 5)
    for i = 2, 19 do LDc(list[i]).answer(true) end
    list[20].online = false -- left before answering
    net.step(60 * 12)
    eq(#LDc(lead).accepted(LDc(lead).current), 19)
    ok(LDc(lead).start(), "start without the one who left")
    net.step(60 * 30)
    for i = 1, 19 do ok(list[i].ns.App.session and list[i].ns.App.session.loot, list[i].name .. " races") end
  end)
end)

return H
