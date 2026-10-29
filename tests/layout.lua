--[[
  Layout resolver for the WoW API mock: turns SetPoint/SetSize/SetAllPoints into absolute
  rectangles (WoW coordinates: origin bottom-left of the main window, y up), so we can
    * check that text and buttons stay inside the window and don't collide (tests), and
    * draw developer previews of each screen (tools/render_preview.py).
  Text size is ESTIMATED from the font size (no real glyph metrics), so the checks are approximate.
]]
local L = {}

local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

-- point name -> horizontal (L|C|R) and vertical (T|C|B) part
local PT = {
  TOPLEFT = { "L", "T" }, TOP = { "C", "T" }, TOPRIGHT = { "R", "T" },
  LEFT = { "L", "C" }, CENTER = { "C", "C" }, RIGHT = { "R", "C" },
  BOTTOMLEFT = { "L", "B" }, BOTTOM = { "C", "B" }, BOTTOMRIGHT = { "R", "B" },
}

local function stripCodes(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return s
end
L.stripCodes = stripCodes

--- Estimated pixel width of one line of text at `size` (Friz Quadrata-like proportions).
function L.textWidth(line, size)
  local w = 0
  for ch in stripCodes(line):gmatch(".") do
    local f
    if ch:match("%u") then f = 0.70
    elseif ch:match("%l") then f = 0.53
    elseif ch:match("%d") then f = 0.58
    elseif ch == " " then f = 0.28
    else f = 0.36 end
    w = w + f * size
  end
  return w
end

local function textLines(fs)
  local txt = fs._text
  if type(txt) ~= "string" or txt == "" then return {}, 0 end
  local size = fs._font and fs._font[2] or 12
  local lines, maxw = {}, 0
  for raw in (txt .. "\n"):gmatch("(.-)\n") do
    if fs._w and fs._w > 0 then
      -- greedy word wrap at the set width
      local cur = ""
      for word in raw:gmatch("%S+") do
        local try = (cur == "") and word or (cur .. " " .. word)
        if cur ~= "" and L.textWidth(try, size) > fs._w then
          lines[#lines + 1] = cur; cur = word
        else
          cur = try
        end
      end
      lines[#lines + 1] = cur
    else
      lines[#lines + 1] = raw
    end
  end
  for _, l in ipairs(lines) do maxw = math.max(maxw, L.textWidth(l, size)) end
  return lines, maxw
end
L.textLines = textLines

function L.new(root)
  local self = { root = root, cache = {} }

  local function size(o)
    if o._kind == "FontString" then
      local lines, maxw = textLines(o)
      local fsz = o._font and o._font[2] or 12
      local w = (o._w and o._w > 0) and o._w or maxw
      local h = (o._h and o._h > 0) and o._h or (#lines * fsz * 1.2)
      return w, h
    end
    return o._w or 0, o._h or 0
  end

  local rect
  rect = function(o)
    if o == root then return { l = 0, r = root._w, b = 0, t = root._h } end
    local c = self.cache[o]
    if c then return c end
    local parent = o._parent
    local pts = o._points
    local out
    if pts[1] == "ALL" then
      local rr = rect(o._allRel or parent)
      out = { l = rr.l, r = rr.r, b = rr.b, t = rr.t }
    else
      local H, V = {}, {}
      for _, p in ipairs(pts) do
        local point, rel, relPoint, x, y = p[1], nil, nil, 0, 0
        if type(p[2]) == "table" then
          rel = p[2]
          if type(p[3]) == "string" then relPoint, x, y = p[3], p[4] or 0, p[5] or 0
          else relPoint, x, y = point, p[3] or 0, p[4] or 0 end
        elseif type(p[2]) == "number" then
          x, y = p[2], p[3] or 0
        end
        rel = rel or parent
        relPoint = relPoint or point
        local rr = rect(rel)
        local rp = PT[relPoint]
        local ax = (rp[1] == "L" and rr.l) or (rp[1] == "R" and rr.r) or (rr.l + rr.r) / 2
        local ay = (rp[2] == "B" and rr.b) or (rp[2] == "T" and rr.t) or (rr.b + rr.t) / 2
        local mp = PT[point]
        H[mp[1]] = ax + x
        V[mp[2]] = ay + y
      end
      local w, h = size(o)
      local l, r, b, t
      if H.L and H.R then l, r = H.L, H.R
      elseif H.L then l, r = H.L, H.L + w
      elseif H.R then l, r = H.R - w, H.R
      elseif H.C then l, r = H.C - w / 2, H.C + w / 2
      else l, r = 0, w end
      if V.B and V.T then b, t = V.B, V.T
      elseif V.T then b, t = V.T - h, V.T
      elseif V.B then b, t = V.B, V.B + h
      elseif V.C then b, t = V.C - h / 2, V.C + h / 2
      else b, t = 0, h end
      out = { l = l, r = r, b = b, t = t }
    end
    self.cache[o] = out
    return out
  end
  self.rect = rect

  --- Visible = itself and every ancestor shown (up to the root).
  function self.visible(o)
    local cur = o
    while cur do
      if not cur._shown then return false end
      if cur == root then return true end
      cur = cur._parent
    end
    return false
  end

  --- True if `o` is the root or below it.
  function self.inside(o)
    local cur = o
    while cur do
      if cur == root then return true end
      cur = cur._parent
    end
    return false
  end

  --- Effective alpha (product of own and ancestors' alpha).
  function self.alpha(o)
    local a, cur = 1, o
    while cur do
      a = a * (cur._alpha or 1)
      if cur == root then break end
      cur = cur._parent
    end
    return a
  end

  --- Owning frame level for draw order.
  function self.level(o)
    if o._kind == "Texture" or o._kind == "FontString" then return o._parent._level or 0 end
    return o._level or 0
  end
  return self
end

--- All visible drawable regions under `root`, in draw order.
function L.collect(M, root)
  local R = L.new(root)
  local items = {}
  for _, o in ipairs(M.regions) do
    if R.inside(o) and R.visible(o) then items[#items + 1] = o end
  end
  table.sort(items, function(a, b)
    local la, lb = R.level(a), R.level(b)
    if la ~= lb then return la < lb end
    local ya, yb = LAYER[a._layer] or 3, LAYER[b._layer] or 3
    if ya ~= yb then return ya < yb end
    if (a._sub or 0) ~= (b._sub or 0) then return (a._sub or 0) < (b._sub or 0) end
    return a._order < b._order
  end)
  return R, items
end

--- Every visible Button under root.
function L.buttons(M, R)
  local out = {}
  for _, f in ipairs(M.frames) do
    if f._kind == "Button" and R.inside(f) and R.visible(f) then out[#out + 1] = f end
  end
  return out
end

--- Write a flat dump for tools/render_preview.py.
function L.dump(path, root, R, items, title)
  local fh = assert(io.open(path, "w"))
  fh:write(string.format("SIZE\t%d\t%d\t%s\n", root._w, root._h, title or ""))
  for _, o in ipairs(items) do
    local rc = R.rect(o)
    local a = R.alpha(o)
    if o._kind == "Texture" then
      if o._tex then
        fh:write(string.format("IMG\t%.1f\t%.1f\t%.1f\t%.1f\t%.3f\t%s\n", rc.l, rc.b, rc.r, rc.t, a, o._tex))
      elseif o._r then
        fh:write(string.format("RECT\t%.1f\t%.1f\t%.1f\t%.1f\t%.3f\t%.3f\t%.3f\t%.3f\n", rc.l, rc.b, rc.r, rc.t, o._r, o._g, o._b, (o._a or 1) * a))
      end
    else
      local lines = textLines(o)
      if #lines > 0 then
        local fsz = o._font and o._font[2] or 12
        fh:write(string.format("TEXT\t%.1f\t%.1f\t%.1f\t%.1f\t%.3f\t%.3f\t%.3f\t%.3f\t%d\t%s\t%s\t%s\n", rc.l, rc.b, rc.r, rc.t,
          o._tr or 1, o._tg or 1, o._tb or 1, a, fsz, o._justify or "CENTER", (o._font and o._font[3]) or "",
          stripCodes(table.concat(lines, "\\n")):gsub("\t", " ")))
      end
    end
  end
  fh:close()
end

return L
