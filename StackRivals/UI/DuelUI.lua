--[[
  StackRivals - duel screens: Duel sheet (find & challenge players), incoming-invite popup,
  lobby (Ready / Cancel), live rival panel during the match and the duel result.
]]
local _, ns = ...
local T, Board = ns.T, ns.Board
local C = T.C
local UI = ns.UI
local P = ns.Protocol

local OUTCOME = {
  win = { "VICTORY", C.gold }, loss = { "DEFEAT", C.steel }, draw = { "DRAW", C.paper }, void = { "NO RESULT", C.label },
}
-- a result that wasn't played out and replay-checked (forfeit, lost contact, rejected): it is never
-- shown as a VICTORY / DEFEAT
local NOT_PLAYED = {
  win = { "WALKOVER", C.gold }, loss = { "FORFEIT", C.steel }, draw = { "DRAW", C.paper }, void = { "NO RESULT", C.label },
}
local function outcomeOf(m)
  local t = (m.basis == nil or m.basis == "replay") and OUTCOME or NOT_PLAYED
  return t[m.outcome] or OUTCOME.void
end
UI.duelOutcomeOf = outcomeOf
local BASIS = {
  replay = "Replay-checked result.",
  rejected = "Won without a played-out result (your rival's game was rejected).",
  forfeit = "Not played out: decided by a forfeit, not by a replay.",
  timeout = "Not played out: decided by lost contact / time, not by a replay.",
}
local REASON = {
  checked = "Rival's game replayed to the same score on your PC (peer check).",
  unchecked = "Rival's replay didn't arrive, so their score can't be checked: no result.",
  check_failed = "Rival's result failed the replay check on your PC: their result is rejected.",
  you_left = "You left before the result: no result recorded for you.",
  rival_forfeited = "Your rival left the duel.",
  rival_disconnected = "Lost contact with your rival.",
  rival_offline = "Your rival went offline.",
  you_forfeited = "You left the duel.",
  timeout = "Your rival didn't finish in time.",
  rival_no_log = "Your rival never sent their replay (asked again and again): they forfeit. Their game was not checked.",
  rival_pause_limit = "Your rival stayed paused far past the 1-minute limit: they forfeit.",
  you_pause_limit = "You paused for more than a minute in total: the duel is forfeited.",
}
local AGREEMENT = {
  agreed = "Confirmed by both PCs.",
  disputed = "DISPUTED: the two PCs don't agree. Not counted.",
  unconfirmed = "Your rival's PC didn't confirm (older version or gone).",
}
local CANCEL = {
  rival_no = "declined your challenge.", rival_busy = "is busy in another duel.", rival_combat = "is in combat right now.",
  rival_version = "has a different StackRivals version.", rival_timeout = "didn't answer in time.",
  rival_cancel = "cancelled the duel.", no_answer = "didn't answer.", lobby_timeout = "Nobody pressed Ready in time.",
  you_declined = "You declined.", timeout = "The invite timed out.", rival_disconnected = "Lost contact with your rival.",
  you_cancelled = "You cancelled the duel.", rival_offline = "is offline.",
  rival_bad_seed = "sent a seed that didn't match the invite. Duel cancelled.",
}

local function short(n) return ns.Duel.short(n) or "?" end

local SZ = T.SIZE

------------------------------------------------------------------------------------------------
-- Duel sheet: find players + challenge (full window, like Records / How to play)
------------------------------------------------------------------------------------------------
local ROWS = 6

