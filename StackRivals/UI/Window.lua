--[[
  StackRivals - main game window.

  Keyboard rule: the window only takes the keyboard while a run is live (countdown or playing)
  or while you rebind a key. Paused, game over, menu, hidden or in combat => every key goes to
  WoW as normal. Combat always pauses first (PLAYER_REGEN_DISABLED fires before lockdown).
]]
local ADDON, ns = ...
local T, Board, DB, Session = ns.T, ns.Board, ns.DB, ns.Session
local C = T.C

local UI = {}
ns.UI = UI

local CELL = 18
local PAD = 14
local COL = 104
local HEADER = 46
local FOOTER = 30

local CLEAR_WORD = { "SINGLE", "DOUBLE", "TRIPLE", "QUAD" }

-- Keys that always reach WoW, even mid-game (screenshots; Enter/slash pause and open chat).
local ALWAYS_PASS = { PRINTSCREEN = true }
local PAUSE_AND_PASS = { ENTER = true, SLASH = true, ["/"] = true }

local function inCombat()
  return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end
UI.inCombat = inCombat

------------------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------------------
function UI:Create()
  if self.frame then return self.frame end
  local db = ns.db
  local fieldW = 10 * (CELL + 1) + 1
  local fieldH = 20 * (CELL + 1) + 1
  local W = PAD + COL + 12 + fieldW + 12 + COL + PAD
  local H = HEADER + fieldH + 10 + FOOTER

  local F = CreateFrame("Frame", "StackRivalsFrame", UIParent)
  self.frame = F
  F:SetSize(W, H)
  F:SetFrameStrata("HIGH")
  F:SetToplevel(true)
  F:SetClampedToScreen(true)
  F:SetMovable(true)
  F:EnableMouse(true)
  F:RegisterForDrag("LeftButton")
  F:SetScript("OnDragStart", function(f) f:StartMoving() end)
  F:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); UI:SavePosition() end)
  F:Hide()
  tinsert(UISpecialFrames, "StackRivalsFrame") -- Esc closes it when no run is live

  -- body
  local bg = T.tex(F, "BACKGROUND", C.navy, 0.97); bg:SetAllPoints()
  local glow = T.tex(F, "BACKGROUND", C.redDeep, 0.18, 1)
  glow:SetPoint("TOPLEFT"); glow:SetPoint("BOTTOMLEFT"); glow:SetWidth(W * 0.45)
  local glow2 = T.tex(F, "BACKGROUND", C.steelDeep, 0.14, 1)
  glow2:SetPoint("TOPRIGHT"); glow2:SetPoint("BOTTOMRIGHT"); glow2:SetWidth(W * 0.45)
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
    local l = T.tex(F, "BORDER", C.line, 1)
    l:SetPoint(side[1]); l:SetPoint(side[2])
    if side[3] then l:SetWidth(side[3]) else l:SetHeight(side[4]) end
  end
  local edge = T.tex(F, "ARTWORK", C.red, 1)
  edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(2)

  -- header (drag handle is the whole frame; header just carries the brand)
  local mark = F:CreateTexture(nil, "ARTWORK")
  mark:SetTexture(T.MEDIA .. "mark")
  mark:SetSize(28, 28)
  mark:SetPoint("TOPLEFT", PAD - 4, -9)
  local t1 = T.text(F, 18, C.paper, "")
  t1:SetPoint("LEFT", mark, "RIGHT", 6, 0)
  t1:SetText("STACK")
  local t2 = T.text(F, 18, C.redLight, "")
  t2:SetPoint("LEFT", t1, "RIGHT", 0, 0)
  t2:SetText("RIVALS")
  self.modeText = T.text(F, 10, C.label)
  self.modeText:SetPoint("LEFT", t2, "RIGHT", 10, -2)

  local close = T.button(F, "X", 24, 22, "frame", function() F:Hide() end)
  close:SetPoint("TOPRIGHT", -PAD + 4, -11)
  close.tip = "Close (your run pauses)"
  local settings = T.button(F, "Settings", 74, 22, "frame", function() UI:ShowSettings(true) end)
  settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
  self.settingsBtn = settings

  -- playfield
  local field = Board.createField(F, 10, 20, CELL)
  field:SetPoint("TOP", F, "TOP", 0, -HEADER)
  self.field = field
  local frameEdge = T.tex(F, "BORDER", C.red, 0.85)
  frameEdge:SetPoint("TOPLEFT", field, "TOPLEFT", -2, 2); frameEdge:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 2, -2)

  -- left column: hold + stats
  local hold = T.panel(F, C.red)
  hold:SetSize(COL, 92)
  hold:SetPoint("TOPRIGHT", field, "TOPLEFT", -12, 0)
  local hl = T.label(hold, "HOLD"); hl:SetPoint("TOPLEFT", 8, -8)
  self.holdPreview = Board.createPreview(hold, 15)
  self.holdPreview:SetPoint("TOP", hold, "TOP", 0, -24)

  local stats = T.panel(F)
  stats:SetSize(COL, 238)
  stats:SetPoint("TOPRIGHT", hold, "BOTTOMRIGHT", 0, -10)
  local function stat(label, y, size, color)
    local l = T.label(stats, label)
    l:SetPoint("TOPLEFT", 8, y)
    local v = T.text(stats, size or 15, color or C.paper)
    v:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -3)
    v:SetText("0")
    return v
  end
  self.scoreText = stat("SCORE", -10, 18, C.paper)
  self.bestText = stat("BEST", -56, 13, C.gold)
  self.linesText = stat("LINES", -96, 15)
  self.levelText = stat("LEVEL", -138, 15)
  self.timeLabel = T.label(stats, "TIME"); self.timeLabel:SetPoint("TOPLEFT", 8, -180)
  self.timeText = T.text(stats, 15, C.steel); self.timeText:SetPoint("TOPLEFT", self.timeLabel, "BOTTOMLEFT", 0, -3)
  self.timeText:SetText("0:00")

  -- right column: next queue
  local nextP = T.panel(F, C.steel)
  nextP:SetSize(COL, 340)
  nextP:SetPoint("TOPLEFT", field, "TOPRIGHT", 12, 0)
  local nl = T.label(nextP, "NEXT"); nl:SetPoint("TOPLEFT", 8, -8)
  self.nextPreviews = {}
  local y = -24
  for i = 1, 5 do
    local cs = (i == 1) and 15 or 11
    local p = Board.createPreview(nextP, cs)
    p:SetPoint("TOP", nextP, "TOP", 0, y)
    y = y - (4 * cs + 3) - ((i == 1) and 12 or 6)
    self.nextPreviews[i] = p
  end

  -- footer hint
  self.hint = T.text(F, 10, C.label)
  self.hint:SetPoint("BOTTOM", F, "BOTTOM", 0, 11)

  self:CreateOverlays()
  self:CreateSettings()
  self:CreateKeyboard()

  F:SetScript("OnShow", function() UI:OnShow() end)
  F:SetScript("OnHide", function() UI:OnHide() end)
  F:SetScript("OnUpdate", function(_, elapsed) UI:OnUpdate(elapsed) end)

  F:SetScale(db.settings.scale)
  self:RestorePosition()
  self:UpdateHint()
  return F
