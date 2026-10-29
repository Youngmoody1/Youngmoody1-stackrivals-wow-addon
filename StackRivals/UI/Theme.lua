--[[
  StackRivals - visual identity for WoW (from the web design system, docs/DESIGN.md):
  navy foundation, red = the player / primary actions, steel = secondary, gold = records,
  green = success. Built only from flat textures and WoW's own fonts: no external assets.
]]
local ADDON, ns = ...

local T = {}
ns.T = T

local function hex(h)
  return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
T.hex = hex

T.C = {
  ink = { hex("0B0C10") },
  navy = { hex("0A0E1A") },
  surface1 = { hex("171A21") },
  surface2 = { hex("10121A") },
  cell = { hex("13161D") },
  line = { hex("2A3350") },
  red = { hex("E0242F") },
  redLight = { hex("FF4D5A") },
  redDeep = { hex("7E121A") },
  steel = { hex("8FC0DD") },
  steelDeep = { hex("3D6A86") },
  gold = { hex("F2CF6B") },
  green = { hex("7BE3A0") },
  violet = { hex("B98CF0") },
  paper = { hex("F6F4F0") },
  body = { hex("B6BCC7") },
  label = { hex("7F8794") },
}

-- "Circuit" block skin (the web default), converted from its oklch values to sRGB.
-- Order matches Pieces.IDS: bar, cube, tee, hook, jack, zig, zag; 8 = garbage.
T.PIECE = {
  { 1.000, 0.271, 0.285 },
  { 0.301, 0.857, 1.000 },
  { 1.000, 0.801, 0.155 },
  { 0.167, 0.868, 0.642 },
  { 0.901, 0.374, 0.870 },
  { 0.983, 0.915, 0.776 },
  { 0.394, 0.488, 1.000 },
  { 0.420, 0.450, 0.520 },
}

T.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
T.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