function UI:CreateDuelSheet()
  local s = self:Body(40)
  self.duelSheet = s
  local L = 24
  local cw = self.frame:GetWidth() - 2 * L - 2
  local title = T.display(s, SZ.title, C.paper); title:SetPoint("TOPLEFT", L, -14); title:SetText("DUEL")
  local sub = T.text(s, SZ.small, C.label); sub:SetPoint("TOPLEFT", L, -38)
  s.sub = sub

  -- ruleset: a three-way segmented choice
  self.duelRuleset = "b120"
  local b120 = T.button(s, "Blitz 2:00", 96, 30, "frame", function() UI.duelRuleset = "b120"; UI:RefreshDuelSheet() end)
  b120:SetPoint("TOPLEFT", L, -62)
  b120.tip = "Score race: 2 minutes, 3 s countdown."
  local r180 = T.button(s, "3:00", 70, 30, "frame", function() UI.duelRuleset = "r180"; UI:RefreshDuelSheet() end)
  r180:SetPoint("LEFT", b120, "RIGHT", 4, 0)
  r180.tip = "Score race, 3 minutes and a 4 s countdown: the same rules as a 1v1 on stackrivals.io."
  local s180 = T.button(s, "Spell Battle", 112, 30, "frame", function() UI.duelRuleset = "s180"; UI:RefreshDuelSheet() end)
  s180:SetPoint("LEFT", r180, "RIGHT", 4, 0)
  s180.tip = "Spell Battle 3:00 with the web's spells: casts land on your rival's board. Both need StackRivals 0.5+."
  s.b120, s.r180, s.s180 = b120, r180, s180

  local find = T.button(s, "Find players", 120, 30, "primary", function()
    local okFind, why = ns.Duel.findPlayers()
    UI.duelFindNote = okFind and "Asked your guild and group..." or (why == "cooldown" and "Just asked - wait a moment." or (ns.Duel.WHY_NOT[why] or "Join a guild or group to find players."))
    UI:RefreshDuelSheet()
  end)
  find:SetPoint("TOPRIGHT", -L - 2, -62)
  s.note = T.text(s, SZ.small, C.body); s.note:SetPoint("TOPLEFT", L, -102)

  s.rows = {}
  for i = 1, ROWS do
    local row = T.panel(s)
    row:SetSize(cw, 34)
    row:SetPoint("TOPLEFT", L, -122 - (i - 1) * 38)
    row.name = T.display(row, SZ.big, C.paper); row.name:SetPoint("LEFT", 12, 0); row.name:SetJustifyH("LEFT")
    row.info = T.text(row, SZ.label, C.label); row.info:SetPoint("LEFT", 196, 0); row.info:SetJustifyH("LEFT")
    row.btn = T.button(row, "Challenge", 112, 26, "steel", function(b)
      local okC, why = ns.Duel.challenge(b.target, UI.duelRuleset)
      if not okC then UI.duelFindNote = "Can't challenge: " .. (ns.Duel.WHY_NOT[why] or tostring(why)) .. "." end
      UI:RefreshDuelSheet()
    end)
    row.btn:SetPoint("RIGHT", -4, 0)
    row:Hide()
    s.rows[i] = row
  end
  s.empty = T.text(s, SZ.body, C.body); s.empty:SetPoint("TOPLEFT", L, -126); s.empty:SetWidth(cw); s.empty:SetJustifyH("LEFT")
  s.empty:SetSpacing(4)
  s.empty:SetText("Press |cfff6f4f0Find players|r to see who in your guild or group has StackRivals.\nOr type |cffff4d5a/sr duel Name|r to challenge anyone on your realm.")

  -- your record
  local rec = T.label(s, "YOUR DUELS (PLAYED OUT, REPLAY-CHECKED)"); rec:SetPoint("BOTTOMLEFT", L, 74)
  s.won = T.display(s, SZ.title, C.green); s.won:SetPoint("BOTTOMLEFT", L, 48)
  s.lost = T.display(s, SZ.title, C.redLight); s.lost:SetPoint("BOTTOMLEFT", L + 92, 48)
  s.draws = T.display(s, SZ.title, C.paper); s.draws:SetPoint("BOTTOMLEFT", L + 184, 48)
  local trust = T.text(s, SZ.label, C.label); trust:SetPoint("BOTTOMLEFT", L, 22); trust:SetWidth(270); trust:SetJustifyH("LEFT")
  s.trust = trust
  local close = T.button(s, "Close", 130, 32, "frame", function() s:Hide(); UI:RefreshPhase() end)
  close:SetPoint("BOTTOMRIGHT", -20, 16)
  s:SetScript("OnShow", function() UI:RefreshDuelSheet() end)
end

local function setSegment(b, on)
  local c = on and C.steelDeep or C.surface2
  b.bgTex:SetColorTexture(c[1], c[2], c[3], 1)
  local e = on and C.steel or C.line
  b.border:SetColorTexture(e[1], e[2], e[3], 1)
end