end

local function overlayFrame(parent, alpha)
  local o = CreateFrame("Frame", nil, parent)
  o:SetAllPoints(parent)
  o:SetFrameLevel(parent:GetFrameLevel() + 10)
  local bg = T.tex(o, "BACKGROUND", C.navy, alpha or 0.88)
  bg:SetAllPoints()
  o:EnableMouse(true)
  o:Hide()
  return o
end

function UI:CreateOverlays()
  local field = self.field

  -- Mode menu
  local menu = overlayFrame(field, 0.9)
  self.menu = menu
  local mt = T.text(menu, 16, C.paper); mt:SetPoint("TOP", 0, -16); mt:SetText("CHOOSE A MODE")
  local ms = T.label(menu, "Same rules as stackrivals.io"); ms:SetPoint("TOP", mt, "BOTTOM", 0, -4)
  self.modeButtons = {}
  local y = -62
  for _, key in ipairs(Session.MODE_ORDER) do
    local mode = Session.MODES[key]
    local b = T.button(menu, "", 171, 66, key == "daily" and "gold" or "frame", function() ns.App:Start(key) end)
    b:SetPoint("TOP", menu, "TOP", 0, y)
    b.noPress = true
    b.fs:ClearAllPoints(); b.fs:SetPoint("TOPLEFT", 10, -9); b.fs:SetJustifyH("LEFT")
    b.fs:SetFont(T.FONT, 14, "")
    b.fs:SetText(mode.name)
    b.desc = T.text(b, 10, C.body); b.desc:SetPoint("TOPLEFT", b.fs, "BOTTOMLEFT", 0, -4)
    b.desc:SetWidth(152); b.desc:SetJustifyH("LEFT")
    b.desc:SetText(mode.short)
    b.best = T.text(b, 10, C.gold); b.best:SetPoint("BOTTOMLEFT", 10, 8)
    local edgeC = (key == "classic") and C.red or (key == "blitz") and C.steel or C.gold
    local e = T.tex(b, "ARTWORK", edgeC, 1); e:SetPoint("TOPLEFT", 1, -1); e:SetPoint("BOTTOMLEFT", 1, 1); e:SetWidth(3)
    self.modeButtons[key] = b
    y = y - 74
  end
  self.continueBtn = T.button(menu, "Continue last run", 171, 26, "primary", function() ns.App:ContinueSuspended() end)
  self.continueBtn:SetPoint("TOP", menu, "TOP", 0, y - 4)
  self.continueBtn.tip = "Your unfinished run from before /reload or logout, restored exactly."
  self.statsLine = T.text(menu, 10, C.label); self.statsLine:SetPoint("BOTTOM", 0, 14)
  self.statsLine:SetWidth(175)

  -- Countdown number
  self.countText = T.text(field, 64, C.redLight, "OUTLINE")
  self.countText:SetPoint("CENTER", field, "CENTER", 0, 30)
  self.countText:Hide()

  -- Callout (line clears, combos, level ups)
  local co = CreateFrame("Frame", nil, field)
  co:SetAllPoints(field)
  co:SetFrameLevel(field:GetFrameLevel() + 5)
  self.callout = T.text(co, 20, C.paper, "OUTLINE")
  self.callout:SetPoint("TOP", field, "TOP", 0, -70)
  self.callout2 = T.text(co, 13, C.redLight, "OUTLINE")
  self.callout2:SetPoint("TOP", self.callout, "BOTTOM", 0, -4)
  self.calloutT = 0

  -- Pause
  local pause = overlayFrame(field, 0.84)
  self.pause = pause
  local pt = T.text(pause, 22, C.paper); pt:SetPoint("CENTER", 0, 70); pt:SetText("PAUSED")
  self.pauseReason = T.text(pause, 11, C.body); self.pauseReason:SetPoint("TOP", pt, "BOTTOM", 0, -6)
  self.pauseReason:SetWidth(170)
  self.resumeBtn = T.button(pause, "Resume", 150, 28, "primary", function() ns.App:Resume() end)
  self.resumeBtn:SetPoint("CENTER", 0, 0)
  local rs = T.button(pause, "Restart", 150, 24, "frame", function() ns.App:Start(ns.App.session and ns.App.session.mode.key or "classic") end)
  rs:SetPoint("TOP", self.resumeBtn, "BOTTOM", 0, -8)
  self.restartBtn = rs
  local qm = T.button(pause, "Quit to menu", 150, 24, "frame", function() ns.App:Quit() end)
  qm:SetPoint("TOP", rs, "BOTTOM", 0, -6)

  -- Game over
  local over = overlayFrame(field, 0.88)
  self.over = over
  self.overTitle = T.text(over, 22, C.paper); self.overTitle:SetPoint("TOP", 0, -50)
  self.overScore = T.text(over, 28, C.paper); self.overScore:SetPoint("TOP", self.overTitle, "BOTTOM", 0, -12)
  self.overBadge = T.text(over, 13, C.gold, "OUTLINE"); self.overBadge:SetPoint("TOP", self.overScore, "BOTTOM", 0, -6)
  self.overDetail = T.text(over, 11, C.body); self.overDetail:SetPoint("TOP", self.overBadge, "BOTTOM", 0, -10)
  self.overDetail:SetWidth(175)
  local again = T.button(over, "Play again", 150, 28, "primary", function() ns.App:Start(ns.App.lastMode or "classic") end)
  again:SetPoint("TOP", over, "TOP", 0, -210)
  local menuB = T.button(over, "Modes", 150, 24, "frame", function() ns.App:ShowMenu() end)
  menuB:SetPoint("TOP", again, "BOTTOM", 0, -8)
  self.shareGuild = T.button(over, "Share to guild", 72, 22, "steel", function() ns.App:Share("GUILD") end)
  self.shareGuild:SetPoint("TOPLEFT", menuB, "BOTTOMLEFT", 0, -14)
  self.shareGroup = T.button(over, "Share to group", 72, 22, "steel", function() ns.App:Share("GROUP") end)
  self.shareGroup:SetPoint("TOPRIGHT", menuB, "BOTTOMRIGHT", 0, -14)
  self.shareGuild.fs:SetFont(T.FONT, 9, ""); self.shareGroup.fs:SetFont(T.FONT, 9, "")
