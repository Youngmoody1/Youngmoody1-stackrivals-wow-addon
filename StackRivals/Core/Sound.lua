--[[
  StackRivals - sound effects. Our own synthesized OGG files (tools/make_sounds.py), played on
  WoW's SFX channel so the player's normal sound settings apply. Fails silently if a client
  refuses a file: sound must never cause a Lua error.
]]
local _, ns = ...
local T = ns.T

local Sound = { enabled = true }
ns.Sound = Sound

local PATH = T.MEDIA .. "Sounds\\"
local last = {}

-- Minimum seconds between two plays of the same sound (rotate spam etc.).
local GATE = { rotate = 0.05, lock = 0.04, harddrop = 0.03 }

function Sound.play(name)
  if not Sound.enabled then return end
  local now = GetTime and GetTime() or 0
  local g = GATE[name]
  if g and last[name] and now - last[name] < g then return end
  last[name] = now
  local file = PATH .. name .. ".ogg"
  if not pcall(PlaySoundFile, file, "SFX") then pcall(PlaySoundFile, file) end
end

--[[ One frame can bring several events (a hard drop that clears a line on a level-up: four sounds at once; a
  duel catching up at low FPS: dozens). Between begin() and flush() requests are collected, and flush plays at
  most ONE impact sound and ONE melodic sound: the most important of each. ]]
local IMPACT = { harddrop = 3, lock = 2, rotate = 1, hold = 1 }
local MELODIC = { record = 9, gameover = 8, clear4 = 7, levelup = 6, clear3 = 5, clear2 = 4, combo = 3, clear1 = 2, go = 1, count = 1 }
local batch
local playNow = Sound.play
function Sound.begin() batch = {} end
function Sound.flush()
  local b = batch
  batch = nil
  if not b then return end
  if b.melodic then playNow(b.melodic) end
  -- a clear already says "the piece landed": no lock / drop thud under it
  if b.impact and not b.clear then playNow(b.impact) end
end
function Sound.play(name)
  if not batch then return playNow(name) end
  if name:find("^clear") then batch.clear = true end
  local kind, rank = "melodic", MELODIC[name]
  if not rank then kind, rank = "impact", IMPACT[name] or 0 end
  if not batch[kind] or rank > batch[kind .. "Rank"] then batch[kind], batch[kind .. "Rank"] = name, rank end
end

--- Map session events to sounds.
function Sound.forEvent(ev)
  local k = ev.kind
  if k == "harddrop" then Sound.play("harddrop")
  elseif k == "rotate" then Sound.play("rotate")
  elseif k == "hold" then Sound.play("hold")
  elseif k == "lock" then Sound.play("lock")
  elseif k == "clear" then
    local n = math.max(1, math.min(4, ev.a or 1))
    Sound.play("clear" .. n)
    local c = ev.b
    if c and (c.combo or 0) >= 1 and n < 4 then Sound.play("combo") end
  elseif k == "level" then Sound.play("levelup")
  elseif k == "count" then Sound.play("count")
  elseif k == "go" then Sound.play("go")
  end
end