function UI:RefreshDuelSheet()
  local s = self.duelSheet
  if not s or not s:IsShown() then return end
  setSegment(s.b120, self.duelRuleset == "b120")
  setSegment(s.r180, self.duelRuleset == "r180")
  setSegment(s.s180, self.duelRuleset == "s180")
  s.sub:SetText(self.duelRuleset == "s180" and "1v1 Spell Battle. Same pieces, spells hit each other's boards."
    or "1v1 score race. Same pieces for both. Highest score wins.")
  local minV = P.RULESET_MIN_VERSION[self.duelRuleset]
  s.note:SetText(not ns.Comm.enabled and "Addon messages are not available in this client."
    or ns.Comm.trial and "Trial/Veteran account: Blizzard blocks addon messages, so duels can't work."
    or (self.duelFindNote or ""))
  local list = {}
  for _, p in pairs(ns.Duel.players) do list[#list + 1] = p end
  table.sort(list, function(a, b) return a.name < b.name end)
  local busy = ns.Duel.busy() or UI.inCombat()
  for i, row in ipairs(s.rows) do
    local p = list[i]
    if p then
      row.name:SetText(short(p.name))
      local old = minV and not P.versionAtLeast(p.addon, minV)
      row.info:SetText(not p.compatible and "other version" or (p.busy and "in a duel") or (old and ("v" .. p.addon .. ", needs " .. minV)) or ("v" .. p.addon))
      row.btn.target = p.name
      if p.compatible and not p.busy and not busy and not old then row.btn:Enable() else row.btn:Disable() end
      row:Show()
    else
      row:Hide()
    end
  end
  s.empty:SetShown(#list == 0)
  local d = ns.db.duels
  s.won:SetText(d.wins .. " won"); s.lost:SetText(d.losses .. " lost"); s.draws:SetText(d.draws .. " draws")
  -- won / lost / draws count only played-out, replay-checked duels (peer-checked, not by a server)
  s.trust:SetText(string.format("Forfeits: %d won, %d lost  -  Disputed: %d", d.fwins or 0, d.flosses or 0, d.disputes or 0))
end

------------------------------------------------------------------------------------------------
-- Incoming invite popup (works with the main window closed)
------------------------------------------------------------------------------------------------
function UI:CreateInvitePopup()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(340, 124)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  local p = T.panel(f, C.steel, 0.97); p:SetAllPoints()
  local mark = f:CreateTexture(nil, "ARTWORK")
  mark:SetTexture(T.MEDIA .. "marksmall"); mark:SetSize(26, 26); mark:SetPoint("TOPLEFT", 14, -14)
  f.kind = T.label(f, "DUEL CHALLENGE"); f.kind:SetPoint("TOPLEFT", 50, -12); f.kind:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
  f.title = T.display(f, SZ.title, C.paper); f.title:SetPoint("TOPLEFT", 50, -26); f.title:SetJustifyH("LEFT")
  f.sub = T.text(f, SZ.small, C.body); f.sub:SetPoint("TOPLEFT", 50, -50); f.sub:SetJustifyH("LEFT")
  -- time left, as a shrinking bar under the text
  local track = T.tex(f, "ARTWORK", C.line, 1); track:SetPoint("TOPLEFT", 14, -72); track:SetSize(312, 3)
  f.bar = T.tex(f, "OVERLAY", C.steel, 1); f.bar:SetPoint("TOPLEFT", track, "TOPLEFT"); f.bar:SetSize(312, 3)
  local acc = T.button(f, "Accept", 150, 30, "primary", function() ns.Duel.accept(); f:Hide() end)
  acc:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 12)
  local dec = T.button(f, "Decline", 150, 30, "frame", function() ns.Duel.decline("no"); f:Hide() end)
  dec:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 12)
  f.acc = acc
  f:Hide()
  f:SetScript("OnUpdate", function(self)
    local m = ns.Duel.current
    if not m or m.state ~= "invited" then self:Hide(); return end
    local frac = math.max(0, 1 - (GetTime() - m.createdAt) / ns.Duel.INVITE_TIMEOUT)
    self.bar:SetWidth(math.max(1, 312 * frac))
    local left = math.ceil(ns.Duel.INVITE_TIMEOUT * frac)
    if self.left ~= left then
      self.left = left
      self.sub:SetText(m.ruleset.name .. "  -  answer within " .. left .. " s")
    end
    if UI.inCombat() then self.acc:Disable() else self.acc:Enable() end
  end)
  self.invite = f
end

------------------------------------------------------------------------------------------------
-- Lobby: a full-window "YOU vs RIVAL" screen; rival panel under NEXT while playing
------------------------------------------------------------------------------------------------
local function playerCard(parent, edge, w)
  local c = T.panel(parent, edge)
  c:SetSize(w, 92)
  c.who = T.label(c, ""); c.who:SetPoint("TOP", 0, -12)
  c.name = T.display(c, SZ.title, C.paper); c.name:SetPoint("TOP", 0, -28)
  c.state = T.display(c, SZ.small, C.label); c.state:SetPoint("TOP", 0, -60)
  return c