end

------------------------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------------------------
function UI:CreateSettings()
  local F = self.frame
  local s = CreateFrame("Frame", nil, F)
  s:SetPoint("TOPLEFT", F, "TOPLEFT", 1, -HEADER + 6)
  s:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", -1, 1)
  s:SetFrameLevel(F:GetFrameLevel() + 40)
  local bg = T.tex(s, "BACKGROUND", C.navy, 0.985); bg:SetAllPoints()
  s:EnableMouse(true)
  s:Hide()
  self.settings = s
  local db = ns.db

  local title = T.text(s, 15, C.paper); title:SetPoint("TOPLEFT", 20, -12); title:SetText("SETTINGS")

  local y = -42
  local function toggle(label, key, after)
    local t = T.toggle(s, label, function(v) db.settings[key] = v; if after then after(v) end end)
    t:SetPoint("TOPLEFT", 20, y)
    t.key = key
    y = y - 24
    return t
  end
  self.toggles = {
    toggle("Sound effects", "sound", function(v) ns.Sound.enabled = v end),
    toggle("Ghost piece (landing preview)", "ghost", function() UI.dirty = true end),
    toggle("Hide window during combat", "hideInCombat"),
    toggle("Hide minimap button", "minimapHide", function() if ns.Minimap then ns.Minimap:Update() end end),
  }

  local sl = T.label(s, "WINDOW SIZE"); sl:SetPoint("TOPLEFT", 20, y - 6)
  local minus = T.button(s, "-", 26, 22, "frame", function() UI:SetScale(db.settings.scale - 0.1) end)
  minus:SetPoint("TOPLEFT", 130, y - 2)
  self.scaleText = T.text(s, 12, C.paper); self.scaleText:SetPoint("LEFT", minus, "RIGHT", 10, 0)
  local plus = T.button(s, "+", 26, 22, "frame", function() UI:SetScale(db.settings.scale + 0.1) end)
  plus:SetPoint("LEFT", minus, "RIGHT", 52, 0)
  y = y - 36

  local cl = T.label(s, "CONTROLS  (click a key, then press the new key)"); cl:SetPoint("TOPLEFT", 20, y)
  y = y - 18
  self.bindButtons = {}
  for i, action in ipairs(DB.BIND_ORDER) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local lx, ly = 20 + col * 205, y - row * 26
    local l = T.text(s, 11, C.body); l:SetPoint("TOPLEFT", lx, ly - 5); l:SetText(DB.BIND_LABEL[action])
    local b = T.button(s, "", 86, 22, "frame", function(btn) UI:BeginBind(action, btn) end)
    b:SetPoint("TOPLEFT", lx + 96, ly)
    self.bindButtons[action] = b
  end
  y = y - 4 * 26 - 4
  local alt = T.text(s, 10, C.label); alt:SetPoint("TOPLEFT", 20, y)
  alt:SetWidth(390); alt:SetJustifyH("LEFT")
  alt:SetText("Also always: A/D move, S soft drop, W/X rotate, L-Ctrl rotate left, Shift hold, Esc pause.\nKeys are only captured while a run is live. Paused or in combat, WoW gets every key.")
  y = y - 36
  local rb = T.button(s, "Default controls", 130, 22, "frame", function() DB.resetBindings(db); UI:RefreshSettings() end)
  rb:SetPoint("TOPLEFT", 20, y)
  self.resetRecords = T.button(s, "Reset records", 130, 22, "frame", function(btn)
    if btn.armed then
      DB.resetRecords(db); btn.armed = false; btn:SetLabel("Records reset"); UI:RefreshMenu()
    else
      btn.armed = true; btn:SetLabel("Click again to confirm")
    end
  end)
  self.resetRecords:SetPoint("LEFT", rb, "RIGHT", 10, 0)

  local done = T.button(s, "Done", 120, 28, "primary", function() UI:ShowSettings(false) end)
  done:SetPoint("BOTTOM", 0, 16)
  local ver = T.text(s, 9, C.label); ver:SetPoint("BOTTOMRIGHT", -12, 10)
  ver:SetText("StackRivals " .. (ns.VERSION or "") .. "  -  free, no ads, open source")
