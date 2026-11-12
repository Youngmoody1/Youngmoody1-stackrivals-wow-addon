--[[
  StackRivals - Loot Duel screens: the sheet (item, time, players, invite / start, results), the
  invite popup, the live leaderboard beside the window, and the small rank panel under NEXT.
  2-40 players race at once (one race, no 1v1 rounds or heats). The loot master hands out the item in WoW;
  nothing here touches loot.
]]
local _, ns = ...
local T = ns.T
local C = T.C
local UI = ns.UI
local SZ = T.SIZE

local ROWS, ROW_H = 10, 16 -- 10 per page: a party or 10 on one page, a 40-player raid on 4
-- Result colours (the class colour stays on the name): WINNER green, LOST / PASSED red, TIE gold,
-- PLAYING steel; not checked / no result / disconnected are amber and never shown as a defeat.
-- Every status also has an icon (Media/Status), so nothing depends on colour alone.
local AMBER = { 0.91, 0.63, 0.25 }
local ICON = function(n) return T.MEDIA .. "Status\\" .. n end
local STATUS = {
  invited = { "invited...", C.label }, accepted = { "joined", C.green, "ready" }, declined = { "passed", C.redLight, "passed" },
  noanswer = { "no answer: normal loot instead", C.label, "unknown" }, version = { "other StackRivals version", C.label },
  verified = { "replay-checked", C.green, "ready" }, rejected = { "replay failed: out", AMBER, "warn" }, missing = { "no result: out", AMBER, "warn" },
  pending = { "checking...", C.gold, "unknown" }, playing = { "playing", C.steel, "playing" }, watching = { "", C.label },
  locking = { "locking in...", C.gold }, locked = { "ready", C.green, "ready" }, picked = { "", C.label },
  -- final results
  winner = { "WINNER", C.green, "winner" }, lost = { "LOST", C.redLight, "lost" }, tie = { "TIE", C.gold, "tie" },
  passed = { "PASSED", C.redLight, "passed" }, unchecked = { "NOT CHECKED", AMBER, "unknown" },
  noresult = { "NO RESULT", AMBER, "warn" }, failed = { "REPLAY FAILED", AMBER, "warn" }, silent = { "NO ANSWER", C.label, "unknown" },
}
UI.LOOT_STATUS = STATUS
-- the live board's words (Core/LootDuel.lua LD.liveBoard)
local LIVE = {
  playing = { "playing", C.steel, "playing" }, topped_out = { "topped out", C.label, "done" }, time_up = { "finished", C.label, "done" },
  no_signal = { "no signal", AMBER, "warn" }, held = { "held by WoW", AMBER, "warn" }, disconnected = { "disconnected", AMBER, "warn" }, checking = { "checking...", C.gold, "unknown" },
  checked = { "checked", C.green, "ready" }, failed = { "replay failed: out", AMBER, "warn" }, out = { "no result: out", AMBER, "warn" },
}
local ADDON = { yes = { "StackRivals", C.green }, old = { "old StackRivals", C.label }, you = { "you", C.label } }
local REASON = {
  leader_cancelled = "The leader cancelled this Loot Duel.", cancelled = "Loot Duel cancelled.",
  not_started = "The leader didn't start this Loot Duel.",
  bad_start_commit = "The leader's seed share didn't match the offer: cancelled.",
  bad_start_list = "The player list didn't check out: cancelled.", bad_start_not_invited = "Someone not invited was in the list: cancelled.",
  bad_start_commit_swap = "A player's seed share was changed after they joined: cancelled.",
  bad_start_my_commit = "Your seed share was changed in the list: cancelled.",
  bad_start_reveal = "The seed shares didn't check out: cancelled.", bad_start_my_nonce = "Your seed share didn't match: cancelled.",
  noreveal = "Not every player confirmed in time, so the seed couldn't be fixed: cancelled. Start a new one.",
}

local function short(n) return ns.Duel and ns.Duel.short(n) or n end
local function setIcon(tex, name) if name then tex:SetTexture(ICON(name)); tex:Show() else tex:Hide() end end
local function itemText(d)
  local name, _, q = ns.LootDuel.itemInfo(d.itemId)
  local r, g, b = T.qualityColor(q or 1)
  local hex = r and string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) or "ffffffff"
  return "|c" .. hex .. (name and (name:gsub("|", "||")) or ("item " .. d.itemId)) .. "|r", name
end
UI.lootItemText = itemText

--- WoW's own class name ("Warrior"), else the token in title case.
local function className(token)
  if type(token) ~= "string" then return "" end
  local loc = type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[token]
  if loc then return loc end
  return token:sub(1, 1) .. token:sub(2):lower():gsub("hunter$", " Hunter"):gsub("^Deathknight$", "Death Knight")
end

local function setSeg(b, on)
  b.onReEnable = function(x) setSeg(x, on) end -- keep the selection after hover / re-enable
  if b.greyed then -- disabled: grey, but the picked one keeps its border
    local e = on and C.gold or C.line
    b.border:SetColorTexture(e[1], e[2], e[3], 1)
    return
  end
  local c = on and C.goldDeep or C.surface2
  b.bgTex:SetColorTexture(c[1], c[2], c[3], 1)
  local e = on and C.gold or C.line
  b.border:SetColorTexture(e[1], e[2], e[3], 1)
end

local function pickedCount()
  local n = 0
  for _ in pairs(UI.lootPick) do n = n + 1 end
  return n
end

