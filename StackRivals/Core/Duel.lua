--[[
  StackRivals - 1v1 duels between two WoW players (score race on a shared seed).

  Flow
    challenger                         rival
    INV(mid, ruleset, commitA) ----->  popup: Accept / Decline (30 s)
                               <-----  ACC(nonceB)             guest picks nonceB without knowing nonceA
    lobby: both press Ready    <---->  RDY
    GO(nonceA) -----------------------> checks nonceA against commitA; seed = srduel-<mid>-<nonceA><nonceB>
                                        both start the same countdown and the same pieces
    SC every 2 s  <-------------------> SC every 2 s            live rival score + keep-alive
    END + LOG chunks <----------------> END + LOG chunks         final score, hash, input log
    each side replays the rival's log with the engine (Verify) -> winner, "peer-checked"

  Commit-reveal: neither player can choose or grind the seed, and the guest only learns it at GO.

  Everything goes through ns.Comm (whispers, throttled, keyed so repeats replace each other).
  No board state is ever sent. Robust to lost / duplicated / reordered messages: every state
  re-sends what the rival needs, all handlers are idempotent, log chunks that arrive early are
  kept, and missing chunks are requested again (RQ) - also while I'm still playing.
  After the result we keep serving our END and log for LINGER seconds, even if the player
  already went back to the menu (Duel.past), so the rival can still check our run.

  Results
    checked            rival's log replayed to the claimed score -> compare scores
    check_failed       rival's log does NOT replay to their claim  -> I win (their result is rejected)
    unchecked          rival's log never fully arrived              -> no result (void)
    rival_forfeited / rival_disconnected / rival_offline / timeout -> I win
    you_forfeited      I left during play                           -> loss (both forfeited: draw)
    you_left           I left after my run ended, before the result  -> no result for me (void)
  Combat during a duel pauses your own run (safety first); the rival keeps playing.
]]
local _, ns = ...
local P, E, V = ns.Protocol, ns.Engine, ns.Verify

local Duel = { state = "idle", players = {}, listeners = {} }
ns.Duel = Duel

Duel.INVITE_TIMEOUT = 30      -- s to answer an invite
Duel.LOBBY_TIMEOUT = 60       -- s for both to press Ready (host; the guest waits GUEST_GRACE longer)
Duel.GUEST_GRACE = 15         -- s extra lobby time for the guest, so the host always decides first
Duel.SCORE_EVERY = 2          -- s between score heartbeats while playing
Duel.SILENT_WARN = 20         -- s without any message -> "connection lost?"
Duel.SILENT_GONE = 35         -- s without any message -> rival disconnected (web grace is 15 s on top)
Duel.LOG_WAIT = 60            -- s to receive the rival's log, counted from max(their END, my end)
Duel.AFTER_TIME = 300         -- s after the time limit before an unfinished rival loses
Duel.FIND_COOLDOWN = 20       -- s between "find players" broadcasts
Duel.LOG_SEND_GAP = 0.25      -- s between LOG chunks (Comm throttles too)
Duel.RESEND = 4               -- s between re-sends of state messages before/after play
Duel.LINGER = 60              -- s after the result we still serve the rival (END, log chunks)
Duel.EARLY_CANCEL = 20        -- s after GO a rival's cancel still counts if they never played
Duel.CLOCK_MARGIN = 10        -- s: a final result can't arrive faster than the game takes to play
Duel.REPLY_GAP = 10           -- s between unsolicited replies (HI, "busy") to the same player

local function now() return GetTime() end
local function inCombat() return ns.UI and ns.UI.inCombat and ns.UI.inCombat() end
local function rnd(a, b) return math.random(a, b) end
local function session() return ns.App and ns.App.session end

function Duel.on(event, fn) Duel.listeners[event] = fn end
local function emit(event, ...)
  local fn = Duel.listeners[event]
  if fn then fn(...) end
end

-- Messages that are re-sent (or superseded) share a key, so only the newest one waits in the queue.
local KEYED = { INV = true, ACC = true, RDY = true, GO = true, PNG = true, SC = true, END = true }

