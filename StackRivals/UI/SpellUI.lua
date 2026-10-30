--[[
  StackRivals - Spell Battle UI: Pick Spells sheet, spell bar (mana, 4 spells with keys and
  cooldown), the rival panel with a live mini board, spell effects on the boards and the
  Victory / Defeat screen.

  StackRivals spells only change StackRivals boards. Nothing here casts, targets or binds a
  World of Warcraft ability; the spell keys are read only while a Spell Battle run is live.

  Layout in a Spell Battle (same window size as every other mode):
    left   HOLD | SCORE, MANA bar, 2x2 spell tiles (icon, key and cost under it), TIME
    centre your board; ONE message lane under it (where the controls hint is in other modes):
           spell toasts (LINE BLAST, GARBAGE SENT, NOT ENOUGH MANA) and, between toasts, the
           status line (INCOMING GARBAGE 1.2s, FROZEN, SPEED UP, BLACKOUT). Nothing spell-related
           is written over the board, so the falling piece and the stack stay visible; line
           clears keep their callout on the board.
    right  NEXT (2) | RIVAL: name, mini board + mana, score, lead bar
]]
local _, ns = ...
local T, Board, DB, S = ns.T, ns.Board, ns.DB, ns.Spells
local C, SZ = T.C, T.SIZE
local UI = ns.UI

local ICON = T.MEDIA .. "Spells\\"
local DIFF_LABEL = { rookie = "Rookie", challenger = "Challenger", contender = "Contender", elite = "Elite", rival = "Rival" }
UI.DIFF_LABEL = DIFF_LABEL

local function tone(spell) return (S.INFO[spell].target == "self") and C.red or C.steel end
local function keyLabel(i)
  local k = ns.db.bindings["spell" .. i]
  return k and T.keyName(k) or tostring(i)
end
local function secs(ticks) return string.format("%ds", math.ceil(ticks / 60)) end
local function durationText(spell)
  local d = S.INFO[spell].durationTicks
  if d then return math.floor(d / 60 + 0.5) .. "s" end
  if spell == "garbage" or spell == "scramble" then return "1.5s delay" end
  return "Instant"
end
UI.spellDurationText = durationText

--- GameTooltip with the spell's rules (name, cost, target, effect).
local function spellTooltip(owner, spell, extra)
  if not GameTooltip then return end
  local info = S.INFO[spell]
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local c = tone(spell)
  GameTooltip:SetText(info.name, c[1], c[2], c[3])
  GameTooltip:AddLine(info.hint .. ".", 0.8, 0.82, 0.86, true)
  GameTooltip:AddLine(string.format("%d mana  -  %s  -  %s", info.cost, info.target == "self" and "on your board" or "on your rival", durationText(spell)), 0.64, 0.67, 0.73)
  if extra then GameTooltip:AddLine(extra, 0.64, 0.67, 0.73) end
  GameTooltip:Show()
end

