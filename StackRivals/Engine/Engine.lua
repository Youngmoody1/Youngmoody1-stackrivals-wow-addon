--[[
  StackRivals core engine - Lua port of src/game/engine/engine.ts (ENGINE_VERSION 1).

  Same rules as stackrivals.io: same pieces, bag randomizer, rotation, wall kicks, lock delay,
  scoring, combos, back-to-back and levels. Same seed + same input log => identical state
  (tests/parity checks this against the web engine via hashState).

  Differences from the TypeScript version, none of which change outcomes:
   * functions mutate the state in place (no per-tick table copies -> no garbage in WoW);
   * the input log is a flat array {tick, actionIndex, tick, actionIndex, ...};
   * a few extra fields for the UI (lastLockTick) that hashState ignores.
  Pure Lua 5.1: no WoW API, no time, no math.random.
]]
local _, ns = ...
ns = ns or {}
local Prng = ns.Prng
local Pieces = ns.Pieces
local SHAPES, SIZE, IDS = Pieces.SHAPES, Pieces.SIZE, Pieces.IDS

local floor, format, concat = math.floor, string.format, table.concat

local E = {}

E.ENGINE_VERSION = 1
E.TICKS_PER_SECOND = 60
E.INPUT_ACTIONS = { "left", "right", "rotateCW", "rotateCCW", "softDrop", "hardDrop", "hold" }
E.ACTION_INDEX = {} -- 0-based like INPUT_ACTIONS.indexOf in TS
for i, a in ipairs(E.INPUT_ACTIONS) do E.ACTION_INDEX[a] = i - 1 end

E.DEFAULT_CONFIG = {
  width = 10, height = 20, hiddenRows = 2, startLevel = 1, previewCount = 5,
  lockDelayTicks = 30, maxLockResets = 15, linesPerLevel = 10,
}

E.LINE_POINTS = { 100, 300, 500, 800 }
E.B2B_MULTIPLIER = 1.5
E.COMBO_POINTS = 50
E.SOFT_DROP_POINTS = 1
E.HARD_DROP_POINTS = 2
local CLEAR_KIND = { [0] = "none", "single", "double", "triple", "quad" }

-- gravityTicks(level) from the web engine, precomputed so no floating-point pow can differ.
local GRAVITY = { 60, 48, 37, 28, 21, 16, 11, 8, 6, 4, 3, 2, 1, 1, 1, 1, 1, 1, 1, 1 }
function E.gravityTicks(level)
  if level < 1 then level = 1 elseif level > 20 then level = 20 end
  return GRAVITY[level]
end

local function rows(c) return c.height + c.hiddenRows end

--- Iterate absolute cells of a piece: returns array of {x, y}.
function E.cellsOf(p)
  local out = {}
  for i, c in ipairs(SHAPES[p.id][p.rotation + 1]) do out[i] = { p.x + c[1], p.y + c[2] } end
  return out
end

-- Collision check without allocating.
local function collidesAt(s, id, rot, px, py)
  local w = s.config.width
  local h = rows(s.config)
  local board = s.board
  for _, c in ipairs(SHAPES[id][rot + 1]) do
    local x, y = px + c[1], py + c[2]
    if x < 0 or x >= w or y >= h then return true end
    if y >= 0 and board[y * w + x + 1] ~= 0 then return true end
  end
  return false
end
E.collidesAt = collidesAt

local function refillQueue(s)
  local min = s.config.previewCount + 1
  while #s.queue < min do
    local bag, nxt = Prng.shuffle(IDS, s.rngState)
    s.rngState = nxt
    for i = 1, #bag do s.queue[#s.queue + 1] = bag[i] end
  end
end

local function spawn(s, id)
  local px = floor((s.config.width - SIZE[id]) / 2)
  s.gravityCounter = 0
  s.lockCounter = 0
  s.lockResets = 0
  if collidesAt(s, id, 0, px, 0) then
    s.active = nil
    s.gameOver = true
    return
  end
  s.active = { id = id, rotation = 0, x = px, y = 0 }
end

local function spawnNext(s)
  local id = table.remove(s.queue, 1)
  refillQueue(s)
  spawn(s, id)
end