local function send(m, kind, ...)
  if m.rivalOffline then return end -- whispering an offline player only spams the chat
  local key
  if KEYED[kind] then key = kind .. ":" .. m.mid
  elseif kind == "LOG" or kind == "RQ" then key = kind .. ":" .. m.mid .. ":" .. tostring((select(2, ...))) end
  ns.Comm.send(P.encode(kind, ...), "WHISPER", m.rival, function(reason)
    -- never act inside the send call itself: just flag it, update() handles it next frame
    if reason == "offline" then m.rivalOffline = true end
  end, key and { key = key } or nil)
end

local lastReply = {}
local function reply(sender, text)
  local t = now()
  local k = sender:lower()
  if lastReply[k] and t - lastReply[k] < Duel.REPLY_GAP then return end
  lastReply[k] = t
  ns.Comm.send(text, "WHISPER", sender, nil, { low = true })
end

function Duel.busy()
  local m = Duel.current
  return m ~= nil and m.state ~= "done" and m.state ~= "cancelled"
end

------------------------------------------------------------------------------------------------
-- Finding players (guild / group): one broadcast, answers come back by whisper
------------------------------------------------------------------------------------------------
function Duel.findPlayers()
  local t = now()
  if Duel.lastFind and t - Duel.lastFind < Duel.FIND_COOLDOWN then return false, "cooldown" end
  Duel.lastFind = t
  local msg = P.encode("HEL", ns.VERSION, E.ENGINE_VERSION)
  local any = false
  if IsInGuild and IsInGuild() then ns.Comm.send(msg, "GUILD"); any = true end
  if IsInRaid and IsInRaid() then ns.Comm.send(msg, "RAID"); any = true
  elseif IsInGroup and IsInGroup() then ns.Comm.send(msg, "PARTY"); any = true end
  -- forget answers older than 2 minutes
  for name, p in pairs(Duel.players) do if t - p.at > 120 then Duel.players[name] = nil end end
  emit("players")
  return any, any and nil or "no_guild_or_group"
end

local function onHello(m, sender)
  reply(sender, P.encode("HI", ns.VERSION, E.ENGINE_VERSION, Duel.busy() and 1 or 0))
end

local function onHi(m, sender)
  Duel.players[sender] = { name = sender, addon = m.addon, engine = m.engine, busy = m.busy, at = now(),
    compatible = (m.engine == E.ENGINE_VERSION) }
  emit("players")
end

------------------------------------------------------------------------------------------------
-- Match lifecycle
------------------------------------------------------------------------------------------------
local function newMatch(role, rival, ruleset, mid)
  return {
    role = role, rival = rival, ruleset = P.RULESETS[ruleset], rulesetId = ruleset, mid = mid,
    state = "new", createdAt = now(), lastHeard = now(), lastSent = 0, lastRQ = 0,
    myReady = false, rivalReady = false, rival_ = {}, chunks = {},
  }
end

local function pauseSolo()
  local s = session()
  if s and not s.duel and s:isActive() then ns.App:Pause("manual") end
end

--- Challenge a player by full name ("Name-Realm" or "Name" on your realm).
function Duel.challenge(name, rulesetId)
  rulesetId = rulesetId or "b120"
  if not P.RULESETS[rulesetId] then return false, "ruleset" end
  if not ns.Comm.enabled then return false, "unavailable" end
  if Duel.busy() then return false, "busy" end
  if inCombat() then return false, "combat" end
  local rival = ns.Comm.fullName(name)
  if not rival or ns.Comm.same(rival, ns.Comm.me()) then return false, "self" end
  Duel.retire(Duel.current)
  local m = newMatch("host", rival, rulesetId, P.token(6, rnd))
  m.nonceA = P.token(8, rnd)
  m.commitA = P.commit(m.mid, m.nonceA)
  m.state = "inviting"
  Duel.current = m
  pauseSolo()
  send(m, "INV", m.mid, rulesetId, E.ENGINE_VERSION, m.commitA)
  emit("changed", m)
  return true