--- Everyone online in the group (you included), for Invite Party / Invite All.
local function everyone()
  local out = {}
  for _, e in ipairs(ns.LootDuel.roster()) do if e.online ~= false then out[#out + 1] = e.name end end
  return out
end

function UI:CreateLootDuel()
  local LD = ns.LootDuel
  local s = self:Body(40)
  self.lootSheet = s
  local L = 24
  local cw = self.frame:GetWidth() - 2 * L - 2
  local title = T.text(s, SZ.title, C.gold, "", nil, "italic"); title:SetPoint("TOPLEFT", L, -14); title:SetText("LOOT DUEL")
  s.sub = T.text(s, SZ.small, C.label); s.sub:SetPoint("TOPLEFT", L, -38)
  s.sub:SetText("2-40 players race at once for one item. Winning doesn't hand out the item.")

  -- the item
  local it = T.panel(s, C.gold)
  it:SetSize(cw, 40); it:SetPoint("TOPLEFT", L, -56)
  it.icon = it:CreateTexture(nil, "ARTWORK"); it.icon:SetSize(30, 30); it.icon:SetPoint("LEFT", 6, 0)
  it.name = T.display(it, SZ.heading, C.paper); it.name:SetPoint("TOPLEFT", 44, -5); it.name:SetWidth(cw - 52); it.name:SetJustifyH("LEFT")
  if it.name.SetWordWrap then it.name:SetWordWrap(false) end -- one line: a long name ends in "..."
  it.hint = T.text(it, SZ.label, C.label); it.hint:SetPoint("TOPLEFT", 44, -24); it.hint:SetWidth(cw - 52); it.hint:SetJustifyH("LEFT")
  it:EnableMouse(true)
  it:SetScript("OnEnter", function(self)
    local d = LD.current
    local id = (d and d.itemId) or UI.lootItemId
    local link = id and select(2, LD.itemInfo(id))
    if link and GameTooltip.SetHyperlink then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetHyperlink(link); GameTooltip:Show() end
  end)
  it:SetScript("OnLeave", function() GameTooltip:Hide() end)
  s.item = it
  -- the open loot window's items, one click each (read only; cycles when there are several)
  it.fromLoot = T.button(it, "From loot", 84, 22, "frame", function()
    local list = LD.lootWindowItems()
    if #list == 0 then return end
    UI.lootWinIdx = ((UI.lootWinIdx or 0) % #list) + 1
    UI.lootItemId = list[UI.lootWinIdx].itemId
    UI.lootNote = nil
    UI:RefreshLootDuel()
  end)
  it.fromLoot:SetPoint("RIGHT", -6, 0)
  it.fromLoot.tip = "Pick an item from the open loot window (click again for the next one). Nothing is looted."
  -- item input (leader, before inviting): shift-click an item while the box has focus, or paste
  s.input = UI.accountEditBox(s, cw - 106, "Shift-click an item, or paste a link / item ID", 300)
  s.input:SetPoint("TOPLEFT", L, -102)
  local function setItem()
    local id = LD.itemIdFrom(s.input:GetText())
    UI.lootItemId = id
    UI.lootNote = (not id) and LD.WHY.no_item or nil
    s.input:ClearFocus()
    UI:RefreshLootDuel()
  end
  s.input:SetScript("OnEnterPressed", setItem)
  s.setItem = T.button(s, "Set item", 100, 24, "frame", setItem)
  s.setItem:SetPoint("LEFT", s.input, "RIGHT", 6, 0)
  if hooksecurefunc and ChatEdit_InsertLink then
    -- shift-click puts the item link into our box while it has focus (WoW's normal link insert)
    pcall(hooksecurefunc, "ChatEdit_InsertLink", function(link)
      if s:IsShown() and s.input:IsShown() and s.input:HasFocus() and type(link) == "string" and link:find("item:", 1, true) then
        s.input:SetText(link); setItem()
      end
    end)
  end
  -- time + rules
  UI.lootRs = "l060"
  s.l060 = T.button(s, "1:00", 60, 24, "frame", function() UI.lootRs = "l060"; UI:RefreshLootDuel() end)
  s.l060:SetPoint("TOPLEFT", L, -132)
  s.l060.tip = "1 minute (default): quick enough between pulls."
  s.l120 = T.button(s, "2:00", 60, 24, "frame", function() UI.lootRs = "l120"; UI:RefreshLootDuel() end)
  s.l120:SetPoint("LEFT", s.l060, "RIGHT", 4, 0)
  s.l120.tip = "2 minutes: a bit more skill, a bit more waiting."
  s.rules = T.text(s, SZ.label, C.body); s.rules:SetPoint("LEFT", s.l120, "RIGHT", 10, 0); s.rules:SetWidth(cw - 140); s.rules:SetJustifyH("LEFT")
  s.rules:SetText("Same pieces, no spells, all at once. Highest score wins; tie: lines, then /roll.")
  s.banner = T.display(s, SZ.title, C.gold); s.banner:SetPoint("TOPLEFT", L, -100); s.banner:SetWidth(cw); s.banner:SetJustifyH("LEFT")
  -- final result header (everyone sees the same, once every needed replay is checked)
  local fin = CreateFrame("Frame", nil, s)
  fin:SetSize(cw, 62); fin:SetPoint("TOPLEFT", L, -98)
  fin.glow = fin:CreateTexture(nil, "BACKGROUND"); fin.glow:SetTexture(T.MEDIA .. "glow"); fin.glow:SetBlendMode("ADD")
  fin.glow:SetSize(220, 90); fin.glow:SetPoint("LEFT", -60, 0); fin.glow:SetVertexColor(0.48, 0.89, 0.63); fin.glow:SetAlpha(0)
  fin.icon = fin:CreateTexture(nil, "ARTWORK"); fin.icon:SetSize(30, 30); fin.icon:SetPoint("TOPLEFT", 0, -2)
  fin.big = T.text(fin, SZ.title, C.green, "", nil, "italic"); fin.big:SetPoint("TOPLEFT", 38, 0); fin.big:SetWidth(cw - 40); fin.big:SetJustifyH("LEFT")
  fin.line = T.display(fin, SZ.heading, C.paper); fin.line:SetPoint("TOPLEFT", 38, -22); fin.line:SetWidth(cw - 40); fin.line:SetJustifyH("LEFT")
  if fin.line.SetWordWrap then fin.line:SetWordWrap(false) end
  fin.detail = T.text(fin, SZ.label, C.label); fin.detail:SetPoint("TOPLEFT", 38, -42); fin.detail:SetWidth(cw - 40); fin.detail:SetJustifyH("LEFT")
  if fin.detail.SetWordWrap then fin.detail:SetWordWrap(false) end
  fin.pop = T.popAnim(fin, 1.12, 0.35, false)
  local ga = fin.glow:CreateAnimationGroup()
  local g1 = ga:CreateAnimation("Alpha"); g1:SetFromAlpha(0); g1:SetToAlpha(0.7); g1:SetDuration(0.25); g1:SetOrder(1)
  local g2 = ga:CreateAnimation("Alpha"); g2:SetFromAlpha(0.7); g2:SetToAlpha(0.15); g2:SetDuration(1.2); g2:SetOrder(2)
  ga:SetScript("OnFinished", function() fin.glow:SetAlpha(0.15) end)
  fin.glowAnim = ga
  fin:Hide()
  s.final = fin

  -- players (paged: a raid can have 40)
  s.head = T.label(s, "PLAYERS"); s.head:SetPoint("TOPLEFT", L, -162)
  s.prev = T.button(s, "<", 26, 18, "frame", function() UI.lootPage = math.max(1, (UI.lootPage or 1) - 1); UI:RefreshLootDuel() end)
  s.next = T.button(s, ">", 26, 18, "frame", function() UI.lootPage = (UI.lootPage or 1) + 1; UI:RefreshLootDuel() end)
  s.next:SetPoint("TOPRIGHT", -L - 2, -158); s.prev:SetPoint("RIGHT", s.next, "LEFT", -4, 0)
  s.page = T.text(s, SZ.label, C.label); s.page:SetPoint("RIGHT", s.prev, "LEFT", -6, 0)
  -- Select All / Deselect All (online members, at most 40): picking is not inviting
  s.selNone = T.button(s, "None", 44, 18, "frame", function() UI.lootPick = {}; UI.lootNote, UI.lootConfirmAll = nil, nil; UI:RefreshLootDuel() end)
  s.selAll = T.button(s, "All", 40, 18, "frame", function()
    UI.lootPick = {}
    for _, n in ipairs(everyone()) do if pickedCount() < ns.Protocol.LOOT_MAX then UI.lootPick[n:lower()] = true end end
    UI.lootNote, UI.lootConfirmAll = nil, nil
    UI:RefreshLootDuel()
  end)
  s.selAll.tip = "Tick everyone online (you included). Nobody is invited until you click Invite Selected."
  s.selNone.tip = "Untick everyone."
  s.rows = {}
  UI.lootPick = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, s)
    row:SetSize(cw, ROW_H); row:SetPoint("TOPLEFT", L, -178 - (i - 1) * ROW_H)
    row.box = T.tex(row, "BORDER", C.line, 1); row.box:SetSize(12, 12); row.box:SetPoint("LEFT", 2, 0)
    row.fill = T.tex(row, "OVERLAY", C.gold, 1); row.fill:SetSize(8, 8); row.fill:SetPoint("CENTER", row.box, "CENTER")
    row.rank = T.display(row, SZ.small, C.label); row.rank:SetPoint("LEFT", 2, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(13, 13); row.icon:Hide()
    row.bg = T.tex(row, "BACKGROUND", C.green, 0); row.bg:SetAllPoints()
    row.name = T.text(row, SZ.small, C.paper); row.name:SetPoint("LEFT", 22, 0); row.name:SetWidth(150); row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.detail = T.text(row, SZ.label, C.label); row.detail:SetPoint("LEFT", 176, 0); row.detail:SetWidth(104); row.detail:SetJustifyH("LEFT")
    if row.detail.SetWordWrap then row.detail:SetWordWrap(false) end
    row.score = T.display(row, SZ.small, C.paper); row.score:SetPoint("RIGHT", -150, 0); row.score:SetJustifyH("RIGHT")
    row.status = T.text(row, SZ.label, C.label); row.status:SetPoint("RIGHT", -2, 0); row.status:SetWidth(144); row.status:SetJustifyH("RIGHT")
    if row.status.SetWordWrap then row.status:SetWordWrap(false) end
    row:SetScript("OnClick", function(self)
      if not self.pickable then return end
      if not UI.lootPick[self.key] then
        if pickedCount() >= ns.Protocol.LOOT_MAX then UI.lootNote = LD.WHY.many_heats; UI:RefreshLootDuel(); return end
        UI.lootPick[self.key] = true
      else
        UI.lootPick[self.key] = nil
      end
      UI.lootNote, UI.lootConfirmAll = nil, nil
      UI:RefreshLootDuel()
    end)
    row:SetScript("OnEnter", function(self)
      local e = self.entry
      if not (e and GameTooltip) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(T.classText(e.class, e.name))
      local bits = {}
      if e.level then bits[#bits + 1] = "Level " .. e.level end
      if e.class then bits[#bits + 1] = className(e.class) end
      if e.faction then bits[#bits + 1] = e.faction end
      if e.subgroup then bits[#bits + 1] = "group " .. e.subgroup end
      if #bits > 0 then GameTooltip:AddLine(table.concat(bits, "  -  "), 1, 1, 1) end
      local a = ADDON[LD.addonStatus(e.name) or ""]
      GameTooltip:AddLine(a and a[1] or "No StackRivals answer yet (it may not be installed)", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Being in the group doesn't make anyone eligible: pick who wants the item and may get it under your group's loot rules.", 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:Hide()
    s.rows[i] = row
  end
  s.empty = T.text(s, SZ.small, C.body); s.empty:SetPoint("TOPLEFT", L, -182); s.empty:SetWidth(cw); s.empty:SetJustifyH("LEFT")
  s.note = T.text(s, SZ.label, C.gold); s.note:SetPoint("BOTTOMLEFT", L, 52); s.note:SetWidth(cw); s.note:SetJustifyH("LEFT")

  -- actions: Invite Selected / Start / New, and Invite Party (5) / Invite All (raid, confirmed)
  s.go = T.button(s, "Invite Selected", 160, 30, "gold", function()
    local d = LD.current
    local okA, why
    if d and d.role == "leader" and d.state == "inviting" then okA, why = LD.start()
    elseif d and d.state == "done" and d.role == "leader" then LD.clear(); UI.lootPick = {}; okA = true
    else
      local names = {}
      for _, e in ipairs(LD.roster()) do if UI.lootPick[e.name:lower()] then names[#names + 1] = e.name end end
      okA, why = LD.create(UI.lootItemId, UI.lootRs, names)
    end
    UI.lootNote, UI.lootConfirmAll = (not okA) and (LD.WHY[why] or tostring(why)) or nil, nil
    UI:RefreshLootDuel()
  end)
  s.go:SetPoint("BOTTOMLEFT", L, 14)
  s.all = T.button(s, "Invite Party", 132, 30, "frame", function()
    local names = everyone()
    local raid = IsInRaid and IsInRaid()
    if #names > ns.Protocol.LOOT_MAX then UI.lootNote = LD.WHY.all_many; UI:RefreshLootDuel(); return end
    -- a raid-wide invite is confirmed with a second click (a party of 5 isn't)
    if raid and not UI.lootConfirmAll then
      UI.lootConfirmAll = GetTime()
      UI.lootNote = "Invite all " .. #names .. " raid members? Click again to confirm. Each still clicks Join or Pass."
      UI:RefreshLootDuel(); return
    end
    UI.lootPick = {}
    for _, n in ipairs(names) do UI.lootPick[n:lower()] = true end
    local okA, why = LD.create(UI.lootItemId, UI.lootRs, names)
    UI.lootNote, UI.lootConfirmAll = (not okA) and (LD.WHY[why] or tostring(why)) or nil, nil
    UI:RefreshLootDuel()
  end)
  s.all:SetPoint("LEFT", s.go, "RIGHT", 6, 0)
  s.cancel = T.button(s, "Cancel", 110, 30, "frame", function() LD.cancel("cancel"); UI:RefreshLootDuel() end)
  s.cancel:SetPoint("LEFT", s.go, "RIGHT", 6, 0)
  s.announce = T.button(s, "Announce", 110, 30, "frame", function() UI:AnnounceLoot() end)
  s.announce:SetPoint("LEFT", s.go, "RIGHT", 6, 0)
  s.announce.tip = "Post the result in party / raid chat (only when you click)."
  local close = T.button(s, "Close", 110, 30, "frame", function() s:Hide(); UI:RefreshPhase() end)
  close:SetPoint("BOTTOMRIGHT", -20, 14)
  s:SetScript("OnShow", function()
    -- which members have StackRivals: one hidden group message, at most every 20 s (no invite)
    if LD.mayLead() and not LD.current then LD.checkAddons() end
    UI:RefreshLootDuel()
  end)
  local acc = 0
  s:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc >= 1 then
      acc = 0
      if UI.lootConfirmAll and GetTime() - UI.lootConfirmAll > 6 then UI.lootConfirmAll, UI.lootNote = nil, nil end
      UI:RefreshLootDuel()
    end
  end)

  self:CreateLootPopup()
  self:CreateLootBoard()
  -- an item the client hadn't loaded yet arrives later: refresh name, quality colour and icon
  local ev = CreateFrame("Frame")
  pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
  pcall(ev.RegisterEvent, ev, "LOOT_OPENED")
  pcall(ev.RegisterEvent, ev, "LOOT_CLOSED")
  pcall(ev.RegisterEvent, ev, "GROUP_ROSTER_UPDATE")
  ev:SetScript("OnEvent", function() UI:RefreshLootDuel(); if UI.RefreshLootCard then UI:RefreshLootCard() end end)
  if ns.Duel and ns.Duel.on then
    -- a StackRivals answer (HI) arrived: show it in the list
    local prev = ns.Duel.listeners and ns.Duel.listeners.players
    ns.Duel.on("players", function(...) if prev then prev(...) end UI:RefreshLootDuel() end)
  end
  LD.on("changed", function(d)
    if d and d.state == "playing" and d.iPlay and s:IsShown() then s:Hide() end
    UI:RefreshLootDuel(); UI:RenderRival()
    if UI.RefreshLootCard then UI:RefreshLootCard() end
  end)
  LD.on("live", function() UI:RenderRival(); UI:RefreshLootDuel() end)
  LD.on("invite", function(d)
    local f = UI.lootPopup
    f.d = d
    f:Show()
    if ns.Sound.enabled and PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
  end)
  LD.on("result", function(d)
    -- everyone (players and watchers) gets the same result: the sheet with the final header,
    -- and one line in your own chat window (shown to you only, nothing is sent)
    if UI.frame and UI.frame:IsShown() then UI:ShowSheet("loot") end
    if ns.App and ns.App.Print and not d.printed then
      d.printed = true
      -- the shared moment of the addon gets a sound: the winner's fanfare on the winner's PC, a short one for
      -- the others (once per Loot Duel; follows the Sound effects setting)
      local mine = d.winner and ns.Comm.same(d.winner, ns.Comm.me())
      ns.Sound.play(mine and "record" or "levelup")
      if mine and UI.frame and UI.frame:IsShown() and UI.over:IsShown() then UI:FxResult("win") end
      local item = itemText(d)
      local line = d.winner and ("Loot Duel for " .. item .. ": " .. short(d.winner) .. " wins (replay-checked). The loot master hands out the item.")
        or (#d.tied > 1 and ("Loot Duel for " .. item .. ": a tie - roll off.")) or (d.unconfirmed and ("Loot Duel for " .. item .. ": UNVERIFIED - " .. short(d.unconfirmed.name) .. "'s run (" .. T.commas(d.unconfirmed.score) .. ") didn't arrive complete, so no winner is confirmed. Run it again or use your normal loot rules."))
        or ("Loot Duel for " .. item .. ": no checked result - use your normal loot rules.")
      ns.App:Print(line)
    end
    local s2 = ns.App and ns.App.session
    if s2 and s2.loot == d and UI.over:IsShown() then
      UI.overBadge:SetText(d.winner and ("WINNER: " .. string.upper(short(d.winner))) or (#d.tied > 1 and "TIE: ROLL OFF" or d.unconfirmed and "UNVERIFIED: NO WINNER" or "NO WINNER"))
    end
    UI:RefreshLootBoard()
  end)
end

function UI:CreateLootPopup()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(340, 196)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  local p = T.panel(f, C.gold, 0.97); p:SetAllPoints()
  f.icon = p:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(30, 30); f.icon:SetPoint("TOPLEFT", 12, -12)
  f.kind = T.label(p, "LOOT DUEL"); f.kind:SetPoint("TOPLEFT", 50, -10); f.kind:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  f.title = T.display(p, SZ.big, C.paper); f.title:SetPoint("TOPLEFT", 50, -24); f.title:SetWidth(280); f.title:SetJustifyH("LEFT")
  f.sub = T.text(p, SZ.label, C.body); f.sub:SetPoint("TOPLEFT", 50, -64); f.sub:SetWidth(280); f.sub:SetJustifyH("LEFT")
  local track = T.tex(p, "ARTWORK", C.line, 1); track:SetPoint("TOPLEFT", 14, -142); track:SetSize(312, 3)
  f.bar = T.tex(p, "OVERLAY", C.gold, 1); f.bar:SetPoint("TOPLEFT", track, "TOPLEFT"); f.bar:SetSize(312, 3)
  local acc = T.button(f, "Join", 150, 30, "gold", function() ns.LootDuel.answer(true); f:Hide(); UI:ShowSheet("loot") end)
  acc:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 12)
  local dec = T.button(f, "Pass", 150, 30, "frame", function() ns.LootDuel.answer(false); f:Hide() end)
  dec:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 12)
  f.acc = acc
  f:Hide()
  f:SetScript("OnUpdate", function(self)
    local d = ns.LootDuel.current
    if not d or d ~= self.d or d.state ~= "inviting" or d.myAnswer then self:Hide(); return end
    local frac = math.max(0, 1 - (GetTime() - d.createdAt) / ns.LootDuel.INVITE_TIME)
    self.bar:SetWidth(math.max(1, 312 * frac))
    if frac <= 0 then self:Hide(); return end
    local secs = math.ceil(ns.LootDuel.INVITE_TIME * frac)
    if self.shownSecs == secs and self.shownFor == d then return end -- the texts change once a second
    self.shownSecs, self.shownFor = secs, d
    local _, _, _, icon = ns.LootDuel.itemInfo(d.itemId)
    self.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.title:SetText(itemText(d))
    local n = #(d.inviteOrder or {})
    self.sub:SetText(short(d.leader) .. "  -  " .. (d.rs == "l120" and "2:00" or "1:00") .. "  -  " .. (n > 0 and (n .. " invited, ") or "") .. "all at once\n"
      .. "Join = you accept the result. The loot master hands out the item.\n"
      .. math.ceil(ns.LootDuel.INVITE_TIME * frac) .. " s to answer. Pass = normal loot rules.")
    if frac <= 0 then self:Hide() end
  end)
  self.lootPopup = f
end

--- Final status of one standing (WINNER / TIE / LOST, or a separate amber status).
local function finalKey(d, x)
  if x.status == "verified" then
    if d.winner and ns.Comm.same(x.name, d.winner) then return "winner" end
    for _, t in ipairs(d.tied or {}) do if ns.Comm.same(t, x.name) then return "tie" end end
    return "lost"
  end
  return ({ unchecked = "unchecked", missing = "noresult", rejected = "failed" })[x.status] or "noresult"
end
UI.lootFinalKey = finalKey

--- The final header: CONGRATULATIONS (one winner), TIE (roll off), or NO WINNER. The same on
--- every PC, shown only once every needed replay is checked (state "done").
function UI:FillLootFinal(d)
  local s = self.lootSheet
  local fin = s.final
  local LD = ns.LootDuel
  local item = itemText(d)
  local n = #(d.participants or {})
  if d.winner then
    local r = d.results[d.winner:lower()] or {}
    setIcon(fin.icon, "winner")
    fin.big:SetText("CONGRATULATIONS!"); fin.big:SetTextColor(C.green[1], C.green[2], C.green[3])
    fin.line:SetText(T.classText(r.class or LD.classOf(d.winner), short(d.winner)) .. " wins the Loot Duel!")
    -- the item (name + icon) is in the item box right above
    fin.detail:SetText("Score " .. T.commas(r.score or 0) .. "  -  #1 of " .. n .. "  -  highest replay-checked score")
    fin.glow:SetVertexColor(0.48, 0.89, 0.63)
  elseif #(d.tied or {}) > 1 then
    local names = {}
    for _, x in ipairs(d.tied) do names[#names + 1] = T.classText(LD.classOf(x), short(x)) end
    local r = d.results[d.tied[1]:lower()] or {}
    setIcon(fin.icon, "tie")
    fin.big:SetText("TIE!"); fin.big:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    if #names <= 3 then fin.line:SetText(table.concat(names, ", ") .. " tie at " .. T.commas(r.score or 0))
    else fin.line:SetText(#names .. " players tie at " .. T.commas(r.score or 0) .. " (listed below)") end
    fin.detail:SetText("Roll off with /roll (the agreed tiebreak). No winner is invented.")
    fin.glow:SetVertexColor(0.95, 0.81, 0.42)
  else
    setIcon(fin.icon, "warn")
    fin.big:SetText("NO WINNER"); fin.big:SetTextColor(AMBER[1], AMBER[2], AMBER[3])
    if d.unconfirmed then
      -- the best checked run is not a confirmed winner: a higher claim couldn't be checked on this PC
      fin.big:SetText("UNVERIFIED")
      fin.line:SetText(T.classText(LD.classOf(d.unconfirmed.name), short(d.unconfirmed.name)) .. "'s run (" .. T.commas(d.unconfirmed.score) .. ") couldn't be checked")
      fin.detail:SetText("Its replay didn't arrive complete. No winner is confirmed: run it again, or use your normal loot rules.")
    else
      fin.line:SetText("No replay-checked result")
      fin.detail:SetText("Use your normal loot rules for " .. item .. ".")
    end
    fin.glow:SetVertexColor(AMBER[1], AMBER[2], AMBER[3])
  end
  -- a short victory effect, once per Loot Duel
  if fin.shownFor ~= d.lid then
    fin.shownFor = d.lid
    fin.pop:Play(); fin.glowAnim:Play()
  end
end

--- One row per player: before the invite the group (pick), then the invitees, then standings.
function UI:RefreshLootDuel()
  local s = self.lootSheet
  if not s or not s:IsShown() then return end
  local LD = ns.LootDuel
  local d = LD.current
  local state = d and d.state or "setup"
  local leader = d and d.role == "leader"
  local mayLead, why = LD.mayLead()
  local raid = IsInRaid and IsInRaid()
  local MAX = ns.Protocol.LOOT_MAX
  -- item
  local itemId = d and d.itemId or self.lootItemId
  local it = s.item
  local editable = (not d or state == "cancelled") and mayLead
  local lootList = editable and LD.lootWindowItems() or {}
  it.fromLoot:SetShown(#lootList > 0)
  it.fromLoot:SetLabel("From loot" .. (#lootList > 1 and (" " .. #lootList) or ""))
  local nameW = (#lootList > 0) and (s.item:GetWidth() - 52 - 92) or (s.item:GetWidth() - 52)
  it.name:SetWidth(nameW); it.hint:SetWidth(nameW)
  if itemId then
    local _, link, _, icon = LD.itemInfo(itemId)
    local txt, name = itemText({ itemId = itemId })
    it.name:SetText(txt)
    it.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    it.hint:SetText(name and ("Item " .. itemId .. (link and "  -  hover for the tooltip" or "")) or "Loading the item from the server...")
  else
    it.name:SetText("No item yet")
    it.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    it.hint:SetText(#lootList > 0 and "Pick it from the loot window, or shift-click / paste below." or "The leader, an assistant or the master looter picks the item.")
  end
  s.input:SetShown(editable); s.setItem:SetShown(editable)
  -- compact: without the item box the rules and the list move up; the result header takes room
  local done = state == "done"
  local top = editable and 0 or 30
  local listTop = done and -164 or (-162 + top)
  s.l060:ClearAllPoints(); s.l060:SetPoint("TOPLEFT", 24, -132 + top)
  s.head:ClearAllPoints(); s.head:SetPoint("TOPLEFT", 24, listTop)
  s.next:ClearAllPoints(); s.next:SetPoint("TOPRIGHT", -26, listTop + 4)
  for i, row in ipairs(s.rows) do row:ClearAllPoints(); row:SetPoint("TOPLEFT", 24, listTop - 16 - (i - 1) * ROW_H) end
  s.empty:ClearAllPoints(); s.empty:SetPoint("TOPLEFT", 24, listTop - 20)
  -- rules / result header
  local rs = d and d.rs or self.lootRs
  setSeg(s.l060, rs == "l060"); setSeg(s.l120, rs == "l120")
  local showRules = not done
  s.l060:SetShown(showRules); s.l120:SetShown(showRules); s.rules:SetShown(showRules)
  if editable then s.l060:Enable(); s.l120:Enable() else s.l060:Disable(); s.l120:Disable() end
  s.banner:Hide()
  s.final:SetShown(done)
  if done then self:FillLootFinal(d) end
  -- rows
  local rows = {}
  local setup = not d or state == "cancelled"
  if setup then
    local picked = pickedCount()
    s.head:SetText("PICK 2-" .. MAX .. " WHO WANT IT  -  " .. picked .. " PICKED")
    for _, e in ipairs(LD.roster()) do
      local key = e.name:lower()
      local a = LD.addonStatus(e.name)
      local det = {}
      if e.level and e.level > 0 then det[#det + 1] = tostring(e.level) end
      if e.class then det[#det + 1] = className(e.class) end
      if raid and e.subgroup then det[#det + 1] = "G" .. e.subgroup end
      local st = (e.online == false) and { "offline", C.line } or ADDON[a or ""] or { "no answer yet", C.label }
      rows[#rows + 1] = { name = e.name, class = e.class, pick = mayLead, picked = UI.lootPick[key] and true or false, key = key, entry = e,
        detail = table.concat(det, " "), status = st[1], statusColor = st[2],
        order = (UI.lootPick[key] and 0 or 2) + ((a == "yes" or a == "you") and 0 or 1) + (e.online == false and 4 or 0) }
    end
    -- picked first, then players whose StackRivals answered, then the rest (offline last)
    table.sort(rows, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.name:lower() < b.name:lower() end)
  elseif state == "inviting" then
    local joined, passed = #LD.accepted(d), 0
    local left = math.max(0, math.ceil(LD.INVITE_TIME - (GetTime() - d.createdAt)))
    for _, n in ipairs(d.inviteOrder) do
      local a = d.answers[n:lower()]
      if a and not a.accept then passed = passed + 1 end
      local st = a and (a.accept and "accepted" or "declined") or (left == 0 and "noanswer" or "invited")
      rows[#rows + 1] = { name = n, class = LD.classOf(n), statusKey = st }
    end
    s.head:SetText(#d.inviteOrder .. " INVITED  -  " .. joined .. " JOINED  -  " .. passed .. " PASSED")
  elseif state == "revealing" then
    local ready = 0
    for _, p in ipairs(d.participants) do
      local r = d.reveals[p.name:lower()] and true
      if r then ready = ready + 1 end
      rows[#rows + 1] = { name = p.name, statusKey = r and "locked" or "locking" }
    end
    s.head:SetText("READY CHECK  -  " .. ready .. " OF " .. #d.participants .. " READY")
  elseif state == "playing" then
    local board = LD.liveBoard(d)
    local checked = 0
    for _, x in ipairs(board) do
      if x.checked then checked = checked + 1 end
      local st = LIVE[x.status] or LIVE.playing
      rows[#rows + 1] = { name = x.name, class = x.class, score = x.score, rank = x.rank, status = st[1], statusColor = st[2], icon = st[3] }
    end
    s.head:SetText("LIVE  -  " .. #d.participants .. " PLAYERS  -  PROVISIONAL" .. (checked > 0 and ("  -  " .. checked .. " CHECKED") or ""))
  elseif done then
    s.head:SetText("FINAL RESULTS  -  " .. ns.Protocol.LOOT_RULESETS[d.rs].name .. "  -  " .. #d.participants .. " PLAYERS")
    local prev, prevRank
    for i, x in ipairs(d.standings) do
      -- equal score and lines share a place (a tie is a tie); only replay-checked runs get a place
      local rank = i
      if prev and prev.status == "verified" and x.score == prev.score and x.lines == prev.lines then rank = prevRank end
      local fk = finalKey(d, x)
      rows[#rows + 1] = { name = x.name, class = x.class, score = (x.status ~= "missing") and x.score or nil, statusKey = fk,
        rank = (x.status == "verified" or x.status == "unchecked") and rank or nil, tint = (fk == "winner" and C.green) or (fk == "tie" and C.gold) or nil }
      prev, prevRank = x, rank
    end
    -- who was invited but passed or never answered: listed last, never a defeat for the others
    local inRace = {}
    for _, p in ipairs(d.participants) do inRace[p.name:lower()] = true end
    for _, n in ipairs(d.inviteOrder or {}) do
      if not inRace[n:lower()] then
        local a = d.answers[n:lower()]
        rows[#rows + 1] = { name = n, class = LD.classOf(n), statusKey = (a and not a.accept) and "passed" or "silent" }
      end
    end
  end
  -- the final header is taller: 9 rows per page there, so the last row never meets the footer
  local per = done and ROWS - 1 or ROWS
  local pages = math.max(1, math.ceil(#rows / per))
  UI.lootPage = math.min(math.max(1, UI.lootPage or 1), pages)
  s.prev:SetShown(pages > 1); s.next:SetShown(pages > 1); s.page:SetShown(pages > 1)
  s.page:SetText(UI.lootPage .. " / " .. pages)
  if UI.lootPage > 1 then s.prev:Enable() else s.prev:Disable() end
  if UI.lootPage < pages then s.next:Enable() else s.next:Disable() end
  -- All / None sit left of the page buttons while picking
  local pickBtns = setup and mayLead and #rows > 0
  s.selAll:SetShown(pickBtns); s.selNone:SetShown(pickBtns)
  if pickBtns then
    s.selNone:ClearAllPoints()
    if pages > 1 then s.selNone:SetPoint("RIGHT", s.page, "LEFT", -8, 0) else s.selNone:SetPoint("TOPRIGHT", -26, listTop + 4) end
    s.selAll:ClearAllPoints(); s.selAll:SetPoint("RIGHT", s.selNone, "LEFT", -4, 0)
  end
  local first = (UI.lootPage - 1) * per
  for i, row in ipairs(s.rows) do
    local r = i <= per and rows[first + i] or nil
    if r then
      row.key, row.pickable, row.entry = r.key, r.pick, r.entry
      row.box:SetShown(r.pick and true or false); row.fill:SetShown(r.pick and r.picked or false)
      row.rank:SetShown(r.rank ~= nil); row.rank:SetText(r.rank and ("#" .. r.rank) or "")
      local st = STATUS[r.statusKey or ""]
      local iconName = r.icon or (st and st[3])
      setIcon(row.icon, (not r.pick) and iconName or nil)
      local x0 = r.pick and 22 or (r.rank and 30 or 2)
      row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", x0, 0)
      local cls = r.class or LD.classOf(r.name)
      row.name:SetText(T.classText(cls, short(r.name)))
      row.name:ClearAllPoints(); row.name:SetPoint("LEFT", x0 + ((not r.pick and iconName) and 17 or 0), 0)
      row.detail:SetText(r.detail or "")
      row.status:SetWidth((r.detail and r.detail ~= "") and 118 or 144) -- the setup list has a level / class column
      row.score:SetText(r.score and T.commas(r.score) or ((r.statusKey == "passed" or r.statusKey == "silent") and "-" or ""))
      row.status:SetText(st and st[1] or (r.status or ""))
      local c = (st and st[2]) or r.statusColor or C.label
      row.status:SetTextColor(c[1], c[2], c[3])
      if r.tint then row.bg:SetColorTexture(r.tint[1], r.tint[2], r.tint[3], 0.10) else row.bg:SetColorTexture(0, 0, 0, 0) end
      row:Show()
    else
      row:Hide()
    end
  end
  s.empty:SetShown(#rows == 0)
  s.empty:SetText(LD.channel() and "Nobody else in your group yet." or "Join a party or raid: Loot Duels are for your group.")
  -- buttons
  s.cancel:SetShown(leader and (state == "inviting" or state == "revealing"))
  s.announce:SetShown(done)
  s.all:SetShown(setup and mayLead and LD.channel() ~= nil)
  if setup then
    local n = pickedCount()
    s.go:SetLabel("Invite Selected (" .. n .. ")"); s.go:SetShown(mayLead)
    if itemId and n >= 2 and n <= MAX then s.go:Enable() else s.go:Disable() end
    local all = #everyone()
    s.all:SetLabel(UI.lootConfirmAll and ("Confirm: " .. all) or ((raid and "Invite All (" or "Invite Party (") .. all .. ")"))
    s.all.tip = raid and ("Invites every online raid member (" .. all .. ", you included). Asks you to confirm. Each still clicks Join or Pass.")
      or ("Invites everyone in your party (" .. all .. ", you included). Each still clicks Join or Pass.")
    if itemId and all >= 2 and all <= MAX then s.all:Enable() else s.all:Disable() end
  elseif leader and state == "inviting" then
    local n = #LD.accepted(d)
    local open = LD.canStart(d)
    s.go:SetLabel(not open and "Invite expired" or n >= 2 and ("Start (" .. n .. ")") or "Start: needs 2"); s.go:Show()
    if n >= 2 and open then s.go:Enable() else s.go:Disable() end
  elseif leader and done then
    s.go:SetLabel("New Loot Duel"); s.go:Show(); s.go:Enable()
  else
    s.go:Hide()
  end
  -- note: what happens / why not
  local note = self.lootNote
  local commOk, commWhy = LD.commState()
  if not note then
    if not commOk and commWhy == "locked" and (state == "revealing" or state == "playing") then
      note = "WoW is holding addon messages right now (boss fight, Mythic+ or PvP match). Your run goes on; live scores and results follow when it lifts, and every timer waits."
    elseif not commOk and (not d or state == "done" or state == "cancelled" or state == "inviting") and (commWhy == "locked" or commWhy == "locked_map" or commWhy == "trial") then
      note = LD.WHY[commWhy]
    elseif done then
      note = "No item is handed out by StackRivals: the loot master does it by hand, if your loot rules still allow it. Peer-checked, not proof against a modified addon."
      if d.agreement == "disputed" then note = "The leader's PC got a different result: check with the group before handing out loot." end
    elseif state == "cancelled" then note = REASON[d.endReason] or "Loot Duel cancelled."
    elseif d and d.leftOut and (state == "revealing" or state == "playing") then note = "You joined, but " .. short(d.leader) .. " left you out of the list. Tell the group before any loot is handed out."
    elseif state == "revealing" then note = "Every player's addon confirms its secret seed share, then all start at once (nobody, the leader included, can know the pieces before)."
    elseif state == "playing" and d.skipped == "duel" then note = "You were in a duel, so you're not racing in this one."
    elseif state == "playing" and not d.iPlay then note = "You're watching. Scores are provisional until the best runs are replayed (out after the time limit + " .. LD.graceFor(d.rs) .. " s)."
    elseif state == "playing" and d.myFinal then note = "Your run is in. The best " .. LD.CONTENDERS .. " runs are replayed on every PC; then everyone sees the same result."
    elseif state == "playing" then note = "Same pieces for everyone. Pauses (combat, chat) count: past " .. LD.PAUSE_BUDGET .. " s in total your run ends where it is."
    elseif leader and state == "inviting" and not LD.canStart(d) then note = LD.WHY.expired
    elseif state == "inviting" and not leader then note = "Waiting for " .. short(d.leader) .. " to start. Players who don't join use the normal loot rules."
    elseif leader and state == "inviting" then
      local joined = #LD.accepted(d)
      note = joined >= 2 and ("Joined " .. joined .. " of " .. #d.inviteOrder .. ". Start when everyone who wants it has joined: all play at once (no answer = not in).")
        or ("Joined " .. joined .. " of " .. #d.inviteOrder .. ": a Loot Duel needs at least 2 players who clicked Join.")
    elseif not mayLead then note = (LD.WHY[why] or "") .. " Anyone can join when invited."
    else note = "Tick who wants the item and may get it under your loot rules (All / None), or Invite " .. (raid and "All" or "Party") .. ". Nobody is entered automatically." end
  end
  s.note:SetText(note)
end

--- Post the result in party / raid chat (only on click).
function UI:AnnounceLoot()
  local d = ns.LootDuel.current
  if not d or d.state ~= "done" then return end
  local ch = ns.LootDuel.channel()
  if not ch then return end
  local name, link = ns.LootDuel.itemInfo(d.itemId)
  local function line(what)
    if d.agreement == "disputed" then
      -- my PC and the leader's PC don't show the same result: never announce mine as the result
      return string.format("[StackRivals] Loot Duel for %s: DISPUTED - the PCs don't agree on the result. Ask the leader, or use normal loot.", what)
    end
    if d.unconfirmed then
      return string.format("[StackRivals] Loot Duel for %s: UNVERIFIED - %s's run (%s) couldn't be checked, no winner confirmed. Run it again or use normal loot.", what, short(d.unconfirmed.name), T.commas(d.unconfirmed.score))
    end
    if d.winner then
      local r = d.results[d.winner:lower()] or {}
      return string.format("[StackRivals] Loot Duel for %s: %s wins (%s) of %d. Checked by replay on my PC.", what, short(d.winner), T.commas(r.score or 0), #d.participants)
    elseif #d.tied > 1 then
      local n = {}
      for _, x in ipairs(d.tied) do n[#n + 1] = short(x) end
      return string.format("[StackRivals] Loot Duel for %s: tie between %s - roll off.", what, table.concat(n, ", "))
    end
    return string.format("[StackRivals] Loot Duel for %s: no checked result - use normal loot.", what)
  end
  local msg = line(link or name or ("item " .. d.itemId))
  -- WoW's chat line limit is 255: never cut a link in half (drop the link, then shorten plain text)
  if #msg > 255 then msg = line(name and name:gsub("|", "") or ("item " .. d.itemId)) end
  if #msg > 255 then msg = T.cut(msg, 252) .. "..." end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if send then pcall(send, msg, ch) end
end

------------------------------------------------------------------------------------------------
-- Live leaderboard beside the window (where match chat sits in a duel): never over the board
------------------------------------------------------------------------------------------------
local BOARD_ROWS, BOARD_ROW = 10, 30
function UI:CreateLootBoard()
  local F = self.frame
  local w = 200
  local p = T.panel(F, C.gold, 0.96)
  p._layoutRoot = true -- sits outside the window: checked as its own screen (tests/layout.lua)
  p:SetSize(w, 44 + BOARD_ROWS * BOARD_ROW + 46)
  p:SetPoint("TOPLEFT", F, "TOPRIGHT", 6, 0)
  p.title = T.label(p, "LOOT DUEL  -  LIVE"); p.title:SetPoint("TOPLEFT", 10, -10); p.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  p.sub = T.text(p, SZ.label, C.label); p.sub:SetPoint("TOPLEFT", 10, -26); p.sub:SetWidth(w - 20); p.sub:SetJustifyH("LEFT")
  if p.sub.SetWordWrap then p.sub:SetWordWrap(false) end
  p.rows = {}
  for i = 1, BOARD_ROWS do
    local r = CreateFrame("Frame", nil, p)
    r:SetSize(w - 12, BOARD_ROW); r:SetPoint("TOPLEFT", 6, -44 - (i - 1) * BOARD_ROW)
    r.me = T.tex(r, "BACKGROUND", C.goldDeep, 0.9); r.me:SetAllPoints()
    r.rank = T.display(r, SZ.small, C.label); r.rank:SetPoint("TOPLEFT", 4, -2); r.rank:SetWidth(28); r.rank:SetJustifyH("LEFT")
    r.name = T.text(r, SZ.small, C.paper); r.name:SetPoint("TOPLEFT", 32, -2); r.name:SetWidth(88); r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.score = T.display(r, SZ.small, C.paper); r.score:SetPoint("TOPRIGHT", -4, -2); r.score:SetWidth(58); r.score:SetJustifyH("RIGHT")
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(11, 11); r.icon:SetPoint("TOPLEFT", 32, -18); r.icon:Hide()
    r.status = T.text(r, SZ.label, C.label); r.status:SetPoint("TOPLEFT", 46, -17); r.status:SetWidth(w - 70); r.status:SetJustifyH("LEFT")
    if r.status.SetWordWrap then r.status:SetWordWrap(false) end
    r:Hide()
    p.rows[i] = r
  end
  p.foot = T.text(p, SZ.label, C.label); p.foot:SetPoint("BOTTOMLEFT", 10, 8); p.foot:SetWidth(w - 20); p.foot:SetJustifyH("LEFT")
  p.foot:SetText("Live = provisional, until the best runs are replayed.")
  -- many players: the mouse wheel scrolls the list (your own row stays in view)
  p.offset = 0
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    p.offset = math.max(0, (p.offset or 0) - delta * 3)
    p.dirtyAt = nil
    UI:RefreshLootBoard(true)
  end)
  p:Hide()
  self.lootBoard = p
  p:SetScript("OnShow", function(f) UI:PlaceSidePanel(f) end)
end

--- Fill the live board (shown while you race in a Loot Duel and the window is open). At most 4
--- times a second (40 players send ~7 scores a second); `force` redraws now (scrolling).
function UI:RefreshLootBoard(force)
  local p = self.lootBoard
  if not p then return end
  local s = ns.App and ns.App.session
  local d = s and s.loot
  local show = d and self.frame and self.frame:IsShown() and not ns.App.inMenu and self.rivalPanel and self.rivalPanel:IsShown()
  p:SetShown(show and true or false)
  if not show then return end
  local t = GetTime()
  if not force and p.drawnAt and t - p.drawnAt < 0.25 then return end
  p.drawnAt = t
  local rows = ns.LootDuel.liveBoard(d)
  local mine
  for _, x in ipairs(rows) do if ns.Comm.same(x.name, ns.Comm.me()) then mine = x end end
  p.sub:SetText((d.rs == "l120" and "2:00" or "1:00") .. "  -  " .. #rows .. " players" .. (mine and ("  -  you #" .. mine.rank) or ""))
  local foot = d.lockedNow and "WoW is holding addon messages (boss fight / M+ / PvP): live scores wait, timers too."
    or "Live = provisional, until the best runs are replayed."
  if p.footText ~= foot then p.footText = foot; p.foot:SetText(foot) end
  -- the window: top rows from the scroll offset; your own row pinned at the bottom if out of view
  local maxOff = math.max(0, #rows - BOARD_ROWS)
  p.offset = math.min(p.offset or 0, maxOff)
  local list = {}
  for i = 1, math.min(BOARD_ROWS, #rows) do list[i] = rows[p.offset + i] end
  if mine and #rows > BOARD_ROWS then
    local inView = false
    for _, x in ipairs(list) do if x == mine then inView = true end end
    if not inView then list[BOARD_ROWS] = mine end
  end
  for i, r in ipairs(p.rows) do
    local x = list[i]
    if x then
      r.rank:SetText("#" .. x.rank)
      r.name:SetText(T.classText(x.class or ns.LootDuel.classOf(x.name), short(x.name)))
      r.score:SetText(T.commas(x.score or 0))
      local st = LIVE[x.status] or LIVE.playing
      r.status:SetText(st[1]); r.status:SetTextColor(st[2][1], st[2][2], st[2][3])
      setIcon(r.icon, st[3])
      r.status:ClearAllPoints(); r.status:SetPoint("TOPLEFT", st[3] and 46 or 32, -17)
      r.me:SetShown(x == mine)
      r:Show()
    else
      r:Hide()
    end
  end
end

--- Your place in the small panel under NEXT while racing (the full list is beside the window).
function UI:RenderLootPanel(s)
  local rp = self.rivalPanel
  local d = s.loot
  local list = ns.LootDuel.liveBoard(d)
  local myRank = 1
  for _, x in ipairs(list) do if ns.Comm.same(x.name, ns.Comm.me()) then myRank = x.rank end end
  rp.name:SetText("LOOT DUEL")
  rp.score:SetText("#" .. myRank .. " of " .. #list)
  rp.score:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  local top = list[1]
  rp.state:SetText(top and ("top " .. T.commas(top.score)) or "")
  local best = top and top.score or 0
  local share = best > 0 and math.min(1, s.state.score / best) or 1
  rp.bar:SetWidth(math.max(1, 88 * share))
  self:RefreshLootBoard()
end
