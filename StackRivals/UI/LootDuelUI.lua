--[[
  StackRivals - Loot Duel screens: the sheet (item, time, players, invite / start, results), the
  invite popup, and the live leaderboard in the rival panel. The loot master hands out the item
  in WoW; nothing here touches loot.
]]
local _, ns = ...
local T = ns.T
local C = T.C
local UI = ns.UI
local SZ = T.SIZE

local ROWS = 8
local STATUS = {
  invited = { "invited...", C.label }, accepted = { "accepted", C.green }, declined = { "declined", C.redLight },
  noanswer = { "no answer: no StackRivals? /roll instead", C.label }, version = { "other StackRivals version", C.label },
  verified = { "replay-checked", C.green }, rejected = { "replay failed: out", C.redLight }, missing = { "no result: out", C.redLight },
  pending = { "checking...", C.gold }, playing = { "playing", C.steel }, watching = { "", C.label },
  locking = { "locking in...", C.gold }, locked = { "ready", C.green },
}
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
local function itemText(d)
  local name, _, q = ns.LootDuel.itemInfo(d.itemId)
  local r, g, b = T.qualityColor(q or 1)
  local hex = r and string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) or "ffffffff"
  return "|c" .. hex .. (name and (name:gsub("|", "||")) or ("item " .. d.itemId)) .. "|r", name
end
UI.lootItemText = itemText

local function setSeg(b, on)
  local c = on and C.goldDeep or C.surface2
  b.bgTex:SetColorTexture(c[1], c[2], c[3], 1)
  local e = on and C.gold or C.line
  b.border:SetColorTexture(e[1], e[2], e[3], 1)
end

