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
local REASON = {
  checked = "Rival's game replayed to the same score on your PC (peer check).",
  unchecked = "Rival's replay didn't arrive: result by their reported score.",
  check_failed = "Rival's result failed the replay check: no winner recorded.",
  rival_forfeited = "Your rival left the duel.",
  rival_disconnected = "Lost contact with your rival.",
  rival_offline = "Your rival went offline.",
  you_forfeited = "You left the duel.",
  timeout = "Your rival didn't finish in time.",
}
local CANCEL = {
  rival_no = "declined your challenge.", rival_busy = "is busy in another duel.", rival_combat = "is in combat right now.",
  rival_version = "has a different StackRivals version.", rival_timeout = "didn't answer in time.",
  rival_cancel = "cancelled the duel.", no_answer = "didn't answer.", lobby_timeout = "Nobody pressed Ready in time.",
  you_declined = "You declined.", timeout = "The invite timed out.", rival_disconnected = "Lost contact with your rival.",
}

local function short(n) return ns.Duel.short(n) or "?" end

------------------------------------------------------------------------------------------------
-- Duel sheet: find players + challenge
------------------------------------------------------------------------------------------------
function UI:CreateDuelSheet()
  local F = self.frame
  local s = CreateFrame("Frame", nil, F)
  s:SetPoint("TOPLEFT", F, "TOPLEFT", 1, -40)
  s:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", -1, 1)
  s:SetFrameLevel(F:GetFrameLevel() + 40)
  local bg = T.tex(s, "BACKGROUND", C.navy, 1); bg:SetAllPoints()
  s:EnableMouse(true)
  s:Hide()
  self.duelSheet = s
  local title = T.text(s, 15, C.paper); title:SetPoint("TOPLEFT", 20, -12); title:SetText("DUEL")
  local sub = T.text(s, 10, C.label); sub:SetPoint("TOPLEFT", 20, -32)
  sub:SetText("1v1 score race. Same pieces for both. Highest score wins.")

  self.duelRuleset = "b120"
  local b120 = T.button(s, "Blitz 2:00", 96, 22, "steel", function() UI.duelRuleset = "b120"; UI:RefreshDuelSheet() end)
  b120:SetPoint("TOPLEFT", 20, -52)
  local r180 = T.button(s, "3:00 web rules", 112, 22, "frame", function() UI.duelRuleset = "r180"; UI:RefreshDuelSheet() end)
  r180:SetPoint("LEFT", b120, "RIGHT", 6, 0)
  s.b120, s.r180 = b120, r180

  local find = T.button(s, "Find players", 110, 22, "primary", function()
    local okFind, why = ns.Duel.findPlayers()
    UI.duelFindNote = okFind and "Asked your guild and group..." or (why == "cooldown" and "Just asked - wait a moment." or "Join a guild or group to find players.")
    UI:RefreshDuelSheet()
  end)
  find:SetPoint("TOPRIGHT", -20, -52)
  s.note = T.text(s, 10, C.body); s.note:SetPoint("TOPLEFT", 20, -82)

  s.rows = {}
  for i = 1, 8 do
    local row = CreateFrame("Frame", nil, s)
    row:SetSize(410, 26)
    row:SetPoint("TOPLEFT", 20, -100 - (i - 1) * 30)
    local rbg = T.tex(row, "BACKGROUND", C.surface1, 0.9); rbg:SetAllPoints()
    row.name = T.text(row, 12, C.paper); row.name:SetPoint("LEFT", 8, 0); row.name:SetJustifyH("LEFT")
    row.info = T.text(row, 10, C.label); row.info:SetPoint("LEFT", 190, 0); row.info:SetJustifyH("LEFT")
    row.btn = T.button(row, "Challenge", 84, 20, "steel", function(b)
      local okC, why = ns.Duel.challenge(b.target, UI.duelRuleset)
      if not okC then UI.duelFindNote = "Can't challenge now (" .. tostring(why) .. ")." end
      UI:RefreshDuelSheet()
    end)
    row.btn:SetPoint("RIGHT", -4, 0)
    row:Hide()
    s.rows[i] = row
  end
  s.empty = T.text(s, 11, C.label); s.empty:SetPoint("TOPLEFT", 20, -104); s.empty:SetWidth(410); s.empty:SetJustifyH("LEFT")
  s.empty:SetText("Press Find players to see who in your guild or group has StackRivals.\nOr type /sr duel Name to challenge anyone on your realm.")

  s.stats = T.text(s, 10, C.label); s.stats:SetPoint("BOTTOMLEFT", 20, 58); s.stats:SetWidth(410); s.stats:SetJustifyH("LEFT")
  local close = T.button(s, "Close", 120, 28, "primary", function() s:Hide(); UI:RefreshPhase() end)
  close:SetPoint("BOTTOM", 0, 16)
  s:SetScript("OnShow", function() UI:RefreshDuelSheet() end)
