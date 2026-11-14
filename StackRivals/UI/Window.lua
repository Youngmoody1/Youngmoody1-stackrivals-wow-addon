--[[
  StackRivals - main game window.

  Keyboard rule: the window only takes the keyboard while a run is live (countdown or playing)
  or while you rebind a key. Paused, game over, menu, hidden or in combat => every key goes to
  WoW as normal. Combat always pauses first (PLAYER_REGEN_DISABLED fires before lockdown).

  Layout (window units; UI:ApplyScale sizes the whole window to the screen):
    header  mark + wordmark, mode, Settings, X
    body    HOLD + stats | 10x20 board | NEXT        (menu and sheets cover the whole body)
    footer  controls hint
]]
local ADDON, ns = ...
local T, Board, DB, Session = ns.T, ns.Board, ns.DB, ns.Session
local C, SZ = T.C, T.SIZE

local UI = {}
ns.UI = UI

local CELL = 18
local PAD = 16
local COL = 108
local HEADER = 50
local FOOTER = 30
local GUTTER = 12
UI.HEADER, UI.FOOTER, UI.PAD = HEADER, FOOTER, PAD

local CLEAR_WORD = { "SINGLE", "DOUBLE", "TRIPLE", "QUAD" }
local FIRST_RUNS_WITH_HINT = 3 -- the countdown shows the controls on a player's first runs

-- Keys that always reach WoW, even mid-game (screenshots; Enter/slash pause and open chat).
local ALWAYS_PASS = { PRINTSCREEN = true }
local PAUSE_AND_PASS = { ENTER = true, SLASH = true, ["/"] = true }

--- SetText only when the value changed (no string building or UI work for unchanged HUD values).
local function setNum(fs, n, fmt)
  if fs._n == n then return end
  fs._n, fs._s = n, nil
  fs:SetText(fmt and fmt(n) or tostring(n))
end
local function setStr(fs, s)
  if fs._s == s then return end
  fs._s, fs._n = s, nil
  fs:SetText(s)
end

local function inCombat()
  if UI.combatNow then return true end
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

local function hexColor(c) return string.format("|cff%02x%02x%02x", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) end
UI.hexColor = hexColor

------------------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------------------
function UI:Create()
  if self.frame then return self.frame end
  local fieldW = 10 * (CELL + 1) + 1
  local fieldH = 20 * (CELL + 1) + 1
  local W = PAD + COL + GUTTER + fieldW + GUTTER + COL + PAD
  local H = HEADER + fieldH + 10 + FOOTER

  local F = CreateFrame("Frame", "StackRivalsFrame", UIParent)
  self.frame = F
  F:SetSize(W, H)
  F:SetFrameStrata("MEDIUM") -- with Toplevel: above the world UI, below bags / mail / dialogs
  F:SetToplevel(true)
  F:SetClampedToScreen(true)
  F:SetMovable(true)
  if F.SetDontSavePosition then F:SetDontSavePosition(true) end -- we save the position ourselves
  F:EnableMouse(true)
  F:RegisterForDrag("LeftButton")
  F:SetScript("OnDragStart", function(f) f:StartMoving() end)
  F:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); UI:SavePosition(); UI:PlaceSidePanels() end)
  F:Hide()
  tinsert(UISpecialFrames, "StackRivalsFrame") -- Esc closes it when no run is live

  -- body: navy with the "rival split" (red glow from the left, steel from the right), built
  -- from whole-pixel strips (no gradient API needed, works on every client)
  local bg = T.tex(F, "BACKGROUND", C.navy, 0.97); bg:SetAllPoints()
  local STRIPS = 12
  local span = math.floor(W * 0.5 / STRIPS) * STRIPS
  for i = 1, STRIPS do
    local a = 0.20 * (1 - (i - 1) / STRIPS)
    local l = T.tex(F, "BACKGROUND", C.redDeep, a, 1)
    l:SetPoint("TOPLEFT", F, "TOPLEFT", (i - 1) * span / STRIPS, 0); l:SetPoint("BOTTOMLEFT", F, "BOTTOMLEFT", (i - 1) * span / STRIPS, 0)
    l:SetWidth(span / STRIPS)
    local r = T.tex(F, "BACKGROUND", C.steelDeep, a * 0.75, 1)
    r:SetPoint("TOPRIGHT", F, "TOPRIGHT", -(i - 1) * span / STRIPS, 0); r:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", -(i - 1) * span / STRIPS, 0)
    r:SetWidth(span / STRIPS)
  end
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
    local l = T.tex(F, "BORDER", C.line, 1)
    l:SetPoint(side[1]); l:SetPoint(side[2])
    if side[3] then l:SetWidth(side[3]) else l:SetHeight(side[4]) end
  end
  local edge = T.tex(F, "ARTWORK", C.red, 1)
  edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(2)

  -- header: the brand lockup (mark + "STACKRIVALS" in Chakra Petch Bold Italic, like the site)
  local mark = F:CreateTexture(nil, "ARTWORK")
  mark:SetTexture(T.MEDIA .. "mark")
  mark:SetSize(32, 32)
  mark:SetPoint("TOPLEFT", PAD - 3, -9)
  self.mark = mark
  -- one run of text like the site's wordmark: STACK in paper, RIVALS in brand red, no gap
  local word = T.text(F, 22, C.paper, "", nil, "italic")
  word:SetPoint("LEFT", mark, "RIGHT", 6, 0)
  word:SetText("STACK|cffe0242fRIVALS|r") -- #E0242F = the site's --brand-red; STACK = --foreground #F6F4F0
  self.wordmark = word
  self.modeText = T.display(F, SZ.label, C.label)
  self.modeText:SetPoint("LEFT", word, "RIGHT", 12, -1)

  local close = T.button(F, "\195\151", 30, 26, "frame", function() F:Hide() end) -- U+00D7, not the logo's X
  close:SetPoint("TOPRIGHT", -PAD + 4, -12)
  close.tip = "Close (your run pauses)"
  local settings = T.button(F, "Settings", 84, 26, "frame", function() UI:ShowSettings(true) end)
  settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
  self.settingsBtn = settings

  -- playfield
  local field = Board.createField(F, 10, 20, CELL)
  field:SetPoint("TOP", F, "TOP", 0, -HEADER)
  self.field = field
  -- board frame like the site's: a soft red halo and a 3-step edge (deep red, brand red, light)
  local halo = F:CreateTexture(nil, "BACKGROUND", nil, 2)
  halo:SetTexture(T.MEDIA .. "glow")
  halo:SetPoint("TOPLEFT", field, "TOPLEFT", -56, 56); halo:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 56, -56)
  halo:SetAlpha(0.32)
  for k, c in ipairs({ { T.hex("8A1018") }, C.red, { T.hex("FF5A66") } }) do
    local e = T.tex(F, "BORDER", c, k == 3 and 0.7 or 1, k - 1)
    e:SetPoint("TOPLEFT", field, "TOPLEFT", -(4 - k), 4 - k); e:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 4 - k, -(4 - k))
  end
  -- hard-drop impact: a bright rim that flashes and fades (AnimationGroup, no Lua per frame)
  local rim = CreateFrame("Frame", nil, F)
  rim:SetPoint("TOPLEFT", field, "TOPLEFT", -2, 2); rim:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 2, -2)
  rim:SetFrameLevel(field:GetFrameLevel() + 1)
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
    local l = T.tex(rim, "OVERLAY", C.paper, 1)
    l:SetPoint(side[1]); l:SetPoint(side[2])
    if side[3] then l:SetWidth(side[3]) else l:SetHeight(side[4]) end
  end
  rim:SetAlpha(0)
  self.rim = rim
  local rg = rim:CreateAnimationGroup()
  local ra = rg:CreateAnimation("Alpha"); ra:SetFromAlpha(0.35); ra:SetToAlpha(0); ra:SetDuration(0.35); ra:SetOrder(1); ra:SetSmoothing("OUT")
  self.rimAnim = rg -- quads only (a full-board flash on every drop is too much in a WoW corner)
  self.thump = T.thumpAnim(field, 2) -- hard-drop impact: the board nudges down 2 units and back

  -- left column: hold + stats
  local hold = T.panel(F, C.red)
  hold:SetSize(COL, 96)
  hold:SetPoint("TOPRIGHT", field, "TOPLEFT", -GUTTER, 0)
  local hl = T.label(hold, "HOLD"); hl:SetPoint("TOPLEFT", 10, -9)
  self.holdPreview = Board.createPreview(hold, 15)
  self.holdPreview:SetPoint("TOP", hold, "TOP", 0, -26)

  local stats = T.panel(F)
  stats:SetSize(COL, fieldH - 96 - 10)
  stats:SetPoint("TOPRIGHT", hold, "BOTTOMRIGHT", 0, -10)
  self.stats = stats
  local function label(txt, x, y) local l = T.label(stats, txt); l:SetPoint("TOPLEFT", x, y); return l end
  label("SCORE", 10, -10)
  local scoreBox = CreateFrame("Frame", nil, stats) -- own frame so the score can pulse on clears
  scoreBox:SetSize(COL - 14, 28); scoreBox:SetPoint("TOPLEFT", 8, -24)
  self.scoreText = T.display(scoreBox, 22, C.paper); self.scoreText:SetPoint("LEFT", 2, 0)
  self.scoreText:SetText("0")
  self.scorePulse = T.pulseAnim(scoreBox, 1.12, 0.22, "LEFT")
  self.bestLabel = label("BEST", 10, -60)
  self.bestText = T.display(stats, SZ.big, C.gold); self.bestText:SetPoint("TOPLEFT", 10, -74)
  local div = T.tex(stats, "ARTWORK", C.line, 1); div:SetPoint("TOPLEFT", 10, -100); div:SetPoint("TOPRIGHT", -10, -100); div:SetHeight(1)
  self.statsDiv = div
  self.linesLabel = label("LINES", 10, -112)
  self.linesText = T.display(stats, SZ.title, C.paper); self.linesText:SetPoint("TOPLEFT", 10, -126)
  self.levelLabel = label("LEVEL", 60, -112)
  self.levelText = T.display(stats, SZ.title, C.paper); self.levelText:SetPoint("TOPLEFT", 60, -126)
  -- time sits at the bottom of the panel (steel; red in the last 10 s of a timed run)
  self.timeLabel = T.label(stats, "TIME"); self.timeLabel:SetPoint("BOTTOMLEFT", 10, 40)
  local timeBox = CreateFrame("Frame", nil, stats)
  timeBox:SetSize(COL - 16, 30); timeBox:SetPoint("BOTTOMLEFT", 8, 8)
  self.timeText = T.display(timeBox, 24, C.steel); self.timeText:SetPoint("LEFT", 2, 0)
  self.timeText:SetText("0:00")
  self.timePulse = T.pulseAnim(timeBox, 1.18, 0.3, "LEFT") -- last 5 seconds of a timed run

  -- right column: next queue
  local nextP = T.panel(F, C.red) -- your own panels are red; steel means the rival (as on the site)
  nextP:SetSize(COL, fieldH)
  nextP:SetPoint("TOPLEFT", field, "TOPRIGHT", GUTTER, 0)
  self.nextPanel = nextP
  local nl = T.label(nextP, "NEXT"); nl:SetPoint("TOPLEFT", 10, -9)
  self.nextPreviews = {}
  local y = -26
  for i = 1, 5 do
    local cs = (i == 1) and 15 or 12
    local p = Board.createPreview(nextP, cs)
    p:SetPoint("TOP", nextP, "TOP", 0, y)
    y = y - (4 * cs + 3) - ((i == 1) and 14 or 10)
    self.nextPreviews[i] = p
  end

  -- footer hint
  self.hint = T.text(F, SZ.label, C.label)
  self.hint:SetPoint("BOTTOM", F, "BOTTOM", 0, 10)

  self:CreateOverlays()
  self:CreateMenu()
  self:CreateSettings()
  self:CreateKeyboard()
  if ns.Duel and self.CreateDuel then self:CreateDuel() end
  if ns.Quickplay and self.CreateQuickplay then self:CreateQuickplay() end
  if ns.Chat and self.CreateMatchChat then self:CreateMatchChat() end
  if ns.Account and self.CreateAccount then self:CreateAccount() end
  if ns.LootDuel and self.CreateLootDuel then self:CreateLootDuel() end
  if ns.SpellBattle and self.CreateSpell then self:CreateSpell() end

  F:SetScript("OnShow", function() UI:OnShow() end)
  F:SetScript("OnHide", function() UI:OnHide() end)
  F:SetScript("OnUpdate", function(_, elapsed) UI:OnUpdate(elapsed) end)

  self.W, self.H = W, H
  self:ApplyScale()
  self:RestorePosition()
  self.positioned = true
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
UI.overlayFrame = overlayFrame

