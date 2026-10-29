--[[
  StackRivals - Spell Battle rules (Lua port of src/game/engine/spells.ts, web 48fdf46).

  StackRivals spells only: they change the StackRivals boards, never anything in World of
  Warcraft. Pure and deterministic like the core engine: a cast is an entry in the input log
  (code CAST_BASE + spell index) applied at a tick. Self spells take effect on the caster's tick;
  opponent spells land on the target exactly DELIVERY_TICKS later, so both logs can be replayed in
  lockstep (Sim) to get the exact same boards on every machine - the verification primitive.

  Differences from the TypeScript version, none of which change outcomes:
   * sides and games are mutated in place (no per-tick copies -> no garbage in WoW);
   * side.log is a flat array {tick, code, tick, code, ...}.
  Pure Lua 5.1: no WoW API.
]]
local _, ns = ...
ns = ns or {}
local E = ns.Engine
local Prng = ns.Prng
local Pieces = ns.Pieces

local floor, huge = math.floor, math.huge

local S = {}
ns.Spells = S

S.SPELLS = { "bomb", "lineBlast", "freeze", "swap", "clearBoard", "garbage", "speedUp", "blackout", "scramble" }
S.INDEX = {} -- 0-based like SPELLS.indexOf
for i, id in ipairs(S.SPELLS) do S.INDEX[id] = i - 1 end