function E.createGame(seed, config)
  local cfg = {}
  for k, v in pairs(E.DEFAULT_CONFIG) do cfg[k] = v end
  if config then for k, v in pairs(config) do cfg[k] = v end end
  local board = {}
  for i = 1, cfg.width * rows(cfg) do board[i] = 0 end
  local s = {
    engineVersion = E.ENGINE_VERSION,
    seed = seed,
    config = cfg,
    board = board,
    active = nil,
    hold = nil,
    holdUsed = false,
    queue = {},
    rngState = Prng.hashString(tostring(seed)),
    tick = 0,
    gravityCounter = 0,
    lockCounter = 0,
    lockResets = 0,
    score = 0,
    lines = 0,
    level = cfg.startLevel,
    combo = -1,
    backToBack = false,
    piecesPlaced = 0,
    clears = { none = 0, single = 0, double = 0, triple = 0, quad = 0 },
    lastClear = nil,
    lastLockTick = -1,
    gameOver = false,
    inputLog = {},
  }
  refillQueue(s)
  spawnNext(s)
  return s
end

local function isGrounded(s)
  local p = s.active
  return p ~= nil and collidesAt(s, p.id, p.rotation, p.x, p.y + 1)
end

local function lockPiece(s)
  local p = s.active
  if not p then return end
  local cfg = s.config
  local w, hidden = cfg.width, cfg.hiddenRows
  local value = Pieces.cellValue(p.id)
  local allHidden = true
  for _, c in ipairs(SHAPES[p.id][p.rotation + 1]) do
    local x, y = p.x + c[1], p.y + c[2]
    if y >= 0 then s.board[y * w + x + 1] = value end
    if y >= hidden then allHidden = false end
  end
  s.active = nil
  s.piecesPlaced = s.piecesPlaced + 1
  s.holdUsed = false
  s.lastLockTick = s.tick

  -- Clear full rows (rows kept in order; empty rows added on top).
  local h = rows(cfg)
  local board = s.board
  local keptRows, cleared = {}, 0
  for y = 0, h - 1 do
    local full = true
    for x = 0, w - 1 do
      if board[y * w + x + 1] == 0 then full = false; break end
    end
    if full then cleared = cleared + 1 else keptRows[#keptRows + 1] = y end
  end
  if cleared > 0 then
    local nb, n = {}, 0
    for _ = 1, cleared * w do n = n + 1; nb[n] = 0 end
    for _, y in ipairs(keptRows) do
      for x = 0, w - 1 do n = n + 1; nb[n] = board[y * w + x + 1] end
    end
    s.board = nb
  end

  local levelAtClear = s.level
  local kind = CLEAR_KIND[cleared]
  s.clears[kind] = s.clears[kind] + 1
  if cleared > 0 then
    s.combo = s.combo + 1
    local points = E.LINE_POINTS[cleared] * levelAtClear
    local isQuad = cleared == 4
    local b2b = isQuad and s.backToBack
    if b2b then points = floor(points * E.B2B_MULTIPLIER) end
    if s.combo > 0 then points = points + E.COMBO_POINTS * s.combo * levelAtClear end
    s.backToBack = isQuad
    s.score = s.score + points
    s.lines = s.lines + cleared
    s.level = cfg.startLevel + floor(s.lines / cfg.linesPerLevel)
    s.lastClear = { kind = kind, lines = cleared, points = points, combo = s.combo, backToBack = b2b, tick = s.tick }
  else
    s.combo = -1
  end

  -- Lock-out: a piece locked entirely above the visible field ends the game.
  if allHidden and cleared == 0 then
    s.gameOver = true
    return
  end
  spawnNext(s)
end

local function tryMove(s, dx, dy)
  local p = s.active
  if not p then return false end
  if collidesAt(s, p.id, p.rotation, p.x + dx, p.y + dy) then return false end
  p.x, p.y = p.x + dx, p.y + dy
  return true
end

local function tryRotate(s, dir)
  local p = s.active
  if not p then return false end
  local to = ((p.rotation + dir) % 4 + 4) % 4
  for _, k in ipairs(Pieces.getKicks(p.id, p.rotation, to)) do
    if not collidesAt(s, p.id, to, p.x + k[1], p.y + k[2]) then
      p.rotation, p.x, p.y = to, p.x + k[1], p.y + k[2]
      return true
    end
  end
  return false
end

local function onManipulate(s)
  if s.lockResets < s.config.maxLockResets then
    s.lockCounter = 0
    s.lockResets = s.lockResets + 1
  end
end

--- Apply one input at the state's current tick. Mutates s. Returns true if it was recorded.
function E.applyInput(s, action)
  if s.gameOver or not s.active then return false end
  local idx = E.ACTION_INDEX[action]
  if not idx then error("Unknown action " .. tostring(action)) end
  local log = s.inputLog
  log[#log + 1] = s.tick
  log[#log + 1] = idx

  if action == "left" or action == "right" then
    if tryMove(s, action == "left" and -1 or 1, 0) then onManipulate(s) end
  elseif action == "rotateCW" or action == "rotateCCW" then
    if tryRotate(s, action == "rotateCW" and 1 or -1) then onManipulate(s) end
  elseif action == "softDrop" then
    if tryMove(s, 0, 1) then
      s.score = s.score + E.SOFT_DROP_POINTS
      s.gravityCounter = 0
    end
  elseif action == "hardDrop" then
    local dist = 0
    while tryMove(s, 0, 1) do dist = dist + 1 end
    s.score = s.score + dist * E.HARD_DROP_POINTS
    lockPiece(s)
  elseif action == "hold" then
    if not s.holdUsed and s.active then
      local current = s.active.id
      s.holdUsed = true
      if s.hold then
        local swap = s.hold
        s.hold = current
        spawn(s, swap)
      else
        s.hold = current
        spawnNext(s)
      end
      s.holdUsed = true
    end
  end
  return true
end

--- Advance one fixed 60 Hz tick: gravity + lock delay. Mutates s.
function E.tick(s)
  if s.gameOver then return end
  s.tick = s.tick + 1
  if not s.active then return end
  if isGrounded(s) then
    s.lockCounter = s.lockCounter + 1
    if s.lockCounter >= s.config.lockDelayTicks then lockPiece(s) end
    return
  end
  s.lockCounter = 0
  s.gravityCounter = s.gravityCounter + 1
  if s.gravityCounter >= E.gravityTicks(s.level) then
    s.gravityCounter = 0
    tryMove(s, 0, 1)
  end
end

--- Landing position of the active piece (or nil).
function E.getGhost(s)
  local p = s.active
  if not p then return nil end
  local y = p.y
  while not collidesAt(s, p.id, p.rotation, p.x, y + 1) do y = y + 1 end
  return { id = p.id, rotation = p.rotation, x = p.x, y = y }
end

--- Re-simulate from seed + flat input log up to untilTick (same semantics as the web replay()).
function E.replay(seed, config, log, untilTick)
  local s = E.createGame(seed, config)
  local i, n = 1, #log
  for k = 3, n, 2 do
    if log[k] < log[k - 2] then error("Input log is not tick-ordered") end
  end
  while s.tick <= untilTick and not s.gameOver do
    while i <= n and log[i] == s.tick do
      E.applyInput(s, E.INPUT_ACTIONS[log[i + 1] + 1])
      i = i + 2
      if s.gameOver then break end
    end
    if s.gameOver or s.tick == untilTick then break end
    E.tick(s)
  end
  return s
end

local function num(n) return format("%.0f", n) end

--- Stable FNV-1a hash over everything that defines the outcome (same string as the web engine).
function E.hashState(s)
  local a = s.active
  local parts = {
    num(s.engineVersion), tostring(s.seed), num(s.tick), num(s.score), num(s.lines), num(s.level),
    num(s.combo), s.backToBack and "1" or "0", num(s.piecesPlaced), s.gameOver and "1" or "0",
    s.hold or "-",
    a and (a.id .. num(a.rotation) .. ":" .. num(a.x) .. "," .. num(a.y)) or "-",
    concat(s.queue, ""), num(s.rngState),
  }
  local b = {}
  for i = 1, #s.board do b[i] = num(s.board[i]) end
  parts[#parts + 1] = concat(b, "")
  local h = Prng.hashString(concat(parts, "|"))
  return format("%08x", h)
end

--- Compact, web-compatible log: same fields as SerializedInputLog in engine.ts.
--- Encoded as "v;seed;startLevel;ticks;t,a t,a ..." (a = action index).
function E.serializeLog(s)
  local out, log = {}, s.inputLog
  for k = 1, #log, 2 do out[#out + 1] = num(log[k]) .. "," .. num(log[k + 1]) end
  return concat({ num(s.engineVersion), tostring(s.seed), num(s.config.startLevel), num(s.tick), concat(out, " ") }, ";")
end

--- Parse a log made by serializeLog. Returns table {v, seed, startLevel, ticks, log} or nil.
function E.deserializeLog(str)
  if type(str) ~= "string" then return nil end
  local v, seed, startLevel, ticks, rest = str:match("^(%d+);([^;]*);(%d+);(%d+);(.*)$")
  if not v then return nil end
  local log = {}
  for t, a in rest:gmatch("(%d+),(%d+)") do
    log[#log + 1] = tonumber(t)
    log[#log + 1] = tonumber(a)
  end
  return { v = tonumber(v), seed = seed, startLevel = tonumber(startLevel), ticks = tonumber(ticks), log = log }
end

ns.Engine = E
return E