end

function UI:RefreshSettings()
  local db = ns.db
  for _, t in ipairs(self.toggles) do t:SetValue(db.settings[t.key]) end
  self.scaleText:SetText(string.format("%d%%", math.floor(db.settings.scale * 100 + 0.5)))
  for action, b in pairs(self.bindButtons) do
    b:SetLabel(T.keyName(db.bindings[action]))
  end
  self.resetRecords.armed = false
  self.resetRecords:SetLabel("Reset records")
  self:UpdateHint()
end

function UI:ShowSettings(show)
  if show then
    ns.App:Pause("settings")
    self:RefreshSettings()
    self.settings:Show()
  else
    self:EndBind()
    self.settings:Hide()
  end
end

function UI:SetScale(v)
  v = math.max(0.6, math.min(1.6, math.floor(v * 10 + 0.5) / 10))
  ns.db.settings.scale = v
  self.frame:SetScale(v)
  self:RefreshSettings()
end

function UI:BeginBind(action, btn)
  if inCombat() then return end
  self:EndBind()
  self.binding = { action = action, btn = btn }
  btn:SetLabel("Press a key...")
  self:SetKeyboard(true)
end

function UI:EndBind()
  if not self.binding then return end
  self.binding = nil
  self:SetKeyboard(false)
  self:RefreshSettings()
