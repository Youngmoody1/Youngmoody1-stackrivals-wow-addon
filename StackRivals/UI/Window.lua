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

--- SetText only when the value changed (no string building or UI work for unchanged HUD values).
local function setNum(fs, n, fmt)
  if fs._n == n then return end
  fs._n = n
  fs:SetText(fmt and fmt(n) or tostring(n))
end
local function setStr(fs, s)
  if fs._s == s then return end
  fs._s = s
  fs:SetText(s)
end

local function inCombat()
  if InCombatLockdown and InCombatLockdown() then return true end
  if UnitAffectingCombat then
    local v = UnitAffectingCombat("player")
    -- Modern clients (Midnight / Forever) can return "secret" values that error when tested.
    if issecretvalue and issecretvalue(v) then return false end
    return v and true or false
  end
  return false
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
  if F.SetDontSavePosition then F:SetDontSavePosition(true) end -- we save the position ourselves
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

  -- header (drag the window by its border, header or side panels)
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
  self.scoreText = stat("SCORE", -10, 16, C.paper)
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

  self.W, self.H = W, H
  self:ApplyScale()
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
    b.best = T.text(b, 10, C.gold); b.best:SetPoint("BOTTOMLEFT", 10, 6)
    local edgeC = (key == "classic") and C.red or (key == "blitz") and C.steel or C.gold
    local e = T.tex(b, "ARTWORK", edgeC, 1); e:SetPoint("TOPLEFT", 1, -1); e:SetPoint("BOTTOMLEFT", 1, 1); e:SetWidth(3)
    self.modeButtons[key] = b
    y = y - 74
  end
  self.continueBtn = T.button(menu, "Continue last run", 171, 26, "primary", function() ns.App:ContinueSuspended() end)
  self.continueBtn:SetPoint("TOP", menu, "TOP", 0, y - 4)
  self.continueBtn.tip = "Your unfinished run from before /reload or logout, restored exactly."
  local howBtn = T.button(menu, "How to play", 82, 22, "frame", function() UI:ShowSheet("help") end)
  howBtn:SetPoint("BOTTOMLEFT", menu, "BOTTOM", -85, 34)
  local recBtn = T.button(menu, "Records", 82, 22, "frame", function() UI:ShowSheet("records") end)
  recBtn:SetPoint("BOTTOMRIGHT", menu, "BOTTOM", 85, 34)
  self.statsLine = T.text(menu, 10, C.label); self.statsLine:SetPoint("BOTTOM", 0, 12)
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
  self.againHint = T.text(over, 10, C.label); self.againHint:SetPoint("TOP", again, "BOTTOM", 0, -3)
  self.againBtn = again
  local menuB = T.button(over, "Modes", 150, 24, "frame", function() ns.App:ShowMenu() end)
  menuB:SetPoint("TOP", again, "BOTTOM", 0, -18)
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
  alt:SetText("Also: A/D move, S soft drop, W/X rotate, L-Ctrl rotate left, Shift hold, Esc pause.\nKeys are only captured while a run is live.")
  y = y - 40
  local rb = T.button(s, "Default controls", 130, 22, "frame", function() DB.resetBindings(db); UI:RefreshSettings() end)
  rb:SetPoint("TOPLEFT", 20, y)
  self.resetRecords = T.button(s, "Reset records", 160, 22, "frame", function(btn)
    if btn.armed then
      DB.resetRecords(db); btn.armed = false; btn:SetLabel("Records reset"); UI:RefreshMenu()
    else
      btn.armed = true; btn:SetLabel("Click again to reset")
    end
  end)
  self.resetRecords:SetPoint("LEFT", rb, "RIGHT", 10, 0)

  local done = T.button(s, "Done", 120, 28, "primary", function() UI:ShowSettings(false) end)
  done:SetPoint("BOTTOM", 0, 16)
  local ver = T.text(s, 9, C.label); ver:SetPoint("BOTTOMLEFT", 20, 10)
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
    if self.help then self.help:Hide(); self.records:Hide() end
    self:RefreshSettings()
    self.settings:Show()
  else
    self:EndBind()
    self.settings:Hide()
    self:RefreshPhase()
  end
end

function UI:SetScale(v)
  v = math.max(0.6, math.min(1.6, math.floor(v * 10 + 0.5) / 10))
  ns.db.settings.scale = v
  self:ApplyScale()
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
  self.down = {}
  -- New frames start with keyboard off and propagation off; nothing to call here, which also
  -- keeps creation safe if the window is first opened during combat.
  k:SetScript("OnKeyDown", function(f, key) UI:OnKeyDown(f, key) end)
  k:SetScript("OnKeyUp", function(f, key) UI:OnKeyUp(f, key) end)