--- A full-body sheet (covers the board and both side columns; header stays).
function UI:Body(level, keepFooter)
  local F = self.frame
  local s = CreateFrame("Frame", nil, F)
  s:SetPoint("TOPLEFT", F, "TOPLEFT", 1, -HEADER + 4)
  s:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", -1, keepFooter and (FOOTER - 2) or 1)
  s:SetFrameLevel(F:GetFrameLevel() + (level or 40))
  local bg = T.tex(s, "BACKGROUND", C.navy, 1); bg:SetAllPoints()
  s:EnableMouse(true)
  s:Hide()
  return s
end

function UI:CreateOverlays()
  local field = self.field

  -- Countdown number (pulses on every second)
  local cd = CreateFrame("Frame", nil, field)
  cd:SetSize(120, 90); cd:SetPoint("CENTER", field, "CENTER", 0, -36)
  cd:SetFrameLevel(field:GetFrameLevel() + 6)
  self.countText = T.text(cd, 76, C.redLight, "OUTLINE", nil, "italic")
  self.countText:SetPoint("CENTER")
  self.countBox = cd
  self.countPulse = T.popAnim(cd, 1.6, 0.6, 0.25)
  cd:Hide()

  -- First runs: the controls, shown on the board during the countdown
  -- (upper board: the stack and the ghost stay visible; gone at GO)
  local strip = CreateFrame("Frame", nil, field)
  strip:SetSize(field:GetWidth() - 16, 106); strip:SetPoint("TOP", field, "TOP", 0, -20)
  strip:SetFrameLevel(field:GetFrameLevel() + 6)
  local sbg = T.tex(strip, "BACKGROUND", C.navy, 0.92); sbg:SetAllPoints()
  local sl = T.tex(strip, "BORDER", C.red, 1); sl:SetPoint("TOPLEFT"); sl:SetPoint("TOPRIGHT"); sl:SetHeight(2)
  local sh = T.label(strip, "YOUR KEYS"); sh:SetPoint("TOP", 0, -8)
  self.controlsKeys = T.display(strip, SZ.small, C.paper); self.controlsKeys:SetPoint("TOPRIGHT", strip, "TOP", -6, -26)
  self.controlsKeys:SetWidth(82); self.controlsKeys:SetJustifyH("RIGHT"); self.controlsKeys:SetSpacing(3)
  self.controlsText = T.text(strip, SZ.small, C.label); self.controlsText:SetPoint("TOPLEFT", strip, "TOP", 6, -26)
  self.controlsText:SetWidth(76); self.controlsText:SetJustifyH("LEFT"); self.controlsText:SetSpacing(3)
  self.controlsStrip = strip
  strip:Hide()

  -- Callouts (line clears, combos, level ups): pop in, hold, fade
  local co = CreateFrame("Frame", nil, field)
  co:SetSize(field:GetWidth(), 60); co:SetPoint("TOP", field, "TOP", 0, -64)
  co:SetFrameLevel(field:GetFrameLevel() + 5)
  co:SetSize(field:GetWidth(), 76)
  self.calloutTop = T.display(co, SZ.small, C.gold, "OUTLINE") -- BACK-TO-BACK
  self.calloutTop:SetPoint("TOP", co, "TOP", 0, 0)
  self.callout = T.text(co, 28, C.paper, "OUTLINE", nil, "italic")
  self.callout:SetPoint("TOP", co, "TOP", 0, -16)
  self.callout2 = T.display(co, SZ.big, C.gold, "OUTLINE")
  self.callout2:SetPoint("TOP", self.callout, "BOTTOM", 0, -4)
  self.calloutBox = co
  self.calloutAnim = T.popAnim(co, 1.3, 0.75, 0.35)     -- doubles and up
  self.calloutSoft = T.popAnim(co, 1.0, 0.45, 0.3)      -- singles, level-ups: no scale, shorter
  co:SetAlpha(0)
  -- score gained, floating up from the middle of the board
  local sp = CreateFrame("Frame", nil, field)
  sp:SetSize(field:GetWidth(), 24); sp:SetPoint("TOP", co, "BOTTOM", 0, -6)
  sp:SetFrameLevel(field:GetFrameLevel() + 5)
  self.scorePop = T.display(sp, SZ.title, C.paper, "OUTLINE")
  self.scorePop:SetPoint("CENTER")
  self.scorePopBox = sp
  self.scorePopAnim = T.popAnim(sp, 1.2, 0.55, 0.35, 22)
  sp:SetAlpha(0)

  -- Pause
  local pause = overlayFrame(field, 0.86)
  self.pause = pause
  local pt = T.text(pause, SZ.display, C.paper, "", nil, "italic"); pt:SetPoint("CENTER", 0, 92); pt:SetText("PAUSED")
  self.pauseReason = T.text(pause, SZ.body, C.body); self.pauseReason:SetPoint("TOP", pt, "BOTTOM", 0, -8)
  self.pauseReason:SetWidth(172)
  self.resumeBtn = T.button(pause, "Resume", 164, 32, "primary", function() ns.App:Resume() end)
  self.resumeBtn:SetPoint("CENTER", 0, 4)
  local rs = T.button(pause, "Restart", 164, 28, "frame", function() UI:PlayAgain() end) -- the same mode; a web challenge restarts as that challenge
  rs:SetPoint("TOP", self.resumeBtn, "BOTTOM", 0, -10)
  self.restartBtn = rs
  local qm = T.button(pause, "Quit to menu", 164, 28, "frame", function()
    local s = ns.App.session
    if s and s.duel and ns.Duel.busy() then
      -- a forfeit is a loss: ask for a second click within 3 s
      if not (UI.forfeitArmedAt and GetTime() - UI.forfeitArmedAt < 3) then
        UI.forfeitArmedAt = GetTime()
        UI.quitBtn:SetLabel("Click again to forfeit")
        return
      end
      UI.forfeitArmedAt = nil
    end
    ns.App:Quit() -- in a duel App:Quit turns this into a forfeit
  end)
  qm:SetPoint("TOP", rs, "BOTTOM", 0, -8)
  self.quitBtn = qm
  self.pauseFade = T.fadeInAnim(pause, 0.18)

  -- Game over
  local over = overlayFrame(field, 0.9)
  self.over = over
  self.overTitle = T.text(over, SZ.display, C.paper, "", nil, "italic"); self.overTitle:SetPoint("TOP", 0, -40)
  local scoreBox = CreateFrame("Frame", nil, over)
  scoreBox:SetSize(field:GetWidth(), 44); scoreBox:SetPoint("TOP", self.overTitle, "BOTTOM", 0, -6)
  self.overScore = T.display(scoreBox, SZ.hero, C.paper); self.overScore:SetPoint("CENTER")
  local badgeBox = CreateFrame("Frame", nil, over)
  badgeBox:SetSize(field:GetWidth(), 22); badgeBox:SetPoint("TOP", scoreBox, "BOTTOM", 0, -2)
  self.overBadge = T.display(badgeBox, SZ.big, C.gold); self.overBadge:SetPoint("CENTER")
  self.badgePulse = T.popAnim(badgeBox, 1.5, nil, false) -- pops in and stays
  self.overDetail = T.text(over, SZ.small, C.body); self.overDetail:SetPoint("TOP", badgeBox, "BOTTOM", 0, -10)
  self.overDetail:SetWidth(176); self.overDetail:SetSpacing(2)
  local again = T.button(over, "Play again", 164, 32, "primary", function() UI:PlayAgain() end)
  again:SetPoint("TOP", over, "TOP", 0, -222)
  self.againHint = T.text(over, SZ.label, C.label); self.againHint:SetPoint("TOP", again, "BOTTOM", 0, -4)
  self.againBtn = again
  local menuB = T.button(over, "Modes", 164, 28, "frame", function()
    local s = ns.App.session
    if s and s.spell and not s.duel then ns.App:ShowMenu(); UI:ShowSheet("spell") else ns.App:ShowMenu() end
  end)
  menuB:SetPoint("TOP", again, "BOTTOM", 0, -22)
  self.modesBtn = menuB
  self.shareRow = CreateFrame("Frame", nil, over)
  self.shareRow:SetSize(164, 24); self.shareRow:SetPoint("TOP", menuB, "BOTTOM", 0, -10)
  self.shareLabel = T.label(self.shareRow, "SHARE")
  self.shareGuild = T.button(self.shareRow, "Guild", 56, 24, "steel", function() ns.App:Share("GUILD") end)
  self.shareGroup = T.button(self.shareRow, "Group", 56, 24, "steel", function() ns.App:Share("GROUP") end)
  self.overFade = T.fadeInAnim(over, 0.35)
