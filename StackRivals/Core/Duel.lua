--[[
  StackRivals - 1v1 duels between two WoW players (score race on a shared seed).

  Flow
    challenger                         rival
    INV(mid, ruleset, nonceA)  ----->  popup: Accept / Decline (30 s)
                               <-----  ACC(nonceB)            seed = srduel-<mid>-<nonceA><nonceB>
    lobby: both press Ready    <---->  RDY                     (neither player chose the seed alone)
    GO  ------------------------------> both start the same countdown and the same pieces
    SC every 2 s  <-------------------> SC every 2 s           live rival score + keep-alive
    END + LOG chunks <----------------> END + LOG chunks        final score, hash, input log
    each side replays the rival's log with the engine (Verify) -> winner, "peer-checked"

  Everything goes through ns.Comm (whispers, throttled). No board state is ever sent.
  Robust to lost / duplicated / late messages: every state re-sends what the rival needs
  (INV while inviting, ACC/RDY in the lobby, SC while playing, END while waiting), all handlers
  are idempotent, and missing log chunks are requested again (RQ).
  Combat during a duel pauses your own run (safety first); the rival keeps playing. A match
  has a hard deadline so nobody waits forever.
]]
local _, ns = ...
local P, E, V = ns.Protocol, ns.Engine, ns.Verify

local Duel = { state = "idle", players = {}, listeners = {} }
ns.Duel = Duel

Duel.INVITE_TIMEOUT = 30      -- s to answer an invite
Duel.LOBBY_TIMEOUT = 60       -- s for both to press Ready
Duel.SCORE_EVERY = 2          -- s between score heartbeats while playing
Duel.PING_EVERY = 5           -- s between keep-alives otherwise
Duel.SILENT_WARN = 20         -- s without any message -> "connection lost?"
Duel.SILENT_GONE = 35         -- s without any message -> rival disconnected (web grace is 15 s on top)
Duel.LOG_WAIT = 60            -- s to receive the rival's log after their END
Duel.AFTER_TIME = 300         -- s after the time limit before an unfinished rival loses
Duel.FIND_COOLDOWN = 20       -- s between "find players" broadcasts
Duel.LOG_SEND_GAP = 0.25      -- s between LOG chunks (Comm throttles too)
Duel.RESEND = 4               -- s between re-sends of state messages before/after play
Duel.LINGER = 60              -- s after the result we still answer the rival (END, chunks)

local function now() return GetTime() end
local function inCombat() return ns.UI and ns.UI.inCombat and ns.UI.inCombat() end
local function rnd(a, b) return math.random(a, b) end

function Duel.on(event, fn) Duel.listeners[event] = fn end
local function emit(event, ...)
  local fn = Duel.listeners[event]
  if fn then fn(...) end
end

local function send(m, kind, ...)
  ns.Comm.send(P.encode(kind, ...), "WHISPER", m.rival, function(reason)
    if reason == "offline" and Duel.current == m and m.state ~= "done" then
      Duel.finish(m, "rival_offline")
    end
  end)
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

local helloAnswered = {}
local function onHello(m, sender)
  local t = now()
  if helloAnswered[sender] and t - helloAnswered[sender] < 10 then return end
  helloAnswered[sender] = t
  ns.Comm.send(P.encode("HI", ns.VERSION, E.ENGINE_VERSION, Duel.busy() and 1 or 0), "WHISPER", sender)
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
    state = "new", createdAt = now(), lastHeard = now(), lastSent = 0,
    myReady = false, rivalReady = false, rival_ = {}, chunks = {}, sentLog = false,
  }
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
  local m = newMatch("host", rival, rulesetId, P.token(6, rnd))
  m.nonceA = P.token(8, rnd)
  m.state = "inviting"
  Duel.current = m
  if ns.App and ns.App.session and ns.App.session:isActive() then ns.App:Pause("manual") end
  send(m, "INV", m.mid, rulesetId, E.ENGINE_VERSION, m.nonceA)
  emit("changed", m)
  return true
end