function UI:CreateLootDuel()
  local LD = ns.LootDuel
  local s = self:Body(40)
  self.lootSheet = s
  local L = 24
  local cw = self.frame:GetWidth() - 2 * L - 2
  local title = T.text(s, SZ.title, C.gold, "", nil, "italic"); title:SetPoint("TOPLEFT", L, -14); title:SetText("LOOT DUEL")
  s.sub = T.text(s, SZ.small, C.label); s.sub:SetPoint("TOPLEFT", L, -38)
  s.sub:SetText("Settle loot with a race instead of /roll. The loot master hands it out.")

  -- the item
  local it = T.panel(s, C.gold)
  it:SetSize(cw, 46); it:SetPoint("TOPLEFT", L, -58)
  it.icon = it:CreateTexture(nil, "ARTWORK"); it.icon:SetSize(34, 34); it.icon:SetPoint("LEFT", 6, 0)
  it.name = T.display(it, SZ.heading, C.paper); it.name:SetPoint("TOPLEFT", 48, -8); it.name:SetWidth(cw - 56); it.name:SetJustifyH("LEFT")
  it.hint = T.text(it, SZ.label, C.label); it.hint:SetPoint("TOPLEFT", 48, -28); it.hint:SetWidth(cw - 56); it.hint:SetJustifyH("LEFT")
  it:EnableMouse(true)
  it:SetScript("OnEnter", function(self)
    local d = LD.current
    local link = d and select(2, LD.itemInfo(d.itemId))
    if link and GameTooltip.SetHyperlink then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetHyperlink(link); GameTooltip:Show() end
  end)
  it:SetScript("OnLeave", function() GameTooltip:Hide() end)
  s.item = it
  -- item input (leader, before inviting): shift-click an item while the box has focus, or paste
  s.input = UI.accountEditBox(s, cw - 106, "Shift-click an item, or paste a link / item ID", 300)
  s.input:SetPoint("TOPLEFT", L, -110)
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
  s.l060:SetPoint("TOPLEFT", L, -142)
  s.l060.tip = "1 minute: quick enough between pulls."
  s.l120 = T.button(s, "2:00", 60, 24, "frame", function() UI.lootRs = "l120"; UI:RefreshLootDuel() end)
  s.l120:SetPoint("LEFT", s.l060, "RIGHT", 4, 0)
  s.l120.tip = "2 minutes: a bit more skill, a bit more waiting."
  s.rules = T.text(s, SZ.label, C.body); s.rules:SetPoint("LEFT", s.l120, "RIGHT", 10, 0); s.rules:SetWidth(cw - 140); s.rules:SetJustifyH("LEFT")
  s.rules:SetText("Same pieces, no spells. Highest score wins; tie: lines, then /roll.")
  s.banner = T.display(s, SZ.title, C.gold); s.banner:SetPoint("TOPLEFT", L, -140); s.banner:SetWidth(cw); s.banner:SetJustifyH("LEFT")

  -- players
  s.head = T.label(s, "PLAYERS"); s.head:SetPoint("TOPLEFT", L, -174)
  s.rows = {}
  UI.lootPick = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, s)
    row:SetSize(cw, 19); row:SetPoint("TOPLEFT", L, -190 - (i - 1) * 19)
    row.box = T.tex(row, "BORDER", C.line, 1); row.box:SetSize(12, 12); row.box:SetPoint("LEFT", 2, 0)
    row.fill = T.tex(row, "OVERLAY", C.gold, 1); row.fill:SetSize(8, 8); row.fill:SetPoint("CENTER", row.box, "CENTER")
    row.rank = T.display(row, SZ.small, C.label); row.rank:SetPoint("LEFT", 2, 0)
    row.name = T.text(row, SZ.small, C.paper); row.name:SetPoint("LEFT", 22, 0); row.name:SetJustifyH("LEFT")
    row.score = T.display(row, SZ.small, C.paper); row.score:SetPoint("RIGHT", -150, 0); row.score:SetJustifyH("RIGHT")
    row.status = T.text(row, SZ.label, C.label); row.status:SetPoint("RIGHT", -2, 0); row.status:SetWidth(144); row.status:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(self)
      if not self.pickable then return end
      UI.lootPick[self.key] = not UI.lootPick[self.key] or nil
      UI:RefreshLootDuel()
    end)
    row:Hide()
    s.rows[i] = row
  end
  s.empty = T.text(s, SZ.small, C.body); s.empty:SetPoint("TOPLEFT", L, -194); s.empty:SetWidth(cw); s.empty:SetJustifyH("LEFT")
  s.note = T.text(s, SZ.label, C.gold); s.note:SetPoint("BOTTOMLEFT", L, 54); s.note:SetWidth(cw); s.note:SetJustifyH("LEFT")

  -- actions
  s.go = T.button(s, "Invite", 140, 30, "gold", function()
    local d = LD.current
    local okA, why
    if d and d.role == "leader" and d.state == "inviting" then okA, why = LD.start()
    elseif d and d.state == "done" and d.role == "leader" then LD.clear(); UI.lootPick = {}; okA = true
    else
      local names = {}
      for _, e in ipairs(LD.roster()) do if UI.lootPick[e.name:lower()] then names[#names + 1] = e.name end end
      okA, why = LD.create(UI.lootItemId, UI.lootRs, names)
    end
    UI.lootNote = (not okA) and (LD.WHY[why] or tostring(why)) or nil
    UI:RefreshLootDuel()
  end)
  s.go:SetPoint("BOTTOMLEFT", L, 16)
  s.cancel = T.button(s, "Cancel", 110, 30, "frame", function() LD.cancel("cancel"); UI:RefreshLootDuel() end)
  s.cancel:SetPoint("LEFT", s.go, "RIGHT", 8, 0)
  s.announce = T.button(s, "Announce", 110, 30, "frame", function() UI:AnnounceLoot() end)
  s.announce:SetPoint("LEFT", s.go, "RIGHT", 8, 0)
  s.announce.tip = "Post the result in party / raid chat (only when you click)."
  local close = T.button(s, "Close", 110, 30, "frame", function() s:Hide(); UI:RefreshPhase() end)
  close:SetPoint("BOTTOMRIGHT", -20, 16)
  s:SetScript("OnShow", function() UI:RefreshLootDuel() end)
  local acc = 0
  s:SetScript("OnUpdate", function(_, e) acc = acc + e; if acc >= 1 then acc = 0; UI:RefreshLootDuel() end end)

  self:CreateLootPopup()
  LD.on("changed", function(d)
    if d and d.state == "playing" and d.iPlay and s:IsShown() then s:Hide() end
    UI:RefreshLootDuel(); UI:RenderRival()
  end)
  LD.on("live", function() UI:RenderRival(); UI:RefreshLootDuel() end)
  LD.on("invite", function(d)
    local f = UI.lootPopup
    f.d = d
    f:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
  end)
  LD.on("result", function(d)
    -- the standings: open the sheet on the results (the over screen stays underneath)
    if UI.frame and UI.frame:IsShown() then UI:ShowSheet("loot") end
    local s2 = ns.App and ns.App.session
    if s2 and s2.loot == d and UI.over:IsShown() then
      UI.overBadge:SetText(d.winner and ("WINNER: " .. string.upper(short(d.winner))) or (#d.tied > 1 and "TIE: ROLL OFF" or "NO WINNER"))
    end
  end)
end

function UI:CreateLootPopup()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(340, 152)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  local p = T.panel(f, C.gold, 0.97); p:SetAllPoints()
  f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(30, 30); f.icon:SetPoint("TOPLEFT", 12, -12)
  f.kind = T.label(f, "LOOT DUEL"); f.kind:SetPoint("TOPLEFT", 50, -10); f.kind:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  f.title = T.display(f, SZ.big, C.paper); f.title:SetPoint("TOPLEFT", 50, -24); f.title:SetWidth(280); f.title:SetJustifyH("LEFT")
  f.sub = T.text(f, SZ.label, C.body); f.sub:SetPoint("TOPLEFT", 50, -64); f.sub:SetWidth(280); f.sub:SetJustifyH("LEFT")
  local track = T.tex(f, "ARTWORK", C.line, 1); track:SetPoint("TOPLEFT", 14, -100); track:SetSize(312, 3)
  f.bar = T.tex(f, "OVERLAY", C.gold, 1); f.bar:SetPoint("TOPLEFT", track, "TOPLEFT"); f.bar:SetSize(312, 3)
  local acc = T.button(f, "Join", 150, 30, "gold", function() ns.LootDuel.answer(true); f:Hide(); UI:ShowSheet("loot") end)
  acc:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 12)
  local dec = T.button(f, "Pass", 150, 30, "frame", function() ns.LootDuel.answer(false); f:Hide() end)
  dec:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 12)
  f.acc = acc
  f:Hide()
  f:SetScript("OnUpdate", function(self)
    local d = ns.LootDuel.current
    if not d or d ~= self.d or d.state ~= "inviting" or d.myAnswer then self:Hide(); return end
    local _, _, _, icon = ns.LootDuel.itemInfo(d.itemId)
    self.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.title:SetText(itemText(d))
    local frac = math.max(0, 1 - (GetTime() - d.createdAt) / ns.LootDuel.INVITE_TIME)
    self.bar:SetWidth(math.max(1, 312 * frac))
    self.sub:SetText(short(d.leader) .. "  -  " .. ns.Protocol.LOOT_RULESETS[d.rs].name .. "  -  same pieces, no spells\nanswer within " .. math.ceil(ns.LootDuel.INVITE_TIME * frac) .. " s. Pass = not in (roll instead).")
    if frac <= 0 then self:Hide() end
  end)
  self.lootPopup = f
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
  -- item
  local itemId = d and d.itemId or self.lootItemId
  local it = s.item
  if itemId then
    local _, link, _, icon = LD.itemInfo(itemId)
    local txt, name = itemText({ itemId = itemId })
    it.name:SetText(txt)
    it.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    it.hint:SetText(name and ("Item " .. itemId .. (link and "  -  hover for the tooltip" or "")) or "Loading the item from the server...")
  else
    it.name:SetText("No item yet")
    it.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    it.hint:SetText("The raid leader, an assistant or the master looter picks the item.")
  end
  local editable = (not d or state == "cancelled") and mayLead
  s.input:SetShown(editable); s.setItem:SetShown(editable)
  -- rules / banner
  local rs = d and d.rs or self.lootRs
  setSeg(s.l060, rs == "l060"); setSeg(s.l120, rs == "l120")
  local showRules = state ~= "done"
  s.l060:SetShown(showRules); s.l120:SetShown(showRules); s.rules:SetShown(showRules)
  if editable then s.l060:Enable(); s.l120:Enable() else s.l060:Disable(); s.l120:Disable() end
  s.banner:SetShown(state == "done")
  if state == "done" then
    if d.winner then
      local r, g, b = T.qualityColor(select(3, LD.itemInfo(d.itemId)) or 4)
      s.banner:SetText("WINNER: " .. T.classText((d.results[d.winner:lower()] or {}).class, short(d.winner)))
      s.banner:SetTextColor(r or 1, g or 1, b or 1)
    elseif #d.tied > 1 then
      local n = {}
      for _, x in ipairs(d.tied) do n[#n + 1] = short(x) end
      s.banner:SetText("TIE: " .. table.concat(n, ", ") .. "  -  /roll off")
      s.banner:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    else
      s.banner:SetText("NO WINNER  -  use /roll")
      s.banner:SetTextColor(C.label[1], C.label[2], C.label[3])
    end
  end
  -- rows
  local rows = {}
  if not d or state == "cancelled" then
    s.head:SetText("PICK 2-8 PLAYERS (CLICK TO SELECT)")
    for _, e in ipairs(LD.roster()) do
      local key = e.name:lower()
      local p = ns.Duel and ns.Duel.presence(e.name)
      rows[#rows + 1] = { name = e.name, class = e.class, pick = mayLead, picked = UI.lootPick[key] and true or false, key = key,
        status = (p and "has StackRivals") or (ns.Comm and ns.Comm.same(e.name, ns.Comm.me()) and "you") or (e.online == false and "offline" or "") }
    end
  elseif state == "inviting" then
    s.head:SetText("INVITED  -  " .. #LD.accepted(d) .. " JOINED")
    local left = math.max(0, math.ceil(LD.INVITE_TIME - (GetTime() - d.createdAt)))
    for _, n in ipairs(d.inviteOrder) do
      local a = d.answers[n:lower()]
      local st = a and (a.accept and "accepted" or "declined") or (left == 0 and "noanswer" or "invited")
      rows[#rows + 1] = { name = n, class = LD.classOf(n), statusKey = st }
    end
  elseif state == "revealing" then
    s.head:SetText("LOCKING IN THE PIECES  -  " .. #d.participants .. " PLAYERS")
    for _, p in ipairs(d.participants) do
      rows[#rows + 1] = { name = p.name, statusKey = d.reveals[p.name:lower()] and "locked" or "locking" }
    end
  elseif state == "playing" then
    s.head:SetText("LIVE  -  SAME PIECES FOR " .. #d.participants .. " PLAYERS")
    local list = {}
    for _, p in ipairs(d.participants) do
      local r = d.results[p.name:lower()]
      local lv = d.live[p.name:lower()]
      list[#list + 1] = { name = p.name, score = (r and r.score) or (lv and lv.score) or 0, statusKey = r and r.status or "playing" }
    end
    table.sort(list, function(a, b) return a.score > b.score end)
    for i, x in ipairs(list) do x.rank = i; rows[#rows + 1] = x end
  elseif state == "done" then
    s.head:SetText("RESULT  -  " .. ns.Protocol.LOOT_RULESETS[d.rs].name)
    for i, x in ipairs(d.standings) do
      rows[#rows + 1] = { name = x.name, class = x.class, score = x.score, statusKey = x.status, rank = (x.status == "verified") and i or nil }
    end
  end
  for i, row in ipairs(s.rows) do
    local r = rows[i]
    if r then
      row.key, row.pickable = r.key, r.pick
      row.box:SetShown(r.pick and true or false); row.fill:SetShown(r.pick and r.picked or false)
      row.rank:SetShown(r.rank ~= nil); row.rank:SetText(r.rank and ("#" .. r.rank) or "")
      local cls = r.class or LD.classOf(r.name)
      row.name:SetText(T.classText(cls, short(r.name)))
      row.name:ClearAllPoints(); row.name:SetPoint("LEFT", (r.pick or r.rank) and 22 or 2, 0)
      row.score:SetText(r.score and T.commas(r.score) or "")
      local st = STATUS[r.statusKey or ""]
      row.status:SetText(st and st[1] or (r.status or ""))
      local c = st and st[2] or C.label
      row.status:SetTextColor(c[1], c[2], c[3])
      row:Show()
    else
      row:Hide()
    end
  end
  s.empty:SetShown(#rows == 0)
  s.empty:SetText(LD.channel() and "Nobody else in your group yet." or "Join a party or raid: Loot Duels are for your group.")
  -- buttons
  s.cancel:SetShown(leader and (state == "inviting" or state == "revealing"))
  s.announce:SetShown(state == "done")
  if not d or state == "cancelled" then
    local n = 0
    for _ in pairs(UI.lootPick) do n = n + 1 end
    s.go:SetLabel("Invite " .. n); s.go:SetShown(mayLead)
    if itemId and n >= 2 and n <= ns.Protocol.LOOT_MAX then s.go:Enable() else s.go:Disable() end
  elseif leader and state == "inviting" then
    local n = #LD.accepted(d)
    local open = LD.canStart(d)
    s.go:SetLabel(open and ("Start (" .. n .. ")") or "Invite expired"); s.go:Show()
    if n >= 2 and open then s.go:Enable() else s.go:Disable() end
  elseif leader and state == "done" then
    s.go:SetLabel("New Loot Duel"); s.go:Show(); s.go:Enable()
  else
    s.go:Hide()
  end
  -- note: what happens / why not
  local note = self.lootNote
  if not note then
    if state == "done" then
      note = "Every PC replayed every run (peer check, not proof against a modified addon). The loot master hands out the item in WoW."
      if d.agreement == "disputed" then note = "The leader's PC got a different result: check with the group before handing out loot. " .. note end
    elseif state == "cancelled" then note = REASON[d.endReason] or "Loot Duel cancelled."
    elseif d and d.leftOut and (state == "revealing" or state == "playing") then note = "You joined, but " .. short(d.leader) .. " left you out of the list. Tell the group before any loot is handed out."
    elseif state == "revealing" then note = "Every player confirms their secret seed share: then the race starts (nobody, the leader included, can know the pieces before)."
    elseif state == "playing" and d.skipped == "duel" then note = "You were in a duel, so you're not racing in this one."
    elseif state == "playing" and not d.iPlay then note = "You're watching. Results arrive as players finish (out after the time limit + " .. LD.graceFor(d.rs) .. " s)."
    elseif state == "playing" then note = "Same pieces for everyone. Pauses (combat, chat) count: past " .. LD.PAUSE_BUDGET .. " s in total your run ends where it is."
    elseif leader and state == "inviting" and not LD.canStart(d) then note = LD.WHY.expired
    elseif state == "inviting" and not leader then note = "Waiting for " .. short(d.leader) .. " to start. Players who don't join can /roll instead."
    elseif not mayLead then note = LD.WHY[why] or ""
    else note = "Players who join must click Join. Nobody is entered automatically; no loot is handed out by the addon." end
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
    if d.winner then
      local r = d.results[d.winner:lower()] or {}
      return string.format("[StackRivals] Loot Duel for %s: %s wins (%s). Every PC replayed every run.", what, short(d.winner), T.commas(r.score or 0))
    elseif #d.tied > 1 then
      local n = {}
      for _, x in ipairs(d.tied) do n[#n + 1] = short(x) end
      return string.format("[StackRivals] Loot Duel for %s: tie between %s - roll off.", what, table.concat(n, ", "))
    end
    return string.format("[StackRivals] Loot Duel for %s: no checked result - /roll instead.", what)
  end
  local msg = line(link or name or ("item " .. d.itemId))
  -- WoW's chat line limit is 255: never cut a link in half (drop the link, then shorten plain text)
  if #msg > 255 then msg = line(name and name:gsub("|", "") or ("item " .. d.itemId)) end
  if #msg > 255 then msg = msg:sub(1, 252) .. "..." end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if send then pcall(send, msg, ch) end
end

--- Live leaderboard in the rival panel while racing.
function UI:RenderLootPanel(s)
  local rp = self.rivalPanel
  local d = s.loot
  local list = {}
  for _, p in ipairs(d.participants or {}) do
    local k = p.name:lower()
    local sc = (k == (ns.Comm.me() or ""):lower()) and s.state.score or (d.live[k] and d.live[k].score) or 0
    list[#list + 1] = { name = p.name, score = sc }
  end
  table.sort(list, function(a, b) return a.score > b.score end)
  local myRank = 1
  for i, x in ipairs(list) do if ns.Comm.same(x.name, ns.Comm.me()) then myRank = i end end
  rp.name:SetText("LOOT DUEL")
  rp.score:SetText("#" .. myRank .. " of " .. #list)
  rp.score:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  local top = list[1]
  rp.state:SetText(top and ("top " .. T.commas(top.score)) or "")
  local best = top and top.score or 0
  local share = best > 0 and math.min(1, s.state.score / best) or 1
  rp.bar:SetWidth(math.max(1, 88 * share))
end
