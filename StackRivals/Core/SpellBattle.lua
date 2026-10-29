--[[
  StackRivals - live Spell Battle (vs Bot here; guild duels reuse the same per-tick step).

  Mirrors the web's live loop (VersusGame.tsx) tick for tick, so a live game IS the lockstep
  simulation (Spells.Sim) of the player's log against the bot:
    1. opponent spells that are due land on your board,
    2. your moves, then your casts (only castable ones are logged, like the web),
    3. your gravity tick,
    4. the bot plays the same tick (incoming, its decisions, its gravity).
  The match ends when you top out, the time cap is reached, or the result can no longer change
  (the bot topped out and you are ahead: Spells.botMatchDecided). After you top out the bot plays
  on to the cap, like on the web: its final score decides. Nothing here touches WoW gameplay:
  these are StackRivals spells on StackRivals boards. Pure Lua (no WoW API).
]]
local _, ns = ...
ns = ns or {}
local E, S, Bot = ns.Engine, ns.Spells, ns.Bot

local SB = {}
ns.SpellBattle = SB

SB.CAP_TICKS = 10800 -- web DEFAULT_TIME_CAP_MS (3:00)
SB.FAST_FORWARD_PER_FRAME = 600 -- bot ticks per frame after you top out (spread, no hitch)