end

------------------------------------------------------------------------------------------------
-- Mode menu: the whole body, three big cards, one click to play
------------------------------------------------------------------------------------------------
local MODE_EDGE = { classic = "red", blitz = "steel", daily = "gold" }
local MODE_PIECE = { classic = "bar", blitz = "cube", daily = "tee" } -- red, steel-blue, gold pieces

function UI:CreateMenu()
  local menu = self:Body(30, true)
  self.menu = menu
  local cw = self.frame:GetWidth() - 2 * 24 - 2
  local CARD, GAP = 48, 4
  local mt = T.display(menu, SZ.title, C.paper); mt:SetPoint("TOPLEFT", 24, -14); mt:SetText("PICK A MODE")
  local ms = T.text(menu, SZ.small, C.label); ms:SetPoint("TOPLEFT", 24, -38); ms:SetText("Same rules and pieces as stackrivals.io. Click a mode to play.")
  self.menuSub = ms
  self.modeButtons = {}
  local y = -62
  -- big cards: Classic, Time Trial, then LOOT DUEL (Daily Challenge moved to the button row)
  for _, key in ipairs({ "classic", "blitz" }) do
    local mode = Session.MODES[key]
    local b = T.button(menu, "", cw, CARD, key == "daily" and "gold" or "frame", function() ns.App:Start(key) end)
    b:SetPoint("TOP", menu, "TOP", 0, y)
    b.noPress = true
    b.fs:ClearAllPoints(); b.fs:SetPoint("TOPLEFT", 62, -7); b.fs:SetJustifyH("LEFT")
    T.setFont(b.fs, T.DISPLAY, SZ.title)
    b.fs:SetText(mode.name)
    b.desc = T.text(b, SZ.small, C.body); b.desc:SetPoint("TOPLEFT", 62, -29)
    b.desc:SetWidth(200); b.desc:SetJustifyH("LEFT")
    b.desc:SetText(mode.short)
    b.best = T.display(b, SZ.heading, C.gold); b.best:SetPoint("TOPRIGHT", -16, -8); b.best:SetJustifyH("RIGHT")
    b.bestLabel = T.label(b, key == "daily" and "TODAY" or "BEST"); b.bestLabel:SetPoint("RIGHT", b.best, "LEFT", -6, 0); b.bestLabel:SetJustifyH("RIGHT")
    b.side = T.text(b, SZ.label, C.label); b.side:SetPoint("TOPRIGHT", -16, -30); b.side:SetJustifyH("RIGHT")
    local edgeC = C[MODE_EDGE[key]]
    local e = T.tex(b, "ARTWORK", edgeC, 1); e:SetPoint("TOPLEFT", 1, -1); e:SetPoint("BOTTOMLEFT", 1, 1); e:SetWidth(4)
    -- a piece in the mode colour: the cards read as things to play, not form fields
    b.icon = Board.createPreview(b, 9)
    b.icon:SetPoint("LEFT", 14, 0)
    Board.renderPreview(b.icon, MODE_PIECE[key])
    -- hover: the border lights up in the mode colour
    b:HookScript("OnEnter", function(self) self.border:SetColorTexture(edgeC[1], edgeC[2], edgeC[3], 1) end)
    b:HookScript("OnLeave", function(self) local c = self.style.border; self.border:SetColorTexture(c[1], c[2], c[3], 1) end)
    self.modeButtons[key] = b
  end
  self.cardStep = CARD + GAP
  -- LOOT DUEL: the group races for an item (gold, the epic gem); opens the lobby, sends nothing
  local lc = T.button(menu, "", cw, CARD, "gold", function() UI:ShowSheet("loot") end)
  lc.noPress = true
  lc.fs:ClearAllPoints(); lc.fs:SetPoint("TOPLEFT", 62, -7); lc.fs:SetJustifyH("LEFT")
  T.setFont(lc.fs, T.DISPLAY_ITALIC, SZ.title)
  lc.fs:SetText("LOOT DUEL")
  lc.fs:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  lc.desc = T.text(lc, SZ.small, C.body); lc.desc:SetPoint("TOPLEFT", 62, -29); lc.desc:SetWidth(170); lc.desc:SetJustifyH("LEFT")
  lc.desc:SetText("Compete for raid loot")
  lc.cta = T.display(lc, SZ.heading, C.gold); lc.cta:SetPoint("TOPRIGHT", -16, -8); lc.cta:SetJustifyH("RIGHT")
  lc.side = T.text(lc, SZ.label, C.label); lc.side:SetPoint("TOPRIGHT", -16, -30); lc.side:SetJustifyH("RIGHT")
  local ge = T.tex(lc, "ARTWORK", C.gold, 1); ge:SetPoint("TOPLEFT", 1, -1); ge:SetPoint("BOTTOMLEFT", 1, 1); ge:SetWidth(4)
  lc.icon = lc:CreateTexture(nil, "ARTWORK"); lc.icon:SetSize(34, 34); lc.icon:SetPoint("LEFT", 14, 0); lc.icon:SetTexture(T.MEDIA .. "lootduel")
  lc.shine = T.tex(lc, "BACKGROUND", C.gold, 0); lc.shine:SetPoint("TOPLEFT", 1, -1); lc.shine:SetPoint("BOTTOMRIGHT", -1, 1)
  -- hover: a warm gold wash and the CTA in white (calm: no animation over gameplay)
  lc:HookScript("OnEnter", function(self) self.shine:SetAlpha(0.10); self.cta:SetTextColor(C.paper[1], C.paper[2], C.paper[3]) end)
  lc:HookScript("OnLeave", function(self) self.shine:SetAlpha(0); self.cta:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end)
  lc.tip = "Loot Duel: 2-40 players in your party or raid race at once for one item, instead of /roll. Same pieces, no spells. The loot master still hands out the item by hand."
  self.lootCard = lc
  self.lootBtn = lc -- (the old name: everything that opened Loot Duel still does)
  -- QUICKPLAY: one wide red bar between the solo modes and the VERSUS row
  local qp = T.button(menu, "", cw, 34, "primary", function() UI:ShowSheet("quickplay") end)
  qp.noPress = true
  qp.fs:ClearAllPoints(); qp.fs:SetPoint("LEFT", 44, 0); qp.fs:SetJustifyH("LEFT")
  T.setFont(qp.fs, T.DISPLAY_ITALIC, SZ.title)
  qp.fs:SetText("QUICKPLAY")
  qp.icon = qp:CreateTexture(nil, "ARTWORK"); qp.icon:SetSize(24, 24); qp.icon:SetPoint("LEFT", 12, 0); qp.icon:SetTexture(T.MEDIA .. "marksmall")
  qp.desc = T.text(qp, SZ.small, C.paper); qp.desc:SetPoint("RIGHT", -14, 0); qp.desc:SetJustifyH("RIGHT")
  qp.desc:SetText("Quick Duel  -  a random rival")
  qp.tip = "Quick Duel: meet a random StackRivals player who is searching right now and that WoW lets you reach (your guild, your group, friends with StackRivals). A StackRivals puzzle duel, not WoW's /duel. Not connected to stackrivals.io yet."
  self.qpBar = qp
  if ns.BUILD and not ns.BUILD.duels then
    qp:Disable(); qp.desc:SetText("Off in this test build")
    qp.tip = "This is a Spell Battle vs Bot test build: Quickplay and duels are switched off."
  end
  -- VERSUS row: Spell Battle (vs the web's bot) and Duel (a guild / group member)
  local half = math.floor((cw - 8) / 2)
  local function vsCard(name, desc, style, edgeC, iconPath, onClick)
    local b = T.button(menu, "", half, 46, style, onClick)
    b.noPress = true
    b.fs:ClearAllPoints(); b.fs:SetPoint("TOPLEFT", 50, -6); b.fs:SetJustifyH("LEFT")
    T.setFont(b.fs, T.DISPLAY, SZ.heading)
    b.fs:SetText(name)
    b.desc = T.text(b, SZ.label, C.body); b.desc:SetPoint("TOPLEFT", 50, -26); b.desc:SetWidth(half - 58); b.desc:SetJustifyH("LEFT")
    b.desc:SetText(desc)
    local e = T.tex(b, "ARTWORK", edgeC, 1); e:SetPoint("TOPLEFT", 1, -1); e:SetPoint("BOTTOMLEFT", 1, 1); e:SetWidth(4)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 12, 0); b.icon:SetTexture(iconPath)
    b:HookScript("OnEnter", function(self) self.border:SetColorTexture(edgeC[1], edgeC[2], edgeC[3], 1) end)
    b:HookScript("OnLeave", function(self) local c = self.style.border; self.border:SetColorTexture(c[1], c[2], c[3], 1) end)
    return b
  end
  self.spellCard = vsCard("Spell Battle", "vs Bot", "frame", C.red, T.MEDIA .. "Spells\\bomb", function() UI:ShowSheet("spell") end)
  self.spellCard.tip = "Spells, mana and the stackrivals.io bot. Pick 2 spells for your board, 2 for the bot's."
  self.duelBtn = vsCard("Guild Duels", "Guild, friends, group", "frame", C.steel, T.MEDIA .. "marksmall", function() UI:ShowSheet("duel") end)
  self.duelBtn.tip = "Guild Duels: challenge guild members, WoW and Battle.net friends, your group or anyone by name to a Duel or Spell Duel. A StackRivals puzzle duel, not WoW's /duel; both need StackRivals."
  if ns.BUILD and not ns.BUILD.duels then -- vs-Bot test build
    self.duelBtn:Disable(); self.duelBtn.desc:SetText("Off in this test build")
    self.duelBtn.tip = "This is a Spell Battle vs Bot test build: Guild Duels are switched off."
  end
  self.continueBtn = T.button(menu, "Continue last run", cw, 30, "primary", function() ns.App:ContinueSuspended() end)
  self.continueBtn:SetPoint("TOP", menu, "TOP", 0, -40) -- above the cards when there is a run to continue
  self.continueBtn.tip = "Your unfinished run from before /reload or logout, restored exactly."
  -- secondary navigation
  self.navRow = CreateFrame("Frame", nil, menu)
  self.navRow:SetSize(cw, 28); self.navRow:SetPoint("BOTTOM", menu, "BOTTOM", 0, 30)
  self.howBtn = T.button(self.navRow, "How to play", 98, 28, "frame", function() UI:ShowSheet("help") end)
  self.recBtn = T.button(self.navRow, "Records", 98, 28, "frame", function() UI:ShowSheet("records") end)
  self.accBtn = T.button(self.navRow, "Account", 98, 28, "frame", function() UI:ShowSheet("account") end)
  self.accBtn.tip = "Link this character to your stackrivals.io account (one-time code), import your profile, sync."
  -- Daily Challenge keeps its mode, seed and records; it moved from the big cards to this row
  self.dailyBtn = T.button(self.navRow, "Daily Challenge", 124, 28, "gold", function() ns.App:Start("daily") end)
  self.modeButtons.daily = self.dailyBtn
  if ns.BUILD and not ns.BUILD.duels then
    lc:Disable(); lc.cta:SetText(""); lc.side:SetText("Off in this test build")
    lc.tip = "This is a Spell Battle vs Bot test build: Loot Duel is switched off."
  end
  self.howBtn:SetWidth(90); self.recBtn:SetWidth(82); self.accBtn:SetWidth(84)
  self:LayoutNav({ self.howBtn, self.recBtn, self.accBtn, self.dailyBtn }, 6)
  self.statsLine = T.text(menu, SZ.label, C.label); self.statsLine:SetPoint("BOTTOM", 0, 10)
  self.statsLine:SetWidth(cw)
  self.menuFade = T.fadeInAnim(menu, 0.2)