--- Solid colour texture.
function T.tex(parent, layer, c, a, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

--- Font string with the addon's type settings.
function T.text(parent, size, c, flags, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(T.FONT, size or 12, flags or "")
  c = c or T.C.paper
  fs:SetTextColor(c[1], c[2], c[3], 1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetShadowOffset(1, -1)
  return fs
end

--- Uppercase mono-style label (letter-spaced feel via spaces is avoided: keep it readable).
function T.label(parent, txt, size)
  local fs = T.text(parent, size or 10, T.C.label)
  fs:SetText(txt)
  return fs
end

--- Panel: dark surface, 1px hairline border, optional coloured top edge-light.
function T.panel(parent, edge, alpha)
  local f = CreateFrame("Frame", nil, parent)
  local bg = T.tex(f, "BACKGROUND", T.C.surface1, alpha or 0.92)
  bg:SetAllPoints()
  f.bg = bg
  local function line(p1, p2, w, h)
    local l = T.tex(f, "BORDER", T.C.line, 1)
    l:SetPoint(p1); l:SetPoint(p2)
    if w then l:SetWidth(w) end
    if h then l:SetHeight(h) end
    return l
  end
  line("TOPLEFT", "TOPRIGHT", nil, 1)
  line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  line("TOPLEFT", "BOTTOMLEFT", 1, nil)
  line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
  if edge then
    local e = T.tex(f, "ARTWORK", edge, 1)
    e:SetPoint("TOPLEFT"); e:SetPoint("TOPRIGHT"); e:SetHeight(2)
    f.edge = e
  end
  return f
end

local STYLES = {
  primary = { bg = T.C.red, hover = T.C.redLight, text = T.C.paper, border = T.C.red },
  steel = { bg = T.C.steelDeep, hover = T.C.steel, text = T.C.paper, border = T.C.steel },
  frame = { bg = T.C.surface2, hover = T.C.surface1, text = T.C.paper, border = T.C.line },
  gold = { bg = { 0.35, 0.28, 0.08 }, hover = { 0.5, 0.4, 0.12 }, text = T.C.gold, border = T.C.gold },
}

--- Flat brand button. style: primary | steel | frame | gold.
function T.button(parent, label, w, h, style, onClick)
  local st = STYLES[style or "frame"]
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 120, h or 26)
  local border = T.tex(b, "BACKGROUND", st.border, 1)
  border:SetAllPoints()
  local bg = T.tex(b, "BORDER", st.bg, 1)
  bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
  local fs = T.text(b, 12, st.text, "")
  fs:SetPoint("CENTER", 0, 0)
  fs:SetText(label)
  b.fs, b.bgTex, b.style = fs, bg, st
  b:SetScript("OnEnter", function(self)
    if self:IsEnabled() then self.bgTex:SetColorTexture(st.hover[1], st.hover[2], st.hover[3], 1) end
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.bgTex:SetColorTexture(st.bg[1], st.bg[2], st.bg[3], 1)
    if self.tip then GameTooltip:Hide() end
  end)
  b:SetScript("OnMouseDown", function(self) if self:IsEnabled() and not self.noPress then self.fs:SetPoint("CENTER", 1, -1) end end)
  b:SetScript("OnMouseUp", function(self) if not self.noPress then self.fs:SetPoint("CENTER", 0, 0) end end)
  b:SetScript("OnDisable", function(self) self.fs:SetAlpha(0.4); self.bgTex:SetAlpha(0.5) end)
  b:SetScript("OnEnable", function(self) self.fs:SetAlpha(1); self.bgTex:SetAlpha(1) end)
  if onClick then b:SetScript("OnClick", onClick) end
  function b:SetLabel(t) self.fs:SetText(t) end
  return b
end

--- On/off switch row: "[x] Label". Calls onChange(newValue).
function T.toggle(parent, labelText, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(220, 20)
  local box = T.tex(b, "BORDER", T.C.line, 1)
  box:SetSize(14, 14); box:SetPoint("LEFT", 0, 0)
  local inner = T.tex(b, "ARTWORK", T.C.surface2, 1)
  inner:SetSize(12, 12); inner:SetPoint("CENTER", box, "CENTER")
  local fill = T.tex(b, "OVERLAY", T.C.red, 1)
  fill:SetSize(8, 8); fill:SetPoint("CENTER", box, "CENTER")
  local fs = T.text(b, 12, T.C.body)
  fs:SetPoint("LEFT", box, "RIGHT", 8, 0)
  fs:SetText(labelText)
  b.value = false
  function b:SetValue(v) self.value = v and true or false; fill:SetShown(self.value) end
  b:SetScript("OnClick", function(self)
    self:SetValue(not self.value)
    if onChange then onChange(self.value) end
  end)
  b:SetScript("OnEnter", function() fs:SetTextColor(T.C.paper[1], T.C.paper[2], T.C.paper[3]) end)
  b:SetScript("OnLeave", function() fs:SetTextColor(T.C.body[1], T.C.body[2], T.C.body[3]) end)
  return b
end

--- 12345678 -> "12,345,678"
function T.commas(n)
  local s = string.format("%d", math.floor(n or 0))
  local out, k = s, 0
  repeat out, k = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
  return out
end

--- 1 -> "1 try", 3 -> "3 tries"
function T.plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

--- seconds -> "m:ss"
function T.clock(sec)
  sec = math.max(0, math.floor(sec + 0.0001))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--- Friendly name for a WoW key code ("LEFT" -> "Left Arrow").
local KEY_NAMES = {
  LEFT = "Left", RIGHT = "Right", UP = "Up", DOWN = "Down", SPACE = "Space", ESCAPE = "Esc",
  LSHIFT = "L-Shift", RSHIFT = "R-Shift", LCTRL = "L-Ctrl", RCTRL = "R-Ctrl", LALT = "L-Alt", RALT = "R-Alt",
  ENTER = "Enter", TAB = "Tab", BACKSPACE = "Backspace",
}
function T.keyName(k) return KEY_NAMES[k] or k or "-" end