end

--- Take or release the keyboard. During combat lockdown nothing is called at all: the keyboard
--- was already released on PLAYER_REGEN_DISABLED, which fires before lockdown begins.
function UI:SetKeyboard(on)
  if not self.keys then return end
  on = on and not inCombat() and true or false
  if InCombatLockdown and InCombatLockdown() then return end
  if not on then self.down = {} end
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
  if sess and sess.phase == "over" and not ns.App.inMenu then
    -- only the hard-drop key (play again) is ours; everything else goes to WoW
    if DB.actionForKey(ns.db, key) == "hardDrop" and not self.overReadyAt and not inCombat() then
      setPropagate(f, false)
      ns.App:Start(sess.mode.key)
    else
      setPropagate(f, true)
    end
    return
  end
  if sess and sess.phase == "paused" then
    -- the pause key (not Esc: Esc keeps closing windows) resumes; everything else goes to WoW
    if key ~= "ESCAPE" and DB.actionForKey(ns.db, key) == "pause" and not inCombat() then
      setPropagate(f, false)
      self.down[key] = true
      ns.App:Resume()
    else
      setPropagate(f, true)
    end
    return
  end
  if not sess or not sess:isActive() then setPropagate(f, true); return end
  if PAUSE_AND_PASS[key] then
    setPropagate(f, true) -- decide propagation before the keyboard is released by the pause
    ns.App:Pause("chat")
    return
  end
  setPropagate(f, false)
  -- Ignore auto-repeat while a key is held: DAS/ARR is ours, like the web game.
  if self.down[key] then return end
  self.down[key] = true
  local action = DB.actionForKey(ns.db, key)
  if action == "pause" then ns.App:Pause("manual")
  elseif action then sess:press(action) end
end

function UI:OnKeyUp(f, key)
  if not self.down[key] then
    -- We never took this key's press (e.g. you were already running when the run started):
    -- hand the release to WoW so the character doesn't keep moving.
    setPropagate(f, true)
    return
  end
  self.down[key] = nil
  setPropagate(f, false)
  local sess = ns.App.session
  local action = DB.actionForKey(ns.db, key)
  if sess and action and action ~= "pause" then sess:release(action) end
end

------------------------------------------------------------------------------------------------
-- Show / hide / position
------------------------------------------------------------------------------------------------
function UI:OnShow()
  self:ApplyScale()
  if not ns.App.session then ns.App:ShowMenu() end
  -- first visit: explain the game once (only on the menu, never on top of a run)
  if not ns.db.seenHelp and (not ns.App.session or ns.App.inMenu) then
    ns.db.seenHelp = true
    self:ShowSheet("help")
  end
  self:RefreshMenu()
  self.dirty = true
  self:RefreshPhase()
  if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
end

