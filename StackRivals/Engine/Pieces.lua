--[[
  StackRivals - piece set (port of src/game/engine/pieces.ts).
  Seven original-named shapes. Colours live in the theme, never here.
]]
local _, ns = ...
ns = ns or {}

local Pieces = {}

Pieces.IDS = { "bar", "cube", "tee", "hook", "jack", "zig", "zag" }
Pieces.INDEX = {}
for i, id in ipairs(Pieces.IDS) do Pieces.INDEX[id] = i end

--- Board cell value: 0 = empty, 1..7 = piece index, 8 = garbage.
function Pieces.cellValue(id) return Pieces.INDEX[id] end

-- Spawn-orientation layouts inside an N x N box (y grows downward), 0-based coordinates.
local BASE = {
  bar = { size = 4, cells = { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } } },
  cube = { size = 2, cells = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } },
  tee = { size = 3, cells = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } } },
  hook = { size = 3, cells = { { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } } },
  jack = { size = 3, cells = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } } },
  zig = { size = 3, cells = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } } },
  zag = { size = 3, cells = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } } },
}

local function rotateCW(cells, size)
  local out = {}
  for i, c in ipairs(cells) do out[i] = { size - 1 - c[2], c[1] } end
  return out
end

--- SHAPES[id][rotation + 1] = list of {x, y}. Rotation is 0..3 like the web engine.
Pieces.SHAPES = {}
Pieces.SIZE = {}
for _, id in ipairs(Pieces.IDS) do
  local b = BASE[id]
  local rots = { b.cells }
  for r = 2, 4 do rots[r] = (id == "cube") and b.cells or rotateCW(rots[r - 1], b.size) end
  Pieces.SHAPES[id] = rots
  Pieces.SIZE[id] = b.size
end

-- Wall-kick offsets (x, y with y downward) tried in order when rotating from>to.
local KICKS_3 = {
  ["0>1"] = { { 0, 0 }, { -1, 0 }, { -1, -1 }, { 0, 2 }, { -1, 2 } },
  ["1>0"] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, -2 }, { 1, -2 } },
  ["1>2"] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, -2 }, { 1, -2 } },
  ["2>1"] = { { 0, 0 }, { -1, 0 }, { -1, -1 }, { 0, 2 }, { -1, 2 } },
  ["2>3"] = { { 0, 0 }, { 1, 0 }, { 1, -1 }, { 0, 2 }, { 1, 2 } },
  ["3>2"] = { { 0, 0 }, { -1, 0 }, { -1, 1 }, { 0, -2 }, { -1, -2 } },
  ["3>0"] = { { 0, 0 }, { -1, 0 }, { -1, 1 }, { 0, -2 }, { -1, -2 } },
  ["0>3"] = { { 0, 0 }, { 1, 0 }, { 1, -1 }, { 0, 2 }, { 1, 2 } },
}
local KICKS_BAR = {
  ["0>1"] = { { 0, 0 }, { -2, 0 }, { 1, 0 }, { -2, 1 }, { 1, -2 } },
  ["1>0"] = { { 0, 0 }, { 2, 0 }, { -1, 0 }, { 2, -1 }, { -1, 2 } },
  ["1>2"] = { { 0, 0 }, { -1, 0 }, { 2, 0 }, { -1, -2 }, { 2, 1 } },
  ["2>1"] = { { 0, 0 }, { 1, 0 }, { -2, 0 }, { 1, 2 }, { -2, -1 } },
  ["2>3"] = { { 0, 0 }, { 2, 0 }, { -1, 0 }, { 2, -1 }, { -1, 2 } },
  ["3>2"] = { { 0, 0 }, { -2, 0 }, { 1, 0 }, { -2, 1 }, { 1, -2 } },
  ["3>0"] = { { 0, 0 }, { 1, 0 }, { -2, 0 }, { 1, 2 }, { -2, -1 } },
  ["0>3"] = { { 0, 0 }, { -1, 0 }, { 2, 0 }, { -1, -2 }, { 2, 1 } },
}
local NO_KICK = { { 0, 0 } }

function Pieces.getKicks(id, from, to)
  if id == "cube" then return NO_KICK end
  local t = (id == "bar") and KICKS_BAR or KICKS_3
  return t[from .. ">" .. to]
end

ns.Pieces = Pieces
return Pieces
