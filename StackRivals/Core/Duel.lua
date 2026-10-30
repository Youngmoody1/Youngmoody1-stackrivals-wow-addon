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
    FIN  <----------------------------> FIN                      "I have your result": stop re-sending

  Spell Battle (ruleset s180, 0.5+): RDY / GO also carry the player's 4 spells (locked at Ready).
  A spell cast on the rival is sent at once (SP, repeated twice) and lands on their board 90 ticks
  later on their clock, as on the web. The result is the web's verification: both players replay
  BOTH logs in lockstep (Spells.verifyMatch), so both PCs get the same boards and the same scores
  even if a spell arrived late in the live view.

  Commit-reveal: neither player can choose or grind the seed, and the guest only learns it at GO.

  A successful SendAddonMessage only means "queued", never "delivered" (warcraft.wiki.gg), so
  nothing here trusts a send: state messages repeat until the rival's next state shows they
  arrived, results repeat until FIN, and a declined/cancelled match keeps answering with DEC.
  Everything goes through ns.Comm (whispers, throttled, keyed so repeats replace each other).
  No board state is ever sent. Robust to lost / duplicated / reordered messages: every state
  re-sends what the rival needs, all handlers are idempotent, log chunks that arrive early are
  kept, and missing chunks are requested again (RQ) - also while I'm still playing.
  After the result we keep serving our END and log for LINGER seconds, even if the player
  already went back to the menu (Duel.past), so the rival can still check our run.

  Results. Every result has a BASIS (what it rests on); only "replay" is a played-out result
  (docs/SPELL_BATTLE.md "Result classes" has the evidence each one needs):
    reason               outcome                                        basis
    checked              rival's log replayed -> compare scores          replay
    check_failed         rival's log/clock failed my checks -> I win     rejected
    rival_forfeited      rival left during play -> I win                 forfeit
    rival_pause_limit    rival paused > 60 s (seen here) -> I win        forfeit
    rival_no_log         rival's log never came although they still talked to me, or their own
                         claim was lower than my score -> I win          forfeit
    you_forfeited / you_pause_limit -> loss (both forfeited: draw)       forfeit
    rival_disconnected / rival_offline / timeout -> I win                timeout
    unchecked            rival's log never came, rival silent -> void    void
    you_left             I left after my run, before the result -> void  void
  After the result both PCs exchange verdicts (VER): the same outcome (and, when both replayed,
  the same two scores) -> "agreed"; anything else -> "disputed" (not counted).
  A pause in a duel (combat, chat, ...) pauses BOTH runs; see PAUSE_BUDGET below.
]]
local _, ns = ...
local P, E, V, S = ns.Protocol, ns.Engine, ns.Verify, ns.Spells

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
Duel.OFFLINE_GRACE = 6        -- s of silence needed before an "offline" report ends a match
Duel.CLOCK_MARGIN = 10        -- s: a final result can't arrive faster than the game takes to play
Duel.REPLY_GAP = 10           -- s between unsolicited replies (HI, "busy") to the same player
Duel.CLOSED_KEEP = 300        -- s we remember a declined/cancelled match to answer late messages
Duel.closed = {}              -- mid -> { rival, reason, at }