local TPS = E.TICKS_PER_SECOND
S.INFO = {
  bomb = { name = "Bomb", cost = 4, target = "self", hint = "Clears 3\195\1513 where your piece lands" },
  lineBlast = { name = "Line Blast", cost = 5, target = "self", hint = "Clears your bottom 2 rows" },
  freeze = { name = "Freeze", cost = 6, target = "self", hint = "Stops your gravity for 5s", durationTicks = 5 * TPS },
  swap = { name = "Swap", cost = 3, target = "self", hint = "Swaps current piece with hold/next" },
  clearBoard = { name = "Clear Board", cost = 16, target = "self", hint = "Clears your whole board" },
  garbage = { name = "Garbage", cost = 4, target = "opponent", hint = "Sends 2 garbage rows" },
  speedUp = { name = "Speed Up", cost = 6, target = "opponent", hint = "Doubles their gravity for 8s", durationTicks = 8 * TPS },
  blackout = { name = "Blackout", cost = 5, target = "opponent", hint = "Hides their next queue for 10s", durationTicks = 10 * TPS },
  scramble = { name = "Scramble", cost = 7, target = "opponent", hint = "Their next piece becomes the worst fit" },
}
S.SELF_SPELLS, S.OPPONENT_SPELLS = {}, {}
for _, id in ipairs(S.SPELLS) do
  local list = (S.INFO[id].target == "self") and S.SELF_SPELLS or S.OPPONENT_SPELLS
  list[#list + 1] = id
end
S.DEFAULT_LOADOUT = { "lineBlast", "bomb", "garbage", "blackout" }

S.CAST_BASE = 100
S.MANA_MAX = 20
S.CAST_COOLDOWN_TICKS = 3 * TPS
--- Opponent spells land this many ticks after the cast (covers network latency for live play).
S.DELIVERY_TICKS = 90
local MANA_BY_LINES = { [0] = 0, 1, 3, 5, 8 }
local CAST_BASE, NSPELLS = S.CAST_BASE, #S.SPELLS

function S.castCode(spell) return CAST_BASE + S.INDEX[spell] end
function S.isCastCode(c) return type(c) == "number" and c % 1 == 0 and c >= CAST_BASE and c < CAST_BASE + NSPELLS end
function S.spellOfCode(c) if S.isCastCode(c) then return S.SPELLS[c - CAST_BASE + 1] end return nil end
--- Any code a Spell Battle log may contain: a move (0..6) or a cast (100..108).
function S.isValidCode(c)
  return type(c) == "number" and c % 1 == 0 and ((c >= 0 and c < #E.INPUT_ACTIONS) or S.isCastCode(c))
end

function S.manaForClear(lines, combo)
  if lines > 4 then lines = 4 end
  return (MANA_BY_LINES[lines] or 0) + math.max(0, combo)
end

--- A valid loadout is 4 distinct spells: exactly 2 self + 2 opponent.
function S.isValidLoadout(l)
  if type(l) ~= "table" or #l ~= 4 then return false end
  local seen, self = {}, 0
  for i = 1, 4 do
    local id = l[i]
    if type(id) ~= "string" or not S.INFO[id] or seen[id] then return false end
    seen[id] = true
    if S.INFO[id].target == "self" then self = self + 1 end
  end
  for k in pairs(l) do if type(k) ~= "number" or k < 1 or k > 4 or k % 1 ~= 0 then return false end end
  return self == 2
end

--- Compact loadout text for messages and saved data: four spell indexes, e.g. "1052" (index order
--- = the loadout's slot order, so slot 1 is key 1). Returns nil for an invalid loadout.
function S.encodeLoadout(l)
  if not S.isValidLoadout(l) then return nil end
  return tostring(S.INDEX[l[1]]) .. S.INDEX[l[2]] .. S.INDEX[l[3]] .. S.INDEX[l[4]]
end
function S.decodeLoadout(str)
  if type(str) ~= "string" or not str:match("^%d%d%d%d$") then return nil end
  local l = {}
  for i = 1, 4 do l[i] = S.SPELLS[tonumber(str:sub(i, i)) + 1] end
  if not S.isValidLoadout(l) then return nil end
  return l
end

function S.createSide(seed, loadout)
  return {
    game = E.createGame(seed, { startLevel = 1 }),
    loadout = loadout,
    mana = 0,
    lastCastTick = -1000000,
    freezeUntil = 0,
    speedUntil = 0,
    blackoutUntil = 0,
    log = {},          -- flat {tick, code, ...}: moves and casts, valid or not
    invalidCasts = {}, -- { {tick, code, reason}, ... }
    casts = {},        -- { {tick = t, spell = id}, ... }
    hits = {},         -- last 5 effects that hit this side: {tick, spell, fromSelf}
  }
end

function S.gravityOf(side, t)
  t = t or side.game.tick
  if t < side.freezeUntil then return "frozen" end
  if t < side.speedUntil then return "double" end
  return "normal"
end

local function inLoadout(side, spell)
  for i = 1, #side.loadout do if side.loadout[i] == spell then return true end end
  return false
end

--- ok, reason ("topped_out" | "not_in_loadout" | "insufficient_mana" | "cooldown")
function S.canCast(side, spell, t)
  t = t or side.game.tick
  if side.game.gameOver then return false, "topped_out" end
  if not inLoadout(side, spell) then return false, "not_in_loadout" end
  if side.mana < S.INFO[spell].cost then return false, "insufficient_mana" end
  if t - side.lastCastTick < S.CAST_COOLDOWN_TICKS then return false, "cooldown" end
  return true
end

function S.cooldownLeft(side, t)
  t = t or side.game.tick
  return math.max(0, S.CAST_COOLDOWN_TICKS - (t - side.lastCastTick))
end

local function withMana(side, prevClear)
  local lc = side.game.lastClear
  if lc and lc ~= prevClear then
    local m = side.mana + S.manaForClear(lc.lines, lc.combo)
    side.mana = (m > S.MANA_MAX) and S.MANA_MAX or m
  end
end

--- JS Math.round (halves round up, also for negatives).
local function round(x) return floor(x + 0.5) end

--- 3x3 cells centred on where the active piece would land: { {x, y}, ... } (9, or 0 without a piece).
function S.bombCells(game)
  local g = E.getGhost(game)
  if not g then return {} end
  local cells = E.cellsOf(g)
  local sx, sy = 0, 0
  for _, c in ipairs(cells) do sx, sy = sx + c[1], sy + c[2] end
  local cx, cy = round(sx / #cells), round(sy / #cells)
  local out = {}
  for dy = -1, 1 do for dx = -1, 1 do out[#out + 1] = { cx + dx, cy + dy } end end
  return out
end

--- Garbage gap column: derived from the shared seed and the cast tick, never chosen by a client.
function S.garbageGap(seed, castTick, width)
  return Prng.hashString(tostring(seed) .. ":garbage:" .. string.format("%.0f", castTick)) % width
end

--- Worst-fit piece for Scramble: for each piece, its best placement (fewest new holes, then
--- lowest stack); the piece whose best placement is worst wins. Ties -> piece order.
function S.worstFitPiece(game)
  local w = game.config.width
  local h = game.config.height + game.config.hiddenRows
  local b = game.board
  local worst, worstScore = Pieces.IDS[1], -huge
  for _, id in ipairs(Pieces.IDS) do
    local best = huge
    for r = 1, 4 do
      local cells = Pieces.SHAPES[id][r]
      local minX, maxX = huge, -huge
      for _, c in ipairs(cells) do
        if c[1] < minX then minX = c[1] end
        if c[1] > maxX then maxX = c[1] end
      end
      local x = 0 - minX -- +0, never -0
      while x + maxX < w do
        local function fits(y)
          for _, c in ipairs(cells) do
            local by = y + c[2]
            if by >= h then return false end
            if by >= 0 and b[by * w + x + c[1] + 1] ~= 0 then return false end
          end
          return true
        end
        if fits(0) then
          local y = 0
          while fits(y + 1) do y = y + 1 end
          local placed = {}
          for _, c in ipairs(cells) do placed[(y + c[2]) * w + x + c[1]] = true end
          local holes, top = 0, h
          for _, c in ipairs(cells) do
            if y + c[2] < top then top = y + c[2] end
            local below = (y + c[2] + 1) * w + x + c[1]
            if y + c[2] + 1 < h and b[below + 1] == 0 and not placed[below] then holes = holes + 1 end
          end
          local score = holes * 10 + (h - top)
          if score < best then best = score end
        end
        x = x + 1
      end
    end
    if best > worstScore then
      worstScore = best
      worst = id
    end
  end
  return worst
end

local function applyEffect(side, spell, at, castTick, fromSelf)
  local g = side.game
  if g.gameOver then return end
  if spell == "bomb" then E.clearCells(g, S.bombCells(g))
  elseif spell == "lineBlast" then E.removeBottomRows(g, 2)
  elseif spell == "clearBoard" then E.clearBoard(g)
  elseif spell == "swap" then E.swapActive(g)
  elseif spell == "freeze" then side.freezeUntil = at + S.INFO.freeze.durationTicks
  elseif spell == "garbage" then E.addGarbage(g, 2, S.garbageGap(g.seed, castTick, g.config.width))
  elseif spell == "speedUp" then side.speedUntil = at + S.INFO.speedUp.durationTicks
  elseif spell == "blackout" then side.blackoutUntil = at + S.INFO.blackout.durationTicks
  elseif spell == "scramble" then E.replaceNext(g, S.worstFitPiece(g))
  end
  local hits = side.hits
  hits[#hits + 1] = { tick = at, spell = spell, fromSelf = fromSelf }
  if #hits > 5 then table.remove(hits, 1) end
end

--- Apply one log entry (move or cast) at the side's current tick. Opponent spells are handed to
--- `send({spell, at, castTick})` with their landing tick. Invalid casts are logged and recorded
--- and have no effect. Mutates side; returns true when the code took effect.
function S.applyCode(side, code, send)
  local g = side.game
  local t = g.tick
  local log = side.log
  log[#log + 1] = t
  log[#log + 1] = code
  local spell = S.spellOfCode(code)
  if not spell then
    local action = (type(code) == "number" and code % 1 == 0) and E.INPUT_ACTIONS[code + 1] or nil
    if not action then
      side.invalidCasts[#side.invalidCasts + 1] = { tick = t, code = code, reason = "unknown_code" }
      return false
    end
    local prev = g.lastClear
    local applied = E.applyInput(g, action)
    withMana(side, prev)
    return applied
  end
  local ok, reason = S.canCast(side, spell, t)
  if not ok then
    side.invalidCasts[#side.invalidCasts + 1] = { tick = t, code = code, reason = reason }
    return false
  end
  side.mana = side.mana - S.INFO[spell].cost
  side.lastCastTick = t
  side.casts[#side.casts + 1] = { tick = t, spell = spell }
  if S.INFO[spell].target == "self" then
    applyEffect(side, spell, t, t, true)
  elseif send then
    send({ spell = spell, at = t + S.DELIVERY_TICKS, castTick = t })
  end
  return true
end

--- An opponent spell lands on this side now.
function S.receive(side, inc) applyEffect(side, inc.spell, side.game.tick, inc.castTick, false) end

--- Gravity + lock for one tick (with Freeze / Speed Up), and mana from any clear it caused.
function S.stepSide(side)
  local g = side.game
  if g.gameOver then return end
  local prev = g.lastClear
  E.tick(g, S.gravityOf(side))
  withMana(side, prev)
end

------------------------------------------------------------------------------------------------
-- Lockstep simulation of a full Spell Battle (port of SpellSim). Per tick and side: incoming
-- effects land, then the side's inputs/casts, then gravity. Side 1 is processed before side 2.
-- players[i] = { loadout, log = flat {t, code, ...} or nil, actor = {act = fn(self, me, opp)},
--                untilTick }
------------------------------------------------------------------------------------------------
local Sim = {}
Sim.__index = Sim
S.Sim = Sim

function Sim.new(seed, players)
  local self = setmetatable({
    seed = seed, players = players,
    sides = { S.createSide(seed, players[1].loadout), S.createSide(seed, players[2].loadout) },
    pending = { {}, {} }, idx = { 1, 1 }, t = 0, bestCombo = { 0, 0 },
  }, Sim)
  return self
end

function Sim:endTick() return math.max(self.players[1].untilTick, self.players[2].untilTick) end

function Sim:done()
  if self.t > self:endTick() then return true end
  for i = 1, 2 do
    if not (self.sides[i].game.gameOver or self.t > self.players[i].untilTick) then return false end
  end
  return true
end

--- Number of log entries (pairs) consumed so far per side.
function Sim:consumed() return (self.idx[1] - 1) / 2, (self.idx[2] - 1) / 2 end

--- Process tick t for both sides, then t = t + 1. limits[i]: side i is not processed at ticks >= limit.
function Sim:step(limits)
  local t = self.t
  for i = 1, 2 do
    local p, side, o = self.players[i], self.sides[i], 3 - i
    if not (side.game.gameOver or t > p.untilTick or (limits and t >= limits[i])) then
      local pend = self.pending[i]
      if #pend > 0 then
        local keep, due = {}, {}
        for _, x in ipairs(pend) do
          if x.at <= t then due[#due + 1] = x else keep[#keep + 1] = x end
        end
        if #due > 0 then
          self.pending[i] = keep
          for _, inc in ipairs(due) do S.receive(side, inc) end
        end
      end
      local players, sides, pending = self.players, self.sides, self.pending
      local function send(inc)
        if not (sides[o].game.gameOver or inc.at > players[o].untilTick) then
          local q = pending[o]
          q[#q + 1] = inc
        end
      end
      if p.log then
        local log, k = p.log, self.idx[i]
        while k <= #log and log[k] == t and not side.game.gameOver do
          S.applyCode(side, log[k + 1], send)
          k = k + 2
        end
        self.idx[i] = k
      elseif p.actor then
        for _ = 1, 2 do
          if side.game.gameOver then break end
          local c = p.actor:act(side, sides[o])
          if c == nil then break end
          S.applyCode(side, c, send)
        end
      end
      if t < p.untilTick then S.stepSide(side) end
      if side.game.combo > self.bestCombo[i] then self.bestCombo[i] = side.game.combo end
    end
  end
  self.t = t + 1
end

--- Run to the end. Returns { sides, unprocessed = {n1, n2}, bestCombo }.
function Sim:run()
  for i = 1, 2 do
    local log = self.players[i].log
    if log then
      for k = 3, #log, 2 do if log[k] < log[k - 2] then error("Input log is not tick-ordered") end end
    end
  end
  while not self:done() do self:step() end
  local un = {}
  for i = 1, 2 do
    local log = self.players[i].log
    un[i] = log and (#log - (self.idx[i] - 1)) / 2 or 0
  end
  return { sides = self.sides, unprocessed = un, bestCombo = { self.bestCombo[1], self.bestCombo[2] } }
end

------------------------------------------------------------------------------------------------
-- Results (port of src/lib/match/rules.ts: verifySpellMatch, decideOutcome, botMatchDecided)
------------------------------------------------------------------------------------------------

--- Higher score wins; equal is a draw. A forfeit always loses (both forfeited: draw).
function S.decideOutcome(a, b)
  if a.forfeited and not b.forfeited then return "loss", "win" end
  if b.forfeited and not a.forfeited then return "win", "loss" end
  if a.score == b.score then return "draw", "draw" end
  if a.score > b.score then return "win", "loss" end
  return "loss", "win"
end

--- vs Bot: decided once the bot has topped out (its score can't change) and the player is
--- strictly ahead. Behind or level, the player keeps playing.
function S.botMatchDecided(me, bot)
  return (not me.gameOver) and bot.gameOver and me.score > bot.score
end

--- Shape/timing checks for one player's log (the web's checkLog with Spell Battle codes).
--- p = { v, seed, startLevel, ticks, log (flat), elapsedMs? }. Returns reasons list, or "malformed".
function S.checkLog(p, seed, capTicks)
  local V = ns.Verify
  if p.v ~= E.ENGINE_VERSION then return { "engine_mismatch" } end
  if p.seed ~= seed then return { "seed_mismatch" } end
  local ticks = p.ticks
  if p.startLevel ~= 1 or type(ticks) ~= "number" or ticks % 1 ~= 0 or ticks < 0 then return "malformed" end
  local reasons = {}
  if ticks > capTicks then reasons[#reasons + 1] = "over_time_cap" end
  if p.elapsedMs and (ticks / TPS) * 1000 > p.elapsedMs + V.CLOCK_SLACK_MS then reasons[#reasons + 1] = "faster_than_clock" end
  local log = p.log
  if type(log) ~= "table" or #log % 2 ~= 0 then return "malformed" end
  local prev, run, burst = -1, 0, false
  for k = 1, #log, 2 do
    local t, c = log[k], log[k + 1]
    if type(t) ~= "number" or t % 1 ~= 0 or t < prev or t > ticks or not S.isValidCode(c) then return "malformed" end
    if t == prev then run = run + 1 else run = 1 end
    if run > V.MAX_INPUTS_PER_TICK then burst = true end
    prev = t
  end
  if burst then reasons[#reasons + 1] = "inhuman_input_rate" end
  return reasons
end

local function contains(list, x) for _, v in ipairs(list) do if v == x then return true end end return false end

--- Replay both logs in lockstep and return the authoritative result per player.
--- opts = { seed, capTicks, players = { p1, p2? }, bot = { actor, loadout }? }
--- p = { v, seed, startLevel, ticks, log, loadout, elapsedMs? }
--- Returns results[i] = { ok, reasons, score, lines, level, ticks, hash, toppedOut, mana, casts,
--- bestCombo, invalidCasts }, and the bot's side (or nil).
function S.verifyMatch(opts)
  local cap = opts.capTicks
  local pre = {}
  for i, p in ipairs(opts.players) do
    local r = S.checkLog(p, opts.seed, cap)
    local reasons = (r == "malformed") and { "malformed_log" } or r
    local loadoutOk = S.isValidLoadout(p.loadout)
    if not loadoutOk then reasons[#reasons + 1] = "invalid_loadout" end
    local usable = r ~= "malformed" and not contains(reasons, "engine_mismatch") and not contains(reasons, "seed_mismatch") and loadoutOk
    pre[i] = { reasons = reasons, usable = usable, loadout = loadoutOk and p.loadout or S.DEFAULT_LOADOUT }
  end
  local function simPlayer(i)
    local p = opts.players[i]
    return { loadout = pre[i].loadout, log = pre[i].usable and p.log or {}, untilTick = pre[i].usable and math.min(p.ticks, cap) or 0 }
  end
  local second = opts.bot and { loadout = opts.bot.loadout, log = nil, actor = opts.bot.actor, untilTick = cap } or simPlayer(2)
  local run = Sim.new(opts.seed, { simPlayer(1), second }):run()
  local results = {}
  for i, p in ipairs(opts.players) do
    local reasons = pre[i].reasons
    if not pre[i].usable then
      results[i] = { ok = false, reasons = reasons, score = 0, lines = 0, level = 1, ticks = 0, hash = nil, toppedOut = false, mana = 0, casts = 0, bestCombo = 0, invalidCasts = {} }
    else
      local side = run.sides[i]
      if #side.invalidCasts > 0 then reasons[#reasons + 1] = "impossible_cast" end
      local within = 0
      for k = 1, #p.log, 2 do if p.log[k] <= cap then within = within + 1 end end
      if #side.log / 2 < within then reasons[#reasons + 1] = "inputs_after_topout" end
      local g = side.game
      results[i] = {
        ok = #reasons == 0, reasons = reasons, score = g.score, lines = g.lines, level = g.level,
        ticks = g.tick, hash = E.hashState(g), toppedOut = g.gameOver, mana = side.mana,
        casts = #side.casts, bestCombo = run.bestCombo[i], invalidCasts = side.invalidCasts, side = side,
      }
    end
  end
  return results, opts.bot and run.sides[2] or nil
end

return S