local function onInvite(msg, sender)
  local function decline(reason)
    ns.Comm.send(P.encode("DEC", msg.mid, reason), "WHISPER", sender)
  end
  local cur = Duel.current
  if cur and cur.mid == msg.mid and ns.Comm.same(cur.rival, sender) then cur.lastHeard = now(); return end -- re-sent invite
  -- a rematch invite from the rival we just played replaces the finished match
  if Duel.busy() then return decline("busy") end
  if msg.engine ~= E.ENGINE_VERSION then return decline("version") end
  if inCombat() then return decline("combat") end
  local m = newMatch("guest", sender, msg.ruleset, msg.mid)
  m.nonceA = msg.nonce
  m.state = "invited"
  m.rematch = cur ~= nil and cur.rival ~= nil and ns.Comm.same(cur.rival, sender)
  Duel.current = m
  emit("invite", m)
  emit("changed", m)
end

function Duel.accept()
  local m = Duel.current
  if not m or m.state ~= "invited" then return false end
  if inCombat() then return false, "combat" end
  m.nonceB = P.token(8, rnd)
  m.seed = P.seed(m.mid, m.nonceA, m.nonceB)
  m.state = "lobby"
  m.lobbyAt = now()
  if ns.App and ns.App.session and ns.App.session:isActive() then ns.App:Pause("manual") end
  send(m, "ACC", m.mid, m.nonceB)
  emit("changed", m)
  return true
end

function Duel.decline(reason)
  local m = Duel.current
  if not m or (m.state ~= "invited" and m.state ~= "inviting" and m.state ~= "lobby") then return false end
  send(m, "DEC", m.mid, reason or "no")
  m.state = "cancelled"
  m.endReason = (reason == "timeout") and "timeout" or "you_declined"
  emit("changed", m)
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

function Duel.go(m)
  if m.role == "host" then send(m, "GO", m.mid) end
  m.state = "playing"
  m.goAt = now()
  m.deadline = m.goAt + m.ruleset.limitTicks / 60 + m.ruleset.countdownTicks / 60 + Duel.AFTER_TIME
  ns.App:StartDuel(m)
  emit("changed", m)
end

--- Leave the match. Before the start this is a cancel, during/after it is a forfeit.
function Duel.leave()
  local m = Duel.current
  if not m then return end
  if m.state == "invited" or m.state == "inviting" or m.state == "lobby" then return Duel.decline("cancel") end
  if m.state == "playing" or m.state == "waiting" then
    send(m, "BYE", m.mid, "forfeit")
    m.myForfeit = true
    Duel.finish(m, "you_forfeited")
  end
end

