--[[
  StackRivals - playfield and piece previews drawn with plain textures.
  Cells are created once and recoloured only when the game state changes (dirty flag in the
  window), so idle CPU cost is zero and a busy frame is ~200 texture colour updates.
]]
local _, ns = ...
local T = ns.T
local P = ns.Pieces
local E = ns.Engine

local Board = {}
ns.Board = Board

local function makeCell(parent, size)
  local c = {}
  c.base = parent:CreateTexture(nil, "ARTWORK", nil, 1)
  c.base:SetSize(size, size)
  local hl = math.max(2, math.floor(size / 6))
  c.hi = parent:CreateTexture(nil, "ARTWORK", nil, 2)
  c.hi:SetPoint("TOPLEFT", c.base, "TOPLEFT"); c.hi:SetPoint("TOPRIGHT", c.base, "TOPRIGHT"); c.hi:SetHeight(hl)
  c.hi:SetColorTexture(1, 1, 1, 0.28)
  c.lo = parent:CreateTexture(nil, "ARTWORK", nil, 2)
  c.lo:SetPoint("BOTTOMLEFT", c.base, "BOTTOMLEFT"); c.lo:SetPoint("BOTTOMRIGHT", c.base, "BOTTOMRIGHT"); c.lo:SetHeight(hl)
  c.lo:SetColorTexture(0, 0, 0, 0.32)
  c.value = -1
  return c
end

local EMPTY = T.C.cell
-- mode: 0 empty, 1 solid block, 2 ghost
local function paint(c, value, mode)
  local key = value * 4 + mode
  if c.value == key then return end
  c.value = key
  if mode == 0 then
    c.base:SetColorTexture(EMPTY[1], EMPTY[2], EMPTY[3], 1)
    c.hi:Hide(); c.lo:Hide()
  elseif mode == 2 then
    local col = T.PIECE[value]
    c.base:SetColorTexture(col[1] * 0.55, col[2] * 0.55, col[3] * 0.55, 0.45)
    c.hi:Hide(); c.lo:Hide()
  else
    local col = T.PIECE[value] or T.PIECE[8]
    c.base:SetColorTexture(col[1], col[2], col[3], 1)
    c.hi:Show(); c.lo:Show()
  end
end

--- Playfield frame: width x visibleRows cells of `cell` px with 1px gaps.
function Board.createField(parent, width, rows, cell)
  local f = CreateFrame("Frame", nil, parent)
  local gap = 1
  f:SetSize(width * (cell + gap) + gap, rows * (cell + gap) + gap)
  local bg = T.tex(f, "BACKGROUND", T.C.ink, 1)
  bg:SetAllPoints()
  f.cells = {}
  for y = 0, rows - 1 do
    for x = 0, width - 1 do
      local c = makeCell(f, cell)
      c.base:SetPoint("TOPLEFT", f, "TOPLEFT", gap + x * (cell + gap), -(gap + y * (cell + gap)))
      paint(c, 0, 0)
      f.cells[y * width + x + 1] = c
    end
  end
  f.width, f.rows = width, rows
  f.overlay = {} -- reused per render: index -> value*4+mode

  -- full-board flash for line clears
  f.flash = f:CreateTexture(nil, "OVERLAY")
  f.flash:SetAllPoints()
  f.flash:SetColorTexture(1, 1, 1, 1)
  f.flash:SetAlpha(0)
  return f
end

--- Draw the game state (board + ghost + active piece).
function Board.renderField(f, s, showGhost)
  local w, hidden = s.config.width, s.config.hiddenRows
  local rows = f.rows
  local ov = f.overlay
  for k in pairs(ov) do ov[k] = nil end
  local a = s.active
  if a then
    if showGhost then
      local g = E.getGhost(s)
      if g and g.y ~= a.y then
        for _, c in ipairs(P.SHAPES[g.id][g.rotation + 1]) do
          local x, y = g.x + c[1], g.y + c[2] - hidden
          if y >= 0 and y < rows then ov[y * w + x + 1] = P.INDEX[g.id] * 4 + 2 end
        end
      end
    end
    for _, c in ipairs(P.SHAPES[a.id][a.rotation + 1]) do
      local x, y = a.x + c[1], a.y + c[2] - hidden
      if y >= 0 and y < rows then ov[y * w + x + 1] = P.INDEX[a.id] * 4 + 1 end
    end
  end
  local board = s.board
  for y = 0, rows - 1 do
    local by = (y + hidden) * w
    for x = 0, w - 1 do
      local i = y * w + x + 1
      local o = ov[i]
      if o then
        paint(f.cells[i], math.floor(o / 4), o % 4)
      else
        local v = board[by + x + 1]
        if v ~= 0 then paint(f.cells[i], v, 1) else paint(f.cells[i], 0, 0) end
      end
    end
  end
end

--- Small 4x4 preview box for hold/next.
function Board.createPreview(parent, cell)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(4 * cell + 3, 4 * cell + 3)
  f.cells = {}
  f.cell = cell
  for i = 1, 4 do
    local c = makeCell(f, cell)
    c.base:Hide(); c.hi:Hide(); c.lo:Hide()
    f.cells[i] = c
  end
  return f
end

--- Show piece `id` centred in the preview (nil clears). `dim` greys it (hold already used).
function Board.renderPreview(f, id, dim)
  if f.id == id and f.dim == dim then return end
  f.id, f.dim = id, dim
  for _, c in ipairs(f.cells) do c.base:Hide(); c.hi:Hide(); c.lo:Hide(); c.value = -1 end
  if not id then return end
  local shape = P.SHAPES[id][1]
  local minx, maxx, miny, maxy = 9, -9, 9, -9
  for _, c in ipairs(shape) do
    minx, maxx = math.min(minx, c[1]), math.max(maxx, c[1])
    miny, maxy = math.min(miny, c[2]), math.max(maxy, c[2])
  end
  local cs = f.cell + 1
  local bw, bh = (maxx - minx + 1) * cs, (maxy - miny + 1) * cs
  local ox, oy = (f:GetWidth() - bw) / 2, (f:GetHeight() - bh) / 2
  local col = T.PIECE[P.INDEX[id]]
  for i, c in ipairs(shape) do
    local cell = f.cells[i]
    cell.base:ClearAllPoints()
    cell.base:SetPoint("TOPLEFT", f, "TOPLEFT", ox + (c[1] - minx) * cs, -(oy + (c[2] - miny) * cs))
    local m = dim and 0.35 or 1
    cell.base:SetColorTexture(col[1] * m, col[2] * m, col[3] * m, 1)
    cell.base:Show()
    if not dim then cell.hi:Show(); cell.lo:Show() end
  end
end
