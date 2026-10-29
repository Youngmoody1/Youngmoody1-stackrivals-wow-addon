--[[
  StackRivals - deterministic bots (Lua port of src/game/bot/bot.ts and spell-bot.ts, web 48fdf46).

  Given (seed, difficulty, tuning version) a bot makes exactly the same decisions as on
  stackrivals.io: the same placement evaluation, the same seeded randomness, the same "think time"
  in engine ticks and the same casting rules. Pure Lua 5.1, no WoW API, no time, no math.random.
]]
local _, ns = ...
ns = ns or {}
local E = ns.Engine
local Prng = ns.Prng
local Pieces = ns.Pieces
local S = ns.Spells

local floor, huge, abs = math.floor, math.huge, math.abs

local Bot = {}
ns.Bot = Bot

Bot.DIFFICULTIES = { "rookie", "challenger", "contender", "elite", "rival" }

--- Tuning versions: a match always uses the tuning that was current when it was created.
--- v2 (web, 28 Oct 2026) = much easier than the launch tuning. Unknown time = current (v2).
Bot.V2_FROM_MS = 1793216640000 -- Date.parse("2026-10-28T19:44:00Z")

Bot.PROFILES_V1 = {
  rookie = { label = "Rookie", thinkTicks = 36, actionTicks = 8, topN = 3, pickBest = 0.5, errorRate = 0.1 },
  challenger = { label = "Challenger", thinkTicks = 26, actionTicks = 6, topN = 3, pickBest = 0.7, errorRate = 0.05 },
  contender = { label = "Contender", thinkTicks = 16, actionTicks = 4, topN = 2, pickBest = 0.85, errorRate = 0.03 },
  elite = { label = "Elite", thinkTicks = 9, actionTicks = 3, topN = 2, pickBest = 0.95, errorRate = 0.01 },
  rival = { label = "Rival", thinkTicks = 5, actionTicks = 2, topN = 1, pickBest = 1, errorRate = 0 },
}
Bot.PROFILES = {
  rookie = { label = "Rookie", thinkTicks = 55, actionTicks = 12, topN = 3, pickBest = 0.4, errorRate = 0.14 },
  challenger = { label = "Challenger", thinkTicks = 42, actionTicks = 9, topN = 3, pickBest = 0.55, errorRate = 0.09 },
  contender = { label = "Contender", thinkTicks = 32, actionTicks = 7, topN = 3, pickBest = 0.68, errorRate = 0.06 },
  elite = { label = "Elite", thinkTicks = 22, actionTicks = 5, topN = 2, pickBest = 0.8, errorRate = 0.04 },
  rival = { label = "Rival", thinkTicks = 14, actionTicks = 4, topN = 2, pickBest = 0.9, errorRate = 0.02 },
}

function Bot.isV1(createdAtMs)
  return type(createdAtMs) == "number" and createdAtMs == createdAtMs and createdAtMs < Bot.V2_FROM_MS
end
function Bot.profiles(createdAtMs) return Bot.isV1(createdAtMs) and Bot.PROFILES_V1 or Bot.PROFILES end

local W_HEIGHT, W_LINES, W_HOLES, W_BUMP = -0.51, 0.76, -0.36, -0.18