end

function UI:CreateDuelOverlays()
  local o = self:Body(35, true)
  self.lobby = o
  local w = self.frame:GetWidth()
  o.rules = T.display(o, SZ.small, C.steel); o.rules:SetPoint("TOP", 0, -20)
  local cardW = 160
  o.meCard = playerCard(o, C.red, cardW); o.meCard:SetPoint("TOPRIGHT", o, "TOP", -34, -48)
  o.themCard = playerCard(o, C.steel, cardW); o.themCard:SetPoint("TOPLEFT", o, "TOP", 34, -48)
  o.meCard.who:SetText("YOU")
  o.themCard.who:SetText("RIVAL")
  local vs = T.text(o, 30, C.red, "", nil, "italic"); vs:SetPoint("TOP", 0, -74); vs:SetText("VS")
  o.rival = o.themCard.name
  o.status = T.text(o, SZ.body, C.body); o.status:SetPoint("TOP", 0, -162); o.status:SetWidth(w - 80)
  o.ready = T.button(o, "Ready", 220, 36, "primary", function() ns.Duel.ready() end)
  o.ready:SetPoint("TOP", 0, -202)
  -- Spell Battle: your 4 spells (locked at Ready) and a way to change them
  local sr = CreateFrame("Frame", nil, o)
  sr:SetSize(4 * 32 + 10 + 120, 30); sr:SetPoint("TOP", 0, -190)
  sr.icons = {}
  for i = 1, 4 do
    local ic = sr:CreateTexture(nil, "ARTWORK"); ic:SetSize(28, 28); ic:SetPoint("LEFT", (i - 1) * 32, 0)
    sr.icons[i] = ic
  end
  sr.change = T.button(sr, "Change spells", 120, 28, "frame", function() UI:ShowSpellPicker(true) end)
  sr.change:SetPoint("LEFT", 4 * 32 + 10, 0)
  sr.locked = T.text(sr, SZ.small, C.label); sr.locked:SetPoint("LEFT", 4 * 32 + 10, 0); sr.locked:SetText("locked")
  sr:Hide()
  o.spells = sr
  o.cancel = T.button(o, "Cancel", 220, 28, "frame", function()
    local m = ns.Duel.current
    if m and (m.state == "cancelled") then ns.Duel.clear(); ns.App:ShowMenu() else ns.Duel.leave() end
    UI:RefreshPhase()
  end)
  o.cancel:SetPoint("TOP", o.ready, "BOTTOM", 0, -10)
  o.hint = T.text(o, SZ.label, C.label); o.hint:SetPoint("BOTTOM", 0, 14); o.hint:SetWidth(w - 80)
  o.hint:SetText("The countdown starts when both are ready. A pause (combat, chat) pauses both runs: at most 60 s in total each.")
  o.fade = T.fadeInAnim(o, 0.2)

  -- rival panel under NEXT (only during a duel; NEXT shortens to make room)
  local rp = T.panel(self.frame, C.steel)
  rp:SetSize(108, 72)
  rp:SetPoint("BOTTOMLEFT", self.field, "BOTTOMRIGHT", 12, 0)
  rp.name = T.label(rp, ""); rp.name:SetPoint("TOPLEFT", 10, -9); rp.name:SetJustifyH("LEFT")
  rp.name:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
  rp.score = T.display(rp, SZ.title, C.steel); rp.score:SetPoint("TOPLEFT", 10, -24); rp.score:SetJustifyH("LEFT")
  rp.state = T.text(rp, SZ.label, C.label); rp.state:SetPoint("TOPLEFT", 10, -48); rp.state:SetJustifyH("LEFT")
  -- tug-of-war bar: red = you lead, steel = rival leads
  local track = T.tex(rp, "ARTWORK", C.line, 1); track:SetPoint("BOTTOMLEFT", 10, 6); track:SetSize(88, 3)
  rp.bar = T.tex(rp, "OVERLAY", C.red, 1); rp.bar:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT"); rp.bar:SetSize(44, 3)
  rp:Hide()
  self.rivalPanel = rp
end

local function chip(fs, ready)
  fs:SetText(ready and "READY" or "not ready")
  local c = ready and C.green or C.label
  fs:SetTextColor(c[1], c[2], c[3])
