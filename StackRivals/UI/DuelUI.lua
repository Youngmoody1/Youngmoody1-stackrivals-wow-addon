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
-- Challenge Friends sheet (full window, like Records / How to play): pick a mode, a list (guild,
-- WoW friends, Battle.net friends, group, recent rivals) or type a name, then Challenge.
-- A player is "ready" only after their own StackRivals answered (HI); nobody is asked anything
-- until you press Refresh, and invites are only ever sent by your click.
------------------------------------------------------------------------------------------------
local ROWS = 4
local SOURCE_LABEL = { guild = "Guild", friends = "Friends", bnet = "Battle.net", group = "Group", recent = "Recent" }
local SOURCE_TIP = {
  guild = "Online guild members. Refresh asks the guild once who has StackRivals.",
  friends = "Your WoW friends list (online friends). Refresh asks each of them once.",
  bnet = "Battle.net friends playing this WoW version on your realm (or a connected one). Refresh asks each once.",
  group = "Your party or raid. Refresh asks the group once.",
  recent = "Players you dueled before. Refresh asks each once.",
}
local EMPTY = {
  guild = "You're not in a guild, or nobody else is online.",
  friends = "No WoW friends online.",
  bnet = "No Battle.net friends on WoW right now.",
  group = "You're not in a party or raid.",
  recent = "No duels yet: your rivals will show up here.",
}

local function setSegment(b, on)
  local c = on and C.steelDeep or C.surface2
  b.bgTex:SetColorTexture(c[1], c[2], c[3], 1)
  local e = on and C.steel or C.line
  b.border:SetColorTexture(e[1], e[2], e[3], 1)
end