local function scoreBoard(board, w, h)
  -- clear lines: full rows are removed, the rest drop (only their order matters here)
  local lines = 0
  local keep = {}
  for y = 0, h - 1 do
    local full = true
    for x = 0, w - 1 do if board[y * w + x + 1] == 0 then full = false; break end end
    if full then lines = lines + 1 else keep[#keep + 1] = y end
  end
  local off = h - #keep -- empty rows on top after the clear
  local function cell(y, x) -- y in the cleared board
    if y < off then return 0 end
    return board[keep[y - off + 1] * w + x + 1]
  end
  local heights, holes = {}, 0
  for x = 0, w - 1 do
    local top = h
    for y = 0, h - 1 do if cell(y, x) ~= 0 then top = y; break end end
    heights[x + 1] = h - top
    for y = top + 1, h - 1 do if cell(y, x) == 0 then holes = holes + 1 end end
  end
  local agg = 0
  for x = 1, w do agg = agg + heights[x] end
  local bump = 0
  for x = 2, w do bump = bump + abs(heights[x] - heights[x - 1]) end
  return W_HEIGHT * agg + W_LINES * lines + W_HOLES * holes + W_BUMP * bump
end
Bot._scoreBoard = scoreBoard

--- Every distinct (rotation, column) drop of the active piece, best first.
function Bot.evaluatePlacements(state)
  local p = state.active
  if not p then return {} end
  local w = state.config.width
  local h = state.config.height + state.config.hiddenRows
  local board = state.board
  local out, seen = {}, {}
  for r = 0, 3 do
    local cells = Pieces.SHAPES[p.id][r + 1]
    local minX, maxX = huge, -huge
    for _, c in ipairs(cells) do
      if c[1] < minX then minX = c[1] end
      if c[1] > maxX then maxX = c[1] end
    end
    local x = 0 - minX -- +0, never -0
    while x + maxX < w do
      local function fits(y)
        for _, c in ipairs(cells) do
          local bx, by = x + c[1], y + c[2]
          if bx < 0 or bx >= w or by >= h then return false end
          if by >= 0 and board[by * w + bx + 1] ~= 0 then return false end
        end
        return true
      end
      if fits(0) then
        local y = 0
        while fits(y + 1) do y = y + 1 end
        -- the set of cells the piece covers (same set = same placement, kept once)
        local idx = {}
        for i, c in ipairs(cells) do idx[i] = (y + c[2]) * 64 + (x + c[1]) end
        table.sort(idx)
        local key = table.concat(idx, ";")
        if not seen[key] then
          seen[key] = true
          local b2 = {}
          for i = 1, #board do b2[i] = board[i] end
          for _, c in ipairs(cells) do if y + c[2] >= 0 then b2[(y + c[2]) * w + x + c[1] + 1] = 1 end end
          out[#out + 1] = { rotation = r, x = x, score = scoreBoard(b2, w, h) }
        end
      end
      x = x + 1
    end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.x ~= b.x then return a.x < b.x end
    return a.rotation < b.rotation
  end)
  return out
end

--- Pick a placement. Returns plan {piece, id, rotation, x} (or nil) and the next rng state.
function Bot.choose(state, prof, rng)
  local cands = Bot.evaluatePlacements(state)
  if #cands == 0 or not state.active then return nil, rng end
  local r
  r, rng = Prng.nextRandom(rng)
  local pick = cands[1]
  if r >= prof.pickBest then
    r, rng = Prng.nextRandom(rng)
    pick = cands[math.min(#cands, floor(r * prof.topN) + 1)]
  end
  local x = pick.x
  r, rng = Prng.nextRandom(rng)
  if r < prof.errorRate then
    r, rng = Prng.nextRandom(rng)
    x = x + ((r < 0.5) and -1 or 1)
  end
  return { piece = state.piecesPlaced, id = state.active.id, rotation = pick.rotation, x = x }, rng
end

function Bot.nextAction(state, plan)
  local a = state.active
  if a.rotation ~= plan.rotation then
    return ((plan.rotation - a.rotation + 4) % 4 == 3) and "rotateCCW" or "rotateCW"
  end
  if a.x < plan.x then return "right" end
  if a.x > plan.x then return "left" end
  return "hardDrop"
end

--- A full classic bot game up to untilTick (or top-out). Returns the final state (with its log).
function Bot.generateGame(seed, difficulty, untilTick, createdAtMs)
  local prof = Bot.profiles(createdAtMs)[difficulty]
  local rng = Prng.hashString(tostring(seed) .. ":bot:" .. difficulty)
  local s = E.createGame(seed, { startLevel = 1 })
  local plan, nextAt = nil, 0
  local lastX, lastRot, stuck = -99, -1, 0
  while not s.gameOver and s.tick < untilTick do
    if s.active and (not plan or plan.piece ~= s.piecesPlaced or plan.id ~= s.active.id) then
      plan, rng = Bot.choose(s, prof, rng)
      nextAt = s.tick + prof.thinkTicks
      stuck, lastX, lastRot = 0, -99, -1
    end
    if plan and s.active and s.tick >= nextAt then
      local action = Bot.nextAction(s, plan)
      if action ~= "hardDrop" and s.active.x == lastX and s.active.rotation == lastRot then
        stuck = stuck + 1
        if stuck > 1 then action = "hardDrop" end
      end
      lastX, lastRot = s.active.x, s.active.rotation
      E.applyInput(s, action)
      nextAt = s.tick + prof.actionTicks
      if s.gameOver then break end
    end
    E.tick(s)
  end
  return s
end

------------------------------------------------------------------------------------------------
-- Spell Battle bot
------------------------------------------------------------------------------------------------
Bot.LOADOUTS = {
  rookie = { "lineBlast", "freeze", "garbage", "blackout" },
  challenger = { "lineBlast", "freeze", "garbage", "blackout" },
  contender = { "lineBlast", "bomb", "garbage", "speedUp" },
  elite = { "lineBlast", "clearBoard", "garbage", "scramble" },
  rival = { "lineBlast", "clearBoard", "garbage", "scramble" },
}
local CAST_STYLE_V1 = {
  rookie = { every = 120, chance = 0.4 }, challenger = { every = 90, chance = 0.55 },
  contender = { every = 60, chance = 0.7 }, elite = { every = 30, chance = 0.85 }, rival = { every = 20, chance = 1 },
}
local CAST_STYLE = {
  rookie = { every = 240, chance = 0.3 }, challenger = { every = 180, chance = 0.4 },
  contender = { every = 120, chance = 0.55 }, elite = { every = 75, chance = 0.7 }, rival = { every = 45, chance = 0.85 },
}

--- Height of the tallest column in rows.
function Bot.stackHeight(g)
  local w = g.config.width
  local h = g.config.height + g.config.hiddenRows
  for y = 0, h - 1 do
    for x = 0, w - 1 do if g.board[y * w + x + 1] ~= 0 then return h - y end end
  end
  return 0
end

--- Ordered casting rules; the first castable one that applies.
function Bot.pickSpell(me, opp)
  local h = Bot.stackHeight(me.game)
  local function ok(s) return (S.canCast(me, s)) end
  if h >= 15 and ok("clearBoard") then return "clearBoard" end
  if h > 14 and ok("lineBlast") then return "lineBlast" end
  if h >= 12 and ok("freeze") then return "freeze" end
  if h >= 10 and ok("bomb") then return "bomb" end
  if me.game.score >= opp.game.score and ok("garbage") then return "garbage" end
  for _, s in ipairs({ "scramble", "speedUp", "blackout" }) do
    if me.mana >= 12 and ok(s) then return s end
  end
  return nil
end

local SpellBot = {}
SpellBot.__index = SpellBot
Bot.SpellBot = SpellBot

--- createdAtMs = when the match was created (picks the tuning the match is played with).
function SpellBot.new(seed, difficulty, createdAtMs)
  return setmetatable({
    difficulty = difficulty, createdAtMs = createdAtMs,
    rng = Prng.hashString(tostring(seed) .. ":spellbot:" .. difficulty),
    plan = nil, nextAt = 0, lastX = -99, lastRot = -1, stuck = 0, lastCastCheck = -1,
  }, SpellBot)
end

--- The next code for this side at its current tick, or nil (the Sim asks up to twice per tick).
function SpellBot:act(me, opp)
  local s = me.game
  if s.gameOver or not s.active then return nil end
  local style = (Bot.isV1(self.createdAtMs) and CAST_STYLE_V1 or CAST_STYLE)[self.difficulty]
  if s.tick % style.every == 0 and self.lastCastCheck ~= s.tick then
    self.lastCastCheck = s.tick
    local spell = Bot.pickSpell(me, opp)
    if spell then
      local r
      r, self.rng = Prng.nextRandom(self.rng)
      if r < style.chance then return S.castCode(spell) end
    end
  end
  local prof = Bot.profiles(self.createdAtMs)[self.difficulty]
  if not self.plan or self.plan.piece ~= s.piecesPlaced or self.plan.id ~= s.active.id then
    self.plan, self.rng = Bot.choose(s, prof, self.rng)
    self.nextAt = s.tick + prof.thinkTicks
    self.stuck, self.lastX, self.lastRot = 0, -99, -1
  end
  if not self.plan or s.tick < self.nextAt then return nil end
  local action = Bot.nextAction(s, self.plan)
  if action ~= "hardDrop" and s.active.x == self.lastX and s.active.rotation == self.lastRot then
    self.stuck = self.stuck + 1
    if self.stuck > 1 then action = "hardDrop" end
  end
  self.lastX, self.lastRot = s.active.x, s.active.rotation
  self.nextAt = s.tick + prof.actionTicks
  return E.ACTION_INDEX[action]
end

return Bot
