--[[
  StackRivals - Quickplay screen: pick Blitz 2:00 or Spell Battle 3:00, Search, watch the search,
  cancel. When an opponent is found the duel lobby takes over (it is the ready check), then the
  normal duel: countdown, match, result, rematch.
  Honest about reach: it says where it is looking (guild, group, friends with StackRivals) and that
  stackrivals.io players are NOT connected (no fake queue).
]]
local _, ns = ...
local T = ns.T
local C = T.C
local UI = ns.UI
local SZ = T.SIZE

local MODE_LABEL = { b120 = "Duel 2:00", s180 = "Spell Duel 3:00" }
UI.QP_MODE_LABEL = MODE_LABEL
local NOTE = {
  no_opponent = "No opponent found in 5 minutes. Only players who are searching right now and that WoW lets you reach can be matched.",
  fell_through = "Your opponent didn't get ready. Searching again (they are skipped for 2 minutes).",
  cancelled = "Search cancelled.",
  you_not_ready = "You didn't press Ready in time, so the search stopped. Search again when you're set.",
}

local function clock(sec)
  sec = math.max(0, math.floor(sec or 0))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
UI.qpClock = clock

local function setSegment(b, on)
  local c = on and C.steelDeep or C.surface2
  b.bgTex:SetColorTexture(c[1], c[2], c[3], 1)
  local e = on and C.steel or C.line
  b.border:SetColorTexture(e[1], e[2], e[3], 1)
end