end

function UI:RefreshDuelSheet()
  local s = self.duelSheet
  if not s or not s:IsShown() then return end
  local st = s.b120.bgTex
  local on, off = C.steelDeep, C.surface2
  s.b120.bgTex:SetColorTexture((self.duelRuleset == "b120" and on or off)[1], (self.duelRuleset == "b120" and on or off)[2], (self.duelRuleset == "b120" and on or off)[3], 1)
  s.r180.bgTex:SetColorTexture((self.duelRuleset == "r180" and on or off)[1], (self.duelRuleset == "r180" and on or off)[2], (self.duelRuleset == "r180" and on or off)[3], 1)
  s.note:SetText(not ns.Comm.enabled and "Addon messages are not available in this client." or (self.duelFindNote or ""))
  local list = {}
  for _, p in pairs(ns.Duel.players) do list[#list + 1] = p end
  table.sort(list, function(a, b) return a.name < b.name end)
  local busy = ns.Duel.busy() or UI.inCombat()
  for i, row in ipairs(s.rows) do
    local p = list[i]
    if p then
      row.name:SetText(short(p.name))
      row.info:SetText(not p.compatible and "other version" or (p.busy and "in a duel" or ("v" .. p.addon)))
      row.btn.target = p.name
      if p.compatible and not p.busy and not busy then row.btn:Enable() else row.btn:Disable() end
      row:Show()
    else
      row:Hide()
    end
  end
  s.empty:SetShown(#list == 0)
  local d = ns.db.duels
  s.stats:SetText(string.format("Your duels: %d won, %d lost, %d draws.  Results are checked by both players' addons\n(replay of the rival's game), not by a server.", d.wins, d.losses, d.draws))
end

------------------------------------------------------------------------------------------------
-- Incoming invite popup (works with the main window closed)
------------------------------------------------------------------------------------------------
function UI:CreateInvitePopup()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(300, 96)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f:SetFrameStrata("DIALOG")
  local p = T.panel(f, C.steel, 0.97); p:SetAllPoints()
  f.title = T.text(f, 13, C.paper); f.title:SetPoint("TOP", 0, -12)
  f.sub = T.text(f, 10, C.body); f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
  local acc = T.button(f, "Accept", 110, 24, "primary", function() ns.Duel.accept(); f:Hide() end)
  acc:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 12)
  local dec = T.button(f, "Decline", 110, 24, "frame", function() ns.Duel.decline("no"); f:Hide() end)
  dec:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 12)
  f.acc = acc
  f:Hide()
  f:SetScript("OnUpdate", function(self)
    local m = ns.Duel.current
    if not m or m.state ~= "invited" then self:Hide(); return end
    local left = math.max(0, math.ceil(ns.Duel.INVITE_TIMEOUT - (GetTime() - m.createdAt)))
    if self.left ~= left then
      self.left = left
      self.sub:SetText(m.ruleset.name .. "  -  " .. left .. " s")
    end
    if UI.inCombat() then self.acc:Disable() else self.acc:Enable() end
  end)
  self.invite = f
end

------------------------------------------------------------------------------------------------
-- Lobby overlay on the playfield + rival panel
------------------------------------------------------------------------------------------------
function UI:CreateDuelOverlays()
  local field = self.field
  local o = CreateFrame("Frame", nil, field)
  o:SetAllPoints(field)
  o:SetFrameLevel(field:GetFrameLevel() + 12)
  local bg = T.tex(o, "BACKGROUND", C.navy, 0.95); bg:SetAllPoints()
  o:EnableMouse(true)
  o:Hide()
  self.lobby = o
  local vs = T.text(o, 13, C.label); vs:SetPoint("TOP", 0, -60); vs:SetText("DUEL")
  o.rival = T.text(o, 18, C.paper); o.rival:SetPoint("TOP", vs, "BOTTOM", 0, -8)
  o.rules = T.text(o, 10, C.steel); o.rules:SetPoint("TOP", o.rival, "BOTTOM", 0, -6)
  o.status = T.text(o, 11, C.body); o.status:SetPoint("TOP", o.rules, "BOTTOM", 0, -24); o.status:SetWidth(170)
  o.me = T.text(o, 11, C.body); o.me:SetPoint("TOP", o.status, "BOTTOM", 0, -18)
  o.them = T.text(o, 11, C.body); o.them:SetPoint("TOP", o.me, "BOTTOM", 0, -6)
  o.ready = T.button(o, "Ready", 150, 28, "primary", function() ns.Duel.ready() end)
  o.ready:SetPoint("BOTTOM", 0, 74)
  o.cancel = T.button(o, "Cancel", 150, 24, "frame", function()
    local m = ns.Duel.current
    if m and (m.state == "cancelled") then ns.Duel.clear(); ns.App:ShowMenu() else ns.Duel.leave() end
    UI:RefreshPhase()
  end)
  o.cancel:SetPoint("TOP", o.ready, "BOTTOM", 0, -8)

  -- rival panel under NEXT (only during a duel)
  local rp = T.panel(self.frame, C.steel)
  rp:SetSize(104, 34)
  rp:SetPoint("BOTTOMLEFT", field, "BOTTOMRIGHT", 12, 0)
  rp.name = T.text(rp, 9, C.label); rp.name:SetPoint("TOPLEFT", 6, -5); rp.name:SetJustifyH("LEFT")
  rp.score = T.text(rp, 13, C.steel); rp.score:SetPoint("TOPLEFT", 6, -16); rp.score:SetJustifyH("LEFT")
  rp:Hide()
  self.rivalPanel = rp