end

--- Centre a row of nav buttons with 10 px gaps.
function UI:LayoutNav(buttons, gap)
  gap = gap or 10
  local total = -gap
  for _, b in ipairs(buttons) do total = total + b:GetWidth() + gap end
  local x = -total / 2
  for _, b in ipairs(buttons) do
    b:ClearAllPoints()
    b:SetPoint("LEFT", self.navRow, "CENTER", x, 0)
    x = x + b:GetWidth() + gap
  end
end

------------------------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------------------------
function UI:CreateSettings()
  local s = self:Body(40)
  self.settings = s
  local db = ns.db
  local L, R = 24, 236

  local title = T.display(s, SZ.title, C.paper); title:SetPoint("TOPLEFT", L, -14); title:SetText("SETTINGS")
  local ver = T.text(s, SZ.label, C.label); ver:SetPoint("TOPRIGHT", -20, -18); ver:SetJustifyH("RIGHT")
  ver:SetText("v" .. (ns.VERSION or "") .. "  -  free, no ads")

  local function section(txt, x, y) local l = T.label(s, txt); l:SetPoint("TOPLEFT", x, y); return l end
  local function toggle(label, key, x, y, after)
    local t = T.toggle(s, label, function(v) db.settings[key] = v; if after then after(v) end end, 204)
    t:SetPoint("TOPLEFT", x, y)
    t.key = key
    return t
  end
  section("GAME", L, -50)
  section("WINDOW", R, -50)
  self.toggles = {
    toggle("Sound effects", "sound", L, -66, function(v) ns.Sound.enabled = v end),
    toggle("Show ghost piece", "ghost", L, -90, function() UI.dirty = true end),
    toggle("Loot Duel group button", "lootButton", L, -114, function() if ns.LootButton then ns.LootButton:Update() end end),
    toggle("Reduce effects", "reduceEffects", L, -138, function() UI:ClearFx() end),
    toggle("Hide window in combat", "hideInCombat", R, -66),
    toggle("Hide minimap button", "minimapHide", R, -92, function() if ns.Minimap then ns.Minimap:Update() end end),
  }
  local sl = T.text(s, SZ.body, C.body); sl:SetPoint("TOPLEFT", R, -126); sl:SetText("Size")
  local minus = T.button(s, "-", 30, 26, "frame", function() UI:SetScale(db.settings.scale - 0.1) end)
  minus:SetPoint("TOPLEFT", R + 52, -120)
  self.scaleText = T.display(s, SZ.body, C.paper); self.scaleText:SetPoint("LEFT", minus, "RIGHT", 10, 0)
  local plus = T.button(s, "+", 30, 26, "frame", function() UI:SetScale(db.settings.scale + 0.1) end)
  plus:SetPoint("LEFT", minus, "RIGHT", 60, 0)
  minus.tip = "Smaller window (100% = fitted to your screen and UI scale)"
  plus.tip = "Bigger window (it never grows past your screen)"

  section("CONTROLS  -  click a key, then press the new key", L, -162)
  self.bindButtons = {}
  local n = 0
  for _, action in ipairs(DB.BIND_ORDER) do
    if not action:match("^spell") then
      n = n + 1
      local col = (n - 1) % 2
      local row = math.floor((n - 1) / 2)
      local lx, ly = (col == 0) and L or R, -180 - row * 30
      local l = T.text(s, SZ.body, C.body); l:SetPoint("TOPLEFT", lx, ly - 6); l:SetText(DB.BIND_LABEL[action])
      local b = T.button(s, "", 96, 26, "frame", function(btn) UI:BeginBind(action, btn) end)
      b:SetPoint("TOPLEFT", lx + 104, ly)
      self.bindButtons[action] = b
    end
  end
  -- Spell Battle keys: one row, slot 1-4 (the order of your loadout)
  local sl2 = T.text(s, SZ.body, C.body); sl2:SetPoint("TOPLEFT", L, -306); sl2:SetText("Spells 1-4")
  for i = 1, 4 do
    local action = "spell" .. i
    local b = T.button(s, "", 50, 26, "frame", function(btn) UI:BeginBind(action, btn) end)
    b:SetPoint("TOPLEFT", L + 104 + (i - 1) * 56, -300)
    b.tip = "Spell slot " .. i .. " (Spell Battle only)"
    self.bindButtons[action] = b
  end
  local alt = T.text(s, SZ.label, C.label); alt:SetPoint("TOPLEFT", L, -336)
  alt:SetWidth(412); alt:SetJustifyH("LEFT"); alt:SetSpacing(2)
  alt:SetText("Also: A/D move, S soft drop, W/X rotate, L-Ctrl rotate left, Shift hold, Esc pause, 1-4 spells. Keys are only captured while a run is live.")
  local rb = T.button(s, "Default controls", 136, 28, "frame", function() DB.resetBindings(db); UI:RefreshSettings() end)
  rb:SetPoint("BOTTOMLEFT", L, 18)
  self.resetRecords = T.button(s, "Reset records", 150, 28, "frame", function(btn)
    if btn.armed then
      DB.resetRecords(db); btn.armed = false; btn:SetLabel("Records reset"); UI:RefreshMenu()
    else
      btn.armed = true; btn:SetLabel("Click again to reset")
    end
  end)
  self.resetRecords:SetPoint("LEFT", rb, "RIGHT", 10, 0)

  local done = T.button(s, "Done", 110, 32, "primary", function() UI:ShowSettings(false) end)
  done:SetPoint("BOTTOMRIGHT", -20, 16)
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
    self.settingsBtn:Hide() -- the sheet has its own Close
    self:RefreshPhase()
  else
    self:EndBind()
    self.settings:Hide()
    self.settingsBtn:Show()
    self:RefreshPhase()
  end
end

function UI:SetScale(v)
  v = math.max(0.7, math.min(1.4, math.floor(v * 10 + 0.5) / 10)) -- factor on the fitted size
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
  if sess and sess.phase == "over" and not ns.App.inMenu and not self:SheetOpen() then
    if self.overReadyAt then
      -- grace second: a game key pressed just after the end is swallowed; anything else is WoW's
      setPropagate(f, DB.actionForKey(ns.db, key) == nil)
      return
    end
    -- only the hard-drop key (play again) is ours; everything else goes to WoW
    -- and only while the cursor is on the window: Space must not be stolen from a player who moved on
    if DB.actionForKey(ns.db, key) == "hardDrop" and not self.overReadyAt and not inCombat() and self.frame:IsMouseOver() then
      setPropagate(f, false)
      UI:PlayAgain()
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
  self:RefreshMenu()
  self.dirty = true
  self:RefreshPhase()
  if ns.Sound.enabled and PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
end

function UI:OnHide()
  self:ClearFx()
  self.overListenUntil = 0 -- after closing the window, "play again" is only by click
  if self.settings and self.settings:IsShown() then self.settings:Hide() end
  if self.help then self.help:Hide(); self.records:Hide() end
  if self.duelSheet then self.duelSheet:Hide() end
  if self.qpSheet then self.qpSheet:Hide() end
  if self.accountSheet then self.accountSheet:Hide() end
  if self.lootSheet then self.lootSheet:Hide() end
  if self.spellSheet then self.spellSheet:Hide() end
  local sess = ns.App.session
  if sess and sess.spell and sess.spell.settling then
    ns.SpellBattle.settleAll(sess) -- the bot's last ticks run while the window is shown; finish them now
    for _, ev in ipairs(sess:takeEvents()) do self:OnEvent(ev) end
  end
  ns.App:Pause("hidden")
  self:EndBind()
  self:SetKeyboard(false)
end

--- The window's centre is stored in UIParent units, so changing the size never moves it.
function UI:SavePosition()
  local F = self.frame
  local cx, cy = F:GetCenter()
  if not cx then return end
  local s = F:GetScale() or 1
  local w = ns.db.window
  w.cx, w.cy = cx * s, cy * s
  w.point, w.relPoint, w.x, w.y = nil, nil, nil, nil