end

--- Sync the duel UI with the current duel state; returns true if the lobby took over the window.
function UI:RefreshDuel(phase)
  if not self.lobby then return false end
  local m = ns.Duel.current
  local o = self.lobby
  local pre = m and (m.state == "inviting" or m.state == "lobby" or m.state == "cancelled" or m.state == "invited")
  -- an invite still waiting for our answer is shown in the popup, not the lobby
  if m and m.state == "invited" then pre = false end
  local s = ns.App.session
  local inDuel = s and s.duel and s.duel == m
  if pre and not (inDuel and s:isActive()) then
    -- the lobby covers the window: never let a solo run keep falling underneath it
    if s and not s.duel and s:isActive() then s:pause("manual") end
    if not o:IsShown() then o:Show(); o.fade:Play() end
    o.meCard.name:SetText(short(ns.Comm.me()) or "You")
    o.themCard.name:SetText(short(m.rival))
    o.rules:SetText(string.upper(m.ruleset.name) .. "  -  SAME PIECES FOR BOTH")
    o.ready:Hide()
    o.cancel:SetLabel("Cancel")
    if m.state == "inviting" then
      o.status:SetText("Challenge sent. Waiting for " .. short(m.rival) .. "...")
      o.meCard.state:SetText(""); o.themCard.state:SetText("invited...")
      o.themCard.state:SetTextColor(C.label[1], C.label[2], C.label[3])
    elseif m.state == "lobby" then
      o.status:SetText(m.silentWarned and "No answer from your rival... (connection?)" or "Press Ready when you are set.")
      chip(o.meCard.state, m.myReady); chip(o.themCard.state, m.rivalReady)
      if not m.myReady then o.ready:Show() end
      if m.ruleset.spell then
        local S = ns.Spells
        local lo = S.decodeLoadout(m.myLoadout or ns.db.spell.loadout) or S.DEFAULT_LOADOUT
        for i, ic in ipairs(o.spells.icons) do ic:SetTexture(T.MEDIA .. "Spells\\" .. lo[i]) end
        o.spells.change:SetShown(not m.myReady)
        o.spells.locked:SetShown(m.myReady)
      end
      if UI.inCombat() then o.ready:Disable() else o.ready:Enable() end
    else
      local why = CANCEL[m.endReason] or "Duel cancelled."
      o.status:SetText(why:match("^%l") and (short(m.rival) .. " " .. why) or why)
      o.meCard.state:SetText(""); o.themCard.state:SetText("")
      o.cancel:SetLabel("Back")
    end
    local spell = m.ruleset and m.ruleset.spell and m.state == "lobby"
    o.spells:SetShown(spell and true or false)
    o.ready:ClearAllPoints(); o.ready:SetPoint("TOP", 0, spell and -232 or -202)
    self.menu:Hide(); self.pause:Hide(); self.over:Hide()
  else
    o:Hide()
  end
  local showRival = inDuel and true or false
  self.rivalPanel:SetShown(showRival)
  self.nextPanel:SetHeight(self.field:GetHeight() - (showRival and 82 or 0))
  self.nextPreviews[5]:SetShown(not showRival)
  self:RenderRival()
  return o:IsShown()
end

function UI:RenderRival()
  local rp = self.rivalPanel
  if not rp or not rp:IsShown() then return end
  local s = ns.App.session
  local m = s and s.duel
  if not m then return end
  local r = m.rival_
  local my = s.state.score
  local their = r.score or 0
  rp.name:SetText("VS " .. string.upper(short(m.rival)):sub(1, 13))
  rp.score:SetText(T.commas(their))
  rp.state:SetText(m.silentWarned and "no signal..." or (r.over and "finished" or "playing"))
  local c = (their > my) and C.redLight or C.steel
  rp.score:SetTextColor(c[1], c[2], c[3])
  -- share of the combined score that is mine (half/half at the start)
  local total = my + their
  local share = total > 0 and (my / total) or 0.5
  rp.bar:SetWidth(math.max(1, 88 * share))
end