end

------------------------------------------------------------------------------------------------
-- Keyboard
------------------------------------------------------------------------------------------------
local function setPropagate(frame, v)
  if not inCombat() then frame:SetPropagateKeyboardInput(v) end
end

function UI:CreateKeyboard()
  local k = CreateFrame("Frame", nil, self.frame)
  k:SetAllPoints(self.frame)
  self.keys = k
  -- New frames start with keyboard off and propagation off; nothing to call here, which also
  -- keeps creation safe if the window is first opened during combat.
  k:SetScript("OnKeyDown", function(f, key) UI:OnKeyDown(f, key) end)
  k:SetScript("OnKeyUp", function(_, key) UI:OnKeyUp(key) end)
end

--- Take or release the keyboard. During combat lockdown nothing is called at all: the keyboard
--- was already released on PLAYER_REGEN_DISABLED, which fires before lockdown begins.
function UI:SetKeyboard(on)
  if not self.keys then return end
  on = on and not inCombat() and true or false
  if InCombatLockdown and InCombatLockdown() then return end
  if self.keyboardOn == on then return end
  self.keys:EnableKeyboard(on)
  self.keyboardOn = on
end

function UI:OnKeyDown(f, key)
  if ALWAYS_PASS[key] then setPropagate(f, true); return end
  -- rebinding
  if self.binding then
    setPropagate(f, false)
    if key == "ESCAPE" then self:EndBind(); return end
    if key:match("^[LR]?META$") then return end
    DB.setBinding(ns.db, self.binding.action, key)
    self:EndBind()
    return
  end
  local sess = ns.App.session
  if not sess or not sess:isActive() then setPropagate(f, true); return end
  if PAUSE_AND_PASS[key] then
    ns.App:Pause("chat")
    setPropagate(f, true)
    return
  end
  setPropagate(f, false)
  local action = DB.actionForKey(ns.db, key)
  if action == "pause" then ns.App:Pause("manual")
  elseif action then sess:press(action) end
end

function UI:OnKeyUp(key)
  local sess = ns.App.session
  local action = DB.actionForKey(ns.db, key)
  if sess and action and action ~= "pause" then sess:release(action) end
end

------------------------------------------------------------------------------------------------
-- Show / hide / position
------------------------------------------------------------------------------------------------
function UI:OnShow()
  if not ns.App.session then ns.App:ShowMenu() end
  self:RefreshMenu()
  self.dirty = true
  self:RefreshPhase()
  if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
