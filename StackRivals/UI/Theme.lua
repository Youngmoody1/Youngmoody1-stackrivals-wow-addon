--[[
  StackRivals - visual identity for WoW, matched to the website's design tokens
  (stackrivals.io src/styles.css + src/components/brand/BrandMark.tsx):
    navy background, red = the player / primary actions, steel blue = the rival / secondary,
    gold = records, green = success. Display type: Chakra Petch (the site's display font, bundled
    under the SIL Open Font License, Media/Fonts/OFL-ChakraPetch.txt). Body text stays in WoW's
    own font so every client locale renders it.
  Flat textures + fonts only; animations are AnimationGroups on frames (run by the client, no
  per-frame Lua).
]]
local ADDON, ns = ...

local T = {}
ns.T = T

local function hex(h)
  return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
T.hex = hex

-- Web tokens (names in comments)
T.C = {
  ink = { hex("0B0C10") },        -- --brand-ink
  navy = { hex("0A0E1A") },       -- --background
  surface1 = { hex("121A2E") },   -- --card
  surface2 = { hex("10162A") },   -- --surface
  raised = { hex("182036") },     -- --surface-raised
  cell = { hex("141B2D") },       -- empty board cell (between --grid and --surface)
  line = { hex("27324F") },       -- --border on navy, a touch stronger for 1px WoW lines
  red = { hex("E0242F") },        -- --brand-red
  redLight = { hex("FF4D5A") },   -- --brand-red-text (small red text)
  redDeep = { hex("7E121A") },    -- --brand-red-deep
  steel = { hex("4FA8FF") },      -- --brand-steel (rival)
  steelDeep = { hex("1D4E80") },  -- steel button fill
  gold = { hex("F2CF6B") },       -- --brand-gold (records)
  goldDeep = { hex("4A3A12") },
  green = { hex("7BE3A0") },      -- --brand-green
  violet = { hex("B98CF0") },
  paper = { hex("F6F4F0") },      -- --foreground
  body = { hex("CDD2DC") },
  label = { hex("A3ABBA") },      -- --muted-foreground
  dim = { hex("6E7789") },
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
T.DISPLAY = T.MEDIA .. "Fonts\\ChakraPetch-Bold.ttf"
T.DISPLAY_ITALIC = T.MEDIA .. "Fonts\\ChakraPetch-BoldItalic.ttf"

-- Type scale (window units; the window itself is scaled to the screen, see UI:ApplyScale).
-- Nothing visible is smaller than `label`.
T.SIZE = { hero = 36, display = 26, title = 19, heading = 16, big = 15, body = 13, small = 12, label = 11 }

--- Set a font, falling back to WoW's font if the file can't be loaded (never invisible text).
function T.setFont(fs, path, size, flags)
  fs:SetFont(path, size, flags or "")
  if path ~= T.FONT and not fs:GetFont() then fs:SetFont(T.FONT, size, flags or "") end
end

--- Font string. kind: nil = body font, "display" = Chakra Petch Bold, "italic" = Bold Italic.
function T.text(parent, size, c, flags, layer, kind)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  local path = (kind == "display" and T.DISPLAY) or (kind == "italic" and T.DISPLAY_ITALIC) or T.FONT
  T.setFont(fs, path, size or T.SIZE.body, flags)
  c = c or T.C.paper
  fs:SetTextColor(c[1], c[2], c[3], 1)
  fs:SetShadowColor(0, 0, 0, 0.85)
  fs:SetShadowOffset(1, -1)
  return fs
end

--- Display-font shortcut (headings, numbers, buttons).
function T.display(parent, size, c, flags, layer) return T.text(parent, size, c, flags, layer, "display") end

--- Small uppercase label (muted).
function T.label(parent, txt, size)
  local fs = T.display(parent, size or T.SIZE.label, T.C.label)
  fs:SetText(txt)
  return fs
end

--- Panel: card surface, 1px hairline border, optional coloured top edge-light.
function T.panel(parent, edge, alpha)
  local f = CreateFrame("Frame", nil, parent)
  local bg = T.tex(f, "BACKGROUND", T.C.surface1, alpha or 0.94)
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

--- Solid colour texture.
function T.tex(parent, layer, c, a, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

local STYLES = {
  primary = { bg = T.C.red, hover = { hex("EA3A44") }, text = T.C.paper, border = T.C.red }, -- hover keeps text contrast
  steel = { bg = T.C.steelDeep, hover = { hex("2A69A8") }, text = T.C.paper, border = T.C.steel },
  frame = { bg = T.C.surface2, hover = T.C.raised, text = T.C.paper, border = T.C.line },
  gold = { bg = T.C.goldDeep, hover = { hex("54421A") }, text = T.C.gold, border = T.C.gold },
}
T.STYLES = STYLES

--- Flat brand button. style: primary | steel | frame | gold.
function T.button(parent, label, w, h, style, onClick)
  local st = STYLES[style or "frame"]
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 120, h or 28)
  local border = T.tex(b, "BACKGROUND", st.border, 1)
  border:SetAllPoints()
  local bg = T.tex(b, "BORDER", st.bg, 1)
  bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
  local fs = T.display(b, (h or 28) >= 30 and T.SIZE.big or T.SIZE.small, st.text)
  fs:SetPoint("CENTER", 0, 0)
  fs:SetText(label)
  b.fs, b.bgTex, b.border, b.style = fs, bg, border, st
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
function T.toggle(parent, labelText, onChange, width)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 230, 24)
  local box = T.tex(b, "BORDER", T.C.line, 1)
  box:SetSize(16, 16); box:SetPoint("LEFT", 0, 0)
  local inner = T.tex(b, "ARTWORK", T.C.surface2, 1)
  inner:SetSize(14, 14); inner:SetPoint("CENTER", box, "CENTER")
  local fill = T.tex(b, "OVERLAY", T.C.red, 1)
  fill:SetSize(10, 10); fill:SetPoint("CENTER", box, "CENTER")
  local fs = T.text(b, T.SIZE.body, T.C.body)
  fs:SetPoint("LEFT", box, "RIGHT", 9, 0)
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