--- Where the search reaches, in words.
local function reachText(r)
  if not r then return "" end
  local parts = {}
  if r.guild then parts[#parts + 1] = "your guild" end
  if r.group then parts[#parts + 1] = "your group" end
  if (r.friends or 0) > 0 then parts[#parts + 1] = r.friends .. (r.friends == 1 and " friend" or " friends") .. " with StackRivals" end
  if #parts == 0 then return "Nobody to reach yet: join a guild or group, or add friends who use StackRivals." end
  return "Looking in: " .. table.concat(parts, ", ") .. "."
end
UI.qpReachText = reachText

function UI:CreateQuickplay()
  local QP = ns.Quickplay
  local s = self:Body(40)
  self.qpSheet = s
  local L = 24
  local cw = self.frame:GetWidth() - 2 * L - 2
  local title = T.text(s, SZ.title, C.paper, "", nil, "italic"); title:SetPoint("TOPLEFT", L, -14); title:SetText("QUICKPLAY")
  local sub = T.text(s, SZ.small, C.label); sub:SetPoint("TOPLEFT", L, -38)
  sub:SetText("Quick Duel: meet a random StackRivals player. Same pieces, same rules.")

  self.qpMode = (ns.db and ns.db.quickplay and ns.db.quickplay.mode) or "b120"
  local function pick(mode)
    if QP.state == "searching" then return end -- change the mode after cancelling
    UI.qpMode = mode
    if ns.db and ns.db.quickplay then ns.db.quickplay.mode = mode end
    UI:RefreshQuickplay()
  end
  s.b120 = T.button(s, "Duel 2:00", 118, 28, "frame", function() pick("b120") end)
  s.b120:SetPoint("TOPLEFT", L, -60)
  s.b120.tip = "Score race: 2 minutes, same pieces for both. Higher score wins."
  s.s180 = T.button(s, "Spell Duel 3:00", 150, 28, "frame", function() pick("s180") end)
  s.s180:SetPoint("LEFT", s.b120, "RIGHT", 4, 0)
  s.s180.tip = "Spell Duel: the web's spells and mana, casts land on your rival's board. First to top out loses."

  -- the search stage
  local st = T.panel(s, C.red)
  st:SetSize(cw, 110); st:SetPoint("TOPLEFT", L, -98)
  st.state = T.text(st, SZ.display, C.paper, "", nil, "italic"); st.state:SetPoint("TOP", 0, -12)
  st.time = T.display(st, SZ.heading, C.gold); st.time:SetPoint("TOP", 0, -44)
  -- five blocks that light up in turn while searching (one texture alpha per step: cheap)
  st.dots = {}
  for i = 1, 5 do
    local d = T.tex(st, "ARTWORK", C.red, 1)
    d:SetSize(10, 10); d:SetPoint("TOP", st, "TOP", (i - 3) * 16, -68)
    st.dots[i] = d
  end
  st.reach = T.text(st, SZ.label, C.label); st.reach:SetPoint("TOP", 0, -86); st.reach:SetWidth(cw - 24)
  s.stage = st

  s.go = T.button(s, "Search", 220, 36, "primary", function()
    if QP.state == "searching" then QP.cancel("cancelled")
    else
      local okS, why = QP.start(UI.qpMode)
      UI.qpNote = (not okS) and ("Can't search: " .. tostring(why) .. ".") or nil
    end
    UI:RefreshQuickplay()
  end)
  s.go:SetPoint("TOP", 0, -218)

  -- your card (what your rival will see) + sharing switch
  local me = T.panel(s)
  me:SetSize(cw, 52); me:SetPoint("TOPLEFT", L, -264)
  local ml = T.label(me, "YOUR CARD"); ml:SetPoint("TOPLEFT", 10, -8)
  me.line = T.text(me, SZ.small, C.paper); me.line:SetPoint("TOPLEFT", 10, -24); me.line:SetWidth(cw - 190); me.line:SetJustifyH("LEFT")
  me.share = T.toggle(me, "Share my card", function(v)
    if ns.db and ns.db.social then ns.db.social.shareCard = v end
    UI:RefreshQuickplay()
  end, 150)
  me.share:SetPoint("RIGHT", -6, 0)
  me.share.tip = "Off: your rival sees Unknown instead of your faction, race, class, level and duel record."
  s.me = me

  -- stackrivals.io: an adapter that exists but is honestly not connected
  s.web = T.text(s, SZ.label, C.label); s.web:SetPoint("TOPLEFT", L, -326); s.web:SetWidth(cw - 150); s.web:SetJustifyH("LEFT")
  s.note = T.text(s, SZ.small, C.body); s.note:SetPoint("TOPLEFT", L, -360); s.note:SetWidth(cw - 150); s.note:SetJustifyH("LEFT")

  local close = T.button(s, "Close", 130, 32, "frame", function() s:Hide(); UI:RefreshPhase() end)
  close:SetPoint("BOTTOMRIGHT", -20, 16)

  -- animation: only while the sheet is shown and a search runs (no work otherwise)
  local acc, step = 0, 0
  s:SetScript("OnUpdate", function(_, elapsed)
    if QP.state ~= "searching" then return end
    acc = acc + elapsed
    if acc < 0.12 then return end
    acc = 0
    step = step % 5 + 1
    for i, d in ipairs(st.dots) do d:SetAlpha(i == step and 1 or 0.25) end
    st.time:SetText(clock(GetTime() - (QP.started or GetTime())))
  end)
  s:SetScript("OnShow", function() UI:RefreshQuickplay() end)

  -- the menu bar keeps its "Searching 0:42" current (twice a second, only while searching)
  local barAcc = 0
  if self.qpBar then
    self.qpBar:SetScript("OnUpdate", function(_, elapsed)
      if QP.state ~= "searching" then return end
      barAcc = barAcc + elapsed
      if barAcc >= 0.5 then barAcc = 0; UI:RefreshQuickplayBar() end
    end)
  end

  QP.on("changed", function()
    if QP.state == "matched" then
      -- opponent found: the duel lobby takes over the window (ready check)
      if s:IsShown() then s:Hide() end
      UI.qpNote = nil
      if UI.frame and not UI.frame:IsShown() and not (UI.inCombat() and ns.db.settings.hideInCombat) then UI.frame:Show() end
      if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
    end
    UI:RefreshQuickplay()
    UI:RefreshQuickplayBar()
    UI:RefreshPhase()
  end)
end

function UI:RefreshQuickplay()
  local s = self.qpSheet
  if not s or not s:IsShown() then return end
  local QP = ns.Quickplay
  local mode = (QP.state == "searching") and QP.mode or self.qpMode
  setSegment(s.b120, mode == "b120"); setSegment(s.s180, mode == "s180")
  local searching = QP.state == "searching"
  if searching then s.b120:Disable(); s.s180:Disable() else s.b120:Enable(); s.s180:Enable() end
  local st = s.stage
  local avail, why = QP.adapters.native.status()
  for _, d in ipairs(st.dots) do d:SetShown(searching); d:SetAlpha(0.25) end
  if searching then
    st.state:SetText("SEARCHING")
    st.state:SetTextColor(C.paper[1], C.paper[2], C.paper[3])
    st.time:SetText(clock(GetTime() - (QP.started or GetTime())))
    st.reach:SetText(reachText(QP.reach))
    s.go:SetLabel("Cancel search")
  elseif QP.state == "none" then
    st.state:SetText("NO OPPONENT")
    st.state:SetTextColor(C.label[1], C.label[2], C.label[3])
    st.time:SetText("")
    st.reach:SetText(reachText(QP.reach))
    s.go:SetLabel("Search again")
  else
    st.state:SetText(avail == "available" and "READY TO SEARCH" or "UNAVAILABLE")
    st.state:SetTextColor(C.paper[1], C.paper[2], C.paper[3])
    st.time:SetText(MODE_LABEL[mode] or "")
    st.reach:SetText(avail == "available" and "Players searching now in your guild, your group and friends with StackRivals." or (why or ""))
    s.go:SetLabel("Search")
  end
  if avail ~= "available" or (ns.Duel and ns.Duel.busy()) or UI.inCombat() then s.go:Disable() else s.go:Enable() end
  if searching then s.go:Enable() end -- cancelling is always possible
  -- your card
  local Card = ns.Card
  local share = Card.sharing()
  s.me.share:SetValue(share)
  s.me.line:SetText(share and Card.describe(Card.mine(), true) or "Hidden: your rival sees Unknown.")
  -- the web adapter, honestly
  local web = QP.adapters.web
  local wst = web.status()
  s.web:SetText("Web players (stackrivals.io): " .. (wst == "not_connected" and "not connected" or wst)
    .. "\nA WoW addon can't reach the website. Web Quickplay needs a tested connection first.")
  s.note:SetText(self.qpNote or NOTE[QP.note or ""] or "")
end

--- The wide QUICKPLAY bar in the menu: what the search is doing.
function UI:RefreshQuickplayBar()
  local b = self.qpBar
  local QP = ns.Quickplay
  if not b or not QP or (ns.BUILD and not ns.BUILD.duels) then return end
  if QP.state == "searching" then
    b.desc:SetText("Searching " .. (MODE_LABEL[QP.mode] or "") .. "  " .. clock(GetTime() - (QP.started or GetTime())))
  elseif QP.state == "matched" then
    b.desc:SetText("Opponent found!")
  elseif QP.state == "none" then
    b.desc:SetText("No opponent found  -  try again")
  else
    b.desc:SetText("Quick Duel  -  a random rival")
  end
  if UI.inCombat() then b:Disable() else b:Enable() end
end