end

function UI:OnHide()
  ns.App:Pause("hidden")
  self:EndBind()
  self:SetKeyboard(false)
end

function UI:SavePosition()
  local p, _, rp, x, y = self.frame:GetPoint(1)
  local w = ns.db.window
  w.point, w.relPoint, w.x, w.y = p, rp, x, y
end

function UI:RestorePosition()
  local F, w = self.frame, ns.db.window
  F:ClearAllPoints()
  if w.point and w.x and w.y then
    F:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x, w.y)
  else
    F:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
end

function UI:ResetPosition()
  local w = ns.db.window
  w.point, w.relPoint, w.x, w.y = nil, nil, nil, nil
  self:RestorePosition()
end

function UI:Toggle()
  local F = self:Create()
  if F:IsShown() then F:Hide() else F:Show() end
end

function UI:UpdateHint()
  if not self.hint then return end
  local b = ns.db.bindings
  self.hint:SetText(string.format("%s/%s move  -  %s/%s rotate  -  %s drop  -  %s hold  -  %s pause",
    T.keyName(b.left), T.keyName(b.right), T.keyName(b.rotateCW), T.keyName(b.rotateCCW),
    T.keyName(b.hardDrop), T.keyName(b.hold), T.keyName(b.pause)))
end

------------------------------------------------------------------------------------------------
-- Per-frame update and drawing
------------------------------------------------------------------------------------------------
function UI:OnUpdate(elapsed)
  local App = ns.App
  local sess = App.session
  if sess and sess:isActive() then
    if sess:update(elapsed) then self.dirty = true end
    local events = sess:takeEvents()
    if #events > 0 then
      for _, ev in ipairs(events) do self:OnEvent(ev) end
    end
  end
  -- effects
  local fl = self.field.flash
  local a = fl:GetAlpha()
  if a > 0 then fl:SetAlpha(math.max(0, a - elapsed * 2.2)) end
  if self.calloutT > 0 then
    self.calloutT = self.calloutT - elapsed
    local alpha = math.min(1, math.max(0, self.calloutT / 0.4))
    self.callout:SetAlpha(alpha); self.callout2:SetAlpha(alpha)
  end
  if self.dirty then
    self.dirty = false
    self:Render()
  end
end

function UI:Callout(main, sub, color)
  color = color or C.paper
  self.callout:SetTextColor(color[1], color[2], color[3])
  self.callout:SetText(main or "")
  self.callout2:SetText(sub or "")
  self.calloutT = 1.1
  self.callout:SetAlpha(1); self.callout2:SetAlpha(1)
end