--- A keycap: small framed box with a key name (How to play, controls strip).
function T.keycap(parent, key, minW)
  local f = CreateFrame("Frame", nil, parent)
  local fs = T.display(f, T.SIZE.small, T.C.paper)
  fs:SetPoint("CENTER", 0, 1)
  local bg = T.tex(f, "BACKGROUND", T.C.raised, 1); bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
  local border = T.tex(f, "BORDER", T.C.line, 1, -1); border:SetAllPoints()
  local base = T.tex(f, "ARTWORK", T.C.line, 1); base:SetPoint("BOTTOMLEFT", 1, 1); base:SetPoint("BOTTOMRIGHT", -1, 1); base:SetHeight(2)
  f.fs = fs
  f.minW = minW or 30
  function f:SetKey(k)
    self.fs:SetText(k)
    -- width from the key name (estimated; Chakra Petch caps ~0.62 em)
    self:SetSize(math.max(self.minW, #k * 7.6 + 14), 22)
  end
  f:SetKey(key or "")
  return f
end

------------------------------------------------------------------------------------------------
-- Animations (AnimationGroups: driven by the client, cheap, nothing runs in Lua per frame)
------------------------------------------------------------------------------------------------
local function anim(group, kind, dur, order, delay)
  local a = group:CreateAnimation(kind)
  a:SetDuration(dur)
  a:SetOrder(order or 1)
  if delay then a:SetStartDelay(delay) end
  a:SetSmoothing("OUT")
  return a
end

--- Pop: scale from `from` to 1 while fading in, hold, then fade out (callouts, score pops).
--- `rise` moves it up while it fades; fade = false keeps it on screen. Returns the AnimationGroup.
function T.popAnim(frame, from, hold, fade, rise)
  local g = frame:CreateAnimationGroup()
  local s = anim(g, "Scale", 0.16, 1)
  if s.SetScaleFrom then s:SetScaleFrom(from or 1.35, from or 1.35); s:SetScaleTo(1, 1) end
  local a = anim(g, "Alpha", 0.12, 1)
  a:SetFromAlpha(0); a:SetToAlpha(1)
  if fade == false then g:SetToFinalAlpha(true); return g end
  local out = anim(g, "Alpha", fade or 0.35, 2, hold or 0.7)
  out:SetFromAlpha(1); out:SetToAlpha(0)
  if rise then
    local t = anim(g, "Translation", (hold or 0.7) + (fade or 0.35), 2)
    t:SetOffset(0, rise)
  end
  g:SetToFinalAlpha(true)
  return g
end

--- Pulse: quick scale bump and back (score, timer). `origin` keeps an edge still ("LEFT" for
--- left-aligned numbers, so they don't slide sideways).
function T.pulseAnim(frame, amount, dur, origin)
  local g = frame:CreateAnimationGroup()
  local up = anim(g, "Scale", (dur or 0.24) * 0.4, 1)
  if up.SetScaleFrom then up:SetScaleFrom(1, 1); up:SetScaleTo(amount or 1.18, amount or 1.18) end
  local down = anim(g, "Scale", (dur or 0.24) * 0.6, 2)
  if down.SetScaleFrom then down:SetScaleFrom(amount or 1.18, amount or 1.18); down:SetScaleTo(1, 1) end
  if origin then up:SetOrigin(origin, 0, 0); down:SetOrigin(origin, 0, 0) end
  return g
end

--- Thump: a short downward nudge and back (hard-drop impact on the board).
function T.thumpAnim(frame, px)
  local g = frame:CreateAnimationGroup()
  local d = anim(g, "Translation", 0.05, 1); d:SetOffset(0, -(px or 2))
  local u = anim(g, "Translation", 0.08, 2); u:SetOffset(0, px or 2)
  return g
end

--- Fade in (overlays).
function T.fadeInAnim(frame, dur)
  local g = frame:CreateAnimationGroup()
  local a = anim(g, "Alpha", dur or 0.25, 1)
  a:SetFromAlpha(0); a:SetToAlpha(1)
  return g
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

--- seconds -> "m:ss" under an hour, "1h 05m" from an hour on (lifetime play time)
function T.duration(sec)
  sec = math.max(0, math.floor(sec or 0))
  if sec < 3600 then return T.clock(sec) end
  return string.format("%dh %02dm", math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end

--- seconds -> "m:ss"
function T.clock(sec)
  sec = math.max(0, math.floor(sec + 0.0001))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--- Friendly name for a WoW key code.
local KEY_NAMES = {
  LEFT = "Left", RIGHT = "Right", UP = "Up", DOWN = "Down", SPACE = "Space", ESCAPE = "Esc",
  LSHIFT = "L-Shift", RSHIFT = "R-Shift", LCTRL = "L-Ctrl", RCTRL = "R-Ctrl", LALT = "L-Alt", RALT = "R-Alt",
  ENTER = "Enter", TAB = "Tab", BACKSPACE = "Backspace",
}
function T.keyName(k) return KEY_NAMES[k] or k or "-" end