end

local function onInvite(msg, sender)
  local cur = Duel.current
  if cur and cur.mid == msg.mid and ns.Comm.same(cur.rival, sender) then cur.lastHeard = now(); return end -- re-sent invite
  -- we challenged each other at the same moment: the lower match id wins, the other side accepts it
  local crossed = cur and cur.state == "inviting" and ns.Comm.same(cur.rival, sender)
  if crossed and cur.mid < msg.mid then return end -- my invite wins; they will accept it
  if not crossed and Duel.busy() then
    return reply(sender, P.encode("DEC", msg.mid, "busy"))
  end
  if msg.engine ~= E.ENGINE_VERSION then return reply(sender, P.encode("DEC", msg.mid, "version")) end
  if inCombat() then return reply(sender, P.encode("DEC", msg.mid, "combat")) end
  if crossed then
    ns.Comm.purge(cur.mid) -- my own invite is obsolete
    cur.state = "cancelled"
  end
  Duel.retire(cur)
  local m = newMatch("guest", sender, msg.ruleset, msg.mid)
  m.commitA = msg.nonce
  m.state = "invited"
  m.rematch = cur ~= nil and not crossed and cur.rival ~= nil and ns.Comm.same(cur.rival, sender)
  Duel.current = m
  if crossed then
    Duel.accept() -- both wanted this duel
    return
  end
  emit("invite", m)
  emit("changed", m)
end

function Duel.accept()
  local m = Duel.current
  if not m or m.state ~= "invited" then return false end
  if inCombat() then return false, "combat" end
  m.nonceB = P.token(8, rnd)
  m.state = "lobby"
  m.lobbyAt = now()
  pauseSolo()
  send(m, "ACC", m.mid, m.nonceB)
  emit("changed", m)
  return true
end

--- Decline an invite, or cancel before the start.
function Duel.decline(reason)
  local m = Duel.current
  if not m or (m.state ~= "invited" and m.state ~= "inviting" and m.state ~= "lobby") then return false end
  local wasInvite = m.state == "invited"
  send(m, "DEC", m.mid, reason or "no")
  m.state = "cancelled"
  m.endReason = (reason == "timeout") and "timeout" or (reason == "cancel") and "you_cancelled" or "you_declined"
  if wasInvite then
    -- an unanswered invite never took over the screen: just forget it (the DEC stays queued)
    Duel.current = nil
    emit("changed", nil)
  else
    emit("changed", m)
  end
  return true
end

function Duel.ready()
  local m = Duel.current
  if not m or m.state ~= "lobby" or m.myReady then return false end
  m.myReady = true
  send(m, "RDY", m.mid)
  if m.role == "host" and m.rivalReady then Duel.go(m) end
  emit("changed", m)
  return true
end

local function seedFor(m) return P.seed(m.mid, m.nonceA, m.nonceB) end

function Duel.go(m)
  m.seed = seedFor(m)
  if m.role == "host" then send(m, "GO", m.mid, m.nonceA) end
  m.state = "playing"
  m.goAt = now()
  m.deadline = m.goAt + m.ruleset.limitTicks / 60 + m.ruleset.countdownTicks / 60 + Duel.AFTER_TIME
  ns.App:StartDuel(m)
  emit("changed", m)
end

--- Leave the match. Before the start this is a cancel, during play a forfeit, after my own
--- run ended it only means "I'm not waiting for the result" (my result still reaches the rival).
function Duel.leave()
  local m = Duel.current
  if not m then return end
  if m.state == "invited" or m.state == "inviting" or m.state == "lobby" then return Duel.decline("cancel") end
  if m.state == "playing" then
    send(m, "BYE", m.mid, "forfeit")
    m.myForfeit = true
    Duel.finish(m, "you_forfeited")
  elseif m.state == "waiting" then
    send(m, "BYE", m.mid, "left")
    Duel.finish(m, "you_left")
  end