------------------------------------------------------------------------------------------------
-- Result on the game-over overlay
------------------------------------------------------------------------------------------------
function UI:ShowDuelOver(m)
  local s = ns.App.session
  self.shareGuild:Hide(); self.shareGroup:Hide(); self.shareLabel:Hide()
  self.againHint:SetText("")
  if m.state ~= "done" then
    self.overTitle:SetText("FINISHED")
    self.overTitle:SetTextColor(C.paper[1], C.paper[2], C.paper[3])
    self.overScore:SetText(T.commas(s and s.state.score or 0))
    local r = m.rival_
    self.overBadge:SetText(short(m.rival) .. ": " .. T.commas(r.score or 0) .. (r.over and "" or "  (playing)"))
    self.overBadge:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
    self.overDetail:SetText(m.silentWarned and "No answer from your rival..." or "Waiting for your rival to finish.")
    self.againBtn:SetLabel("Leave duel")
  else
    local o = outcomeOf(m)
    self.overTitle:SetText(o[1])
    self.overTitle:SetTextColor(o[2][1], o[2][2], o[2][3])
    self.overScore:SetText(T.commas(m.myScore or 0))
    self.overBadge:SetText(short(m.rival) .. ": " .. T.commas(m.theirScore or 0))
    self.overBadge:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
    local note = REASON[m.endReason] or ""
    if m.endReason == "check_failed" and m.check and m.check.reasons and m.check.reasons[1] == "pause_limit" then
      note = "Your rival's game took far longer than its time plus the pauses both PCs saw (a hidden pause or a slowed-down game): rejected."
    end
    if m.spell and m.endReason == "checked" then
      note = "Both games replayed together on your PC (peer check)."
      if m.spell.diverged then note = note .. " A spell reached a board late, so the replay differs from what you saw." end
    elseif m.spell and m.endReason == "check_failed" then
      note = "Your rival's spells or moves failed the replay check: their result is rejected."
    end
    if m.basis and m.basis ~= "replay" and m.basis ~= "void" and BASIS[m.basis] then note = note .. "\n" .. BASIS[m.basis] end
    if m.noClock then note = note .. "\nYour rival's StackRivals has no shared pauses or clock check (older version)." end
    note = note .. "\n" .. (AGREEMENT[m.agreement] or "Confirming with your rival...")
    if m.agreement == "disputed" then
      self.overTitle:SetText("DISPUTED")
      self.overTitle:SetTextColor(C.label[1], C.label[2], C.label[3])
    end
    self.overDetail:SetText(note)
    self.againBtn:SetLabel("Rematch")
    if m.outcome == "win" then self.badgePulse:Stop(); self.badgePulse:Play() end
  end
end


function UI:PlayAgain()
  local s = ns.App.session
  local m = s and s.duel
  if m then
    if m.state == "done" then
      local okR = ns.Duel.rematch()
      if okR then UI:RefreshPhase() end
    else
      ns.Duel.leave()
    end
    return
  end
  ns.App:Start(ns.App.lastMode or "classic")
end

------------------------------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------------------------------
function UI:CreateDuel()
  self:CreateDuelSheet()
  self:CreateInvitePopup()
  self:CreateDuelOverlays()
  local D = ns.Duel
  D.on("players", function() UI:RefreshDuelSheet() end)
  D.on("invite", function(m)
    local f = UI.invite
    f.title:SetText((m.rematch and "Rematch from " or "Duel challenge from ") .. short(m.rival))
    f.left = nil
    f:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
  end)
  D.on("score", function() UI:RenderRival(); if UI.over:IsShown() then local m = D.current; if m then UI:ShowDuelOver(m) end end end)
  D.on("changed", function(m)
    if m and m.state == "lobby" and UI.frame and not UI.frame:IsShown()
      and not (UI.inCombat() and ns.db.settings.hideInCombat) then UI.frame:Show() end
    if m and m.state == "inviting" and UI.duelSheet:IsShown() then UI.duelSheet:Hide() end
    UI:RefreshDuelSheet()
    if UI.frame then
      local s = ns.App.session
      if s and s.duel == m and s.phase == "over" and m then UI:ShowDuelOver(m) end
      UI:RefreshPhase()
    end
  end)
  D.on("trial", function(sender)
    ns.App:Print(short(sender) .. " challenged you to a duel, but Trial/Veteran accounts can't send addon messages (Blizzard rule), so you can't answer.")
  end)
  D.on("result", function(m)
    local o = outcomeOf(m)
    ns.App:Print(string.format("Duel vs %s: %s  (%s - %s). %s", short(m.rival), o[1], T.commas(m.myScore or 0), T.commas(m.theirScore or 0), REASON[m.endReason] or ""))
    if m.outcome == "win" then ns.Sound.play("record") end
  end)
end