------------------------------------------------------------------------------------------------
-- Spell tile (in-game bar and the Pick Spells sheet use the same look)
------------------------------------------------------------------------------------------------
local function makeTile(parent, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.bg = T.tex(b, "BACKGROUND", C.ink, 1); b.bg:SetAllPoints()
  b.edge = {}
  for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
    local l = T.tex(b, "BORDER", C.line, 1)
    l:SetPoint(side[1]); l:SetPoint(side[2])
    if side[3] then l:SetWidth(side[3]) else l:SetHeight(side[4]) end
    b.edge[i] = l
  end
  b.icon = b:CreateTexture(nil, "ARTWORK")
  local is = w - 12
  b.icon:SetSize(is, is)
  b.icon:SetPoint("TOP", 0, -4)
  -- cooldown: a dark curtain that shrinks from the top (no Cooldown frame needed)
  b.cd = T.tex(b, "OVERLAY", C.ink, 0.72)
  b.cd:SetPoint("TOPLEFT", 1, -1); b.cd:SetPoint("TOPRIGHT", -1, -1); b.cd:SetHeight(1)
  b.cd:Hide()
  -- mana progress toward this spell's cost (bottom line)
  b.manaTrack = T.tex(b, "OVERLAY", C.line, 1, 1)
  b.manaTrack:SetPoint("BOTTOMLEFT", 1, 1); b.manaTrack:SetPoint("BOTTOMRIGHT", -1, 1); b.manaTrack:SetHeight(2)
  b.manaFill = T.tex(b, "OVERLAY", C.red, 1, 2)
  b.manaFill:SetPoint("BOTTOMLEFT", 1, 1); b.manaFill:SetHeight(2); b.manaFill:SetWidth(1)
  -- key (left) and mana cost (right) under the icon, never on top of it: readable at any scale
  b.key = T.display(b, SZ.body, C.paper, "OUTLINE", "OVERLAY"); b.key:SetPoint("BOTTOMLEFT", 4, 4)
  b.cost = T.display(b, SZ.body, C.paper, "OUTLINE", "OVERLAY"); b.cost:SetPoint("BOTTOMRIGHT", -4, 4)
  -- cooldown seconds over the icon while the curtain is down
  b.cdText = T.display(b, SZ.big, C.paper, "OUTLINE", "OVERLAY"); b.cdText:SetPoint("CENTER", b.icon, "CENTER", 0, 0)
  b.w, b.h = w, h
  b.pop = T.pulseAnim(b, 1.15, 0.24) -- "ready" bump when it becomes castable, and on cast
  return b
end

local function setTileEdge(b, c, a, thick)
  for i, l in ipairs(b.edge) do
    l:SetColorTexture(c[1], c[2], c[3], a or 1)
    if i <= 2 then l:SetHeight(thick or 1) else l:SetWidth(thick or 1) end
  end
end

local function setTileSpell(b, spell)
  b.spell = spell
  b.icon:SetTexture(ICON .. spell)
  b.cost:SetText(tostring(S.INFO[spell].cost))
  local c = tone(spell)
  b.manaFill:SetColorTexture(c[1], c[2], c[3], 1)
end

------------------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------------------
function UI:CreateSpell()
  local F, field = self.frame, self.field
  local stats = self.stats

  -- spell box inside the left stats panel (replaces BEST / LINES / LEVEL in a Spell Battle)
  local box = CreateFrame("Frame", nil, stats)
  box:SetPoint("TOPLEFT", stats, "TOPLEFT", 0, -58)
  box:SetPoint("TOPRIGHT", stats, "TOPRIGHT", 0, -58)
  box:SetHeight(156)
  self.spellBox = box
  local div = T.tex(box, "ARTWORK", C.line, 1); div:SetPoint("TOPLEFT", 10, 0); div:SetPoint("TOPRIGHT", -10, 0); div:SetHeight(1)
  local ml = T.label(box, "MANA"); ml:SetPoint("TOPLEFT", 10, -9)
  self.manaText = T.display(box, SZ.big, C.paper); self.manaText:SetPoint("TOPRIGHT", -10, -6); self.manaText:SetJustifyH("RIGHT")
  -- mana bar: 20 segments in 4 groups of 5 (whole units, crisp at any scale)
  self.manaSegs = {}
  local segW, gap = 3, 1
  for i = 1, S.MANA_MAX do
    local g = math.floor((i - 1) / 5)
    local seg = T.tex(box, "ARTWORK", C.line, 1)
    seg:SetSize(segW, 8)
    seg:SetPoint("TOPLEFT", 10 + (i - 1) * (segW + gap) + g * 2, -25)
    self.manaSegs[i] = seg
  end
  self.spellTiles = {}
  local tw, th, tg = 42, 56, 4
  for i = 1, 4 do
    local t = makeTile(box, tw, th)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    t:SetPoint("TOPLEFT", 10 + col * (tw + tg), -38 - row * (th + tg))
    t.slot = i
    t:SetScript("OnClick", function() local s = ns.App.session; if s then s:press("spell" .. i) end end)
    t:SetScript("OnEnter", function(btn) if btn.spell then spellTooltip(btn, btn.spell, "Key: " .. keyLabel(i)) end end)
    t:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.spellTiles[i] = t
  end
  box:Hide()

  -- rival panel under a shorter NEXT: name, live mini board + mana, score, lead
  local rp = T.panel(F, C.steel)
  rp:SetSize(108, 197)
  rp:SetPoint("BOTTOMLEFT", field, "BOTTOMRIGHT", 12, 0)
  rp.name = T.label(rp, ""); rp.name:SetPoint("TOPLEFT", 10, -9)
  rp.name:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
  rp.board = Board.createMini(rp, 10, 20, 5)
  rp.board:SetPoint("TOPLEFT", 10, -24)
  -- rival mana: a vertical bar beside the mini board
  local mt = T.tex(rp, "ARTWORK", C.line, 1); mt:SetPoint("TOPLEFT", rp.board, "TOPRIGHT", 8, 0); mt:SetSize(5, rp.board:GetHeight())
  rp.mana = T.tex(rp, "OVERLAY", C.steel, 1); rp.mana:SetPoint("BOTTOMLEFT", mt, "BOTTOMLEFT"); rp.mana:SetSize(5, 1)
  rp.manaTrack = mt
  rp.chips = T.text(rp, SZ.label, C.paper, "OUTLINE"); rp.chips:SetPoint("TOP", rp.board, "TOP", 0, -4)
  rp.chips:SetWidth(rp.board:GetWidth() + 4)
  rp.score = T.display(rp, SZ.title, C.steel); rp.score:SetPoint("TOPLEFT", rp.board, "BOTTOMLEFT", 0, -6)
  rp.lead = T.text(rp, SZ.label, C.label); rp.lead:SetPoint("TOPLEFT", rp.score, "BOTTOMLEFT", 0, -2)
  local track = T.tex(rp, "ARTWORK", C.line, 1); track:SetPoint("BOTTOMLEFT", 10, 6); track:SetSize(88, 3)
  rp.bar = T.tex(rp, "OVERLAY", C.red, 1); rp.bar:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT"); rp.bar:SetSize(44, 3)
  rp.over = T.display(rp, SZ.small, C.redLight, "OUTLINE"); rp.over:SetPoint("CENTER", rp.board, "CENTER")
  rp.over:SetText("TOPPED\nOUT")
  rp.over:Hide()
  rp:Hide()
  self.spellRival = rp

  -- the message lane under the board (status line; toasts below take its place for a moment)
  local LANE_W = F:GetWidth() - 80
  local chips = CreateFrame("Frame", nil, F)
  chips:SetSize(LANE_W, 20); chips:SetPoint("BOTTOM", F, "BOTTOM", 0, 6)
  chips:SetFrameLevel(field:GetFrameLevel() + 4)
  self.spellChips = T.display(chips, SZ.big, C.paper, "OUTLINE"); self.spellChips:SetPoint("CENTER")
  self.spellChipBox = chips
  local tint = field:CreateTexture(nil, "OVERLAY", nil, 1)
  tint:SetAllPoints(); tint:SetColorTexture(C.steel[1], C.steel[2], C.steel[3], 1); tint:SetAlpha(0)
  self.spellTint = tint
  local fx = CreateFrame("Frame", nil, field)
  fx:SetFrameLevel(field:GetFrameLevel() + 3)
  fx:SetAllPoints(field)
  self.spellFx = fx
  self.spellFxTex = fx:CreateTexture(nil, "OVERLAY")
  self.spellFxTex:SetAllPoints()
  self.spellFxTex:SetColorTexture(1, 1, 1, 1)
  fx:SetAlpha(0)
  local fg = fx:CreateAnimationGroup()
  local fa = fg:CreateAnimation("Alpha"); fa:SetFromAlpha(0.4); fa:SetToAlpha(0); fa:SetDuration(0.45); fa:SetSmoothing("OUT")
  fg:SetScript("OnFinished", function() fx:SetAlpha(0) end)
  self.spellFxAnim = fg
  -- bomb target: where Bomb would clear (shown while Bomb is castable)
  local bt = CreateFrame("Frame", nil, field)
  bt:SetFrameLevel(field:GetFrameLevel() + 2)
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
    local l = T.tex(bt, "OVERLAY", C.redLight, 0.8)
    l:SetPoint(side[1]); l:SetPoint(side[2])
    if side[3] then l:SetWidth(side[3]) else l:SetHeight(side[4]) end
  end
  bt:Hide()
  self.bombTarget = bt
  -- spell toast in the lane under the board: "LINE BLAST", "GARBAGE SENT", "INCOMING GARBAGE"
  local toast = CreateFrame("Frame", nil, F)
  toast:SetSize(LANE_W, 22); toast:SetPoint("BOTTOM", F, "BOTTOM", 0, 5)
  toast:SetFrameLevel(field:GetFrameLevel() + 6)
  self.spellToast = T.display(toast, SZ.big, C.paper, "OUTLINE"); self.spellToast:SetPoint("CENTER")
  self.spellToastAnim = T.popAnim(toast, 1.15, 0.9, 0.4)
  toast:SetAlpha(0)
  self.spellToastBox = toast
  -- incoming spells (not landed yet): a steel bar beside the board, 2 rows per garbage, and a chip
  local ib = T.tex(F, "ARTWORK", C.steel, 1)
  ib:SetPoint("BOTTOMRIGHT", field, "BOTTOMLEFT", -4, 0); ib:SetWidth(4); ib:SetHeight(1); ib:Hide()
  self.incomingBar = ib
  -- NEXT panel note while Blackout hides it
  self.blackoutText = T.display(self.nextPanel, SZ.small, C.steel); self.blackoutText:SetPoint("TOP", 0, -50)
  self.blackoutText:Hide()

  self:CreateSpellSheet()
end

------------------------------------------------------------------------------------------------
-- Layout switch: a Spell Battle replaces BEST / LINES / LEVEL and NEXT 3-5 with the spell HUD
------------------------------------------------------------------------------------------------
--- remote = a Spell Battle duel: the rival plays on their own PC, so the right column keeps the
--- duel's rival panel (score, lead) instead of the bot's mini board.
function UI:SetSpellLayout(on, remote)
  local key = on and (remote and "remote" or "bot") or "off"
  if self.spellLayoutOn == key then return end
  self.spellLayoutOn = key
  self.spellBox:SetShown(on)
  for _, r in ipairs({ self.bestLabel, self.bestText, self.statsDiv, self.linesLabel, self.linesText, self.levelLabel, self.levelText }) do
    r:SetShown(not on)
  end
  self.spellRival:SetShown(on and not remote)
  self.spellChipBox:SetShown(on)
  if self.hint then self.hint:SetShown(not on) end -- the message lane takes the hint's place
  if remote then return end -- RefreshDuel sizes NEXT and shows the duel rival panel
  if on then
    self.nextPanel:SetHeight(self.field:GetHeight() - 207)
    for i = 3, 5 do self.nextPreviews[i]:Hide() end
  else
    self.nextPanel:SetHeight(self.field:GetHeight())
    for i = 3, 5 do self.nextPreviews[i]:Show() end
    self.bombTarget:Hide(); self.spellTint:SetAlpha(0); self.blackoutText:Hide()
    self.incomingBar:Hide(); self.incomingRows = 0
    self.nextPreviews[1]:Show(); self.nextPreviews[2]:Show()
  end
end

------------------------------------------------------------------------------------------------
-- Per-frame HUD (called from UI:Render while a Spell Battle session exists)
------------------------------------------------------------------------------------------------
--- Status text for a side; cached per side until a shown second changes (no per-frame strings).
local function chipText(side, sep)
  local t = side.game.tick
  local f = (t < side.freezeUntil) and math.ceil((side.freezeUntil - t) / 60) or 0
  local sp = (t < side.speedUntil) and math.ceil((side.speedUntil - t) / 60) or 0
  local b = (t < side.blackoutUntil) and math.ceil((side.blackoutUntil - t) / 60) or 0
  local key = f * 10000 + sp * 100 + b
  local cache = side._chips
  if cache and cache.key == key and cache.sep == sep then return cache.text end
  local txt = ""
  if f > 0 then txt = "|cff9bd0ffFROZEN " .. f .. "s|r" end
  if sp > 0 then txt = txt .. (txt ~= "" and sep or "") .. "|cffff4d5aSPEED UP " .. sp .. "s|r" end
  if b > 0 then txt = txt .. (txt ~= "" and sep or "") .. "|cff9bd0ffBLACKOUT " .. b .. "s|r" end
  side._chips = { key = key, sep = sep, text = txt }
  return txt
end

function UI:RenderSpell(sess)
  local sp = sess.spell
  local me, o = sp.me, sp.opp
  local live = sess.phase == "playing"
  -- mana
  if self.manaText._n ~= me.mana then
    self.manaText._n = me.mana
    self.manaText:SetText(me.mana .. "/" .. S.MANA_MAX)
    for i, seg in ipairs(self.manaSegs) do
      local c = (i <= me.mana) and C.red or C.line
      seg:SetColorTexture(c[1], c[2], c[3], 1)
    end
  end
  -- tiles
  local cdLeft = S.cooldownLeft(me)
  for i, t in ipairs(self.spellTiles) do
    local spell = me.loadout[i]
    if t.spell ~= spell then setTileSpell(t, spell) end
    local k = keyLabel(i)
    if t.key._s ~= k then t.key._s = k; t.key:SetText(k) end
    local ok = live and (S.canCast(me, spell))
    local enough = me.mana >= S.INFO[spell].cost
    if t.ok ~= ok then
      if ok and t.ok == false then t.pop:Stop(); t.pop:Play() end
      t.ok = ok
      local c = tone(spell)
      setTileEdge(t, ok and c or C.line, 1, ok and 2 or 1) -- castable: a 2-unit edge in the spell's colour
      t.icon:SetDesaturated(not enough)
      t.icon:SetAlpha(enough and 1 or 0.45)
    end
    if t.enough ~= enough then
      t.enough = enough; t.icon:SetDesaturated(not enough); t.icon:SetAlpha(enough and 1 or 0.45)
      local cc = enough and C.paper or C.label
      t.cost:SetTextColor(cc[1], cc[2], cc[3])
    end
    local frac = math.min(1, me.mana / S.INFO[spell].cost)
    local w = math.max(1, (t.w - 2) * frac)
    if t.manaW ~= w then t.manaW = w; t.manaFill:SetWidth(w) end
    if cdLeft > 0 and enough then
      t.cd:SetHeight(math.max(1, (t.h - 2) * cdLeft / S.CAST_COOLDOWN_TICKS)); t.cd:Show()
      local tenth = math.ceil(cdLeft / 6) -- tenths of a second
      if t.cdText._n ~= tenth then t.cdText._n = tenth; t.cdText:SetText(string.format("%.1f", tenth / 10)) end
      t.cdText:Show()
    else
      t.cd:Hide(); t.cdText:Hide()
    end
  end
  -- my board: chips, tint, blackout, bomb target
  local chips = chipText(me, "  ")
  -- spells on their way to you: "INCOMING GARBAGE 1.2s" and the bar beside the board
  local pend = sp.pendingMe
  local now = me.game.tick
  local nextInc, garbageRows = nil, 0
  for _, p in ipairs(pend) do
    if p.at >= now then
      if not nextInc or p.at < nextInc.at then nextInc = p end
      if p.spell == "garbage" then garbageRows = garbageRows + 2 end
    end
  end
  if nextInc then
    local tenth = math.max(0, math.ceil((nextInc.at - now) / 6))
    local inc = string.format("|cff9bd0ffINCOMING %s %.1fs|r", string.upper(S.INFO[nextInc.spell].name), tenth / 10)
    chips = (chips ~= "" and (chips .. "  ") or "") .. inc
  end
  if self.incomingRows ~= garbageRows then
    self.incomingRows = garbageRows
    if garbageRows > 0 then self.incomingBar:SetHeight(garbageRows * 19); self.incomingBar:Show() else self.incomingBar:Hide() end
  end
  if self.spellChips._s ~= chips then self.spellChips._s = chips; self.spellChips:SetText(chips) end
  -- one message at a time in the lane: a toast hides the status line while it shows
  local toastOn = (self.spellToastUntil or 0) > GetTime()
  if self.spellChipsHidden ~= toastOn then self.spellChipsHidden = toastOn; self.spellChipBox:SetAlpha(toastOn and 0 or 1) end
  local tk = me.game.tick
  local tintA, tc = 0, nil
  if tk < me.freezeUntil then tintA, tc = 0.10, C.steel elseif tk < me.speedUntil then tintA, tc = 0.07, C.red end
  if self.spellTintA ~= tintA then
    self.spellTintA = tintA
    if tc then self.spellTint:SetColorTexture(tc[1], tc[2], tc[3], 1) end
    self.spellTint:SetAlpha(tintA)
  end
  local blind = tk < me.blackoutUntil
  if self.blind ~= blind then
    self.blind = blind
    self.nextPreviews[1]:SetShown(not blind); self.nextPreviews[2]:SetShown(not blind)
    self.blackoutText:SetShown(blind)
  end
  if blind then
    local left = math.ceil((me.blackoutUntil - tk) / 60)
    if self.blackoutText._n ~= left then self.blackoutText._n = left; self.blackoutText:SetText("BLACKOUT\n" .. left .. "s") end
  end
  local hasBomb = false
  for _, x in ipairs(me.loadout) do if x == "bomb" then hasBomb = true end end
  local a = me.game.active
  -- bomb target: recomputed only when the piece or its landing spot moves (no per-frame tables)
  local bkey = (hasBomb and live and a and S.canCast(me, "bomb")) and (ns.Pieces.INDEX[a.id] * 1000000 + a.rotation * 100000 + (a.x + 10) * 1000 + (ns.Engine.ghostY(me.game) or 0)) or nil
  if bkey and bkey == self.bombKey then
    -- unchanged: keep the outline where it is
  elseif bkey then
    self.bombKey = bkey
    local cells = S.bombCells(me.game)
    if #cells == 9 then
      local cs = 19 -- CELL + 1
      local hidden = me.game.config.hiddenRows
      local x0, y0 = cells[1][1], cells[1][2] - hidden
      local bt = self.bombTarget
      bt:ClearAllPoints()
      local x1, y1 = math.max(0, x0), math.max(0, y0)
      local x2, y2 = math.min(9, x0 + 2), math.min(19, y0 + 2)
      if x2 >= x1 and y2 >= y1 then
        bt:SetPoint("TOPLEFT", self.field, "TOPLEFT", x1 * cs, -y1 * cs)
        bt:SetSize((x2 - x1 + 1) * cs + 1, (y2 - y1 + 1) * cs + 1)
        bt:Show()
      else
        bt:Hide()
      end
    end
  else
    self.bombKey = nil
    self.bombTarget:Hide()
  end
  if not o then return end -- duel: the rival panel is the duel's (DuelUI)
  -- rival
  local rp = self.spellRival
  local label = string.upper((DIFF_LABEL[sp.difficulty] or "Bot") .. " bot")
  if sp.rivalName then label = "VS " .. string.upper(sp.rivalName):sub(1, 13) end
  if rp.name._s ~= label then rp.name._s = label; rp.name:SetText(label) end
  Board.renderMini(rp.board, o.game, o.game.tick < o.blackoutUntil)
  local mh = math.max(1, rp.manaTrack:GetHeight() * o.mana / S.MANA_MAX)
  if rp.manaH ~= mh then rp.manaH = mh; rp.mana:SetHeight(mh) end
  local oc = chipText(o, "\n")
  if rp.chips._s ~= oc then rp.chips._s = oc; rp.chips:SetText(oc) end
  rp.over:SetShown(o.game.gameOver)
  if rp.score._n ~= o.game.score then rp.score._n = o.game.score; rp.score:SetText(T.commas(o.game.score)) end
  local lead = me.game.score - o.game.score
  local beat = o.game.gameOver and not me.game.gameOver and lead <= 0
  local lkey = (beat and "b" or "l") .. lead
  if rp.lead._k ~= lkey then
    rp.lead._k = lkey
    local lt = (beat and ("beat " .. T.commas(o.game.score) .. " to win")) or (lead > 0 and ("you +" .. T.commas(lead))) or (lead < 0 and ("you -" .. T.commas(-lead))) or "level"
    rp.lead._s = lt; rp.lead:SetText(lt)
    local c = lead > 0 and C.green or (lead < 0 and C.redLight or C.label)
    rp.lead:SetTextColor(c[1], c[2], c[3])
    local total = me.game.score + o.game.score
    rp.bar:SetWidth(math.max(1, 88 * (total > 0 and me.game.score / total or 0.5)))
  end
end

------------------------------------------------------------------------------------------------
-- Events: casts, incoming spells, effects
------------------------------------------------------------------------------------------------
local FX = {
  bomb = { C.redLight, "bomb" }, lineBlast = { C.redLight, "bottom" }, clearBoard = { C.paper, "all" },
  swap = { C.paper, "top" }, freeze = { { 0.61, 0.82, 1 }, "all" }, garbage = { { 0.42, 0.45, 0.52 }, "bottom" },
  speedUp = { C.red, "all" }, blackout = { C.steel, "all" }, scramble = { C.steel, "top" },
}

function UI:SpellFlash(spell, bombCells, fromRival)
  local f = FX[spell]
  if not f then return end
  local tex, field = self.spellFxTex, self.field
  -- your own spells flash in your colour (red), the rival's in theirs (steel); garbage stays grey
  local c = (spell == "garbage") and f[1] or (fromRival and C.steel or f[1])
  tex:SetColorTexture(c[1], c[2], c[3], 1)
  tex:ClearAllPoints()
  local cs = 19
  if f[2] == "bottom" then
    tex:SetPoint("BOTTOMLEFT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetHeight(2 * cs + 1)
  elseif f[2] == "top" then
    tex:SetPoint("TOPLEFT"); tex:SetPoint("TOPRIGHT"); tex:SetHeight(4 * cs)
  elseif f[2] == "bomb" and bombCells and #bombCells == 9 then
    local x0, y0 = bombCells[1][1], bombCells[1][2] - 2
    tex:SetPoint("TOPLEFT", field, "TOPLEFT", math.max(0, x0) * cs, -math.max(0, y0) * cs)
    tex:SetSize(3 * cs + 1, 3 * cs + 1)
  else
    tex:SetAllPoints()
  end
  self.spellFxAnim:Stop(); self.spellFx:SetAlpha(0.4); self.spellFxAnim:Play()
end

function UI:SpellToast(text, color)
  self.spellToastUntil = GetTime() + 1.45 -- the pop animation's length; the status line waits
  self.spellChipBox:SetAlpha(0); self.spellChipsHidden = true
  self.spellToast:SetText(text)
  self.spellToast:SetTextColor(color[1], color[2], color[3])
  self.spellToastAnim:Stop(); self.spellToastAnim:Play()
end

--- Returns true when the event was a Spell Battle event (handled here).
function UI:OnSpellEvent(ev)
  local k = ev.kind
  local sess = ns.App.session
  if k == "cast" then
    local spell = ev.a
    local info = S.INFO[spell]
    if info.target == "self" then
      self:SpellToast(string.upper(info.name), C.redLight)
    else
      self:SpellToast(string.upper(info.name) .. " SENT", C.steel)
    end
    for _, t in ipairs(self.spellTiles) do if t.spell == spell then t.pop:Stop(); t.pop:Play() end end
    ns.Sound.play("hold")
  elseif k == "oppcast" then
    local spell = ev.a
    if S.INFO[spell].target == "opponent" then
      self:SpellToast("INCOMING " .. string.upper(S.INFO[spell].name), C.steel)
      ns.Sound.play("rotate")
    end
  elseif k == "hit" then
    local who, h = ev.a, ev.b
    if who == "me" then
      local cells = (h.spell == "bomb" and sess and sess.spell) and sess.spell.lastBombCells or nil
      self:SpellFlash(h.spell, cells, not h.fromSelf)
      if h.spell == "garbage" or h.spell == "bomb" then self.thump:Stop(); self.thump:Play() end
    end
  elseif k == "castfail" then
    local why = ev.b
    local txt = (why == "insufficient_mana" and "NOT ENOUGH MANA") or (why == "cooldown" and "COOLDOWN") or nil
    if txt then self:SpellToast(txt, C.label) end
  elseif k == "spellresult" then
    ns.App:OnSpellResult()
  else
    return false
  end
  self.dirty = true
  return true
end

------------------------------------------------------------------------------------------------
-- Victory / Defeat
------------------------------------------------------------------------------------------------
local OUTCOME = { win = { "VICTORY", C.gold }, loss = { "DEFEAT", C.redLight }, draw = { "DRAW", C.paper } }
local REASON = {
  decided = "The bot topped out and you were ahead.",
  topout = "You topped out.",
  time = "Time's up.",
}

function UI:ShowSpellOver(sess)
  local sp = sess.spell
  self.spellToastAnim:Stop(); self.spellToastBox:SetAlpha(0); self.spellToastUntil = 0
  self.spellFxAnim:Stop(); self.spellFx:SetAlpha(0)
  self.bombTarget:Hide()
  self.shareGuild:Hide(); self.shareGroup:Hide(); self.shareLabel:Hide()
  self.againBtn:SetLabel("Play again")
  self.modesBtn:SetLabel("Change spells")
  local bot = string.upper(DIFF_LABEL[sp.difficulty] or "Bot") .. " BOT"
  if not sp.result then
    self.overTitle:SetText("FINISHED")
    self.overTitle:SetTextColor(C.paper[1], C.paper[2], C.paper[3])
    self.overScore:SetText(T.commas(sp.me.game.score))
    self.overBadge:SetText(bot .. ": " .. T.commas(sp.opp.game.score))
    self.overBadge:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
    self.overDetail:SetText("You topped out. The bot is finishing its run...")
    return
  end
  local r = sp.result
  local o = OUTCOME[r.outcome]
  self.overTitle:SetText(o[1])
  self.overTitle:SetTextColor(o[2][1], o[2][2], o[2][3])
  self.overScore:SetText(T.commas(r.me))
  self.overBadge:SetText(bot .. ": " .. T.commas(r.bot))
  self.overBadge:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
  local st = ns.db.spell.stats[sp.difficulty]
  local rec = st and string.format("\nvs %s: %d won, %d lost", DIFF_LABEL[sp.difficulty], st.wins, st.losses) or ""
  local why = REASON[r.reason] or ""
  if r.reason == "topout" and r.outcome == "win" then why = "You topped out, but the bot finished lower." end
  self.overDetail:SetText(why .. rec)
  if r.outcome == "win" then self.badgePulse:Stop(); self.badgePulse:Play() end
end

------------------------------------------------------------------------------------------------
-- Pick Spells sheet: 2 for your board + 2 for your rival, and the bot level
------------------------------------------------------------------------------------------------
function UI:CreateSpellSheet()
  local s = self:Body(36, true)
  self.spellSheet = s
  local w = self.frame:GetWidth()
  local title = T.display(s, SZ.title, C.paper); title:SetPoint("TOPLEFT", 24, -14); title:SetText("SPELL BATTLE")
  local sub = T.text(s, SZ.small, C.label); sub:SetPoint("TOPLEFT", 24, -38)
  sub:SetText("Pick 2 spells for your board and 2 for your rival. Line clears give mana.")
  local function group(label, list, y, c)
    local l = T.label(s, label); l:SetPoint("TOPLEFT", 24, y)
    l:SetTextColor(c[1], c[2], c[3])
    local cards = {}
    local cw, gap = 78, 5
    for i, spell in ipairs(list) do
      local b = CreateFrame("Button", nil, s)
      b:SetSize(cw, 72)
      b:SetPoint("TOPLEFT", 24 + (i - 1) * (cw + gap), y - 16)
      b.bg = T.tex(b, "BACKGROUND", C.surface1, 1); b.bg:SetAllPoints()
      b.edge = {}
      for k, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local e = T.tex(b, "BORDER", C.line, 1)
        e:SetPoint(side[1]); e:SetPoint(side[2])
        if side[3] then e:SetWidth(side[3]) else e:SetHeight(side[4]) end
        b.edge[k] = e
      end
      b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(32, 32); b.icon:SetPoint("TOP", 0, -5)
      b.icon:SetTexture(ICON .. spell)
      b.name = T.display(b, SZ.label, C.paper); b.name:SetPoint("TOP", b.icon, "BOTTOM", 0, -2)
      b.name:SetText(S.INFO[spell].name)
      b.cost = T.text(b, SZ.label, C.label); b.cost:SetPoint("TOP", b.name, "BOTTOM", 0, -1)
      b.cost:SetText(S.INFO[spell].cost .. " mana")
      b.key = T.display(b, SZ.label, C.paper, "OUTLINE"); b.key:SetPoint("TOPRIGHT", -4, -3)
      b.spell = spell
      b:SetScript("OnClick", function() UI:ToggleSpell(spell) end)
      b:SetScript("OnEnter", function(btn) spellTooltip(btn, spell); UI.spellHint:SetText(S.INFO[spell].name .. ":  " .. S.INFO[spell].hint .. ".  " .. S.INFO[spell].cost .. " mana, " .. durationText(spell) .. ".") end)
      b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end; UI:RefreshSpellSheet() end)
      cards[#cards + 1] = b
    end
    return cards
  end
  self.spellCards = {}
  for _, b in ipairs(group("ON YOUR BOARD", S.SELF_SPELLS, -60, C.redLight)) do self.spellCards[#self.spellCards + 1] = b end
  for _, b in ipairs(group("ON YOUR RIVAL", S.OPPONENT_SPELLS, -156, C.steel)) do self.spellCards[#self.spellCards + 1] = b end
  self.spellHint = T.text(s, SZ.small, C.body); self.spellHint:SetPoint("TOPLEFT", 24, -250)
  self.spellHint:SetWidth(w - 48); self.spellHint:SetJustifyH("LEFT")
  local bl = T.label(s, "BOT"); bl:SetPoint("TOPLEFT", 24, -276)
  self.spellBotLabel = bl
  self.diffButtons = {}
  local bw = math.floor((w - 48 - 4 * 4) / 5)
  for i, d in ipairs(DB.SPELL_DIFFICULTIES) do
    local b = T.button(s, DIFF_LABEL[d], bw, 26, "frame", function() ns.db.spell.difficulty = d; UI:RefreshSpellSheet() end)
    b:SetPoint("TOPLEFT", 24 + (i - 1) * (bw + 4), -292)
    b.tip = "Same bot and the same tuning as on stackrivals.io."
    b:HookScript("OnLeave", function() UI:RefreshSpellSheet() end)
    self.diffButtons[d] = b
  end
  self.spellRecord = T.text(s, SZ.label, C.label); self.spellRecord:SetPoint("TOPLEFT", 24, -326)
  local back = T.button(s, "Back", 110, 32, "frame", function()
    s:Hide()
    if UI.spellSheetDuel then UI:RefreshPhase() else ns.App:ShowMenu() end
  end)
  back:SetPoint("BOTTOMLEFT", 24, 12)
  self.spellBack = back
  local start = T.button(s, "Start Spell Battle", 200, 32, "primary", function()
    s:Hide()
    if UI.spellSheetDuel then UI:RefreshPhase() else ns.App:Start("spellbot") end
  end)
  start:SetPoint("BOTTOMRIGHT", -24, 12)
  self.spellStart = start
  s:SetScript("OnShow", function() UI:RefreshSpellSheet() end)
end

--- Click a spell: it joins its group (the oldest of the two leaves); clicking a chosen one does nothing
--- (a loadout is always valid, like the web picker).
function UI:ToggleSpell(spell)
  local lo = S.decodeLoadout(ns.db.spell.loadout) or S.DEFAULT_LOADOUT
  local self_, opp = {}, {}
  for _, x in ipairs(lo) do if S.INFO[x].target == "self" then self_[#self_ + 1] = x else opp[#opp + 1] = x end end
  local group = (S.INFO[spell].target == "self") and self_ or opp
  for _, x in ipairs(group) do if x == spell then return end end
  table.remove(group, 1)
  group[#group + 1] = spell
  local new = { self_[1], self_[2], opp[1], opp[2] }
  ns.db.spell.loadout = S.encodeLoadout(new) or ns.db.spell.loadout
  self:RefreshSpellSheet()
end

--- Open the picker from a duel lobby: no bot row, "Done" goes back to the lobby.
function UI:ShowSpellPicker(duel)
  self.spellSheetDuel = duel and true or false
  if duel then
    self.spellSheet:Show()
  else
    self:ShowSheet("spell")
  end
  self:RefreshSpellSheet()
end

function UI:RefreshSpellSheet()
  if not self.spellSheet then return end
  local duel = self.spellSheetDuel and ns.Duel and ns.Duel.current and ns.Duel.current.ruleset and ns.Duel.current.ruleset.spell
  self.spellStart:SetLabel(duel and "Done" or "Start Spell Battle")
  for _, b in pairs(self.diffButtons) do b:SetShown(not duel) end
  self.spellBotLabel:SetShown(not duel)
  local lo = S.decodeLoadout(ns.db.spell.loadout) or S.DEFAULT_LOADOUT
  local slot = {}
  for i, x in ipairs(lo) do slot[x] = i end
  for _, b in ipairs(self.spellCards) do
    local i = slot[b.spell]
    local c = i and tone(b.spell) or C.line
    for _, e in ipairs(b.edge) do e:SetColorTexture(c[1], c[2], c[3], 1) end
    b.bg:SetColorTexture(i and C.raised[1] or C.surface1[1], i and C.raised[2] or C.surface1[2], i and C.raised[3] or C.surface1[3], 1)
    b.icon:SetDesaturated(not i); b.icon:SetAlpha(i and 1 or 0.55)
    b.key:SetText(i and keyLabel(i) or "")
  end
  local names = {}
  for i, x in ipairs(lo) do names[i] = keyLabel(i) .. " " .. S.INFO[x].name end
  self.spellHint:SetText("Your keys:  " .. table.concat(names, "  -  "))
  for d, b in pairs(self.diffButtons) do
    local on = ns.db.spell.difficulty == d
    local st = on and T.STYLES.steel or T.STYLES.frame
    b.bgTex:SetColorTexture(st.bg[1], st.bg[2], st.bg[3], 1)
    b.border:SetColorTexture(st.border[1], st.border[2], st.border[3], 1)
  end
  if duel then
    self.spellRecord:SetText("Your spells lock when you press Ready. Your rival sees them at the start.")
    return
  end
  local d = ns.db.spell.difficulty
  local st = ns.db.spell.stats[d]
  self.spellRecord:SetText(string.format("3:00 vs the %s bot: %d won, %d lost, %d draws%s", DIFF_LABEL[d], st.wins, st.losses, st.draws,
    st.best > 0 and (", best " .. T.commas(st.best)) or ""))
end