end

function UI:RestorePosition()
  local F, w = self.frame, ns.db.window
  F:ClearAllPoints()
  local s = F:GetScale() or 1
  if w.cx and w.cy then
    F:SetPoint("CENTER", UIParent, "BOTTOMLEFT", w.cx / s, w.cy / s)
  elseif w.point and w.x and w.y then -- position saved by 0.3.1 and older
    F:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x, w.y)
  else
    -- right of centre: the character in the middle of the screen stays visible
    F:SetPoint("CENTER", UIParent, "CENTER", (UIParent:GetWidth() or 0) * 0.18 / s, 20 / s)
  end
end

function UI:ResetPosition()
  local w = ns.db.window
  w.cx, w.cy, w.point, w.relPoint, w.x, w.y = nil, nil, nil, nil, nil, nil
  self:RestorePosition()
end

function UI:Toggle()
  local F = self:Create()
  if F:IsShown() then F:Hide() else F:Show() end
end

function UI:UpdateHint()
  if not self.hint then return end
  local b = ns.db.bindings
  local k = T.keyName
  self.hint:SetText(string.format("%s/%s move  -  %s/%s rotate  -  %s drop  -  %s hold  -  %s pause",
    k(b.left), k(b.right), k(b.rotateCW), k(b.rotateCCW), k(b.hardDrop), k(b.hold), k(b.pause)))
  if self.controlsText then
    self.controlsKeys:SetText(table.concat({ k(b.left) .. " / " .. k(b.right), k(b.rotateCW) .. " / " .. k(b.rotateCCW),
      k(b.softDrop), k(b.hardDrop), k(b.hold), k(b.pause) }, "\n"))
    self.controlsText:SetText(table.concat({ "move", "rotate", "soft drop", "hard drop", "hold", "pause" }, "\n"))
  end
end

--- A player's first few runs show the controls on the board during the countdown.
function UI:FirstRuns()
  local total = 0
  for _, key in ipairs(Session.MODE_ORDER) do total = total + ns.db.records[key].games end
  return total < FIRST_RUNS_WITH_HINT
end

------------------------------------------------------------------------------------------------
-- Per-frame update and drawing
------------------------------------------------------------------------------------------------
function UI:OnUpdate(elapsed)
  local App = ns.App
  local sess = App.session
  if sess then
    if (sess:isActive() or (sess.spell and sess.spell.settling)) and sess:update(elapsed) then self.dirty = true end
    if #sess.events > 0 then
      ns.Sound.begin()
      for _, ev in ipairs(sess:takeEvents()) do self:OnEvent(ev) end
      ns.Sound.flush()
    end
  end
  local now = GetTime()
  if self.overReadyAt and now >= self.overReadyAt then
    self.overReadyAt = nil
    self:RefreshPhase()
  elseif self.keyboardOn and self.overListenUntil and now >= self.overListenUntil
      and sess and sess.phase == "over" then
    self:RefreshPhase() -- listening window over: Space is a jump again
  end
  if self.goUntil and now >= self.goUntil then self.goUntil = nil; self.countBox:Hide() end
  -- the spell status line comes back when a toast is over, also while nothing else redraws
  if self.spellChipsHidden and now >= (self.spellToastUntil or 0) then self.spellChipsHidden = false; self.spellChipBox:SetAlpha(1) end
  if self.forfeitArmedAt and now - self.forfeitArmedAt >= 3 then self.forfeitArmedAt = nil; self:RefreshPhase() end
  if sess and sess.duel and sess.phase == "paused" and now - (self.pauseTextAt or 0) >= 1 then
    self.pauseTextAt = now; self:RefreshPhase() -- the duel's pause-time counter
  end
  if self.menu:IsShown() then
    self.menuClock = (self.menuClock or 0) + elapsed
    if self.menuClock >= 20 then self.menuClock = 0; self:RefreshMenu() end -- daily countdown
  end
  if self.rescale then self.rescale = nil; self:ApplyScale() end
  -- line-clear flash fades out
  local fl = self.field.flash
  local a = fl:GetAlpha()
  if a > 0 then fl:SetAlpha(math.max(0, a - elapsed * 2.2)) end
  if self.dirty then
    self.dirty = false
    self:Render()
  end
end

--- tier: "soft" (single, level up: smaller, gentler), "big" (double/triple), "huge" (quad)
function UI:Callout(main, sub, color, points, tier, top)
  color = color or C.paper
  local size = (tier == "soft") and SZ.title or (tier == "huge") and 34 or 28
  if self.calloutSize ~= size then self.calloutSize = size; T.setFont(self.callout, T.DISPLAY_ITALIC, size, "OUTLINE") end
  self.callout:SetTextColor(color[1], color[2], color[3])
  self.callout:SetText(main or "")
  self.callout2:SetText(sub or "")
  self.calloutTop:SetText(top or "")
  self.calloutAnim:Stop(); self.calloutSoft:Stop()
  if tier == "soft" then self.calloutSoft:Play() else self.calloutAnim:Play() end
  if points and points > 0 then
    -- right under the last visible line of the callout (no gap when there's no combo line)
    local sp = self.scorePopBox
    sp:ClearAllPoints(); sp:SetPoint("TOP", (sub and sub ~= "") and self.callout2 or self.callout, "BOTTOM", 0, -6)
    self.scorePop:SetText("+" .. T.commas(points))
    self.scorePopAnim:Stop(); self.scorePopAnim:Play()
  end
end

function UI:OnEvent(ev)
  self:FxEvent(ev)
  if self.OnSpellEvent and self:OnSpellEvent(ev) then return end
  ns.Sound.forEvent(ev)
  local k = ev.kind
  if k == "clear" then
    local c = ev.b
    local quad = ev.a >= 4
    local fl = self.field.flash
    if quad then fl:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1) else fl:SetColorTexture(1, 1, 1, 1) end
    fl:SetAlpha(quad and 0.26 or 0.08 + 0.05 * ev.a)
    -- combo shown like the site: the 2nd clear in a row is x2 (engine combo + 1)
    local sub = (c.combo and c.combo >= 1) and ("COMBO \195\151" .. (c.combo + 1)) or ""
    self.callout2:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    local tier = quad and "huge" or (ev.a == 1 and "soft" or "big")
    self:Callout(CLEAR_WORD[ev.a] or "CLEAR", sub, quad and C.gold or (ev.a == 1 and C.body or C.paper), c.points, tier,
      c.backToBack and "BACK-TO-BACK" or nil)
    self.clearCalloutAt = GetTime()
    self.scorePulse:Stop(); self.scorePulse:Play()
    if quad then self.rimAnim:Stop(); self.rimAnim:Play() end
  elseif k == "level" then
    if self.clearCalloutAt == GetTime() then
      -- the clear that reached the level is the bigger news: its callout stays, the level goes on the top line
      local top = self.calloutTop:GetText()
      self.calloutTop:SetText(((top and top ~= "") and (top .. "  -  ") or "") .. "LEVEL " .. ev.a)
    else
      self.callout2:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
      self:Callout("LEVEL " .. ev.a, "SPEED UP", C.steel, nil, "soft")
    end
  elseif k == "harddrop" then
    self.thump:Stop(); self.thump:Play()
  elseif k == "count" or k == "go" then
    if k == "go" then
      setStr(self.countText, "GO!")
      self.countBox:Show(); self.countPulse:Stop(); self.countPulse:Play()
      self.goUntil = GetTime() + 0.7
      self.controlsStrip:Hide() -- the board is yours from GO
    end
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
    setStr(self.bestText, "-")
    Board.renderPreview(self.holdPreview, nil)
    for _, p in ipairs(self.nextPreviews) do Board.renderPreview(p, nil) end
    for _, c in ipairs(self.field.cells) do c.base:SetColorTexture(C.cell[1], C.cell[2], C.cell[3], 1); c.hi:Hide(); c.lo:Hide(); c.gl:Hide(); c.gr:Hide(); c.ghost = false; c.value = -1 end
    return
  end
  local s = sess.state
  Board.renderField(self.field, s, ns.db.settings.ghost)
  Board.renderPreview(self.holdPreview, s.hold, s.holdUsed)
  for i, p in ipairs(self.nextPreviews) do Board.renderPreview(p, s.queue[i], false) end
  local big = s.score >= 1000000 -- 7 digits: a size down so it stays inside the panel
  if self.scoreBig ~= big then self.scoreBig = big; T.setFont(self.scoreText, T.DISPLAY, big and SZ.title or 22) end
  setNum(self.scoreText, s.score, T.commas)
  setNum(self.linesText, s.lines)
  setNum(self.levelText, s.level)
  local left = sess:timeLeftTicks()
  local timed = left ~= nil
  if self.timeTimed ~= timed then
    -- a countdown is a headline in Blitz; Classic's elapsed time is just information
    self.timeTimed = timed
    T.setFont(self.timeText, T.DISPLAY, timed and 24 or SZ.big)
    self.timeUrgent = nil
  end
  if left then
    setStr(self.timeLabel, "TIME LEFT")
    local secs = math.ceil(left / 60)
    if secs <= 5 and secs > 0 and self.timeText._n ~= secs then
      self.timePulse:Stop(); self.timePulse:Play()
      if sess.phase == "playing" then ns.Sound.play("count") end -- 5..1: heard, not only seen beside the board
    end
    self:FxDanger(left < 600 and sess.phase == "playing")
    setNum(self.timeText, secs, T.clock)
    local urgent = left < 600
    if self.timeUrgent ~= urgent then
      self.timeUrgent = urgent
      local c = urgent and C.redLight or C.steel
      self.timeText:SetTextColor(c[1], c[2], c[3])
    end
  else
    setStr(self.timeLabel, "TIME")
    setNum(self.timeText, math.floor(s.tick / 60), T.clock)
    if self.timeUrgent ~= false then self.timeUrgent = false; self.timeText:SetTextColor(C.label[1], C.label[2], C.label[3]) end
  end
  if sess.mode.ghost and self.RenderGhost then
    self:RenderGhost(sess) -- Race My Best: ahead / behind your best (UI/GhostUI.lua)
  elseif sess.duel then
    -- duel: the lead over the rival instead of a personal best
    local lead = s.score - (sess.duel.rival_.score or 0)
    setStr(self.bestLabel, "LEAD")
    if self.bestLabel._c then self.bestLabel._c = nil; self.bestLabel:SetTextColor(C.label[1], C.label[2], C.label[3]) end
    setStr(self.bestText, (lead > 0 and "+" or (lead < 0 and "-" or "")) .. T.commas(math.abs(lead)))
    local c = lead >= 0 and C.green or C.redLight
    if self.bestText._c ~= c then self.bestText._c = c; self.bestText:SetTextColor(c[1], c[2], c[3]) end
  else
    setStr(self.bestLabel, "BEST")
    if self.bestLabel._c then self.bestLabel._c = nil; self.bestLabel:SetTextColor(C.label[1], C.label[2], C.label[3]) end
    if self.bestText._c ~= C.gold then self.bestText._c = C.gold; self.bestText:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
    local best = ns.App:BestFor(sess.mode.key)
    if best > 0 then setNum(self.bestText, best, T.commas) else setStr(self.bestText, "-") end
  end
  local n = sess:countdownNumber()
  if n then
    if self.countText._n ~= n then
      setNum(self.countText, n)
      self.countPulse:Stop(); self.countPulse:Play()
    end
    self.countBox:Show()
  elseif not self.goUntil then
    self.countBox:Hide()
  end
  if sess.duel and self.RenderRival then self:RenderRival() end
  if sess.spell and self.RenderSpell then self:RenderSpell(sess) end