end

--- Sync the duel UI with the current duel state; returns true if the lobby took over the field.
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
    o:Show()
    o.rival:SetText(short(m.rival))
    o.rules:SetText(m.ruleset.name)
    o.ready:Hide()
    o.cancel:SetLabel("Cancel")
    if m.state == "inviting" then
      o.status:SetText("Challenge sent. Waiting for an answer...")
      o.me:SetText(""); o.them:SetText("")
    elseif m.state == "lobby" then
      o.status:SetText(m.silentWarned and "No answer from your rival... (connection?)" or "Press Ready when you are set.")
      o.me:SetText("You: " .. (m.myReady and "|cff7be3a0READY|r" or "not ready"))
      o.them:SetText(short(m.rival) .. ": " .. (m.rivalReady and "|cff7be3a0READY|r" or "not ready"))
      if not m.myReady then o.ready:Show() end
      if UI.inCombat() then o.ready:Disable() else o.ready:Enable() end
    else
      local why = CANCEL[m.endReason] or "Duel cancelled."
      o.status:SetText(why:match("^%l") and (short(m.rival) .. " " .. why) or why)
      o.me:SetText(""); o.them:SetText("")
      o.cancel:SetLabel("Back")
    end
    self.menu:Hide(); self.pause:Hide(); self.over:Hide()
  else
    o:Hide()
  end
  self.rivalPanel:SetShown(inDuel and true or false)
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
  rp.name:SetText("VS " .. short(m.rival):sub(1, 14) .. (m.silentWarned and "  ?" or ""))
  local lead = their - my
  rp.score:SetText(T.commas(their) .. (r.over and "  done" or ""))
  local c = (lead > 0) and C.redLight or C.steel
  rp.score:SetTextColor(c[1], c[2], c[3])
end

------------------------------------------------------------------------------------------------
-- Result on the game-over overlay
------------------------------------------------------------------------------------------------
function UI:ShowDuelOver(m)
  local s = ns.App.session
  self.shareGuild:Hide(); self.shareGroup:Hide()
  self.againHint:SetText("")
  if m.state ~= "done" then
    self.overTitle:SetText("FINISHED")
    self.overTitle:SetTextColor(C.paper[1], C.paper[2], C.paper[3])
    self.overScore:SetText(T.commas(s and s.state.score or 0))
    local r = m.rival_
    self.overBadge:SetText(short(m.rival) .. ": " .. T.commas(r.score or 0) .. (r.over and "" or "  (playing)"))
    self.overDetail:SetText(m.silentWarned and "No answer from your rival..." or "Waiting for your rival to finish.")
    self.againBtn:SetLabel("Leave duel")
  else
    local o = OUTCOME[m.outcome] or OUTCOME.void
    self.overTitle:SetText(o[1])
    self.overTitle:SetTextColor(o[2][1], o[2][2], o[2][3])
    self.overScore:SetText(T.commas(m.myScore or 0))
    self.overBadge:SetText(short(m.rival) .. ": " .. T.commas(m.theirScore or 0))
    self.overDetail:SetText(REASON[m.endReason] or "")
    self.againBtn:SetLabel("Rematch")
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
    if m and m.state == "lobby" and UI.frame and not UI.frame:IsShown() then UI.frame:Show() end
    if m and m.state == "inviting" and UI.duelSheet:IsShown() then UI.duelSheet:Hide() end
    UI:RefreshDuelSheet()
    if UI.frame then
      local s = ns.App.session
      if s and s.duel == m and s.phase == "over" and m then UI:ShowDuelOver(m) end
      UI:RefreshPhase()
    end
  end)
  D.on("result", function(m)
    local o = OUTCOME[m.outcome] or OUTCOME.void
    ns.App:Print(string.format("Duel vs %s: %s  (%s - %s). %s", short(m.rival), o[1], T.commas(m.myScore or 0), T.commas(m.theirScore or 0), REASON[m.endReason] or ""))
    if m.outcome == "win" then ns.Sound.play("record") end
  end)
end
