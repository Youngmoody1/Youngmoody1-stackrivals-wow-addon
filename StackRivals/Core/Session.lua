--[[
  StackRivals - one play session: mode rules, countdown, pause, fixed 60 Hz stepping and
  events for sound/visuals. Pure Lua (no WoW API) so it can be tested outside the client.
]]
local _, ns = ...
ns = ns or {}
local E = ns.Engine
local Input = ns.Input

local Session = {}
Session.__index = Session

local STEP = 1 / 60
local MAX_STEPS_PER_FRAME = 8
local MAX_DT = 0.25
local COUNTDOWN_TICKS = 180 -- 3 s before a new run
local RESUME_TICKS = 120 -- 2 s when resuming

--- Game modes. `limitTicks` ends the run on time; `daily` uses one shared seed per UTC day.
Session.MODES = {
  classic = { key = "classic", name = "Classic", short = "Endless - levels speed up every 10 lines" },
  blitz = { key = "blitz", name = "Blitz 2:00", short = "Highest score in two minutes", limitTicks = 7200 },
  daily = { key = "daily", name = "Daily Blitz", short = "Same pieces for every player today", limitTicks = 7200, daily = true },
}
Session.MODE_ORDER = { "classic", "blitz", "daily" }

--- Seed shared by every player for a UTC date string "YYYY-MM-DD".
function Session.dailySeed(dateStr) return "srwow-daily-" .. dateStr end
--- The UTC date a daily seed belongs to (or nil for non-daily seeds).
function Session.dailyDate(seed) return type(seed) == "string" and seed:match("^srwow%-daily%-(%d%d%d%d%-%d%d%-%d%d)$") or nil end

--- `dateStr` = UTC date the run started; records are filed under it (a Daily that ends after
--- midnight UTC still counts for the day its pieces belong to).
function Session.new(modeKey, seed, dateStr)
  local mode = Session.MODES[modeKey] or Session.MODES.classic
  local self = setmetatable({
    mode = mode,
    seed = seed,
    date = Session.dailyDate(seed) or dateStr,
    state = E.createGame(seed, { startLevel = 1 }),
    input = Input.new(),
    phase = "countdown",
    countdown = COUNTDOWN_TICKS,
    acc = 0,
    events = {},
    pauseReason = nil,
    endReason = nil,
    playSeconds = 0,
  }, Session)
  self:emit("count", 3)
  return self
end

--- Rebuild an unfinished run from its saved input log (exact same state), paused.
--- Returns nil if the log is unreadable or from another engine version.
function Session.restore(modeKey, logStr, playSeconds, dateStr)
  local d = E.deserializeLog(logStr)
  if not d or d.v ~= E.ENGINE_VERSION then return nil end
  local okRun, state = pcall(E.replay, d.seed, { startLevel = d.startLevel }, d.log, d.ticks)
  if not okRun or state.gameOver then return nil end
  local self = Session.new(modeKey, d.seed, dateStr)
  self.state = state
  self.events = {}
  self.playSeconds = playSeconds or 0
  self.phase = "paused"
  self.resumePhase = "playing"
  self.pauseReason = "restored"
  return self
end

--- Serialize an unfinished run for SavedVariables, or nil if there is nothing to keep.
function Session:suspendData()
  if self.phase == "over" or self.state.gameOver then return nil end
  if self.state.tick == 0 and #self.state.inputLog == 0 then return nil end
  return { mode = self.mode.key, log = E.serializeLog(self.state), playSeconds = self.playSeconds }
end

function Session:emit(kind, a, b)
  local ev = self.events
  ev[#ev + 1] = { kind = kind, a = a, b = b }
end

--- Take all queued events (for sound and visual effects).
local NO_EVENTS = setmetatable({}, { __newindex = function() error("read-only") end })
function Session:takeEvents()
  local ev = self.events
  if #ev == 0 then return NO_EVENTS end
  self.events = {}
  return ev
end

function Session:timeLeftTicks()
  local lim = self.mode.limitTicks
  if not lim then return nil end
  local left = lim - self.state.tick
  return left > 0 and left or 0
end

function Session:isActive() return self.phase == "playing" or self.phase == "countdown" end

function Session:pause(reason)
  if self.phase == "playing" or self.phase == "countdown" then
    self.resumePhase = self.phase
    self.phase = "paused"
    self.pauseReason = reason or "manual"
    self.input:releaseAll()
    self.acc = 0
    return true
  end
  return false
end

function Session:resume()
  if self.phase ~= "paused" then return false end
  -- Always resume through a short countdown so nobody loses a piece to a surprise restart.
  self.phase = "countdown"
  self.countdown = RESUME_TICKS
  self.pauseReason = nil
  self.acc = 0
  self:emit("count", RESUME_TICKS / 60)
  return true
end

function Session:finish(reason)
  if self.phase == "over" then return end
  self.phase = "over"
  self.endReason = reason
  self.input:releaseAll()
  self:emit("over", reason)
end

--- Key handling from the UI. Only works while the board is live (countdown inputs are ignored).
function Session:press(action)
  if self.phase == "playing" then self.input:press(action) end
end
function Session:release(action) self.input:release(action) end

local function stepOnce(self)
  local s = self.state
  -- plain locals, not a table: this runs 60 times a second
  local bLines, bLevel, bPieces = s.lines, s.level, s.piecesPlaced
  local actions = self.input:drain()
  for i = 1, #actions do
    local a = actions[i]
    local bHoldUsed = s.holdUsed
    if E.applyInput(s, a) then
      if a == "hardDrop" then self:emit("harddrop")
      elseif a == "rotateCW" or a == "rotateCCW" then self:emit("rotate")
      elseif a == "hold" and s.holdUsed and not bHoldUsed then self:emit("hold") end
    end
    if s.gameOver then break end
  end
  if not s.gameOver then E.tick(s) end

  if s.piecesPlaced > bPieces then
    if s.lines > bLines and s.lastClear then
      local c = s.lastClear
      self:emit("clear", c.lines, c)
    else
      self:emit("lock")
    end
  end
  if s.level > bLevel then self:emit("level", s.level) end
  if s.gameOver then
    self:finish("topout")
  elseif self.mode.limitTicks and s.tick >= self.mode.limitTicks then
    self:finish("time")
  end
end

--- Advance by real elapsed seconds. Returns true when something visible changed.
function Session:update(dt)
  if self.phase ~= "playing" and self.phase ~= "countdown" then return false end
  if dt > MAX_DT then dt = MAX_DT end
  self.acc = self.acc + dt
  local changed, n = false, 0
  while self.acc >= STEP and n < MAX_STEPS_PER_FRAME do
    self.acc = self.acc - STEP
    n = n + 1
    if self.phase == "countdown" then
      self.countdown = self.countdown - 1
      if self.countdown <= 0 then
        self.phase = "playing"
        self:emit("go")
      elseif self.countdown % 60 == 0 then
        self:emit("count", self.countdown / 60)
      end
      changed = true
    elseif self.phase == "playing" then
      stepOnce(self)
      self.playSeconds = self.playSeconds + STEP
      changed = true
      if self.phase ~= "playing" then break end
    else
      break
    end
  end
  if n >= MAX_STEPS_PER_FRAME then self.acc = 0 end -- never spiral after a long frame
  return changed
end

--- Countdown number to show (3, 2, 1) or nil.
function Session:countdownNumber()
  if self.phase ~= "countdown" then return nil end
  return math.floor((self.countdown - 1) / 60) + 1
end

ns.Session = Session
return Session
