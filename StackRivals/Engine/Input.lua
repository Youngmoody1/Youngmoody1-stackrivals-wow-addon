--[[
  StackRivals - held-key bookkeeping (port of InputHandler in src/game/controls.ts).
  Turns key down/up into discrete engine actions per tick with the same DAS/ARR as the web game.
  Pure Lua, no WoW API.
]]
local _, ns = ...
ns = ns or {}

local Input = {}
Input.__index = Input

Input.HANDLING = { dasTicks = 10, arrTicks = 2, softDropTicks = 2 }

function Input.new()
  return setmetatable({
    pending = {},
    heldDir = nil, heldFor = 0,
    softHeld = false, softFor = 0,
    pressed = {},
  }, Input)
end

function Input:press(action)
  if action == "left" or action == "right" then
    self.pressed[action] = true
    self.heldDir, self.heldFor = action, 0
    self.pending[#self.pending + 1] = action
  elseif action == "softDrop" then
    if not self.softHeld then self.pending[#self.pending + 1] = "softDrop" end
    self.softHeld = true
    self.softFor = 0
  else
    self.pending[#self.pending + 1] = action
  end
end

function Input:release(action)
  if action == "left" or action == "right" then
    self.pressed[action] = nil
    if self.heldDir == action then
      local other = (action == "left") and "right" or "left"
      if self.pressed[other] then self.heldDir, self.heldFor = other, 0
      else self.heldDir, self.heldFor = nil, 0 end
    end
  elseif action == "softDrop" then
    self.softHeld = false
  end
end

function Input:releaseAll()
  self.pressed = {}
  self.heldDir, self.heldFor = nil, 0
  self.softHeld = false
  self.pending = {}
end

--- Actions to apply on this tick.
function Input:drain()
  local out = self.pending
  self.pending = {}
  local H = Input.HANDLING
  if self.heldDir then
    self.heldFor = self.heldFor + 1
    local t = self.heldFor - H.dasTicks
    if t >= 0 and t % H.arrTicks == 0 then out[#out + 1] = self.heldDir end
  end
  if self.softHeld then
    self.softFor = self.softFor + 1
    if self.softFor % H.softDropTicks == 0 then out[#out + 1] = "softDrop" end
  end
  return out
end

ns.Input = Input
return Input