--- Why a challenge can't be sent (shown in chat and on the duel sheet).
Duel.WHY_NOT = {
  trial = "Trial and Veteran accounts can't send addon messages (Blizzard rule)",
  busy = "you are already in a duel", combat = "you are in combat", self = "that's you",
  unavailable = "addon messages are unavailable on this client", ruleset = "unknown rules",
  old = "they need StackRivals 0.5 or newer for Spell Battle",
  deciding = "your last duel's result is still being decided",
}
--- What each result rests on (see the header). Only "replay" is a played-out, checked result.
Duel.BASIS = {
  checked = "replay", check_failed = "rejected",
  rival_forfeited = "forfeit", rival_pause_limit = "forfeit", rival_no_log = "forfeit",
  you_forfeited = "forfeit", you_pause_limit = "forfeit",
  rival_disconnected = "timeout", rival_offline = "timeout", timeout = "timeout",
  unchecked = "void", you_left = "void",
}
Duel.SP_REPEAT = { 1.0, 3.0 } -- s after a cast: send the SP again (lost messages; the rival ignores repeats)
-- Pauses in a duel (0.5+): a pause (combat, chat, ...) pauses BOTH runs; both resume together.
-- Each player may pause for PAUSE_BUDGET seconds in total per duel; past that the duel is forfeited
-- (a "no result" would let a losing player escape by pulling a mob). The rival's clock is checked
-- too: a run that took longer than its ticks + the allowed pauses is rejected (a client that pauses
-- without telling).
Duel.PAUSE_BUDGET = 60
Duel.PAUSE_MIN_CHARGE = 3     -- s: every pause costs at least this (no free micro-pauses to break the rival's rhythm)
Duel.PAUSE_EPISODE_COST = 4   -- s per pause: the resume countdown and message delays
Duel.RIVAL_PAUSE_MARGIN = 10  -- s over the budget (as seen here) before I stop waiting for a paused rival
Duel.RESUME_ALLOW = 2.5       -- s per rival pause on top of its length: their 2 s resume countdown + jitter
-- Clock check: the rival's run may take its ticks + the pauses I SAW (theirs and mine) + this.
-- Duels step the game in real time even at low FPS (Session), so an honest run never needs more.
Duel.STALL_SLACK = 20         -- s: latency, start offset, frames longer than 1 s
Duel.VER_EVERY = 4            -- s between verdict messages after the result
Duel.VER_FOR = 30             -- s we keep sending our verdict / wait for theirs
Duel.LANDING_SLACK = 480      -- ticks (8 s): latency both ways + a lost first copy of a spell

local function now() return GetTime() end
local diag = function() end -- DuelDiag.poll once Duel.init ran
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
  elseif kind == "LOG" or kind == "RQ" or kind == "SP" then key = kind .. ":" .. m.mid .. ":" .. tostring((select(2, ...))) end
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

local function remember(m, reason)
  if not m or not m.mid then return end
  Duel.closed[m.mid] = { rival = m.rival, reason = reason, at = now() }
  local t = now()
  for mid, c in pairs(Duel.closed) do if t - c.at > Duel.CLOSED_KEEP then Duel.closed[mid] = nil end end
end

--- A message for a match we already declined or cancelled: our DEC may have been lost, say it again.
local function answerClosed(msg, sender)
  local c = msg.mid and Duel.closed[msg.mid]
  if c and now() - c.at > Duel.CLOSED_KEEP then Duel.closed[msg.mid] = nil; c = nil end
  if not c or not ns.Comm.same(c.rival, sender) then return false end
  if msg.kind ~= "DEC" and msg.kind ~= "BYE" and msg.kind ~= "FIN" then
    reply(sender, P.encode("DEC", msg.mid, c.reason))
  end
  return true
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
  if ns.Comm.trial then return false, "trial" end -- our messages would never leave the client
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
  if ns.Comm.trial then return end
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
  local m = {
    role = role, rival = rival, ruleset = P.RULESETS[ruleset], rulesetId = ruleset, mid = mid,
    state = "new", createdAt = now(), lastHeard = now(), lastSent = 0, lastRQ = 0,
    myReady = false, rivalReady = false, rival_ = {}, chunks = {},
  }
  return m
end

-- Diagnostics records start when a match becomes real (sent challenge / accepted invite), so a
-- stranger's invites can't push real duels out of the 5 saved records.
local function diagBegin(m) if ns.DuelDiag then ns.DuelDiag.begin(m) end end

local function pauseSolo()
  local s = session()
  if s and not s.duel and s:isActive() then ns.App:Pause("manual") end
end

--- Challenge a player by full name ("Name-Realm" or "Name" on your realm).
function Duel.challenge(name, rulesetId)
  rulesetId = rulesetId or "b120"
  if not P.RULESETS[rulesetId] then return false, "ruleset" end
  -- a player we know runs an older addon can't play this ruleset (they would never see the invite)
  local minV = P.RULESET_MIN_VERSION[rulesetId]
  local known = minV and Duel.players[ns.Comm.fullName(name) or ""]
  if known and not P.versionAtLeast(known.addon, minV) then return false, "old" end
  if not ns.Comm.enabled then return false, "unavailable" end
  if ns.Comm.trial then return false, "trial" end
  if Duel.busy() then return false, (Duel.current and Duel.current.viewLeft) and "deciding" or "busy" end
  if inCombat() then return false, "combat" end
  local rival = ns.Comm.fullName(name)
  if not rival or ns.Comm.same(rival, ns.Comm.me()) then return false, "self" end
  Duel.retire(Duel.current)
  local m = newMatch("host", rival, rulesetId, P.token(6, rnd))
  m.nonceA = P.token(8, rnd)
  m.commitA = P.commit(m.mid, m.nonceA)
  m.state = "inviting"
  Duel.current = m
  diagBegin(m)
  pauseSolo()
  send(m, "INV", m.mid, rulesetId, E.ENGINE_VERSION, m.commitA)
  emit("changed", m)
  return true
end

local function onInvite(msg, sender)
  if answerClosed(msg, sender) then return end -- an invite we already declined, re-sent
  if ns.Comm.trial then
    if not Duel.trialNoted then Duel.trialNoted = true; emit("trial", sender) end
    return -- we can't answer at all: Trial/Veteran accounts can't send addon messages
  end
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
  diagBegin(m)
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
  remember(m, reason or "no")
  m.state = "cancelled"
  m.endReason = (reason == "timeout") and "timeout" or (reason == "cancel") and "you_cancelled" or "you_declined"
  if wasInvite then
    -- an unanswered invite never took over the screen: just forget it (the DEC stays queued)
    if ns.DuelDiag then ns.DuelDiag.poll(m) end
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
  m.myReadyAt = now() -- the host can't start before this (it needs our RDY): safe clock reference
  if m.ruleset.spell then
    m.myLoadout = (ns.db and ns.db.spell and S.decodeLoadout(ns.db.spell.loadout)) and ns.db.spell.loadout or S.encodeLoadout(S.DEFAULT_LOADOUT)
  end
  send(m, "RDY", m.mid, m.myLoadout)
  if m.role == "host" and m.rivalReady then Duel.go(m) end
  emit("changed", m)
  return true
end

local function seedFor(m) return P.seed(m.mid, m.nonceA, m.nonceB) end

function Duel.go(m)
  if m.ruleset.spell and not m.rivalLoadout then return end -- wait for their spells (RDY / GO repeat)
  m.seed = seedFor(m)
  -- a 0.5+ rival (shared pauses, clock check): Spell Battle needs 0.5, or their HI said so
  local known = Duel.players[m.rival]
  m.rival05 = m.rival05 or m.ruleset.spell or (known ~= nil and P.versionAtLeast(known.addon, "0.5.0"))
  if m.role == "host" then send(m, "GO", m.mid, m.nonceA, m.myLoadout) end
  m.state = "playing"
  m.goAt = now()
  m.deadline = m.goAt + m.ruleset.limitTicks / 60 + m.ruleset.countdownTicks / 60 + Duel.AFTER_TIME
  ns.App:StartDuel(m)
  emit("changed", m)
end

--- Leave the match. Before the start this is a cancel, during play a forfeit, after my own
--- run ended it only means "I'm not waiting for the result" (my result still reaches the rival).
function Duel.leave(why)
  local m = Duel.current
  if not m then return end
  if m.state == "invited" or m.state == "inviting" or m.state == "lobby" then return Duel.decline("cancel") end
  if m.state == "playing" then
    send(m, "BYE", m.mid, "forfeit")
    m.myForfeit = true
    Duel.finish(m, (why == "you_pause_limit") and why or "you_forfeited")
  elseif m.state == "waiting" and why == "logout" then
    -- /reload or logout after my run: this PC can't follow the result any more. My END and log
    -- (already streamed) still decide it on the rival's PC; I send no verdict, so theirs stands
    -- ("unconfirmed") instead of becoming "disputed".
    send(m, "BYE", m.mid, "left")
    m.noVerdict = true
    Duel.finish(m, "you_left")
  elseif m.state == "waiting" and not m.viewLeft then
    -- "Leave duel" after my run: back to the menu, but the duel is still decided here in the
    -- background (my log keeps streaming, the rival's is replayed): leaving never voids a result
    m.viewLeft = true
    local s = session()
    if s and s.duel == m then ns.App.session = nil end
    emit("changed", m)
    if ns.App and ns.App.ShowMenu then ns.App:ShowMenu() end
  end
end

local function sendEnd(m)
  send(m, "END", m.mid, P.b36(m.my.ticks), P.b36(m.my.score), P.b36(m.my.lines), P.b36(m.my.level), m.my.hash, #m.outChunks)
end

--- Spell Battle: a spell I cast on the rival (from the live session). Sent now and repeated.
function Duel.sendCast(m, inc)
  if not m or m.state ~= "playing" then return end
  m.castSeq = (m.castSeq or 0) + 1
  local c = { seq = m.castSeq, tick = inc.castTick, idx = S.INDEX[inc.spell], at = now(), n = 0 }
  -- where the rival's clock is at most now (from their last score heartbeat, as if they never
  -- paused): an honest client lands this spell within seconds of that, never much later
  local r = m.rival_
  if r.tick and r.tickAt then c.rivalTick = r.tick + math.floor((now() - r.tickAt) * 60) end
  m.outCasts = m.outCasts or {}
  m.outCasts[#m.outCasts + 1] = c
  send(m, "SP", m.mid, c.seq, P.b36(c.tick), c.idx)
end

--- Called by the app when my run in this duel is over (top-out or time).
--- `log` = the run's full log (Spell Battle: moves + casts); default: the engine's move log.
function Duel.onLocalEnd(state, log, landings)
  local m = Duel.current
  if not m or m.state ~= "playing" then return end
  m.my = { score = state.score, lines = state.lines, level = state.level, ticks = state.tick, hash = E.hashState(state), over = state.gameOver }
  m.myLog = log or state.inputLog
  m.myLandings = landings
  m.myEndAt = now()
  m.outChunks = P.chunk(m.ruleset.spell and P.packSpellLog(m.myLog, landings or {}) or P.packLog(m.myLog))
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
  if not m or m.mid ~= msg.mid or not ns.Comm.same(m.rival, sender) then
    -- a finished match I still serve: the rival is alive (we may be waiting for their verdict)
    local p = Duel.past
    if p and p.mid == msg.mid and ns.Comm.same(p.rival, sender) then p.lastHeard = now() end
    answerClosed(msg, sender)
    return nil
  end
  if m.state == "cancelled" then
    -- the rival still talks about a match we ended: they missed our DEC (DEC/BYE pass through)
    if msg.kind ~= "DEC" and msg.kind ~= "BYE" and msg.kind ~= "FIN" and Duel.closed[m.mid] then
      answerClosed(msg, sender); return nil
    end
  end
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

--- The rival's pause as I see it: from their first PSE to their RSM (or a score heartbeat that
--- shows their clock moving again). Measured on my clock, for the clock check and their budget.
--- The rival's pauses as my PC sees them, on my clock:
---   rivalPausedSeen  the total length;
---   rivalCharged     their budget use: every pause costs at least PAUSE_MIN_CHARGE, like on their
---                    own PC, so fake micro-pauses can't buy clock allowance for free;
---   rivalAllow       what the clock check allows for them: length + RESUME_ALLOW, at least the min.
local function rivalChargedNow(m, t)
  local open = m.rivalPauseFrom and math.max(0, (t - m.rivalPauseFrom) - Duel.PAUSE_MIN_CHARGE) or 0
  return (m.rivalCharged or 0) + open
end
local function closeRivalPause(m, t)
  if m.rivalPauseFrom then
    local dur = math.max(0, t - m.rivalPauseFrom)
    m.rivalPausedSeen = (m.rivalPausedSeen or 0) + dur
    m.rivalCharged = (m.rivalCharged or 0) + math.max(0, dur - Duel.PAUSE_MIN_CHARGE)
    m.rivalAllow = (m.rivalAllow or 0) + math.max(dur + Duel.RESUME_ALLOW, Duel.PAUSE_MIN_CHARGE)
    m.rivalPauseFrom = nil
  end
  m.rivalPaused = false
end
--- The rival is ready again: if I'm only waiting for them, my run goes on too.
local function rivalResumed(m)
  closeRivalPause(m, now())
  local s = session()
  if m.state == "playing" and s and s.duel == m and s.phase == "paused" and s.pauseReason == "rival" then ns.App:Resume() end
  emit("changed", m)
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
  local m = Duel.current
  if not m or m.mid ~= msg.mid or not ns.Comm.same(m.rival, sender) then return end
  local s = session()
  -- lobby race / lost GO: the guest gave up before it ever played (we never got a score from it),
  -- so nobody wins
  local earlyStart = m.state == "playing" and m.role == "host" and m.rival_.tick == nil
  -- an ignored DEC is not a sign of life: it must not keep a dead duel open
  if not (m.state == "inviting" or m.state == "lobby" or m.state == "invited" or earlyStart) then return end
  heard(m)
  m.state = "cancelled"
  m.endReason = "rival_" .. msg.reason
  if earlyStart and s and s.duel == m then ns.App.session = nil end
  emit("changed", m)
end

HANDLERS.RDY = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or m.state ~= "lobby" then return end
  if m.ruleset.spell then
    if not msg.loadout then return end -- a Spell Battle Ready must name the spells
    m.rivalLoadout = m.rivalLoadout or msg.loadout -- locked: the first one counts
  end
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
    m.state = "cancelled"; m.endReason = "rival_bad_seed"; remember(m, "cancel")
    emit("changed", m)
    return
  end
  m.nonceA = msg.nonce
  if m.ruleset.spell then
    if not (m.rivalLoadout or msg.loadout) then return end -- GO repeats with the loadout
    m.rivalLoadout = m.rivalLoadout or msg.loadout
  end
  if not m.myReady then return end -- can't happen with a well-behaved host; ignore
  Duel.go(m)
end

HANDLERS.PNG = function(msg, sender) matchFor(msg, sender) end

--- The rival paused (combat, chat, ...): my run pauses too, so nobody plays on alone. Their pause
--- is measured even after my own run ended (it still makes their run take longer).
HANDLERS.PSE = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m then return end
  m.rival05 = true
  if (m.state ~= "playing" and m.state ~= "waiting") or m.rivalEnd or m.rivalPauseLimit then return end
  if msg.n <= (m.rivalRsmN or 0) then return end -- an old pause (repeats / reordered after their RSM)
  if m.rivalPauseN ~= msg.n then
    local t = now()
    closeRivalPause(m, t) -- a pause still open (its RSM lost) ends where the new one starts
    m.rivalPauses = (m.rivalPauses or 0) + 1
    m.rivalPauseN = msg.n
    m.rivalCharged = (m.rivalCharged or 0) + Duel.PAUSE_MIN_CHARGE
    -- when did their clock stop? From their pause tick and their last score heartbeat: a PSE sent
    -- only after a loading screen still counts the whole pause
    local from, r = t, m.rival_
    -- the newest heartbeat from before the pause (one sent after it may overtake the PSE)
    local rt, ra = r.tick, r.tickAt
    if msg.tick and rt and msg.tick < rt then rt, ra = r.prevTick, r.prevAt end
    if msg.tick and rt and ra and msg.tick >= rt then
      from = math.max(ra, math.min(t, ra + (msg.tick - rt) / 60))
    end
    m.rivalPauseFrom = from
    m.rivalPauseTick = msg.tick -- their clock stands here until they resume
  end
  m.rivalPaused, m.rivalPauseReason = true, msg.reason
  local s = session()
  -- "frozen": their client hung for a while (already over; RSM follows): measured, nothing to wait for
  if msg.reason ~= "frozen" and m.state == "playing" and s and s.duel == m and s:isActive() then ns.App:Pause("rival") end
  emit("changed", m)
end

--- The rival is ready again: if I'm only waiting for them, we both go on.
HANDLERS.RSM = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m then return end
  m.rival05 = true
  m.rivalRsmN = math.max(m.rivalRsmN or 0, msg.n)
  if msg.n < (m.rivalPauseN or 0) or not m.rivalPaused then return end -- they paused again since / repeat
  rivalResumed(m)
end

--- The rival's final verdict: both PCs must agree, or the result is "disputed" (not counted).
HANDLERS.VER = function(msg, sender)
  local m = servedMatch(msg, sender)
  if not m then return end
  m.rival05 = true
  m.rivalVer = { verdict = msg.verdict, mine = msg.mine, yours = msg.yours, basis = msg.basis or "replay", check = msg.check, ack = msg.ack }
  if m.state == "done" then Duel.confirm(m) end
  -- they don't have my verdict yet: answer at once (with "I have yours")
  local t = now()
  if not msg.ack and m.verOut and m.state == "done" and t - (m.verSentAt or -99) >= 1 then
    m.verSentAt, m.verSends = t, (m.verSends or 0) + 1
    send(m, "VER", m.mid, m.verOut[1], m.verOut[2], m.verOut[3], m.verOut[4], 1)
  end
end

--- A rival spell. Checked against what can be known live: a Spell Battle, their announced
--- loadout, an opponent spell (decode), at most one cast per cooldown, within the time cap.
--- Mana can't be checked live (it depends on their board): the final replay checks everything.
HANDLERS.SP = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or not m.ruleset.spell or (m.state ~= "playing" and m.state ~= "waiting") then return end
  m.inCasts = m.inCasts or {}
  if m.inCasts[msg.seq] then return end -- a repeat
  local reject
  local lo = S.decodeLoadout(m.rivalLoadout or "")
  local inLo = false
  for _, x in ipairs(lo or {}) do if x == msg.spell then inLo = true end end
  if not inLo then reject = "not_in_loadout" end
  if msg.tick > m.ruleset.limitTicks then reject = "after_cap" end
  for _, c in pairs(m.inCasts) do
    if c.ok and math.abs(c.tick - msg.tick) < S.CAST_COOLDOWN_TICKS then reject = "cooldown" end
  end
  m.inCasts[msg.seq] = { tick = msg.tick, spell = msg.spell, ok = not reject, reason = reject }
  if reject then m.spRejected = (m.spRejected or 0) + 1; return end
  local s = session()
  if s and s.duel == m and s.spell and m.state == "playing" then ns.SpellBattle.incoming(s, msg.tick, msg.spell) end
  emit("cast", m, msg.spell)
end

HANDLERS.SC = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or (m.state ~= "playing" and m.state ~= "waiting") then return end
  local r = m.rival_
  if r.tick and msg.tick < r.tick then return end -- old / duplicated / reordered
  r.prevTick, r.prevAt = r.tick, r.tickAt
  r.tick, r.score, r.lines, r.over = msg.tick, msg.score, msg.lines, msg.over
  r.tickAt = now()
  -- their clock moved past the tick they paused at: they resumed (all copies of RSM may be lost)
  if m.rivalPaused and m.rivalPauseTick and msg.tick > m.rivalPauseTick then
    m.rivalRsmN = math.max(m.rivalRsmN or 0, m.rivalPauseN or 0)
    rivalResumed(m)
  end
  emit("score", m)
end

local function sendFin(m)
  m.finSentAt = now()
  send(m, "FIN", m.mid)
end

HANDLERS.END = function(msg, sender)
  local m = servedMatch(msg, sender)
  if not m then return end
  -- already have it (their END is being re-sent): our FIN got lost, acknowledge again
  if m.rivalEnd and m.haveAll and now() - (m.finSentAt or 0) >= 2 then return sendFin(m) end
  if (m.state ~= "playing" and m.state ~= "waiting") or m.rivalEnd then return end
  local t = now()
  m.rivalEnd = { ticks = msg.ticks, score = msg.score, lines = msg.lines, level = msg.level, hash = msg.hash, chunks = msg.chunks, at = t }
  -- a result can't arrive before the game could have been played (web: faster_than_clock)
  -- Reference = the earliest moment the rival can have started: for the host, when it sent GO
  -- (the guest starts after receiving it); for the guest, when it sent RDY (the host needs that RDY
  -- before it can start). Never GO's arrival: a late GO would make an honest host look too fast.
  local ref = (m.role == "guest") and (m.myReadyAt or m.goAt) or m.goAt
  local earliest = (ref or t) + (m.ruleset.countdownTicks + msg.ticks) / 60 - Duel.CLOCK_MARGIN
  if t < earliest then m.tooFast = true end
  -- ...nor much later than its ticks plus the pauses the duel allows (a client that pauses without
  -- telling, or ignores the pause limit). Only for 0.5 rivals: 0.4 has no pause limit.
  -- Allowed: the pauses I saw (theirs, from PSE to RSM, + their resume countdown; mine, which they
  -- had to wait for, + 4 s each), my own frozen frames after my run, and STALL_SLACK. A silent
  -- pause or a slowed-down game (easier to play) shows up here.
  if m.rival05 and m.goAt then
    closeRivalPause(m, t) -- their run is over
    local stall = (t - m.goAt) - (m.ruleset.countdownTicks + msg.ticks) / 60
    local allowed = (m.rivalAllow or 0) + (m.myPausedTotal or 0) + (m.myFrozen or 0)
      + Duel.PAUSE_EPISODE_COST * (m.myPauses or 0) + Duel.STALL_SLACK
    m.stall = { stall = math.floor(stall), allowed = math.floor(allowed) }
    if stall > allowed then m.tooSlow = math.floor(stall) end
  end
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

HANDLERS.FIN = function(msg, sender)
  local m = servedMatch(msg, sender)
  if not m then return end
  m.rivalHasMine = true -- stop re-sending END and log chunks (Duel.past stays to re-ack their END)
end

HANDLERS.BYE = function(msg, sender)
  local m = matchFor(msg, sender)
  if not m or m.state == "done" or m.state == "cancelled" then return end
  m.rivalForfeit = msg.reason
  if m.state == "playing" then
    Duel.releaseRivalPause(m)
    emit("changed", m) -- keep playing; the result is decided when my run ends
  else
    Duel.tryDecide(m)
  end
end

local function onOffline(lname)
  for _, m in ipairs({ Duel.current or false, Duel.past or false }) do
    if m and m.rival:lower() == lname then m.rivalOffline = true end
  end
end

-- An invite we can't decode (other protocol version): answer in THE INVITER'S version, so they
-- see "different version" instead of waiting for nothing. "<v>:DEC:<mid>:<reason>" is a frame
-- every protocol version must keep (docs/CROSS_PLATFORM_MULTIPLAYER.md).
local function onOtherVersion(text, sender)
  local v, mid = text:match("^(%d+):INV:([0-9a-z]+):")
  if v and #v <= 3 and #mid >= 4 and #mid <= 10 then reply(sender, v .. ":DEC:" .. mid .. ":version") end
end

function Duel.init()
  ns.Comm.tick = Duel.update
  if ns.DuelDiag then
    ns.Comm.trace = ns.DuelDiag.trace
    diag = ns.DuelDiag.poll
  end
  ns.Comm.on("@version", onOtherVersion)
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

--- Spell Battle result: replay BOTH logs in lockstep (the web's verifySpellMatch), with each
--- player's own record of where the rival's spells landed on their board (the receiver is the
--- authority: a spell lands in the replay exactly when it landed live - lag, pauses and lost
--- messages can't make a replay differ from what a player saw). Both PCs replay the same two logs
--- and the same two landing lists, so they agree on every board and score.
--- The rival's result is rejected when (judged on my PC, about the rival only):
---   * their log is broken / foreign / over the cap / inhuman / faster than the clock, or uses a
---     loadout other than the one announced at Ready, or the replay refuses any of their casts or
---     inputs (with landings the replay is their live game, so an honest client never has those);
---   * a spell they sent me live is not a cast their replay allows (forged, unpaid, or not in the log);
---   * a landing they report doesn't match a cast of mine that my replay allows, is held back (more
---     than 8 s after their clock could have received it), lands before
---     castTick + 90, or the same cast lands twice;
---   * more than one of my allowed casts never landed on their board although I sent it at least 5 s
---     before their run ended (a client that "doesn't receive" spells). One is allowed: three copies
---     can all be lost.
function Duel.decideSpell(m, log, landings)
  local myLand = m.myLandings or {}
  local mine = { v = E.ENGINE_VERSION, seed = m.seed, startLevel = 1, ticks = m.my.ticks, log = m.myLog or {}, loadout = S.decodeLoadout(m.myLoadout or ""), landings = myLand }
  local theirs = { v = E.ENGINE_VERSION, seed = m.seed, startLevel = 1, ticks = m.rivalEnd.ticks, log = log, loadout = S.decodeLoadout(m.rivalLoadout or ""), landings = landings }
  local hostFirst = m.role == "host"
  local res = S.verifyMatch({ seed = m.seed, capTicks = m.ruleset.limitTicks, players = hostFirst and { mine, theirs } or { theirs, mine } })
  local me, them = res[hostFirst and 1 or 2], res[hostFirst and 2 or 1]
  local fraud = {}
  for _, r in ipairs(them.reasons) do fraud[#fraud + 1] = r end
  local function key(t, spell) return t .. ":" .. spell end
  -- casts each replay allowed (opponent spells only: those are the ones that cross)
  local function allowed(side)
    local out = {}
    if side then for _, c in ipairs(side.casts) do if S.INFO[c.spell].target == "opponent" then out[key(c.tick, c.spell)] = true end end end
    return out
  end
  local theirOk, myOk = allowed(them.side), allowed(me.side)
  -- spells they sent me live must be casts their replay allows
  for _, c in pairs(m.inCasts or {}) do
    if c.ok and not theirOk[key(c.tick, c.spell)] then fraud[#fraud + 1] = "forged_cast"; break end
  end
  -- their landings must match my allowed casts, once each, never early, and not held back: at most
  -- LANDING_SLACK ticks after where their clock could be when I sent it (latency + a lost first copy)
  local sentTick = {}
  for _, c in ipairs(m.outCasts or {}) do if c.rivalTick then sentTick[key(c.tick, S.SPELLS[c.idx + 1])] = c.rivalTick end end
  local used = {}
  for _, l in ipairs(landings) do
    local k = key(l.castTick, l.spell)
    if not myOk[k] or used[k] or l.tick < l.castTick + S.DELIVERY_TICKS then fraud[#fraud + 1] = "bad_landing"; break end
    local est = sentTick[k]
    if est and l.tick > math.max(l.castTick + S.DELIVERY_TICKS, est + Duel.LANDING_SLACK) then fraud[#fraud + 1] = "late_landing"; break end
    used[k] = true
  end
  -- my allowed casts that should have landed on them while they were still playing
  local missing = 0
  local theirEnd = them.side and them.side.game.tick or m.rivalEnd.ticks
  -- only casts I sent at least 5 s before their END arrived: they had time to get one of 3 copies
  -- (a cast sent after my own pause can reach them after their run ended: that's not on them)
  local sentAt = {}
  for _, c in ipairs(m.outCasts or {}) do sentAt[key(c.tick, S.SPELLS[c.idx + 1])] = c.at end
  local endAt = m.rivalEnd.at or now()
  for k in pairs(myOk) do
    local t = tonumber(k:match("^(%d+)"))
    if not used[k] and t + S.DELIVERY_TICKS < theirEnd and sentAt[k] and sentAt[k] < endAt - 5 then missing = missing + 1 end
  end
  if missing > 1 then fraud[#fraud + 1] = "spells_not_applied" end
  m.spell = {
    myLive = m.my.score, theirClaim = m.rivalEnd.score,
    my = me.score, their = them.score, diverged = me.hash ~= m.my.hash,
    late = (session() and session().duel == m and session().spell and session().spell.late) or 0,
    reasons = them.reasons, rejected = m.spRejected or 0, missing = missing,
  }
  -- the replay is the result (also for my own score)
  m.my.score, m.rivalEnd.score = me.score, them.score
  m.rival_.score = them.score
  return { ok = #fraud == 0, reasons = fraud, score = them.score }
end

function Duel.tryDecide(m)
  if m.state ~= "waiting" then return end -- my own run must be over first
  -- a complete log beats everything else: the rival finished, even if they left afterwards
  if haveAllChunks(m) then
    m.haveAll = true
    sendFin(m)
    local packed = table.concat(m.chunks, "", 1, m.rivalEnd.chunks)
    local log, landings
    if m.ruleset.spell then log, landings = P.unpackSpellLog(packed) else log = P.unpackLog(packed) end
    if not log then
      m.check = { ok = false, reasons = { "malformed_log" } }
    elseif m.tooFast then
      m.check = { ok = false, reasons = { "faster_than_clock" } }
    elseif m.tooSlow or m.rivalPauseLimit then
      m.check = { ok = false, reasons = { "pause_limit" } }
    elseif m.ruleset.spell then
      m.check = Duel.decideSpell(m, log, landings)
    else
      m.check = V.verify(log, m.seed, m.rivalEnd.ticks, {
        seed = m.seed, capTicks = m.ruleset.limitTicks,
        claimed = { score = m.rivalEnd.score, lines = m.rivalEnd.lines, hash = m.rivalEnd.hash },
      })
    end
    return Duel.finish(m, m.check.ok and "checked" or "check_failed")
  end
  if m.rivalForfeit == "forfeit" or m.rivalForfeit == "quit" then return Duel.finish(m, "rival_forfeited") end
  -- they stayed paused far past the budget (a client that ignores it): I stopped waiting
  if m.rivalPauseLimit and not m.rivalEnd then return Duel.finish(m, "rival_pause_limit") end
  -- "left" means their run had ended: their END/log may still be on its way (it can be overtaken
  -- by the BYE). update() waits LOG_WAIT for it and then gives "no result", never a win.
  if m.rivalForfeit == "left" and not m.rivalEnd then m.leftAt = m.leftAt or now(); return end
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
  m.basis = Duel.BASIS[reason] or "void"
  m.doneAt = now()
  local s = session()
  local mine = s and s.duel == m
  local my = m.my and m.my.score or (mine and s.state.score) or 0
  local their = m.rivalEnd and m.rivalEnd.score or (m.rival_.score or 0)
  if reason == "check_failed" or reason == "rival_forfeited" or reason == "rival_disconnected"
    or reason == "rival_offline" or reason == "timeout" or reason == "rival_no_log" or reason == "rival_pause_limit" then
    m.outcome = "win"
  elseif reason == "unchecked" or reason == "you_left" then
    m.outcome = "void"
  elseif reason == "you_forfeited" or reason == "you_pause_limit" then
    m.outcome = (m.rivalForfeit == "forfeit") and "draw" or "loss" -- both forfeited: draw (web rule)
  elseif my > their then m.outcome = "win"
  elseif my < their then m.outcome = "loss"
  else m.outcome = "draw" end
  m.myScore, m.theirScore = my, their
  if prev == "playing" and mine and s:isActive() then
    s:finish(reason == "you_forfeited" and "forfeit" or "rival_left")
  end
  if ns.DB and ns.db then m.historyRef = ns.DB.recordDuel(ns.db, m, ns.App:Today()) end
  -- my verdict, for the rival to confirm (0.5+); a 0.4 rival never answers: "unconfirmed"
  local code = ({ win = "w", loss = "l", draw = "d" })[m.outcome] or "v"
  m.verOut = (not m.noVerdict) and { code, P.b36(math.max(0, my)), P.b36(math.max(0, their)), P.VER_CODE[m.basis] or "v" } or nil
  -- a rival that never showed it is 0.5+ (no shared pauses, no clock check): said on the result
  m.noClock = (reason == "checked") and not m.rival05 or nil
  m.verSentAt, m.verSends = nil, 0
  if m.rivalVer then Duel.confirm(m) end
  emit("result", m)
  emit("changed", m)
end

--- Both verdicts in: the same outcome (mirrored) and, when BOTH rest on a replay of both games,
--- the same two scores; otherwise "disputed". A forfeit / timeout verdict carries live scores that
--- the other PC can't know exactly, so only the outcome is compared there.
--- A disputed duel is not counted as a win, loss or draw (DB.disputeDuel moves it).
local MIRROR = { win = "l", loss = "w", draw = "d", void = "v" }
function Duel.confirm(m)
  local r = m.rivalVer
  if not r or m.agreement == "agreed" or m.agreement == "disputed" then return end
  local same = MIRROR[m.outcome or "void"] == r.verdict
  if same and m.basis == "replay" and r.basis == "replay" then
    same = (r.mine == (m.theirScore or 0)) and (r.yours == (m.myScore or 0))
  end
  if same then
    m.agreement = "agreed"
  else
    m.agreement = "disputed"
    if ns.DB and ns.db then ns.DB.disputeDuel(ns.db, m) end
  end
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
  if m.rivalHasMine then return true end -- they have everything; stay around only to re-ack (FIN)
  streamLog(m, t)
  if t - m.lastSent >= Duel.RESEND then m.lastSent = t; sendEnd(m) end
  return true
end

-- After the result: send our verdict; "unconfirmed" if the rival's never comes. While the rival is
-- still playing (it still talks to us: I forfeited, or they were out of contact for a while) we wait
-- for their verdict until the duel's deadline, so both PCs end up agreed or disputed.
local function verWaiting(m, t)
  return t - m.doneAt < Duel.VER_FOR
    or (t - (m.lastHeard or 0) < Duel.SILENT_WARN and t < (m.deadline or 0) + Duel.VER_FOR)
end
-- Each VER says whether I already have theirs (ack). I re-send until theirs says it has mine; a VER
-- without the ack is answered at once (HANDLERS.VER), so both PCs get both verdicts.
local function verKeep(m, t)
  if not (m.verOut and m.doneAt) then return false end
  if m.rivalVer and m.rivalVer.ack then return t - m.doneAt < Duel.VER_FOR end -- stay to answer repeats
  return verWaiting(m, t)
end
local function verTick(m, t)
  if not m.verOut or not m.doneAt then return end
  if not verWaiting(m, t) then
    if not m.rivalVer and not m.agreement then m.agreement = "unconfirmed"; emit("changed", m) end
    return
  end
  if m.rivalVer and m.rivalVer.ack then return end -- they have mine
  local every = (t - m.doneAt < Duel.VER_FOR) and Duel.VER_EVERY or 10
  if t - (m.verSentAt or -99) >= every then
    m.verSentAt, m.verSends = t, m.verSends + 1
    send(m, "VER", m.mid, m.verOut[1], m.verOut[2], m.verOut[3], m.verOut[4], m.rivalVer and 1 or 0)
  end
end

-- My own pauses in a running duel: tell the rival (both runs pause), count against the budget,
-- and say "ready" (RSM) when I resume or am only waiting for the rival.
--- Stop waiting for the rival (they left, went silent or finished): my run goes on alone.
local function releaseRivalPause(m)
  closeRivalPause(m, now())
  local s = session()
  if s and s.duel == m and s.phase == "paused" and s.pauseReason == "rival" then
    s.pauseReason = "manual"
    if not inCombat() then ns.App:Resume() end
  end
end
Duel.releaseRivalPause = releaseRivalPause

local function pauseTick(m, t, dt)
  local s = session()
  if not (s and s.duel == m) then return end
  if m.rivalPaused and (m.rivalGone or m.rivalForfeit or m.rivalEnd) then releaseRivalPause(m) end
  -- the rival left or is gone: nobody waits for me, so my pauses cost nothing any more
  if m.rivalForfeit or m.rivalGone or m.rivalPauseLimit then
    if m.myPauseOpen then m.myPauseOpen = false end
    return
  end
  if s.phase == "paused" and s.pauseReason == "rival" and inCombat() then s.pauseReason = "combat" end -- now it's mine
  -- waiting for the rival after my own pause: keep saying "ready" (all 3 RSM copies can be lost,
  -- and with both clocks stopped no score heartbeat would show it)
  if s.phase == "paused" and s.pauseReason == "rival" and (m.pauseN or 0) > 0 and (m.rsmLeft or 0) == 0
    and t - (m.rsmAt or -99) >= Duel.SCORE_EVERY then
    m.rsmAt = t
    send(m, "RSM", m.mid, m.pauseN)
  end
  local own = s.phase == "paused" and s.pauseReason ~= "rival"
  if own then
    if not m.myPauseOpen then
      m.myPauseOpen = true
      m.pauseN = (m.pauseN or 0) + 1
      m.myPauses = (m.myPauses or 0) + 1
      m.pseAt = -99
      m.pauseTickAt = s.state.tick
      -- every pause costs at least PAUSE_MIN_CHARGE of the budget, charged now (shown at once)
      m.myPaused = (m.myPaused or 0) + Duel.PAUSE_MIN_CHARGE
      m.myPauseFree = Duel.PAUSE_MIN_CHARGE
    end
    local use = dt
    if (m.myPauseFree or 0) > 0 then
      local f = math.min(m.myPauseFree, dt)
      m.myPauseFree, use = m.myPauseFree - f, dt - f
    end
    m.myPaused = (m.myPaused or 0) + use              -- the budget
    m.myPausedTotal = (m.myPausedTotal or 0) + dt     -- real time (the rival waited this long)
    if t - m.pseAt >= Duel.SCORE_EVERY then
      m.pseAt = t
      local why = P.PAUSE_REASONS[s.pauseReason] and s.pauseReason or "manual"
      send(m, "PSE", m.mid, m.pauseN, why, P.b36(m.pauseTickAt))
    end
    if m.myPaused > Duel.PAUSE_BUDGET then
      Duel.leave("you_pause_limit") -- the pause limit: a forfeit, never a free "no result"
    end
  elseif m.myPauseOpen then
    m.myPauseOpen = false
    m.rsmLeft, m.rsmAt = 3, -99 -- I'm ready (resumed, or waiting only for the rival)
  end
  if m.rsmLeft and m.rsmLeft > 0 and t - m.rsmAt >= 1 then
    m.rsmLeft, m.rsmAt = m.rsmLeft - 1, t
    send(m, "RSM", m.mid, m.pauseN or 0)
  end
end

function Duel.update()
  local t = now()
  local dt = t - (Duel.lastT or t)
  Duel.lastT = t
  diag(Duel.current); diag(Duel.past)
  if Duel.past then verTick(Duel.past, t) end
  if Duel.past and not serveAfter(Duel.past, t) and not verKeep(Duel.past, t) then Duel.past = nil end
  local m = Duel.current
  if not m or m.state == "cancelled" then return end
  if m.state == "done" then serveAfter(m, t); verTick(m, t); return end
  -- my client hung (a long frame): during my run that is a pause the rival must know about (my
  -- clock lost dt - 1 s: Session catches up at most 1 s), announced as pause "frozen" + RSM;
  -- after my run it only delays my handling of their END (not their stall)
  if dt > 1.5 then
    local s = session()
    if m.state == "playing" and s and s.duel == m and s:isActive() and not (m.rivalForfeit or m.rivalGone) then
      local lost = dt - 1
      m.pauseN = (m.pauseN or 0) + 1
      m.myPauses = (m.myPauses or 0) + 1
      m.myPaused = (m.myPaused or 0) + math.max(lost, Duel.PAUSE_MIN_CHARGE)
      m.myPausedTotal = (m.myPausedTotal or 0) + lost
      -- the tick my clock stood at when the hang began (seen on the frame before it)
      send(m, "PSE", m.mid, m.pauseN, "frozen", P.b36(m.lastTickSeen or s.state.tick))
      m.rsmLeft, m.rsmAt = 3, -99
      if m.myPaused > Duel.PAUSE_BUDGET then Duel.leave("you_pause_limit") end
    elseif m.state == "waiting" then
      m.myFrozen = (m.myFrozen or 0) + dt
    end
  end
  if m.state == "playing" then
    pauseTick(m, t, dt)
    local s = session()
    if s and s.duel == m then m.lastTickSeen = s.state.tick end
  end
  -- a rival far past the budget (it should have forfeited itself; or fake micro-pauses that each
  -- cost the minimum): stop waiting for them
  if (m.state == "playing" or m.state == "waiting") and not m.rivalPauseLimit and not m.rivalEnd
    and rivalChargedNow(m, t) > Duel.PAUSE_BUDGET + Duel.RIVAL_PAUSE_MARGIN then
    m.rivalPauseLimit = true
    releaseRivalPause(m)
    emit("changed", m)
    Duel.tryDecide(m)
    if m.state ~= "playing" and m.state ~= "waiting" then return end
  end
  if m.state ~= "playing" and m.state ~= "waiting" and m.state ~= "lobby" and m.state ~= "inviting" and m.state ~= "invited" then return end

  -- the rival is offline (server said so): stop before the match, or decide during it
  -- (a short grace: one stray "player not found" line must not end a duel if the rival is still talking)
  if m.rivalOffline and not m.offlineSeen and t - m.lastHeard > Duel.OFFLINE_GRACE then
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
    m.state = "cancelled"; m.endReason = "no_answer"; remember(m, "timeout"); emit("changed", m); return
  end
  if m.state == "invited" and t - m.createdAt > Duel.INVITE_TIMEOUT then
    Duel.decline("timeout"); return
  end
  local lobbyLimit = Duel.LOBBY_TIMEOUT + (m.role == "guest" and Duel.GUEST_GRACE or 0)
  if m.state == "lobby" and t - (m.lobbyAt or t) > lobbyLimit then
    send(m, "DEC", m.mid, "timeout")
    m.state = "cancelled"; m.endReason = "lobby_timeout"; remember(m, "timeout"); emit("changed", m); return
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
      if m.myReady then send(m, "RDY", m.mid, m.myLoadout) elseif m.role == "host" then send(m, "PNG", m.mid) end
    elseif m.state == "playing" and s and s.duel == m then
      send(m, "SC", m.mid, P.b36(s.state.tick), P.b36(s.state.score), P.b36(s.state.lines), 0)
      -- "I'm 0.5+" (shared pauses, clock check): RSM #0 on the first heartbeats; 0.4 ignores it
      if (m.rsm0 or 0) < 3 then m.rsm0 = (m.rsm0 or 0) + 1; send(m, "RSM", m.mid, 0) end
      -- repeat GO until the guest's first score shows it started
      if m.role == "host" and m.rival_.tick == nil and t - m.goAt < 30 then send(m, "GO", m.mid, m.nonceA, m.myLoadout) end
    elseif m.state == "waiting" and m.my then
      if not m.rivalHasMine then sendEnd(m) else send(m, "PNG", m.mid) end
    else
      send(m, "PNG", m.mid)
    end
  end
  if m.state == "playing" or m.state == "waiting" then
    requestMissing(m, t, m.state == "playing" and 2 or 3)
  end
  -- Spell Battle: repeat each cast twice (lost whispers); the rival drops the repeats by seq
  if m.outCasts and (m.state == "playing" or m.state == "waiting") then
    for _, c in ipairs(m.outCasts) do
      local due = Duel.SP_REPEAT[c.n + 1]
      if due and t - c.at >= due then c.n = c.n + 1; send(m, "SP", m.mid, c.seq, P.b36(c.tick), c.idx) end
    end
  end
  if not m.rivalHasMine then streamLog(m, t) end
  -- silence
  local quiet = t - m.lastHeard
  if (m.state == "lobby" or m.state == "playing" or m.state == "waiting") then
    if quiet > Duel.SILENT_GONE and not m.rivalGone then
      m.rivalGone = true
      if m.state == "lobby" then
        m.state = "cancelled"; m.endReason = "rival_disconnected"; remember(m, "timeout"); emit("changed", m); return
      end
      emit("changed", m)
      Duel.tryDecide(m)
    elseif quiet > Duel.SILENT_WARN and not m.silentWarned then
      m.silentWarned = true
      emit("changed", m)
    end
  end
  if m.state ~= "waiting" then return end
  -- rival's log never fully arrived (asked for again every few seconds): never a checked result.
  --   * they still talk to me (heard within SILENT_WARN) but don't send it: withheld -> a forfeit
  --     (otherwise a loser could turn every loss into "no result" by keeping the log back);
  --   * their own claim is lower than my score: withholding can't turn their loss into "no result";
  --   * otherwise (silent: they most likely lost their connection right after their run): no result.
  -- A forfeit win is labelled as one (basis "forfeit", never "replay"), and their verdict (VER) can
  -- still make it "disputed".
  if m.rivalEnd and not haveAllChunks(m) and t - math.max(m.rivalEnd.at, m.myEndAt or 0) > Duel.LOG_WAIT then
    m.noLogTalking = t - m.lastHeard < Duel.SILENT_WARN
    if m.my and (m.rivalEnd.score < m.my.score or m.noLogTalking) then return Duel.finish(m, "rival_no_log") end
    return Duel.finish(m, "unchecked")
  end
  if m.leftAt and not m.rivalEnd and t - math.max(m.leftAt, m.myEndAt or 0) > Duel.LOG_WAIT then
    return Duel.finish(m, "unchecked") -- they finished and left, but their result never arrived
  end
  -- hard deadline: an unfinished rival loses
  if m.deadline and t > m.deadline and not m.rivalEnd then
    Duel.finish(m, "timeout")
  end
end

--- Keep serving a finished match in the background (its END / log may still be needed).
function Duel.retire(m)
  if not (m and m.state == "done") then return end
  local serving = m.my and not m.myForfeit and now() - m.doneAt < Duel.LINGER
  local confirming = verKeep(m, now())
  if serving or confirming then Duel.past = m end
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