function UI:OnHide()
  if self.settings and self.settings:IsShown() then self.settings:Hide() end
  if self.help then self.help:Hide(); self.records:Hide() end
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
  if sess then
    if sess:isActive() and sess:update(elapsed) then self.dirty = true end
    if #sess.events > 0 then
      for _, ev in ipairs(sess:takeEvents()) do self:OnEvent(ev) end
    end
  end
  if self.overReadyAt and GetTime() >= self.overReadyAt then
    self.overReadyAt = nil
    self.againHint:SetAlpha(1)
    self:RefreshPhase()
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
    setNum(self.scoreText, 0); setNum(self.linesText, 0); setNum(self.levelText, 1)
    setStr(self.timeLabel, "TIME"); setNum(self.timeText, 0, T.clock)
    setStr(self.bestText, "-"); self.bestText._n = nil
    Board.renderPreview(self.holdPreview, nil)
    for _, p in ipairs(self.nextPreviews) do Board.renderPreview(p, nil) end
    for _, c in ipairs(self.field.cells) do c.base:SetColorTexture(C.cell[1], C.cell[2], C.cell[3], 1); c.hi:Hide(); c.lo:Hide(); c.value = 0 end
    return
  end
  local s = sess.state
  Board.renderField(self.field, s, ns.db.settings.ghost)
  Board.renderPreview(self.holdPreview, s.hold, s.holdUsed)
  for i, p in ipairs(self.nextPreviews) do Board.renderPreview(p, s.queue[i], false) end
  setNum(self.scoreText, s.score, T.commas)
  setNum(self.linesText, s.lines)
  setNum(self.levelText, s.level)
  local left = sess:timeLeftTicks()
  if left then
    setStr(self.timeLabel, "TIME LEFT")
    setNum(self.timeText, math.ceil(left / 60), T.clock)
    local urgent = left < 600
    if self.timeUrgent ~= urgent then
      self.timeUrgent = urgent
      local c = urgent and C.redLight or C.steel
      self.timeText:SetTextColor(c[1], c[2], c[3])
    end
  else
    setStr(self.timeLabel, "TIME")
    setNum(self.timeText, math.floor(s.tick / 60), T.clock)
    if self.timeUrgent ~= false then self.timeUrgent = false; self.timeText:SetTextColor(C.steel[1], C.steel[2], C.steel[3]) end
  end
  setNum(self.bestText, ns.App:BestFor(sess.mode.key), T.commas)
  local n = sess:countdownNumber()
  if n then setNum(self.countText, n); self.countText:Show() else self.countText:Hide() end
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
  -- While paused (out of combat, no sheet open) we listen too, but only to take the pause key
  -- back; every other key is handed straight to WoW.
  local quiet = not inCombat() and not self:SheetOpen()
  local pausedListen = phase == "paused" and quiet
  local overListen = phase == "over" and quiet and not self.overReadyAt
  if not self.binding then self:SetKeyboard((live or pausedListen or overListen) and self.frame:IsShown()) end
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
      local left = ns.App:SecondsToUtcMidnight()
      local reset = string.format("new pieces in %dh %02dm", math.floor(left / 3600), math.floor(left % 3600 / 60))
      b.best:SetText(best > 0 and ("Today: " .. T.commas(best) .. "  -  " .. reset) or ("Same for everyone  -  " .. reset))
      b.tip = tries > 0 and (tries .. " tries today. Seed " .. today .. " (UTC).") or ("Seed " .. today .. " (UTC). Everyone gets the same pieces today.")
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
  local rankTxt = info.rank and ("#" .. info.rank .. " in your top 5  -  ") or ""
  self.overDetail:SetText(string.format("%d lines  -  level %d  -  %d quads\n%s%s", s.lines, s.level, c.quad, rankTxt, info.modeName))
  self.shareGuild:SetShown(IsInGuild and IsInGuild() or false)
  self.shareGroup:SetShown(IsInGroup and IsInGroup() or false)
  -- "press <hard drop> to play again", accepted after a short grace period so a player who is
  -- still hammering hard drop at top-out sees the result first
  self.againHint:SetText("or press " .. T.keyName(ns.db.bindings.hardDrop))
  self.againHint:SetAlpha(0.35)
  self.overReadyAt = GetTime() + 1.0
  self:RefreshPhase()
end

------------------------------------------------------------------------------------------------
-- Scale that always fits the screen
------------------------------------------------------------------------------------------------
--- Use the chosen size, but never larger than the screen (any resolution / UI scale).
function UI:ApplyScale()
  local F = self.frame
  if not F then return end
  local want = ns.db.settings.scale
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  if sw and sh and sw > 0 and sh > 0 then
    local fit = math.min((sw - 24) / self.W, (sh - 24) / self.H)
    if fit < want then want = math.max(0.5, fit) end
  end
  F:SetScale(want)
  self.appliedScale = want
end

------------------------------------------------------------------------------------------------
-- Full-window sheets: How to play, Records
------------------------------------------------------------------------------------------------
local function makeSheet(self, titleText)
  local F = self.frame
  local s = CreateFrame("Frame", nil, F)
  s:SetPoint("TOPLEFT", F, "TOPLEFT", 1, -HEADER + 6)
  s:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", -1, 1)
  s:SetFrameLevel(F:GetFrameLevel() + 40)
  local bg = T.tex(s, "BACKGROUND", C.navy, 0.985); bg:SetAllPoints()
  s:EnableMouse(true)
  s:Hide()
  local title = T.text(s, 15, C.paper); title:SetPoint("TOPLEFT", 20, -12); title:SetText(titleText)
  local done = T.button(s, "Got it", 120, 28, "primary", function() s:Hide(); UI:RefreshPhase() end)
  done:SetPoint("BOTTOM", 0, 16)
  s.done = done
  return s
end