local function challengeName(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then UI.duelFindNote = "Type a character name (Name or Name-Realm)."; UI:RefreshDuelSheet(); return end
  name = name:sub(1, 1):upper() .. name:sub(2)
  local okC, why = ns.Duel.challenge(name, UI.duelRuleset)
  UI.duelFindNote = okC and ("Challenge sent to " .. name .. ".") or ("Can't challenge: " .. (ns.Duel.WHY_NOT[why] or tostring(why)) .. ".")
  UI:RefreshDuelSheet()
end

function UI:CreateDuelSheet()
  local s = self:Body(40)
  self.duelSheet = s
  local L = 24
  local cw = self.frame:GetWidth() - 2 * L - 2
  local title = T.display(s, SZ.title, C.paper); title:SetPoint("TOPLEFT", L, -14); title:SetText("GUILD DUELS")
  local sub = T.text(s, SZ.small, C.label); sub:SetPoint("TOPLEFT", L, -38)
  s.sub = sub

  -- mode: a three-way segmented choice
  self.duelRuleset = "b120"
  local b120 = T.button(s, "Duel 2:00", 96, 28, "frame", function() UI.duelRuleset = "b120"; UI:RefreshDuelSheet() end)
  b120:SetPoint("TOPLEFT", L, -60)
  b120.tip = "Score race: 2 minutes, 3 s countdown."
  local r180 = T.button(s, "Duel 3:00", 96, 28, "frame", function() UI.duelRuleset = "r180"; UI:RefreshDuelSheet() end)
  r180:SetPoint("LEFT", b120, "RIGHT", 4, 0)
  r180.tip = "Score race, 3 minutes and a 4 s countdown: the same rules as a 1v1 on stackrivals.io."
  local s180 = T.button(s, "Spell Duel", 104, 28, "frame", function() UI.duelRuleset = "s180"; UI:RefreshDuelSheet() end)
  s180:SetPoint("LEFT", r180, "RIGHT", 4, 0)
  s180.tip = "Spell Duel 3:00 with the web's spells and mana: casts land on your rival's board. Both need StackRivals 0.5+."
  s.b120, s.r180, s.s180 = b120, r180, s180

  local refresh = T.button(s, "Refresh", 104, 28, "primary", function() UI:RefreshDuelPresence() end)
  refresh:SetPoint("TOPRIGHT", -L - 2, -60)
  refresh.tip = "Ask the players in this list (once) whether they have StackRivals. Nothing is sent before you press it."
  s.refresh = refresh

  -- where to look: five tabs
  self.duelSource = "guild"
  s.tabs = {}
  local tw = math.floor((cw - 4 * 4) / 5)
  for i, src in ipairs(ns.Social and ns.Social.SOURCES or { "guild" }) do
    local tb = T.button(s, SOURCE_LABEL[src], tw, 24, "frame", function() UI.duelSource = src; UI.duelPage = 1; UI.duelFindNote = nil; UI:RefreshDuelSheet() end)
    tb:SetPoint("TOPLEFT", L + (i - 1) * (tw + 4), -96)
    tb.tip = SOURCE_TIP[src]
    s.tabs[src] = tb
  end
  s.note = T.text(s, SZ.small, C.body); s.note:SetPoint("TOPLEFT", L, -128); s.note:SetWidth(cw - 70); s.note:SetJustifyH("LEFT")
  local prev = T.button(s, "<", 28, 20, "frame", function() UI.duelPage = math.max(1, (UI.duelPage or 1) - 1); UI:RefreshDuelSheet() end)
  local nxt = T.button(s, ">", 28, 20, "frame", function() UI.duelPage = (UI.duelPage or 1) + 1; UI:RefreshDuelSheet() end)
  nxt:SetPoint("TOPRIGHT", -L - 2, -124); prev:SetPoint("RIGHT", nxt, "LEFT", -4, 0)
  s.prev, s.next = prev, nxt

  s.rows = {}
  for i = 1, ROWS do
    local row = T.panel(s)
    row:SetSize(cw, 34)
    row:SetPoint("TOPLEFT", L, -150 - (i - 1) * 38)
    row.dot = T.tex(row, "ARTWORK", C.label, 1); row.dot:SetSize(8, 8); row.dot:SetPoint("LEFT", 12, 0)
    row.name = T.display(row, SZ.big, C.paper); row.name:SetPoint("LEFT", 28, 0); row.name:SetJustifyH("LEFT")
    row.info = T.text(row, SZ.label, C.label); row.info:SetPoint("LEFT", 196, 0); row.info:SetJustifyH("LEFT"); row.info:SetWidth(cw - 196 - 120)
    row.btn = T.button(row, "Challenge", 112, 26, "steel", function(b)
      local okC, why = ns.Duel.challenge(b.target, UI.duelRuleset)
      if not okC then UI.duelFindNote = "Can't challenge: " .. (ns.Duel.WHY_NOT[why] or tostring(why)) .. "." end
      UI:RefreshDuelSheet()
    end)
    row.btn:SetPoint("RIGHT", -4, 0)
    row:Hide()
    s.rows[i] = row
  end
  s.empty = T.text(s, SZ.body, C.body); s.empty:SetPoint("TOPLEFT", L, -156); s.empty:SetWidth(cw); s.empty:SetJustifyH("LEFT")
  s.empty:SetSpacing(4)

  -- challenge by name (any realm you can whisper)
  local nl = T.label(s, "OR BY NAME"); nl:SetPoint("TOPLEFT", L, -312)
  local eb = CreateFrame("EditBox", nil, s)
  eb:SetSize(196, 24); eb:SetPoint("TOPLEFT", L + 84, -306)
  eb:SetAutoFocus(false); eb:SetMaxLetters(48)
  eb:SetFont(T.FONT, SZ.body, ""); eb:SetTextInsets(8, 8, 0, 0)
  local ebg = T.tex(eb, "BACKGROUND", C.ink, 1); ebg:SetAllPoints()
  local ebo = T.tex(eb, "BORDER", C.line, 1); ebo:SetPoint("BOTTOMLEFT"); ebo:SetPoint("BOTTOMRIGHT"); ebo:SetHeight(1)
  eb.hint = T.text(eb, SZ.small, C.label); eb.hint:SetPoint("LEFT", 8, 0); eb.hint:SetText("Name or Name-Realm")
  eb:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
  eb:SetScript("OnEnterPressed", function(self) challengeName(self:GetText()); self:ClearFocus() end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  s.nameBox = eb
  local go = T.button(s, "Challenge", 112, 24, "steel", function() challengeName(eb:GetText()); eb:ClearFocus() end)
  go:SetPoint("LEFT", eb, "RIGHT", 6, 0)
  s.nameGo = go

  -- your record
  local rec = T.label(s, "YOUR DUELS (PLAYED OUT, REPLAY-CHECKED)"); rec:SetPoint("BOTTOMLEFT", L, 74)
  s.won = T.display(s, SZ.title, C.green); s.won:SetPoint("BOTTOMLEFT", L, 48)
  s.lost = T.display(s, SZ.title, C.redLight); s.lost:SetPoint("BOTTOMLEFT", L + 92, 48)
  s.draws = T.display(s, SZ.title, C.paper); s.draws:SetPoint("BOTTOMLEFT", L + 184, 48)
  local trust = T.text(s, SZ.label, C.label); trust:SetPoint("BOTTOMLEFT", L, 22); trust:SetWidth(270); trust:SetJustifyH("LEFT")
  s.trust = trust
  local close = T.button(s, "Close", 130, 32, "frame", function() s:Hide(); UI:RefreshPhase() end)
  close:SetPoint("BOTTOMRIGHT", -20, 16)
  s:SetScript("OnShow", function() if ns.Social and UI.duelSource == "guild" then ns.Social.requestGuild() end UI:RefreshDuelSheet() end)
  if ns.Social then ns.Social.init(function() UI:RefreshDuelSheet() end) end
end

--- Refresh: ask this list's players once whether they have StackRivals (never automatic).
function UI:RefreshDuelPresence()
  local src = self.duelSource or "guild"
  local D = ns.Duel
  local note
  if src == "guild" or src == "group" then
    if src == "guild" and ns.Social then ns.Social.requestGuild() end
    local okFind, why = D.findPlayers()
    note = okFind and ("Asked your " .. (src == "guild" and "guild" or "group") .. "...") or (why == "cooldown" and "Just asked - wait a moment." or (D.WHY_NOT[why] or "Join a guild or group to find players."))
  else
    local names = {}
    for _, e in ipairs(ns.Social and ns.Social.list(src) or {}) do
      if e.reach and e.online ~= false then names[#names + 1] = e.name end
    end
    local n, why = D.pingPresence(names)
    note = why and (D.WHY_NOT[why] or why) or (n > 0 and ("Asked " .. n .. " player" .. (n == 1 and "" or "s") .. "...") or (#names > 0 and "Just asked - wait a moment." or EMPTY[src]))
  end
  self.duelFindNote = note
  self:RefreshDuelSheet()
end

-- one row's status: text, colour of the dot, can it be challenged
local function statusOf(e, minV)
  if e.online == false then return "offline", C.line, false end
  if not e.reach then return e.why or "can't be reached", C.line, false end
  local p = ns.Duel.presence(e.name)
  if not p then return (e.source == "recent" and "no answer yet (maybe offline)" or "no StackRivals answer yet"), C.label, false end
  if not p.compatible then return "other StackRivals version", C.label, false end
  if p.busy then return "in a duel", C.gold, false end
  if minV and not P.versionAtLeast(p.addon, minV) then return "v" .. p.addon .. ", needs " .. minV, C.label, false end
  return "StackRivals v" .. p.addon .. " - ready", C.green, true
end

function UI:RefreshDuelSheet()
  local s = self.duelSheet
  if not s or not s:IsShown() then return end
  setSegment(s.b120, self.duelRuleset == "b120")
  setSegment(s.r180, self.duelRuleset == "r180")
  setSegment(s.s180, self.duelRuleset == "s180")
  local src = self.duelSource or "guild"
  for k, tb in pairs(s.tabs) do setSegment(tb, k == src) end
  s.sub:SetText(self.duelRuleset == "s180" and "Spell Duel: 1v1 with spells and mana. First to top out loses."
    or "1v1 score race: same pieces, higher score wins.")
  local minV = P.RULESET_MIN_VERSION[self.duelRuleset]
  -- the list: from the client's own rosters (+ guild / group players who answered a broadcast)
  local list = ns.Social and ns.Social.list(src) or {}
  if src == "guild" or src == "group" then
    local seen = {}
    for _, e in ipairs(list) do seen[e.name:lower()] = true end
    for name, p in pairs(ns.Duel.players) do
      if not seen[name:lower()] and (src == "guild") then list[#list + 1] = { name = name, online = true, reach = true, source = src } end
    end
  end
  local rows = {}
  for _, e in ipairs(list) do
    if e.online ~= false or src ~= "guild" then -- the guild list shows online members only
      local text, col, can = statusOf(e, minV)
      rows[#rows + 1] = { e = e, text = text, col = col, can = can, rank = can and 0 or (e.online == false and 3 or (ns.Duel.presence(e.name) and 1 or 2)) }
    end
  end
  table.sort(rows, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.e.name < b.e.name end)
  local pages = math.max(1, math.ceil(#rows / ROWS))
  self.duelPage = math.min(math.max(1, self.duelPage or 1), pages)
  local first = (self.duelPage - 1) * ROWS
  local busy = ns.Duel.busy() or UI.inCombat()
  for i, row in ipairs(s.rows) do
    local r = rows[first + i]
    if r then
      row.name:SetText(T.classText(r.e.class, short(r.e.name))) -- WoW's class colour when the list tells the class
      row.info:SetText(r.text)
      row.dot:SetColorTexture(r.col[1], r.col[2], r.col[3], 1)
      row.btn.target = r.e.name
      -- only players whose StackRivals answered get a Challenge button; the rest show why not
      row.btn:SetShown(r.can)
      if r.can and not busy then row.btn:Enable() else row.btn:Disable() end
      row:Show()
    else
      row:Hide()
    end
  end
  s.prev:SetShown(pages > 1); s.next:SetShown(pages > 1)
  if pages > 1 then
    if self.duelPage > 1 then s.prev:Enable() else s.prev:Disable() end
    if self.duelPage < pages then s.next:Enable() else s.next:Disable() end
  end
  local ready = 0
  for _, r in ipairs(rows) do if r.can then ready = ready + 1 end end
  s.note:SetText(not ns.Comm.enabled and "Addon messages are not available in this client."
    or ns.Comm.trial and "Trial/Veteran account: Blizzard blocks addon messages, so duels can't work."
    or self.duelFindNote
    or (#rows > 0 and string.format("%d listed, %d ready. Press Refresh to ask who has StackRivals.", #rows, ready))
    or "")
  s.empty:SetShown(#rows == 0)
  s.empty:SetText(EMPTY[src] .. "\nOr type a name below to challenge anyone on your realm.")
  if busy then s.nameGo:Disable() else s.nameGo:Enable() end
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
  f.kind = T.label(f, "STACKRIVALS DUEL"); f.kind:SetPoint("TOPLEFT", 50, -12); f.kind:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
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
-- A WoW character card: name, faction (colour + Blizzard's faction emblem), race / class / level,
-- realm, played-out duel record. Yours comes from WoW's API; your rival's is self-reported by
-- their addon (PRF) and marked "unverified" - only the character name is checked by WoW.
local FACTION_ICON = { Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance", Horde = "Interface\\TargetingFrame\\UI-PVP-Horde" }
local function playerCard(parent, edge, w)
  local c = T.panel(parent, edge)
  c.sideEdge = edge
  c:SetSize(w, 126)
  c.who = T.label(c, ""); c.who:SetPoint("TOP", 0, -10)
  c.name = T.display(c, SZ.title, C.paper); c.name:SetPoint("TOP", 0, -24)
  c.faction = T.display(c, SZ.small, C.label); c.faction:SetPoint("TOP", 0, -50)
  c.line2 = T.text(c, SZ.label, C.body); c.line2:SetPoint("TOP", 0, -65)
  c.line3 = T.text(c, SZ.label, C.label); c.line3:SetPoint("TOP", 0, -79)
  c.line4 = T.text(c, SZ.label, C.label); c.line4:SetPoint("TOP", 0, -93)
  c.state = T.display(c, SZ.small, C.label); c.state:SetPoint("TOP", 0, -108)
  c.fIcon = c:CreateTexture(nil, "ARTWORK"); c.fIcon:SetSize(24, 24); c.fIcon:SetPoint("TOPLEFT", 6, -6)
  c.fIcon:SetTexCoord(0, 0.625, 0, 0.625)
  c.cIcon = c:CreateTexture(nil, "ARTWORK"); c.cIcon:SetSize(22, 22); c.cIcon:SetPoint("TOPRIGHT", -7, -7)
  c.cIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
  c:EnableMouse(true)
  c:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(self.tip, 1, 1, 1, 1, true); GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return c
end

--- Fill a card from a profile { faction, race, class, level, wins, losses } (nil = Unknown).
local function fillCard(c, name, p, own, waiting)
  local base, realm = name:match("^([^%-]+)%-(.+)$")
  local myRealm = (ns.Comm.me() or ""):match("%-(.+)$")
  c.name:SetText(base or name)
  if waiting then
    c.faction:SetText(waiting == "old" and "older StackRivals: no card" or "waiting for card...")
    c.faction:SetTextColor(C.label[1], C.label[2], C.label[3])
    c.line2:SetText(""); c.line3:SetText(""); c.line4:SetText("")
    c.fIcon:Hide(); c.cIcon:Hide()
    c.tip = nil
    return
  end
  p = p or {}
  -- faction theme: Alliance blue, Horde red; unknown keeps the side's own colour
  local th = T.FACTION_THEME[p.faction or ""]
  if th then c:SetTheme(th.fill, th.edge, th.edge) else c:SetTheme(C.surface1, C.line, c.sideEdge) end
  local fc = th and th.text or C.label
  c.faction:SetText(string.upper(p.faction or "Unknown faction"))
  c.faction:SetTextColor(fc[1], fc[2], fc[3])
  c.line2:SetText(ns.Card.who(p, true)) -- the class name in WoW's class colour
  c.line3:SetText(realm or myRealm or "")
  local games = (p.wins or 0) + (p.losses or 0)
  local rec = p.hidden and "Record: Unknown" or games > 0 and string.format("Duels %d-%d (%d%%)", p.wins, p.losses, math.floor(100 * p.wins / games + 0.5)) or "No duels yet"
  c.line4:SetText(own and rec or (rec .. "  -  unverified"))
  local fi = FACTION_ICON[p.faction or ""]
  c.fIcon:SetShown(fi ~= nil)
  if fi then c.fIcon:SetTexture(fi) end
  local tc = p.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.class]
  if own and SetPortraitTexture then
    -- your own card: your real character portrait (WoW draws it from the "player" unit)
    c.cIcon:SetTexCoord(0, 1, 0, 1)
    pcall(SetPortraitTexture, c.cIcon, "player")
    c.cIcon:Show()
  else
    c.cIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    c.cIcon:SetShown(tc ~= nil)
    if tc then c.cIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
  end
  c.tip = (own and "Your character, from WoW." or "Self-reported by your rival's StackRivals: not verified (only the name is checked by WoW).")
    .. "\nStackRivals rank / level: Unknown (needs a linked stackrivals.io account)."
    .. "\nDuels count played-out, replay-checked duels on that PC."
end

function UI:CreateDuelOverlays()
  local o = self:Body(35, true)
  self.lobby = o
  local w = self.frame:GetWidth()
  o.rules = T.display(o, SZ.small, C.steel); o.rules:SetPoint("TOP", 0, -20)
  local cardW = 176
  o.meCard = playerCard(o, C.red, cardW); o.meCard:SetPoint("TOPRIGHT", o, "TOP", -30, -44)
  o.themCard = playerCard(o, C.steel, cardW); o.themCard:SetPoint("TOPLEFT", o, "TOP", 30, -44)
  o.meCard.who:SetText("YOU")
  o.themCard.who:SetText("RIVAL")
  local vs = T.text(o, 30, C.red, "", nil, "italic"); vs:SetPoint("TOP", 0, -88); vs:SetText("VS")
  o.rival = o.themCard.name
  o.status = T.text(o, SZ.body, C.body); o.status:SetPoint("TOP", 0, -180); o.status:SetWidth(w - 80)
  o.ready = T.button(o, "Ready", 220, 36, "primary", function() ns.Duel.ready() end)
  o.ready:SetPoint("TOP", 0, -214)
  -- Spell Battle: your 4 spells (locked at Ready) and a way to change them
  local sr = CreateFrame("Frame", nil, o)
  sr:SetSize(4 * 32 + 10 + 120, 30); sr:SetPoint("TOP", 0, -204)
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
    local mine = ns.Card and ns.Card.mine() or {}
    fillCard(o.meCard, short(ns.Comm.me()) or "You", ns.Card and ns.Card.sharing() and mine or { wins = mine.wins, losses = mine.losses }, true)
    local pres = ns.Duel.presence(m.rival)
    local old = pres and pres.addon and not P.versionAtLeast(pres.addon, "0.6.1")
    fillCard(o.themCard, short(m.rival) or "?", m.rivalCard, false, (m.state == "lobby" and not m.rivalCard) and (old and "old" or true))
    o.rules:SetText(m.quickplay and ("QUICK DUEL  -  MATCH FOUND  -  " .. string.upper(m.ruleset.name))
      or (string.upper(m.ruleset.name) .. "  -  SAME PIECES FOR BOTH"))
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
    o.ready:ClearAllPoints(); o.ready:SetPoint("TOP", 0, spell and -244 or -214)
    self.menu:Hide(); self.pause:Hide(); self.over:Hide()
  else
    o:Hide()
  end
  local showRival = (inDuel or (s and s.loot and not ns.App.inMenu)) and true or false
  self.rivalPanel:SetShown(showRival)
  self.nextPanel:SetHeight(self.field:GetHeight() - (showRival and 82 or 0))
  self.nextPreviews[5]:SetShown(not showRival)
  self:RenderRival()
  if self.RefreshChat then self:RefreshChat() end
  return o:IsShown()
end

function UI:RenderRival()
  local rp = self.rivalPanel
  if not rp or not rp:IsShown() then return end
  local s = ns.App.session
  if s and s.loot and self.RenderLootPanel then return self:RenderLootPanel(s) end
  local m = s and s.duel
  if not m then return end
  local r = m.rival_
  local my = s.state.score
  local their = r.score or 0
  -- the rival's name in WoW's class colour when their card told us the class
  local rc = m.rivalCard
  rp.name:SetText("VS " .. T.classText(rc and rc.class, string.upper(short(m.rival)):sub(1, 13)))
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
    self.overBadge:SetText(T.classText(m.rivalCard and m.rivalCard.class, short(m.rival)) .. ": " .. T.commas(m.theirScore or 0))
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
  if s and s.challenge and ns.App.lastChallenge then ns.App:StartChallenge(ns.App.lastChallenge); return end
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
    f.title:SetText((m.rematch and "Rematch from " or "Duel from ") .. short(m.rival))
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