--- Set up the spell part of a session.
--- vs Bot: opts = { loadout, difficulty, createdAtMs }
--- Duel:   opts = { loadout, remote = { loadout = rival's loadout, send = fn(incoming) } }
---         (the rival plays on their own PC: their casts arrive as messages, ours are sent)
function SB.setup(sess, opts)
  local seed = sess.seed
  if opts.remote then
    sess.spell = {
      remote = opts.remote, rivalLoadout = opts.remote.loadout,
      me = S.createSide(seed, opts.loadout),
      pendingMe = {}, castQueue = {}, seenHitsMe = 0, seenOppCasts = 0,
      late = 0, -- rival spells that arrived after their landing tick (live view differs from the replay)
    }
    sess.state = sess.spell.me.game
    sess.capTicks = sess.mode.limitTicks or SB.CAP_TICKS
    return
  end
  local diff = opts.difficulty or "challenger"
  sess.spell = {
    difficulty = diff,
    createdAtMs = opts.createdAtMs,
    me = S.createSide(seed, opts.loadout),
    opp = S.createSide(seed, Bot.LOADOUTS[diff]),
    actor = Bot.SpellBot.new(seed, diff, opts.createdAtMs),
    pendingMe = {}, pendingOpp = {},
    castQueue = {},
    seenOppCasts = 0, seenHitsMe = 0, seenHitsOpp = 0,
    settling = false, -- you are done; the bot still plays to the cap
    result = nil,
  }
  sess.state = sess.spell.me.game
  sess.capTicks = SB.CAP_TICKS
end

--- Duel: a rival spell arrived (cast at `castTick` on the rival's clock). It lands on your board at
--- castTick + DELIVERY_TICKS on your clock - or now, if your clock is already past that (then the
--- live view differs from the replay, which always lands it exactly).
function SB.incoming(sess, castTick, spell)
  local sp = sess.spell
  if not sp or not sp.remote then return end
  local at = castTick + S.DELIVERY_TICKS
  if at < sp.me.game.tick then sp.late = sp.late + 1 end
  sp.pendingMe[#sp.pendingMe + 1] = { spell = spell, at = at, castTick = castTick }
  sess:emit("oppcast", spell)
end

local function takeDue(list, t)
  local due
  local i = 1
  while i <= #list do
    if list[i].at <= t then
      due = due or {}
      due[#due + 1] = table.remove(list, i)
    else
      i = i + 1
    end
  end
  return due
end

--- The bot (or a replayed opponent) plays its ticks up to `upTo` (exclusive), like advanceOpp.
local function advanceOpp(sess, upTo, budget)
  local sp = sess.spell
  local o, me = sp.opp, sp.me
  local cap = sess.capTicks
  local n = 0
  local function toMe(inc) sp.pendingMe[#sp.pendingMe + 1] = inc end
  while not o.game.gameOver and o.game.tick < math.min(upTo, cap) do
    if budget and n >= budget then return false end
    n = n + 1
    local t = o.game.tick
    local due = takeDue(sp.pendingOpp, t)
    if due then for _, inc in ipairs(due) do S.receive(o, inc) end end
    for _ = 1, 2 do
      if o.game.gameOver then break end
      local c = sp.actor:act(o, me)
      if c == nil then break end
      S.applyCode(o, c, toMe)
    end
    if not o.game.gameOver then S.stepSide(o) end
  end
  return true
end
SB.advanceOpp = advanceOpp

local function emitNew(sess)
  local sp = sess.spell
  local o = sp.opp
  if not o then
    local h = sp.me.hits[#sp.me.hits]
    local key = h and (h.tick * 100 + #sp.me.hits) or 0
    if key ~= sp.seenHitsMe then sp.seenHitsMe = key; if h then sess:emit("hit", "me", h) end end
    return
  end
  if #o.casts > sp.seenOppCasts then
    for i = sp.seenOppCasts + 1, #o.casts do sess:emit("oppcast", o.casts[i].spell) end
    sp.seenOppCasts = #o.casts
  end
  -- effects that landed (hits): yours (incoming + your own self spells) and the bot's board
  local function hits(side, seenKey, who)
    local h = side.hits[#side.hits]
    local key = h and (h.tick * 100 + #side.hits) or 0
    if key ~= sp[seenKey] then
      sp[seenKey] = key
      if h then sess:emit("hit", who, h) end
    end
  end
  hits(sp.me, "seenHitsMe", "me")
  hits(o, "seenHitsOpp", "opp")
end

--- Queue a cast from key slot 1..4 (applied on the next tick, like the web's cast queue).
function SB.cast(sess, slot)
  local sp = sess.spell
  if not sp or sess.phase ~= "playing" then return false end
  local spell = sp.me.loadout[slot]
  if not spell then return false end
  local okCast, reason = S.canCast(sp.me, spell)
  if not okCast then sess:emit("castfail", spell, reason); return false end
  sp.castQueue[#sp.castQueue + 1] = spell
  return true
end

--- One live tick (called by Session's fixed step while playing).
function SB.step(sess)
  local sp = sess.spell
  local me = sp.me
  local s = me.game
  local bLines, bLevel, bPieces = s.lines, s.level, s.piecesPlaced
  local due = takeDue(sp.pendingMe, s.tick)
  if due then for _, inc in ipairs(due) do S.receive(me, inc) end end
  s = me.game
  local function toOpp(inc)
    if sp.remote then sp.remote.send(inc) else sp.pendingOpp[#sp.pendingOpp + 1] = inc end
  end
  local actions = sess.input:drain()
  -- incoming garbage can top you out before your keys: then nothing more is logged this tick
  -- (the verification stops reading a log at the top-out; logging more = "inputs_after_topout")
  if s.gameOver then actions = {}; sp.castQueue = {} end
  for i = 1, #actions do
    local a = actions[i]
    local bHoldUsed = s.holdUsed
    if S.applyCode(me, E.ACTION_INDEX[a], toOpp) then
      if a == "hardDrop" then sess:emit("harddrop")
      elseif a == "rotateCW" or a == "rotateCCW" then sess:emit("rotate")
      elseif a == "hold" and s.holdUsed and not bHoldUsed then sess:emit("hold") end
    end
    s = me.game
    if s.gameOver then break end
  end
  if #sp.castQueue > 0 then
    local q = sp.castQueue
    sp.castQueue = {}
    for _, spell in ipairs(q) do
      if S.canCast(me, spell) then
        if spell == "bomb" then sp.lastBombCells = S.bombCells(me.game) end -- for the flash
        S.applyCode(me, S.castCode(spell), toOpp)
        sess:emit("cast", spell)
      end
    end
  end
  s = me.game
  if not s.gameOver then S.stepSide(me) end
  s = me.game
  sess.state = s
  if not sp.remote then advanceOpp(sess, s.tick) end
  emitNew(sess)

  if s.piecesPlaced > bPieces then
    if s.lines > bLines and s.lastClear then sess:emit("clear", s.lastClear.lines, s.lastClear)
    else sess:emit("lock") end
  end
  if s.level > bLevel then sess:emit("level", s.level) end
  if sp.remote then
    -- duel: the session's own end rules (top-out / time); the duel decides the winner
    if s.gameOver then sp.endReason = "topout"; sess:finish("topout")
    elseif s.tick >= sess.capTicks then sp.endReason = "time"; sess:finish("time") end
    return
  end
  if s.gameOver then
    SB.finish(sess, "topout")
  elseif s.tick >= sess.capTicks then
    SB.finish(sess, "time")
  elseif S.botMatchDecided(s, sp.opp.game) then
    SB.finish(sess, "decided")
  end
end

--- The last tick of each side, exactly as the verification (Spells.Sim) processes it: at a side's
--- final tick (untilTick) incoming spells land and its codes run, but there is no gravity step.
--- The web's live loop skips this tick; its server does not - we follow the server (the result).
local function finalTick(sess)
  local sp = sess.spell
  if sp.finalDone then return end
  sp.finalDone = true
  local me, o = sp.me, sp.opp
  if not me.game.gameOver then
    local due = takeDue(sp.pendingMe, me.game.tick)
    if due then for _, inc in ipairs(due) do S.receive(me, inc) end end
  end
  if not o.game.gameOver and o.game.tick == sess.capTicks then
    local due = takeDue(sp.pendingOpp, o.game.tick)
    if due then for _, inc in ipairs(due) do S.receive(o, inc) end end
    for _ = 1, 2 do
      if o.game.gameOver then break end
      local c = sp.actor:act(o, me)
      if c == nil then break end
      S.applyCode(o, c, nil)
    end
  end
end
SB.finalTick = finalTick

--- Your run is over. The bot may still have ticks to play (after a top-out): it plays them over
--- the next frames (`settle`), then the result is final.
function SB.finish(sess, reason)
  local sp = sess.spell
  sp.endReason = reason
  sp.castQueue = {}
  if reason == "topout" and not sp.opp.game.gameOver and sp.opp.game.tick < sess.capTicks then
    sp.settling = true
  end
  sess:finish(reason)
  if not sp.settling then finalTick(sess); SB.decide(sess) end
end

--- Advance the bot after your top-out; returns true when the result is final.
function SB.settle(sess)
  local sp = sess.spell
  if not sp or not sp.settling then return true end
  local done = advanceOpp(sess, sess.capTicks, SB.FAST_FORWARD_PER_FRAME)
  emitNew(sess)
  if done then
    sp.settling = false
    finalTick(sess)
    SB.decide(sess)
    return true
  end
  return false
end

function SB.decide(sess)
  local sp = sess.spell
  local me, o = sp.me.game, sp.opp.game
  local outcome = S.decideOutcome({ score = me.score }, { score = o.score })
  sp.result = { outcome = outcome, me = me.score, bot = o.score, reason = sp.endReason, ticks = me.tick, botTicks = o.tick }
  sess:emit("spellresult", outcome)
end

--- Data to rebuild an unfinished match after /reload (the bot is rebuilt from the seed).
function SB.suspendData(sess)
  local sp = sess.spell
  local me = sp.me
  local parts = {}
  local log = me.log
  for k = 1, #log, 2 do parts[#parts + 1] = string.format("%.0f,%.0f", log[k], log[k + 1]) end
  return {
    mode = sess.mode.key, seed = sess.seed, ticks = me.game.tick, slog = table.concat(parts, " "),
    loadout = S.encodeLoadout(me.loadout), difficulty = sp.difficulty, createdAtMs = sp.createdAtMs,
  }
end

--- Rebuild both boards in lockstep from your log (the same code path as verification).
function SB.restore(sess, data)
  local loadout = S.decodeLoadout(data.loadout)
  local diff = data.difficulty
  if not loadout or not Bot.PROFILES[diff] or type(data.slog) ~= "string" or type(data.ticks) ~= "number" then return false end
  local log = {}
  for t, c in data.slog:gmatch("(%d+),(%d+)") do log[#log + 1] = tonumber(t); log[#log + 1] = tonumber(c) end
  SB.setup(sess, { loadout = loadout, difficulty = diff, createdAtMs = data.createdAtMs })
  local sp = sess.spell
  local sim = S.Sim.new(sess.seed, {
    { loadout = loadout, log = log, untilTick = sess.capTicks },
    { loadout = Bot.LOADOUTS[diff], actor = sp.actor, untilTick = sess.capTicks },
  })
  local ok = pcall(function()
    local limits = { data.ticks, data.ticks }
    while sim.t < data.ticks do sim:step(limits) end
  end)
  if not ok then return false end
  sp.me, sp.opp = sim.sides[1], sim.sides[2]
  sp.pendingMe, sp.pendingOpp = sim.pending[1], sim.pending[2]
  sp.seenOppCasts = #sp.opp.casts
  sess.state = sp.me.game
  if sess.state.gameOver or sess.state.tick ~= data.ticks then return false end
  return true
end

return SB