end

--- Show the overlay that matches the current phase and take/release the keyboard.
function UI:RefreshPhase()
  if not self.frame then return end
  local App = ns.App
  local sess = App.session
  local phase = sess and sess.phase or "menu"
  if App.inMenu then phase = "menu" end
  if self.fxSession ~= sess then self.fxSession = sess; self:ClearFx() end -- another run (or none): no leftover effects
  if phase == "menu" and not self.menu:IsShown() then self.menu:Show(); self.menuFade:Play() end
  if phase ~= "menu" then self.menu:Hide() end
  if phase == "paused" and not self.pause:IsShown() then self.pause:Show(); self.pauseFade:Play() end
  if phase ~= "paused" then self.pause:Hide() end
  self.over:SetShown(phase == "over")
  if phase == "countdown" then
    self.countBox:Show()
    if self:FirstRuns() and not self.controlsStrip:IsShown() then self.controlsStrip:Show() end
  else
    self.controlsStrip:Hide()
    if phase ~= "playing" and not self.goUntil then self.countBox:Hide() end
  end
  self.modeText:SetText(sess and not App.inMenu and string.upper(sess.mode.name) or "")
  if self.SetSpellLayout then self:SetSpellLayout((sess and sess.spell and not App.inMenu) and true or false, sess and sess.spell and sess.spell.remote) end
  if self.RefreshDuel and self:RefreshDuel(phase) then phase = "lobby" end
  if phase == "paused" then
    local r = sess.pauseReason
    local txt = (r == "combat") and (inCombat() and "You entered combat. Finish the fight, then resume." or "Combat's over. Resume when ready.")
      or (r == "hidden") and "Window was closed. Your run is saved here."
      or (r == "chat") and "Paused so you can type. Resume when ready."
      or (r == "settings") and "Settings were open."
      or (r == "loading") and "Paused for the loading screen."
      or "Take your time."
    local m = sess.duel
    local waitRival = m and r == "rival"
    if waitRival then
      local who = ns.Duel.short(m.rival) or "Your rival"
      txt = m.rivalPaused and (who .. " is paused" .. (m.rivalPauseReason == "combat" and " (combat)" or "") .. ". The duel waits for both of you.")
        or "Starting again..."
    elseif m and m.state == "playing" then
      local left = math.max(0, math.floor(ns.Duel.PAUSE_BUDGET - (m.myPaused or 0)))
      txt = txt .. "\nYour rival waits too. Pause left: " .. left .. " s."
    end
    self.pauseReason:SetText(txt)
    if inCombat() then self.resumeBtn:Disable(); self.resumeBtn:SetLabel("In combat...")
    elseif waitRival then self.resumeBtn:Disable(); self.resumeBtn:SetLabel("Waiting for rival...")
    else self.resumeBtn:Enable(); self.resumeBtn:SetLabel("Resume") end
    local duel = sess.duel ~= nil
    self.restartBtn:SetShown(not duel and not sess.loot)
    if not (self.forfeitArmedAt and GetTime() - self.forfeitArmedAt < 3) then
      self.quitBtn:SetLabel(duel and "Forfeit duel" or "Quit to menu")
    end
  end
  local live = sess and (phase == "countdown" or phase == "playing")
  -- While paused (out of combat, no sheet open) we listen too, but only to take the pause key
  -- back; every other key is handed straight to WoW.
  local quiet = not inCombat() and not self:SheetOpen()
  local pausedListen = phase == "paused" and quiet
  -- Game over: the hard-drop key restarts for 15 s after the result appears (then it's a
  -- normal WoW key again, so a player who walks away can jump).
  local overListen = phase == "over" and quiet and not self.overReadyAt
    and (self.overListenUntil or 0) > GetTime()
  if sess and (sess.duel or sess.loot) then overListen = false end -- a duel needs a deliberate click; a Loot Duel is one run
  -- The second after a run ends: the keyboard stays ours and game keys are swallowed (OnKeyDown), so a key
  -- pressed for the game a moment too late doesn't move the character or fire an action bar button.
  local overGrace = phase == "over" and quiet and self.overReadyAt ~= nil
  if phase ~= "countdown" and phase ~= "playing" then self.down = {} end -- a key released while chat had focus
  if phase == "over" and self.againHint then
    self.againHint:SetText((sess and (sess.duel or sess.loot)) and "" or ("or press " .. T.keyName(ns.db.bindings.hardDrop)))
    self.againHint:SetAlpha(overListen and 1 or 0)
  end
  if not self.binding then self:SetKeyboard((live or pausedListen or overListen or overGrace) and self.frame:IsShown()) end
  self.dirty = true
end

function UI:RefreshMenu()
  if not self.modeButtons then return end
  local db = ns.db
  for key, b in pairs(self.modeButtons) do
    local best = ns.App:BestFor(key)
    if key == "daily" then
      -- the button row: today's best, tries and the reset time live in the tooltip
      local d = db.records.dailyToday
      local today = ns.App:Today()
      local tries = (d.date == today) and d.tries or 0
      local left = ns.App:SecondsToUtcMidnight()
      b.tip = "Daily Challenge: today " .. (best > 0 and T.commas(best) or "-")
        .. (tries > 0 and ("  (" .. T.plural(tries, "try", "tries") .. ")") or "") .. ". "
        .. string.format("New pieces in %dh %02dm. ", math.floor(left / 3600), math.floor(left % 3600 / 60))
        .. "Everyone gets the same pieces until 00:00 UTC (seed " .. today .. ")."
    else
      b.best:SetText(best > 0 and T.commas(best) or "-")
      b.side:SetText("")
    end
    if inCombat() then b:Disable() else b:Enable() end
  end
  self:RefreshLootCard()
  -- Continue (if any) sits above the cards; the cards move down to make room
  local su = db.suspended
  self.continueBtn:SetShown(su ~= nil)
  if su then
    local m = Session.MODES[su.mode]
    self.continueBtn:SetLabel("Continue your " .. (m and m.name or "last") .. " run")
  end
  -- with a run to continue the subtitle makes room for the Continue button
  self.menuSub:SetShown(su == nil)
  local y = su and -74 or -62
  for _, b in ipairs({ self.modeButtons.classic, self.modeButtons.blitz, self.lootCard }) do
    b:ClearAllPoints(); b:SetPoint("TOP", self.menu, "TOP", 0, y)
    y = y - self.cardStep
  end
  self.qpBar:ClearAllPoints(); self.qpBar:SetPoint("TOP", self.menu, "TOP", 0, y)
  y = y - 38
  if self.RefreshQuickplayBar then self:RefreshQuickplayBar() end
  local cw = self.spellCard:GetWidth()
  self.spellCard:ClearAllPoints(); self.spellCard:SetPoint("TOPLEFT", self.menu, "TOP", -cw - 4, y)
  self.duelBtn:ClearAllPoints(); self.duelBtn:SetPoint("TOPLEFT", self.menu, "TOP", 4, y)
  local sd = db.spell and db.spell.difficulty
  if sd then
    local st = db.spell.stats[sd]
    local rec = (st.wins + st.losses + st.draws > 0) and string.format("  -  %d-%d", st.wins, st.losses) or ""
    self.spellCard.desc:SetText("vs " .. (UI.DIFF_LABEL and UI.DIFF_LABEL[sd] or sd) .. " bot" .. rec)
  end
  local du = db.duels
  if du and du.wins + du.losses + du.draws > 0 and (not ns.BUILD or ns.BUILD.duels) then self.duelBtn.desc:SetText(string.format("Friends & guild  -  %d-%d", du.wins, du.losses)) end
  if inCombat() then self.spellCard:Disable() else self.spellCard:Enable() end
  -- a brand-new player gets a default: Blitz is the short, forgiving way in
  local fresh = true
  for _, k in ipairs(Session.MODE_ORDER) do if db.records[k].games > 0 then fresh = false end end
  local blitz = self.modeButtons.blitz
  if fresh then blitz.bestLabel:SetText(""); blitz.best:SetText("Start here"); blitz.best:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
  else blitz.bestLabel:SetText("BEST"); blitz.best:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
  -- first visit: point at the how-to-play sheet without forcing it (play is one click away)
  -- first visit: the how-to-play button is lit red (the nav row has no room for a longer label)
  local hc = (not db.seenHelp) and C.red or C.line
  self.howBtn.border:SetColorTexture(hc[1], hc[2], hc[3], 1)
  self.howBtn:SetLabel(db.seenHelp and "How to play" or "New? Help")
  self.howBtn.tip = db.seenHelp and nil or "New here? The rules, points and keys in one screen."
  local total, lines = 0, 0
  for _, k in ipairs(Session.MODE_ORDER) do
    total = total + db.records[k].games
    lines = lines + db.records[k].totalLines
  end
  if inCombat() then self.statsLine:SetText("In combat. Play after the fight.")
  else self.statsLine:SetText(total > 0 and (T.commas(total) .. " runs  -  " .. T.commas(lines) .. " lines cleared") or "Combat pauses the game and gives your keys back.") end