--- Called by the app when my run in this duel is over (top-out or time).
function Duel.onLocalEnd(state)
  local m = Duel.current
  if not m or m.state ~= "playing" then return end
  m.my = { score = state.score, lines = state.lines, level = state.level, ticks = state.tick, hash = E.hashState(state), over = state.gameOver }
  m.myLog = state.inputLog
  local packed = P.packLog(state.inputLog)
  m.outChunks = P.chunk(packed)
  m.outNext = 1
  m.state = "waiting"
  send(m, "SC", m.mid, P.b36(state.tick), P.b36(state.score), P.b36(state.lines), 1)
  send(m, "END", m.mid, P.b36(m.my.ticks), P.b36(m.my.score), P.b36(m.my.lines), P.b36(m.my.level), m.my.hash, #m.outChunks)
  emit("changed", m)
  Duel.tryDecide(m)
end

------------------------------------------------------------------------------------------------
-- Incoming match messages
------------------------------------------------------------------------------------------------
local function matchFor(msg, sender)
  local m = Duel.current
  if not m or m.mid ~= msg.mid or not ns.Comm.same(m.rival, sender) then return nil end
  m.lastHeard = now()
  m.silentWarned = false
  return m
end

local HANDLERS = {}

HANDLERS.ACC = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or m.state ~= "inviting" then return end
  m.nonceB = msg.nonce
  m.seed = P.seed(m.mid, m.nonceA, m.nonceB)
  m.state = "lobby"
  m.lobbyAt = now()
  emit("changed", m)
end

HANDLERS.DEC = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or (m.state ~= "inviting" and m.state ~= "lobby" and m.state ~= "invited") then return end
  m.state = "cancelled"
  m.endReason = "rival_" .. msg.reason
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
  if not m.myReady then return end -- can't happen with a well-behaved host; ignore
  Duel.go(m)
end

HANDLERS.PNG = function(msg, sender) matchFor(msg, sender) end

HANDLERS.SC = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m then return end
  -- the host already plays, so its GO got lost: start now
  if m.state == "lobby" and m.role == "guest" and m.myReady then Duel.go(m) end
  if m.state ~= "playing" and m.state ~= "waiting" then return end
  local r = m.rival_
  if r.tick and msg.tick < r.tick then return end -- old / duplicated / reordered
  r.tick, r.score, r.lines, r.over = msg.tick, msg.score, msg.lines, msg.over
  emit("score", m)
end

HANDLERS.END = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or (m.state ~= "playing" and m.state ~= "waiting") or m.rivalEnd then return end
  m.rivalEnd = { ticks = msg.ticks, score = msg.score, lines = msg.lines, level = msg.level, hash = msg.hash, chunks = msg.chunks, at = now() }
  local r = m.rival_
  r.score, r.lines, r.over, r.tick = msg.score, msg.lines, true, msg.ticks
  emit("score", m)
  Duel.tryDecide(m)
end

HANDLERS.LOG = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or not m.rivalEnd or m.state == "done" then return end
  if msg.n ~= m.rivalEnd.chunks then return end
  m.chunks[msg.i] = msg.payload -- duplicates simply overwrite
  Duel.tryDecide(m)
end

HANDLERS.RQ = function(msg, sender)
  local m = matchFor(msg, sender)
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

function Duel.init()
  ns.Comm.tick = Duel.update
  ns.Comm.on("HEL", onHello)
  ns.Comm.on("HI", onHi)
  ns.Comm.on("INV", onInvite)
  for kind, fn in pairs(HANDLERS) do ns.Comm.on(kind, fn) end
end

------------------------------------------------------------------------------------------------
-- Deciding the result
------------------------------------------------------------------------------------------------
local function haveAllChunks(m)
  local n = m.rivalEnd and m.rivalEnd.chunks or 0
  for i = 1, n do if not m.chunks[i] then return false end end
  return m.rivalEnd ~= nil
end

function Duel.tryDecide(m)
  if m.state ~= "waiting" and m.state ~= "playing" then return end
  if m.state == "playing" then return end -- my own run must be over first
  if m.rivalForfeit or m.rivalGone then return Duel.finish(m, m.rivalForfeit and "rival_forfeited" or "rival_disconnected") end
  if not m.rivalEnd then return end
  if not haveAllChunks(m) then return end
  -- replay the rival's log with the shared seed
  local packed = table.concat(m.chunks, "", 1, m.rivalEnd.chunks)
  local log = P.unpackLog(packed)
  if not log then
    m.check = { ok = false, reasons = { "malformed_log" } }
  else
    m.check = V.verify(log, m.seed, m.rivalEnd.ticks, {
      seed = m.seed, capTicks = m.ruleset.limitTicks,
      claimed = { score = m.rivalEnd.score, lines = m.rivalEnd.lines, hash = m.rivalEnd.hash },
    })
  end
  Duel.finish(m, m.check.ok and "checked" or "check_failed")
end

--- Final result. reason: checked | check_failed | unchecked | rival_forfeited | rival_disconnected
---                       | rival_offline | you_forfeited | timeout
function Duel.finish(m, reason)
  if m.state == "done" then return end
  local prev = m.state
  m.state = "done"
  m.endReason = reason
  m.doneAt = now()
  local my = m.my and m.my.score or (ns.App.session and ns.App.session.state.score) or 0
  local their = m.rivalEnd and m.rivalEnd.score or (m.rival_.score or 0)
  if reason == "check_failed" then
    m.outcome = "void"
  elseif reason == "you_forfeited" then
    m.outcome = "loss"
  elseif reason == "rival_forfeited" or reason == "rival_disconnected" or reason == "rival_offline" or reason == "timeout" then
    m.outcome = "win"
  elseif my > their then m.outcome = "win"
  elseif my < their then m.outcome = "loss"
  else m.outcome = "draw" end
  m.myScore, m.theirScore = my, their
  if prev == "playing" and ns.App.session and ns.App.session.duel == m and ns.App.session:isActive() then
    ns.App.session:finish(reason == "you_forfeited" and "forfeit" or "rival_left")
  end
  if ns.DB and ns.db then ns.DB.recordDuel(ns.db, m, ns.App:Today()) end
  emit("result", m)
  emit("changed", m)
end

------------------------------------------------------------------------------------------------
-- Timers (called every frame by the transport frame, also while our window is hidden)
------------------------------------------------------------------------------------------------
function Duel.update()
  local m = Duel.current
  if not m or m.state == "cancelled" then return end
  local t = now()
  if m.state == "done" then
    -- linger: keep answering a rival who may still miss our END or log chunks
    if m.my and t - m.doneAt < Duel.LINGER and t - m.lastSent >= Duel.RESEND and not m.myForfeit then
      m.lastSent = t
      send(m, "END", m.mid, P.b36(m.my.ticks), P.b36(m.my.score), P.b36(m.my.lines), P.b36(m.my.level), m.my.hash, #m.outChunks)
    end
    return
  end
  if m.state == "inviting" and t - m.createdAt > Duel.INVITE_TIMEOUT + 5 then
    m.state = "cancelled"; m.endReason = "no_answer"; emit("changed", m); return
  end
  if m.state == "invited" and t - m.createdAt > Duel.INVITE_TIMEOUT then
    Duel.decline("timeout"); return
  end
  if m.state == "lobby" and t - (m.lobbyAt or t) > Duel.LOBBY_TIMEOUT then
    send(m, "DEC", m.mid, "timeout")
    m.state = "cancelled"; m.endReason = "lobby_timeout"; emit("changed", m); return
  end
  -- what the rival needs from us right now (re-sent, so a lost message never stalls a duel)
  local every = (m.state == "playing") and Duel.SCORE_EVERY or Duel.RESEND
  if t - m.lastSent >= every and m.state ~= "invited" then
    m.lastSent = t
    local s = ns.App.session
    if m.state == "inviting" then
      send(m, "INV", m.mid, m.rulesetId, E.ENGINE_VERSION, m.nonceA)
    elseif m.state == "lobby" then
      if m.role == "guest" then send(m, "ACC", m.mid, m.nonceB) end
      if m.myReady then send(m, "RDY", m.mid) elseif m.role == "host" then send(m, "PNG", m.mid) end
    elseif m.state == "playing" and s and s.duel == m then
      send(m, "SC", m.mid, P.b36(s.state.tick), P.b36(s.state.score), P.b36(s.state.lines), 0)
      if m.role == "host" and t - m.goAt < 10 then send(m, "GO", m.mid) end
    elseif m.state == "waiting" and m.my then
      send(m, "END", m.mid, P.b36(m.my.ticks), P.b36(m.my.score), P.b36(m.my.lines), P.b36(m.my.level), m.my.hash, #m.outChunks)
      -- ask again for log chunks that didn't arrive
      if m.rivalEnd and t - m.rivalEnd.at > 3 then
        local asked = 0
        for i = 1, m.rivalEnd.chunks do
          if not m.chunks[i] and asked < 3 then send(m, "RQ", m.mid, i); asked = asked + 1 end
        end
      end
    else
      send(m, "PNG", m.mid)
    end
  end
  -- stream my log after END
  if m.outChunks and m.outNext <= #m.outChunks and t - (m.lastChunkAt or 0) >= Duel.LOG_SEND_GAP then
    m.lastChunkAt = t
    send(m, "LOG", m.mid, m.outNext, #m.outChunks, m.outChunks[m.outNext])
    m.outNext = m.outNext + 1
  end
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
  -- rival's log never fully arrived: decide on the claimed score, marked unchecked
  if m.state == "waiting" and m.rivalEnd and not haveAllChunks(m) and t - m.rivalEnd.at > Duel.LOG_WAIT then
    Duel.finish(m, "unchecked")
  end
  -- hard deadline: an unfinished rival loses
  if m.state == "waiting" and m.deadline and t > m.deadline and not m.rivalEnd then
    Duel.finish(m, "timeout")
  end
end

--- Rematch the same rival with the same rules.
function Duel.rematch()
  local m = Duel.current
  if not m or m.state ~= "done" then return false end
  return Duel.challenge(m.rival, m.rulesetId)
end

function Duel.clear()
  local m = Duel.current
  if m and (m.state == "done" or m.state == "cancelled") then
    ns.Comm.purge(m.mid)
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