function UI:CreateHelp()
  local s = makeSheet(self, "HOW TO PLAY")
  self.help = s
  local body = T.text(s, 11, C.body)
  body:SetPoint("TOPLEFT", 20, -44)
  body:SetWidth(410); body:SetJustifyH("LEFT"); body:SetSpacing(2)
  s.body = body
  s:SetScript("OnShow", function()
    local b = ns.db.bindings
    local k = T.keyName
    body:SetText(table.concat({
      "|cfff6f4f0Stack the falling pieces to complete full rows.|r Full rows clear and score. Clear more rows at once for more points (4 rows = |cfff2cf6bQUAD|r), and keep clearing for combos. It speeds up every 10 lines and ends when the stack reaches the top.",
      "",
      "|cffff4d5aControls|r",
      k(b.left) .. " / " .. k(b.right) .. "  move (hold to slide)",
      k(b.rotateCW) .. " / " .. k(b.rotateCCW) .. "  rotate",
      k(b.softDrop) .. "  soft drop      " .. k(b.hardDrop) .. "  hard drop",
      k(b.hold) .. "  hold piece      " .. k(b.pause) .. "  pause / resume",
      "Enter  pause and open chat",
      "",
      "|cff8fc0ddModes|r  Blitz 2:00 for short waits. Daily Blitz gives everyone the same pieces today. Classic is endless.",
      "",
      "|cff7be3a0Safe in WoW|r  Keys are only used while you play. Combat pauses the game and gives every key back. /reload never loses a run.",
      "",
      "Open with |cffff4d5a/sr|r or the minimap button. Change keys in Settings.",
    }, "\n"))
  end)
end

function UI:CreateRecords()
  local s = makeSheet(self, "RECORDS")
  self.records = s
  s.done:SetLabel("Close")
  local note = T.text(s, 10, C.label)
  note:SetPoint("TOPLEFT", 20, -32)
  note:SetText("Stored on this computer only. Local records are not verified.")
  s.cols = {}
  for i, key in ipairs(Session.MODE_ORDER) do
    local col = CreateFrame("Frame", nil, s)
    col:SetSize(132, 300)
    col:SetPoint("TOPLEFT", 20 + (i - 1) * 140, -54)
    local edgeC = (key == "classic") and C.red or (key == "blitz") and C.steel or C.gold
    local e = T.tex(col, "ARTWORK", edgeC, 1); e:SetPoint("TOPLEFT"); e:SetPoint("TOPRIGHT"); e:SetHeight(2)
    local name = T.text(col, 13, C.paper); name:SetPoint("TOPLEFT", 0, -8); name:SetText(Session.MODES[key].name)
    col.lines = T.text(col, 11, C.body); col.lines:SetPoint("TOPLEFT", 0, -30)
    col.lines:SetWidth(132); col.lines:SetJustifyH("LEFT")
    col.key = key
    s.cols[i] = col
  end
  s:SetScript("OnShow", function()
    local db = ns.db
    for _, col in ipairs(s.cols) do
      local r = db.records[col.key]
      local out = {}
      if #r.top == 0 then out[#out + 1] = "|cff7f8794No runs yet|r" end
      for n, e in ipairs(r.top) do
        out[#out + 1] = string.format("%d.  |cfff6f4f0%s|r  |cff7f8794%s|r", n, T.commas(e.s), e.d and e.d:sub(6) or "")
      end
      out[#out + 1] = ""
      out[#out + 1] = "Runs: " .. T.commas(r.games)
      out[#out + 1] = "Lines: " .. T.commas(r.totalLines)
      out[#out + 1] = "Quads: " .. T.commas(r.quads)
      out[#out + 1] = "Best level: " .. r.bestLevel
      out[#out + 1] = "Played: " .. T.clock(r.playSeconds)
      if col.key == "daily" then
        local d = db.records.dailyToday
        if d.date == ns.App:Today() and d.tries > 0 then
          out[#out + 1] = ""
          out[#out + 1] = "|cfff2cf6bToday: " .. T.commas(d.best) .. "|r (" .. d.tries .. " tries)"
        end
      end
      col.lines:SetText(table.concat(out, "\n"))
    end
  end)
end

function UI:SheetOpen()
  return (self.help and self.help:IsShown()) or (self.records and self.records:IsShown()) or (self.settings and self.settings:IsShown()) or false
end

function UI:ShowSheet(which)
  if not self.help then self:CreateHelp(); self:CreateRecords() end
  ns.App:Pause("settings")
  self.help:SetShown(which == "help")
  self.records:SetShown(which == "records")
  if self.settings:IsShown() then self:ShowSettings(false) end
  self:RefreshPhase()
end