end

--- The Loot Duel card's call to action: what a click does right now (it never sends anything).
function UI:RefreshLootCard()
  local lc = self.lootCard
  local LD = ns.LootDuel
  if not lc or not LD or (ns.BUILD and not ns.BUILD.duels) then return end
  local d = LD.current
  local me = ns.Comm and ns.Comm.me()
  local cta, side
  if d and d.state == "inviting" and d.role ~= "leader" and not d.myAnswer and me and ns.Comm.same and (function()
    for _, n in ipairs(d.inviteOrder or {}) do if ns.Comm.same(n, me) then return true end end end)() then
    cta, side = "Join now", "Invite from " .. (ns.Duel and ns.Duel.short(d.leader) or d.leader)
  elseif d and (d.state == "inviting" or d.state == "revealing") then
    cta, side = "Open lobby", (d.role == "leader") and (#LD.accepted(d) .. " joined") or "Waiting for the start"
  elseif d and d.state == "playing" then
    cta, side = "Live now", #(d.participants or {}) .. " players racing"
  else
    local n = #LD.roster()
    local okLead = LD.mayLead()
    if okLead then cta, side = "Create Loot Duel", ((IsInRaid and IsInRaid()) and "Raid of " or "Party of ") .. n
    elseif LD.channel() then cta, side = "Open", "Your leader starts it"
    else cta, side = "Create Loot Duel", "For parties and raids" end
  end
  lc.cta:SetText(cta); lc.side:SetText(side)
  if inCombat() then lc:Disable() else lc:Enable() end
end

--- A panel beside the window (live standings, match chat): on the right, or on the left when the right
--- side would be off screen (wide addon scale, 4:3 / 16:10 screens). Only the main window is clamped.
function UI:PlaceSidePanel(p)
  local F = self.frame
  if not (p and F) then return end
  local left = false
  if F.GetRight and F:GetRight() and UIParent.GetWidth then
    local sc = F:GetScale() or 1
    local room = (UIParent:GetWidth() or 0) - F:GetRight() * sc
    local need = (p:GetWidth() + 6) * sc
    left = room < need and (F:GetLeft() or 0) * sc >= need
  end
  if p.sideLeft == left then return end
  p.sideLeft = left
  p:ClearAllPoints()
  if left then p:SetPoint("TOPRIGHT", F, "TOPLEFT", -6, 0) else p:SetPoint("TOPLEFT", F, "TOPRIGHT", 6, 0) end
end
function UI:PlaceSidePanels()
  if self.lootBoard and self.lootBoard:IsShown() then self:PlaceSidePanel(self.lootBoard) end
  if self.chat and self.chat:IsShown() then self:PlaceSidePanel(self.chat) end
end

--- Stop every transient effect (callout, score pop, flashes, spell toast). Called when the run on screen
--- changes or ends and when the window hides, so nothing from one run plays over the next.
function UI:ClearFx()
  self.calloutAnim:Stop(); self.calloutSoft:Stop(); self.calloutBox:SetAlpha(0)
  self.scorePopAnim:Stop(); self.scorePopBox:SetAlpha(0)
  self.field.flash:SetAlpha(0)
  self.rimAnim:Stop()
  self.clearCalloutAt = nil
  if self.FxClear then self:FxClear() end
  if self.spellFxAnim then self.spellFxAnim:Stop(); self.spellFx:SetAlpha(0) end
  if self.spellToastAnim then self.spellToastAnim:Stop(); self.spellToastBox:SetAlpha(0); self.spellToastUntil = 0 end
end

function UI:ShowOver(info)
  local s = info.state
  -- a callout from the last line clear must not sit behind the result
  self:ClearFx()
  self.overBadge:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  self.overTitle:SetTextColor(C.paper[1], C.paper[2], C.paper[3])
  self.againBtn:SetLabel("Play again")
  if info.duel then
    self.overReadyAt, self.overListenUntil = GetTime() + 1.0, 0
    self.badgePulse:Stop()
    self:ShowDuelOver(info.duel)
    self.overFade:Play()
    self:RefreshPhase()
    return
  end
  self.modesBtn:SetLabel("Modes")
  if info.spell then
    self.overReadyAt = GetTime() + 1.0
    self.overListenUntil = GetTime() + 6.0
    self.badgePulse:Stop()
    self:ShowSpellOver(ns.App.session)
    self.overFade:Play()
    self:RefreshPhase()
    return
  end
  self.overTitle:SetText(info.reason == "time" and "TIME!" or "GAME OVER")
  self.overScore:SetText(T.commas(s.score))
  self.badgePulse:Stop()
  if info.ghost and self.ShowGhostOver then
    self:ShowGhostOver(info)
  elseif info.loot then
    self.overBadge:SetText("WAITING FOR THE OTHERS...")
  elseif info.challenge then
    self.overBadge:SetText("RESULT CODE READY")
  elseif info.newBest then
    self.overBadge:SetText(info.prevBest > 0 and ("NEW BEST  +" .. T.commas(s.score - info.prevBest)) or "NEW BEST")
    self.badgePulse:Play(); self:FxResult("best")
  elseif info.newTodayBest then
    self.overBadge:SetText("BEST TODAY")
    self.badgePulse:Play(); self:FxResult("best")
  else
    self.overBadge:SetText("Best " .. T.commas(ns.App:BestFor(info.mode)))
  end
  local c = s.clears
  local rankTxt = info.rank and ("#" .. info.rank .. " in your top 5  -  ") or ""
  local quads = (c.quad > 0) and string.format("  -  %d %s", c.quad, c.quad == 1 and "quad" or "quads") or ""
  if not info.ghost then self.overDetail:SetText(info.loot and string.format("%d lines  -  level %d%s\nThe best runs are replayed on every PC. The result opens when all are in.", s.lines, s.level, quads)
    or info.challenge and string.format("%d lines  -  level %d%s\nCopy it from Account > Sync and paste it on stackrivals.io.", s.lines, s.level, quads)
    or string.format("%d lines  -  level %d%s\n%s%s", s.lines, s.level, quads, rankTxt, info.modeName)) end
  local g, p = IsInGuild and IsInGuild() or false, IsInGroup and IsInGroup() or false
  self.shareGuild:SetShown(g); self.shareGroup:SetShown(p); self.shareLabel:SetShown(g or p)
  -- centre whatever is visible: SHARE [Guild] [Group]
  local items, widths, total = { self.shareLabel }, { 40 }, 40
  if g then items[#items + 1] = self.shareGuild end
  if p then items[#items + 1] = self.shareGroup end
  for i = 2, #items do widths[i] = items[i]:GetWidth(); total = total + 6 + widths[i] end
  local x = -total / 2
  for i, o in ipairs(items) do
    o:ClearAllPoints(); o:SetPoint("LEFT", self.shareRow, "CENTER", x, 0); x = x + widths[i] + 6
  end
  self.overFade:Play()
  -- "press <hard drop> to play again", accepted after a short grace period so a player who is
  -- still hammering hard drop at top-out sees the result first
  self.overReadyAt = GetTime() + 1.0
  self.overListenUntil = GetTime() + 6.0 -- then Space is a jump again
  self:RefreshPhase()
end

function UI:PlayAgain()
  local s = ns.App.session
  if s and s.challenge and ns.App.lastChallenge then ns.App:StartChallenge(ns.App.lastChallenge); return end
  if s and s.loot then return end -- one run per Loot Duel
  if s and s.mode.ghost then ns.App:StartGhost(s.mode.base); return end -- race your best again (a won race is the new ghost)
  ns.App:Start((s and not s.duel and not s.mode.duel and s.mode.key) or ns.App.lastMode or "classic")
end

------------------------------------------------------------------------------------------------
-- Size: fitted to the screen, then the player's own factor
------------------------------------------------------------------------------------------------
UI.SCREEN_SHARE = 0.58 -- the window's height as a share of the screen at "100%"

--- 100% = the window takes ~58% of the screen height at ANY resolution and WoW UI scale
--- (UIParent's height in UI units is 768 / UI scale, so this is resolution-independent).
--- The player's factor (70-140%) multiplies it; the result never exceeds the screen.
function UI:ApplyScale()
  local F = self.frame
  if not F then return end
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  local auto = 1
  if sh and sh > 0 then auto = math.max(1.0, math.min(3.2, sh * UI.SCREEN_SHARE / self.H)) end -- floor 1:1 keeps labels at 11 px; 4K at a small UI scale needs ~3x
  local want = auto * (ns.db.settings.scale or 1)
  if sw and sh and sw > 0 and sh > 0 then
    local fit = math.min((sw - 24) / self.W, (sh - 24) / self.H)
    if fit < want then want = math.max(0.5, fit) end
  end
  -- crisp grid: one board cell (18 + 1 units) becomes a whole number of physical pixels
  local ppu
  if GetPhysicalScreenSize then
    local _, physH = GetPhysicalScreenSize()
    local es = UIParent:GetEffectiveScale() or 1
    if physH and physH > 0 then
      ppu = es * physH / 768
      local pitch = 19 * want * ppu
      if pitch > 4 then want = want * math.floor(pitch + 0.5) / pitch end
    end
  end
  F:SetScale(want)
  self.appliedScale = want
  self.autoScale = auto
  -- the full mark (cuts + diamond) needs 32 px; smaller than that the simplified mark (web brand rule)
  if self.mark and ppu then self.mark:SetTexture(T.MEDIA .. ((32 * want * ppu < 32) and "marksmall" or "mark")) end
  if self.positioned then self:RestorePosition() end -- the centre stays where the player put it
end

------------------------------------------------------------------------------------------------
-- Full-body sheets: How to play, Records
------------------------------------------------------------------------------------------------
local function makeSheet(self, titleText)
  local s = self:Body(40)
  local title = T.display(s, SZ.title, C.paper); title:SetPoint("TOPLEFT", 24, -14); title:SetText(titleText)
  local done = T.button(s, "Close", 130, 32, "frame", function() s:Hide(); UI:RefreshPhase() end)
  done:SetPoint("BOTTOMRIGHT", -20, 16)
  s.done = done
  s.title = title
  return s
end

function UI:CreateHelp()
  local s = makeSheet(self, "HOW TO PLAY")
  self.help = s
  local L, R = 24, 248
  local function head(txt, x, y, c) local l = T.label(s, txt); l:SetPoint("TOPLEFT", x, y); if c then l:SetTextColor(c[1], c[2], c[3]) end; return l end
  -- left: the goal and the scoring
  head("THE GOAL", L, -50, C.redLight)
  local goal = T.text(s, SZ.body, C.body); goal:SetPoint("TOPLEFT", L, -66)
  goal:SetWidth(204); goal:SetJustifyH("LEFT"); goal:SetSpacing(3)
  goal:SetText("|cfff6f4f0Fill a row to clear it.|r Clear several rows at once for big points and keep clearing for combos. It speeds up every 10 lines; the run ends when the stack reaches the top.")
  head("POINTS  (x level)", L, -168, C.gold)
  local rows = { { "Single", "100" }, { "Double", "300" }, { "Triple", "500" }, { "Quad", "800" } }
  for i, r in ipairs(rows) do
    local y = -186 - (i - 1) * 20
    local n = T.text(s, SZ.body, C.body); n:SetPoint("TOPLEFT", L, y); n:SetText(r[1])
    local v = T.display(s, SZ.body, i == 4 and C.gold or C.paper); v:SetPoint("TOPRIGHT", s, "TOPLEFT", L + 196, y); v:SetJustifyH("RIGHT"); v:SetText(r[2])
  end
  local extra = T.text(s, SZ.label, C.label); extra:SetPoint("TOPLEFT", L, -270)
  extra:SetWidth(204); extra:SetJustifyH("LEFT"); extra:SetSpacing(2)
  extra:SetText("Quad after quad: x1.5 (back-to-back). Combos add 50 x level per step.")
  -- right: the controls as keycaps
  head("CONTROLS", R, -50, C.steel)
  s.keyRows = {}
  local actions = {
    { { "left", "right" }, "Move" }, { { "rotateCW", "rotateCCW" }, "Rotate" }, { { "softDrop" }, "Soft drop" },
    { { "hardDrop" }, "Hard drop" }, { { "hold" }, "Hold piece" }, { { "pause" }, "Pause" }, { { "ENTER" }, "Chat (pauses)" },
  }
  for i, a in ipairs(actions) do
    local y = -66 - (i - 1) * 28
    local caps = {}
    for j = 1, #a[1] do caps[j] = T.keycap(s, "") end
    local lbl = T.text(s, SZ.body, C.body); lbl:SetText(a[2])
    s.keyRows[i] = { keys = a[1], caps = caps, y = y, lbl = lbl }
  end
  -- safety strip
  local strip = T.panel(s, C.green)
  local stripW = self.frame:GetWidth() - 2 * 24 - 2
  strip:SetSize(stripW, 58); strip:SetPoint("TOPLEFT", L, -296)
  local sh = T.label(strip, "SAFE IN WOW"); sh:SetPoint("TOPLEFT", 12, -9); sh:SetTextColor(C.green[1], C.green[2], C.green[3])
  local st = T.text(strip, SZ.small, C.body); st:SetPoint("TOPLEFT", 12, -24)
  st:SetWidth(stripW - 24); st:SetJustifyH("LEFT"); st:SetSpacing(2)
  st:SetText("Keys are only taken while you play. Combat pauses the game at once and gives every key back. /reload never loses a run.")
  -- play straight from here
  local play = T.button(s, "Play Time Trial", 170, 32, "primary", function() s:Hide(); ns.App:Start("blitz") end)
  play:SetPoint("RIGHT", s.done, "LEFT", -10, 0)
  s.play = play
  s:SetScript("OnShow", function()
    ns.db.seenHelp = true
    UI:RefreshMenu() -- drop the "New?" nudge
    local b = ns.db.bindings
    for _, row in ipairs(s.keyRows) do
      local x = R
      for j, cap in ipairs(row.caps) do
        local key = row.keys[j]
        cap:SetKey(T.keyName(b[key] or key))
        cap:ClearAllPoints(); cap:SetPoint("TOPLEFT", s, "TOPLEFT", x, row.y)
        x = x + cap:GetWidth() + 4
      end
      -- the action name follows the keys (long rebinds push it right instead of overlapping)
      row.lbl:ClearAllPoints(); row.lbl:SetPoint("TOPLEFT", s, "TOPLEFT", math.max(R + 112, x + 6), row.y - 4)
    end
  end)
end

function UI:CreateRecords()
  local s = makeSheet(self, "RECORDS")
  self.records = s
  local note = T.text(s, SZ.small, C.label)
  note:SetPoint("TOPLEFT", 24, -38)
  note:SetText("Stored on this PC only, not verified. Race best: Race My Best only.")
  s.cards = {}
  local cw = math.floor((self.frame:GetWidth() - 2 * 24 - 2 - 2 * 10) / 3)
  for i, key in ipairs(Session.MODE_ORDER) do
    local card = T.panel(s, C[MODE_EDGE[key]])
    card:SetSize(cw, 300)
    card:SetPoint("TOPLEFT", 24 + (i - 1) * (cw + 10), -62)
    local name = T.display(card, SZ.big, C.paper); name:SetPoint("TOPLEFT", 10, -10); name:SetText(Session.MODES[key].name)
    local bl = T.label(card, key == "daily" and "BEST EVER" or "BEST"); bl:SetPoint("TOPLEFT", 10, -36)
    card.best = T.display(card, 22, C.gold); card.best:SetPoint("TOPLEFT", 10, -50)
    local tl = T.label(card, "TOP 5"); tl:SetPoint("TOPLEFT", 10, -84)
    card.top = {}
    for n = 1, 5 do
      local y = -100 - (n - 1) * 17
      local rank = T.display(card, SZ.label, C.label); rank:SetPoint("TOPLEFT", 10, y); rank:SetText(n .. ".")
      local sc = T.display(card, SZ.small, C.paper); sc:SetPoint("TOPLEFT", 26, y)
      local dt = T.text(card, SZ.label, C.label); dt:SetPoint("TOPRIGHT", -10, y); dt:SetJustifyH("RIGHT")
      card.top[n] = { sc = sc, dt = dt, rank = rank }
    end
    local div = T.tex(card, "ARTWORK", C.line, 1); div:SetPoint("TOPLEFT", 10, -192); div:SetPoint("TOPRIGHT", -10, -192); div:SetHeight(1)
    card.stats = {}
    local names = { "Runs", "Lines", "Quads", "Best level", "Played" }
    if key == "daily" then names[#names + 1] = "Today" end
    if key ~= "daily" then names[#names + 1] = "Race best" end -- Race My Best: not an official record
    for n, label in ipairs(names) do
      local y = -202 - (n - 1) * 16
      local l = T.text(card, SZ.label, C.label); l:SetPoint("TOPLEFT", 10, y); l:SetText(label)
      local v = T.display(card, SZ.small, C.body); v:SetPoint("TOPRIGHT", -10, y); v:SetJustifyH("RIGHT")
      card.stats[n] = v
    end
    card.key = key
    s.cards[i] = card
  end
  s:SetScript("OnShow", function()
    local db = ns.db
    for _, card in ipairs(s.cards) do
      local r = db.records[card.key]
      card.best:SetText(r.best > 0 and T.commas(r.best) or "-")
      for n = 1, 5 do
        local e, row = r.top[n], card.top[n]
        row.sc:SetText(e and T.commas(e.s) or (n == 1 and "No runs yet" or ""))
        row.dt:SetText(e and e.d and e.d:sub(6) or "")
        row.rank:SetShown(e ~= nil)
        if not e and n == 1 then row.sc:SetTextColor(C.label[1], C.label[2], C.label[3]) else row.sc:SetTextColor(C.paper[1], C.paper[2], C.paper[3]) end
      end
      local vals = { T.commas(r.games), T.commas(r.totalLines), T.commas(r.quads), tostring(r.bestLevel), T.duration(r.playSeconds) }
      if card.key == "daily" then
        local d = db.records.dailyToday
        vals[6] = (d.date == ns.App:Today() and d.tries > 0) and (T.commas(d.best) .. " \195\151" .. d.tries) or "-"
      end
      if card.key ~= "daily" then
        local rr = db.raceRecords and db.raceRecords[card.key]
        vals[6] = (rr and rr.best > 0) and T.commas(rr.best) or "-"
      end
      for n, v in ipairs(vals) do card.stats[n]:SetText(v) end
    end
  end)
end

function UI:SheetOpen()
  return (self.help and self.help:IsShown()) or (self.records and self.records:IsShown()) or (self.settings and self.settings:IsShown())
    or (self.duelSheet and self.duelSheet:IsShown()) or (self.spellSheet and self.spellSheet:IsShown())
    or (self.qpSheet and self.qpSheet:IsShown()) or (self.accountSheet and self.accountSheet:IsShown())
    or (self.lootSheet and self.lootSheet:IsShown()) or false
end

function UI:HideSheets()
  if self.help then self.help:Hide(); self.records:Hide() end
  if self.duelSheet then self.duelSheet:Hide() end
  if self.qpSheet then self.qpSheet:Hide() end
  if self.accountSheet then self.accountSheet:Hide() end
  if self.lootSheet then self.lootSheet:Hide() end
  if self.spellSheet then self.spellSheet:Hide() end
  if self.settings and self.settings:IsShown() then self:ShowSettings(false) end
end

function UI:ShowSheet(which)
  if not self.help then self:CreateHelp(); self:CreateRecords() end
  ns.App:Pause("settings")
  self.help:SetShown(which == "help")
  self.records:SetShown(which == "records")
  if self.duelSheet then self.duelSheet:SetShown(which == "duel") end
  if self.qpSheet then self.qpSheet:SetShown(which == "quickplay") end
  if self.accountSheet then self.accountSheet:SetShown(which == "account") end
  if self.lootSheet then self.lootSheet:SetShown(which == "loot") end
  if self.spellSheet then self.spellSheet:SetShown(which == "spell"); if which == "spell" then self.spellSheetDuel = false; self:RefreshSpellSheet() end end
  if self.settings:IsShown() then self:ShowSettings(false) end
  self:RefreshPhase()
end