end

local function sendEnd(m)
  send(m, "END", m.mid, P.b36(m.my.ticks), P.b36(m.my.score), P.b36(m.my.lines), P.b36(m.my.level), m.my.hash, #m.outChunks)
end

--- Called by the app when my run in this duel is over (top-out or time).
function Duel.onLocalEnd(state)
  local m = Duel.current
  if not m or m.state ~= "playing" then return end
  m.my = { score = state.score, lines = state.lines, level = state.level, ticks = state.tick, hash = E.hashState(state), over = state.gameOver }
  m.myEndAt = now()
  m.outChunks = P.chunk(P.packLog(state.inputLog))
  m.outNext = 1
  m.state = "waiting"
  send(m, "SC", m.mid, P.b36(state.tick), P.b36(state.score), P.b36(state.lines), 1)
  sendEnd(m)
  m.lastSent = now()
  emit("changed", m)
  Duel.tryDecide(m)
end

------------------------------------------------------------------------------------------------
-- Incoming match messages
------------------------------------------------------------------------------------------------
local function heard(m)
  m.lastHeard = now()
  m.silentWarned = false
  m.rivalGone = false       -- they're back (loading screen, lockdown, ...)
  m.rivalOffline = false
end

local function matchFor(msg, sender)
  local m = Duel.current
  if not m or m.mid ~= msg.mid or not ns.Comm.same(m.rival, sender) then return nil end
  heard(m)
  return m
end

--- Current or lingering match (only to keep serving our END / log).
local function servedMatch(msg, sender)
  local m = matchFor(msg, sender)
  if m then return m end
  local p = Duel.past
  if p and p.mid == msg.mid and ns.Comm.same(p.rival, sender) then return p end
end

local HANDLERS = {}

HANDLERS.ACC = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or m.state ~= "inviting" then return end
  m.nonceB = msg.nonce
  m.state = "lobby"
  m.lobbyAt = now()
  emit("changed", m)
end

HANDLERS.DEC = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m then return end
  local s = session()
  -- lobby race: the guest gave up just as we started; they never played, so nobody wins
  local earlyStart = m.state == "playing" and m.rival_.tick == nil and now() - (m.goAt or 0) < Duel.EARLY_CANCEL
  if not (m.state == "inviting" or m.state == "lobby" or m.state == "invited" or earlyStart) then return end
  m.state = "cancelled"
  m.endReason = "rival_" .. msg.reason
  if earlyStart and s and s.duel == m then ns.App.session = nil end
  emit("changed", m)
end

HANDLERS.RDY = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or m.state ~= "lobby" then return end
  m.rivalReady = true
  if m.role == "host" and m.myReady then Duel.go(m) end
  emit("changed", m)
end

HANDLERS.GO = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or m.state ~= "lobby" or m.role ~= "guest" then return end
  m.rivalReady = true
  if P.commit(m.mid, msg.nonce) ~= m.commitA then
    -- the host revealed a different nonce than it committed to: a manipulated seed
    send(m, "DEC", m.mid, "cancel")
    m.state = "cancelled"; m.endReason = "rival_bad_seed"
    emit("changed", m)
    return
  end
  m.nonceA = msg.nonce
  if not m.myReady then return end -- can't happen with a well-behaved host; ignore
  Duel.go(m)
end

HANDLERS.PNG = function(msg, sender) matchFor(msg, sender) end

HANDLERS.SC = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or (m.state ~= "playing" and m.state ~= "waiting") then return end
  local r = m.rival_
  if r.tick and msg.tick < r.tick then return end -- old / duplicated / reordered
  r.tick, r.score, r.lines, r.over = msg.tick, msg.score, msg.lines, msg.over
  emit("score", m)
end

HANDLERS.END = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or (m.state ~= "playing" and m.state ~= "waiting") or m.rivalEnd then return end
  local t = now()
  m.rivalEnd = { ticks = msg.ticks, score = msg.score, lines = msg.lines, level = msg.level, hash = msg.hash, chunks = msg.chunks, at = t }
  -- a result can't arrive before the game could have been played (web: faster_than_clock)
  local earliest = (m.goAt or t) + (m.ruleset.countdownTicks + msg.ticks) / 60 - Duel.CLOCK_MARGIN
  if t < earliest then m.tooFast = true end
  -- chunks that arrived before this END but for a different log length are useless
  if m.chunksN and m.chunksN ~= msg.chunks then m.chunks = {} end
  m.chunksN = msg.chunks
  local r = m.rival_
  r.score, r.lines, r.over, r.tick = msg.score, msg.lines, true, msg.ticks
  emit("score", m)
  Duel.tryDecide(m)
end

HANDLERS.LOG = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or (m.state ~= "playing" and m.state ~= "waiting") then return end
  if m.chunksN and msg.n ~= m.chunksN then
    if m.rivalEnd then return end -- END is authoritative
    m.chunks = {}
  end
  m.chunksN = msg.n
  m.chunks[msg.i] = msg.payload -- duplicates simply overwrite
  m.lastChunkIn = now()
  Duel.tryDecide(m)
end

HANDLERS.RQ = function(msg, sender)
  local m = servedMatch(msg, sender)
  if not m or not m.outChunks or msg.i > #m.outChunks then return end
  send(m, "LOG", m.mid, msg.i, #m.outChunks, m.outChunks[msg.i])
end

HANDLERS.BYE = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or m.state == "done" or m.state == "cancelled" then return end
  m.rivalForfeit = msg.reason
  if m.state == "playing" then
    emit("changed", m) -- keep playing; the result is decided when my run ends
  else
    Duel.tryDecide(m)
  end
end

local function onOffline(lname)
  for _, m in ipairs({ Duel.current or false, Duel.past or false }) do
    if m and m.rival:lower() == lname or (m and m.rival:lower():match("^[^%-]+") == lname) then m.rivalOffline = true end
  end
end

function Duel.init()
  ns.Comm.tick = Duel.update
  ns.Comm.on("HEL", onHello)
  ns.Comm.on("HI", onHi)
  ns.Comm.on("INV", onInvite)
  ns.Comm.on("@offline", onOffline)
  for kind, fn in pairs(HANDLERS) do ns.Comm.on(kind, fn) end
end

------------------------------------------------------------------------------------------------
-- Deciding the result
------------------------------------------------------------------------------------------------
local function haveAllChunks(m)
  if not m.rivalEnd then return false end
  for i = 1, m.rivalEnd.chunks do if not m.chunks[i] then return false end end
  return true
end

function Duel.tryDecide(m)
  if m.state ~= "waiting" then return end -- my own run must be over first
  -- a complete log beats everything else: the rival finished, even if they left afterwards
  if haveAllChunks(m) then
    local log = P.unpackLog(table.concat(m.chunks, "", 1, m.rivalEnd.chunks))
    if not log then
      m.check = { ok = false, reasons = { "malformed_log" } }
    elseif m.tooFast then
      m.check = { ok = false, reasons = { "faster_than_clock" } }
    else
      m.check = V.verify(log, m.seed, m.rivalEnd.ticks, {
        seed = m.seed, capTicks = m.ruleset.limitTicks,
        claimed = { score = m.rivalEnd.score, lines = m.rivalEnd.lines, hash = m.rivalEnd.hash },
      })
    end
    return Duel.finish(m, m.check.ok and "checked" or "check_failed")
  end
  if m.rivalForfeit == "forfeit" or m.rivalForfeit == "quit" then return Duel.finish(m, "rival_forfeited") end
  local gone = m.rivalGone or m.rivalForfeit
  if gone and not m.rivalEnd then return Duel.finish(m, m.rivalOffline and "rival_offline" or "rival_disconnected") end
  -- gone after their END: their log may still be on its way; update() decides after LOG_WAIT
end

--- Final result (see the header for the reasons).
function Duel.finish(m, reason)
  if m.state == "done" or m.state == "cancelled" then return end
  local prev = m.state
  m.state = "done"
  m.endReason = reason
  m.doneAt = now()
  local s = session()
  local mine = s and s.duel == m
  local my = m.my and m.my.score or (mine and s.state.score) or 0
  local their = m.rivalEnd and m.rivalEnd.score or (m.rival_.score or 0)
  if reason == "check_failed" or reason == "rival_forfeited" or reason == "rival_disconnected"
    or reason == "rival_offline" or reason == "timeout" then
    m.outcome = "win"
  elseif reason == "unchecked" or reason == "you_left" then
    m.outcome = "void"
  elseif reason == "you_forfeited" then
    m.outcome = (m.rivalForfeit == "forfeit") and "draw" or "loss" -- both forfeited: draw (web rule)
  elseif my > their then m.outcome = "win"
  elseif my < their then m.outcome = "loss"
  else m.outcome = "draw" end
  m.myScore, m.theirScore = my, their
  if prev == "playing" and mine and s:isActive() then
    s:finish(reason == "you_forfeited" and "forfeit" or "rival_left")
  end
  if ns.DB and ns.db then ns.DB.recordDuel(ns.db, m, ns.App:Today()) end
  emit("result", m)
  emit("changed", m)
end

------------------------------------------------------------------------------------------------
-- Timers (called every frame by the transport frame, also while our window is hidden)
------------------------------------------------------------------------------------------------
local function streamLog(m, t)
  if m.outChunks and m.outNext <= #m.outChunks and t - (m.lastChunkAt or 0) >= Duel.LOG_SEND_GAP then
    m.lastChunkAt = t
    send(m, "LOG", m.mid, m.outNext, #m.outChunks, m.outChunks[m.outNext])
    m.outNext = m.outNext + 1
  end
end

local function requestMissing(m, t, max)
  -- only when the stream has stalled: chunks still trickling in are on their way already
  if not m.rivalEnd or t - math.max(m.rivalEnd.at, m.lastChunkIn or 0) < 3 or t - m.lastRQ < Duel.RESEND then return end
  m.lastRQ = t
  local asked = 0
  for i = 1, m.rivalEnd.chunks do
    if not m.chunks[i] and asked < max then send(m, "RQ", m.mid, i); asked = asked + 1 end
  end
end

-- After the result: keep sending our END and log until the rival has had time to get them.
local function serveAfter(m, t)
  if not m.my or m.myForfeit or t - m.doneAt >= Duel.LINGER then return false end
  streamLog(m, t)
  if t - m.lastSent >= Duel.RESEND then m.lastSent = t; sendEnd(m) end
  return true
end

function Duel.update()
  local t = now()
  if Duel.past and not serveAfter(Duel.past, t) then Duel.past = nil end
  local m = Duel.current
  if not m or m.state == "cancelled" then return end
  if m.state == "done" then serveAfter(m, t); return end

  -- the rival is offline (server said so): stop before the match, or decide during it
  if m.rivalOffline and not m.offlineSeen then
    m.offlineSeen = true
    if m.state == "inviting" or m.state == "lobby" or m.state == "invited" then
      m.state = "cancelled"; m.endReason = "rival_offline"; emit("changed", m); return
    end
    m.rivalGone = true
    if m.state == "playing" and not haveAllChunks(m) then return Duel.finish(m, "rival_offline") end
    emit("changed", m)
    Duel.tryDecide(m)
    if m.state ~= "playing" and m.state ~= "waiting" then return end
  elseif not m.rivalOffline then
    m.offlineSeen = false
  end

  if m.state == "inviting" and t - m.createdAt > Duel.INVITE_TIMEOUT + 5 then
    m.state = "cancelled"; m.endReason = "no_answer"; emit("changed", m); return
  end
  if m.state == "invited" and t - m.createdAt > Duel.INVITE_TIMEOUT then
    Duel.decline("timeout"); return
  end
  local lobbyLimit = Duel.LOBBY_TIMEOUT + (m.role == "guest" and Duel.GUEST_GRACE or 0)
  if m.state == "lobby" and t - (m.lobbyAt or t) > lobbyLimit then
    send(m, "DEC", m.mid, "timeout")
    m.state = "cancelled"; m.endReason = "lobby_timeout"; emit("changed", m); return
  end
  -- what the rival needs from us right now (re-sent, so a lost message never stalls a duel)
  local every = (m.state == "playing") and Duel.SCORE_EVERY or Duel.RESEND
  if t - m.lastSent >= every and m.state ~= "invited" then
    m.lastSent = t
    local s = session()
    if m.state == "inviting" then
      send(m, "INV", m.mid, m.rulesetId, E.ENGINE_VERSION, m.commitA)
    elseif m.state == "lobby" then
      if m.role == "guest" then send(m, "ACC", m.mid, m.nonceB) end
      if m.myReady then send(m, "RDY", m.mid) elseif m.role == "host" then send(m, "PNG", m.mid) end
    elseif m.state == "playing" and s and s.duel == m then
      send(m, "SC", m.mid, P.b36(s.state.tick), P.b36(s.state.score), P.b36(s.state.lines), 0)
      -- repeat GO until the guest's first score shows it started
      if m.role == "host" and m.rival_.tick == nil and t - m.goAt < 30 then send(m, "GO", m.mid, m.nonceA) end
    elseif m.state == "waiting" and m.my then
      sendEnd(m)
    else
      send(m, "PNG", m.mid)
    end
  end
  if m.state == "playing" or m.state == "waiting" then
    requestMissing(m, t, m.state == "playing" and 2 or 3)
  end
  streamLog(m, t)
  -- silence
  local quiet = t - m.lastHeard
  if (m.state == "lobby" or m.state == "playing" or m.state == "waiting") then
    if quiet > Duel.SILENT_GONE and not m.rivalGone then
      m.rivalGone = true
      if m.state == "lobby" then
        m.state = "cancelled"; m.endReason = "rival_disconnected"; emit("changed", m); return
      end
      emit("changed", m)
      Duel.tryDecide(m)
    elseif quiet > Duel.SILENT_WARN and not m.silentWarned then
      m.silentWarned = true
      emit("changed", m)
    end
  end
  if m.state ~= "waiting" then return end
  -- rival's log never fully arrived: no result (a missing log must never decide a winner)
  if m.rivalEnd and not haveAllChunks(m) and t - math.max(m.rivalEnd.at, m.myEndAt or 0) > Duel.LOG_WAIT then
    return Duel.finish(m, "unchecked")
  end
  -- hard deadline: an unfinished rival loses
  if m.deadline and t > m.deadline and not m.rivalEnd then
    Duel.finish(m, "timeout")
  end
end

--- Keep serving a finished match in the background (its END / log may still be needed).
function Duel.retire(m)
  if m and m.state == "done" and m.my and not m.myForfeit and now() - m.doneAt < Duel.LINGER then
    Duel.past = m
  end
end

--- Rematch the same rival with the same rules.
function Duel.rematch()
  local m = Duel.current
  if not m or m.state ~= "done" then return false end
  return Duel.challenge(m.rival, m.rulesetId)
end

--- Forget a finished / cancelled match (back to the menu). Its result keeps reaching the rival.
function Duel.clear()
  local m = Duel.current
  if m and (m.state == "done" or m.state == "cancelled") then
    ns.Comm.purge(m.mid) -- drops pings/scores; final messages (END, LOG, DEC, BYE) stay queued
    Duel.retire(m)
    Duel.current = nil
    emit("changed", nil)
  end
end

--- Short display name: "Name" for your realm, "Name-Realm" otherwise.
function Duel.short(name)
  local me = ns.Comm.me()
  local realm = me and me:match("%-(.+)$")
  if realm and name and name:sub(-#realm - 1) == "-" .. realm then return name:sub(1, -#realm - 2) end
  return name
end

return Duel