function UI:OnEvent(ev)
  ns.Sound.forEvent(ev)
  local k = ev.kind
  if k == "clear" then
    local c = ev.b
    local quad = ev.a >= 4
    local fl = self.field.flash
    if quad then fl:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1) else fl:SetColorTexture(1, 1, 1, 1) end
    fl:SetAlpha(quad and 0.45 or 0.18 + 0.05 * ev.a)
    local sub = {}
    if c.backToBack then sub[#sub + 1] = "BACK-TO-BACK" end
    if c.combo and c.combo >= 1 then sub[#sub + 1] = "COMBO x" .. c.combo end
    self:Callout(CLEAR_WORD[ev.a] or "CLEAR", table.concat(sub, "  "), quad and C.gold or C.paper)
  elseif k == "level" then
    self:Callout("LEVEL " .. ev.a, "faster!", C.steel)
  elseif k == "count" or k == "go" then
    self:RefreshPhase()
  elseif k == "over" then
    ns.App:OnRunOver(ev.a)
  end
end

function UI:Render()
  local sess = ns.App.session
  if not sess then
    self.scoreText:SetText("0"); self.linesText:SetText("0"); self.levelText:SetText("1")
    return
  end
  local s = sess.state
  Board.renderField(self.field, s, ns.db.settings.ghost)
  Board.renderPreview(self.holdPreview, s.hold, s.holdUsed)
  for i, p in ipairs(self.nextPreviews) do Board.renderPreview(p, s.queue[i], false) end
  self.scoreText:SetText(T.commas(s.score))
  self.linesText:SetText(tostring(s.lines))
  self.levelText:SetText(tostring(s.level))
  local left = sess:timeLeftTicks()
  if left then
    self.timeLabel:SetText("TIME LEFT")
    self.timeText:SetText(T.clock(math.ceil(left / 60)))
    if left < 600 then self.timeText:SetTextColor(C.redLight[1], C.redLight[2], C.redLight[3]) else self.timeText:SetTextColor(C.steel[1], C.steel[2], C.steel[3]) end
  else
    self.timeLabel:SetText("TIME")
    self.timeText:SetText(T.clock(s.tick / 60))
    self.timeText:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
  end
  self.bestText:SetText(T.commas(ns.App:BestFor(sess.mode.key)))
  local n = sess:countdownNumber()
  if n then self.countText:SetText(tostring(n)); self.countText:Show() else self.countText:Hide() end
end

--- Show the overlay that matches the current phase and take/release the keyboard.
function UI:RefreshPhase()
  if not self.frame then return end
  local App = ns.App
  local sess = App.session
  local phase = sess and sess.phase or "menu"
  if App.inMenu then phase = "menu" end
  self.menu:SetShown(phase == "menu")
  self.pause:SetShown(phase == "paused")
  self.over:SetShown(phase == "over")
  self.countText:SetShown(phase == "countdown")
  self.modeText:SetText(sess and not App.inMenu and string.upper(sess.mode.name) or "")
  if phase == "paused" then
    local r = sess.pauseReason
    local txt = (r == "combat") and "You entered combat. Finish the fight, then resume."
      or (r == "hidden") and "Window was closed. Your run is saved here."
      or (r == "chat") and "Paused so you can type. Resume when ready."
      or (r == "settings") and "Settings were open."
      or (r == "loading") and "Paused for the loading screen."
      or "Take your time."
    self.pauseReason:SetText(txt)
    if inCombat() then self.resumeBtn:Disable(); self.resumeBtn:SetLabel("In combat...") else self.resumeBtn:Enable(); self.resumeBtn:SetLabel("Resume") end
  end
  local live = sess and (phase == "countdown" or phase == "playing")
  if not self.binding then self:SetKeyboard(live and self.frame:IsShown()) end
  self.dirty = true
end

function UI:RefreshMenu()
  if not self.modeButtons then return end
  local db = ns.db
  for key, b in pairs(self.modeButtons) do
    local best = ns.App:BestFor(key)
    if key == "daily" then
      local d = db.records.dailyToday
      local today = ns.App:Today()
      local tries = (d.date == today) and d.tries or 0
      b.best:SetText(best > 0 and ("Today: " .. T.commas(best) .. "  (" .. tries .. " tries)") or ("Today's seed: " .. today))
    else
      b.best:SetText(best > 0 and ("Best: " .. T.commas(best)) or "No record yet")
    end
    if inCombat() then b:Disable() else b:Enable() end
  end
  self.continueBtn:SetShown(db.suspended ~= nil)
  local total, lines = 0, 0
  for _, k in ipairs(Session.MODE_ORDER) do
    total = total + db.records[k].games
    lines = lines + db.records[k].totalLines
  end
  self.statsLine:SetText(total > 0 and (T.commas(total) .. " runs  -  " .. T.commas(lines) .. " lines cleared") or "Press a mode to start. Combat pauses the game.")
end

function UI:ShowOver(info)
  local s = info.state
  self.overTitle:SetText(info.reason == "time" and "TIME!" or "GAME OVER")
  self.overScore:SetText(T.commas(s.score))
  if info.newBest then
    self.overBadge:SetText(info.prevBest > 0 and ("NEW BEST  (+" .. T.commas(s.score - info.prevBest) .. ")") or "NEW BEST")
  elseif info.newTodayBest then
    self.overBadge:SetText("BEST TODAY")
  else
    self.overBadge:SetText("Best: " .. T.commas(ns.App:BestFor(info.mode)))
  end
  local c = s.clears
  self.overDetail:SetText(string.format("%d lines  -  level %d  -  %d quads\n%s", s.lines, s.level, c.quad, info.modeName))
  self.shareGuild:SetShown(IsInGuild and IsInGuild() or false)
  self.shareGroup:SetShown(IsInGroup and IsInGroup() or false)
  self:RefreshPhase()
end
