--[[
  StackRivals - Account sheet: link this character to a stackrivals.io account with a one-time
  code, import profile snapshots, see the profile (display only), unlink. Tabs: Account, Profile
  (+ Sync, see UI/SyncUI.lua). No passwords, tokens or e-mail are ever typed here.
]]
local _, ns = ...
local T = ns.T
local C = T.C
local UI = ns.UI
local SZ = T.SIZE

local STATE = {
  not_linked = { "NOT LINKED", C.label },
  pending = { "PENDING", C.gold },
  linked = { "LINKED", C.green },
  not_synced = { "NOT SYNCED", C.redLight },
}
local MODE_NAME = {
  b120 = "Duel 2:00", r180 = "Duel 3:00", s180 = "Spell Duel", classic = "Classic", blitz = "Time Trial",
  daily = "Daily Challenge", spellbot = "Spell Battle",
}
UI.ACCOUNT_MODE_NAME = MODE_NAME

local function when(t)
  if not t then return "never" end
  return date("%Y-%m-%d %H:%M", t)
end
local function ago(t)
  local d = ns.Account.now() - t
  if d < 120 then return "just now" end
  if d < 7200 then return math.floor(d / 60) .. " min ago" end
  if d < 172800 then return math.floor(d / 3600) .. " h ago" end
  return math.floor(d / 86400) .. " days ago"
end
UI.accountAgo = ago
--- Text from the website, shown safely ("|" can't start a WoW escape code).
local function safe(s) return s and (s:gsub("|", "||")) or nil end

local function setSegment(b, on)
  local c = on and C.steelDeep or C.surface2
  b.bgTex:SetColorTexture(c[1], c[2], c[3], 1)
  local e = on and C.steel or C.line
  b.border:SetColorTexture(e[1], e[2], e[3], 1)
end
UI.setSegment = UI.setSegment or setSegment

local function editBox(parent, w, hint, maxLetters)
  local eb = CreateFrame("EditBox", nil, parent)
  eb:SetSize(w, 24)
  eb:SetAutoFocus(false); eb:SetMaxLetters(maxLetters or 64)
  eb:SetFont(T.FONT, SZ.small, ""); eb:SetTextInsets(8, 8, 0, 0)
  local bg = T.tex(eb, "BACKGROUND", C.ink, 1); bg:SetAllPoints()
  local bo = T.tex(eb, "BORDER", C.line, 1); bo:SetPoint("BOTTOMLEFT"); bo:SetPoint("BOTTOMRIGHT"); bo:SetHeight(1)
  eb.hint = T.text(eb, SZ.label, C.label); eb.hint:SetPoint("LEFT", 8, 0); eb.hint:SetText(hint or "")
  eb:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return eb
end
UI.accountEditBox = editBox

--- A read-only box holding text to copy: click selects all (then Ctrl+C); typing can't change it.
local function copyBox(parent, w, maxLetters)
  local eb = editBox(parent, w, "", maxLetters or 4096)
  eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  eb:SetScript("OnTextChanged", function(self)
    if self.locked and not self.setting and self:GetText() ~= self.value then
      self.setting = true; self:SetText(self.value or ""); self:HighlightText(); self.setting = false
    end
    self.hint:SetShown(false)
  end)
  function eb:SetValue(v) self.value = v; self.setting = true; self:SetText(v or ""); self.setting = false; self.locked = true end
  return eb
end
UI.accountCopyBox = copyBox

function UI:CreateAccount()
  local Acc = ns.Account
  local s = self:Body(40)
  self.accountSheet = s
  local L = 24
  local cw = self.frame:GetWidth() - 2 * L - 2
  local title = T.display(s, SZ.title, C.paper); title:SetPoint("TOPLEFT", L, -14); title:SetText("STACKRIVALS ACCOUNT")
  local sub = T.text(s, SZ.small, C.label); sub:SetPoint("TOPLEFT", L, -38)
  sub:SetText("One account for stackrivals.io and WoW. Never type a password here.")
  self.accountTab = "account"
  s.tabs = {}
  local tabs = { { "account", "Account" }, { "profile", "Profile" }, { "sync", "Sync" } }
  for i, t in ipairs(tabs) do
    if t[1] ~= "sync" or self.CreateSync then
      local b = T.button(s, t[2], 100, 24, "frame", function() UI.accountTab = t[1]; UI.accountNote = nil; UI:RefreshAccount() end)
      b:SetPoint("TOPLEFT", L + (i - 1) * 104, -60)
      s.tabs[t[1]] = b
    end
  end

  ------------------------------------------------------------------ Account tab
  local a = CreateFrame("Frame", nil, s)
  a:SetPoint("TOPLEFT", 0, 0); a:SetPoint("BOTTOMRIGHT", 0, 0)
  s.acc = a
  local st = T.panel(a, C.red)
  st:SetSize(cw, 62); st:SetPoint("TOPLEFT", L, -92)
  st.chip = T.display(st, SZ.heading, C.label); st.chip:SetPoint("TOPLEFT", 12, -10)
  st.who = T.text(st, SZ.small, C.body); st.who:SetPoint("TOPRIGHT", -12, -12); st.who:SetJustifyH("RIGHT")
  st.line = T.text(st, SZ.label, C.label); st.line:SetPoint("TOPLEFT", 12, -38); st.line:SetWidth(cw - 24); st.line:SetJustifyH("LEFT")
  a.status = st

  a.steps = T.text(a, SZ.small, C.body); a.steps:SetPoint("TOPLEFT", L, -166); a.steps:SetWidth(cw); a.steps:SetJustifyH("LEFT")
  a.steps:SetSpacing(3)
  -- not linked: type the web code
  a.code = editBox(a, 160, "A7K9-P2XM", 12)
  a.code:SetPoint("TOPLEFT", L, -234)
  local function doLink()
    local req, why = Acc.startLink(a.code:GetText())
    if req then a.code:SetText(""); a.code:ClearFocus(); UI.accountNote = nil
    else UI.accountNote = Acc.ERRORS[why] or why end
    UI:RefreshAccount()
  end
  a.code:SetScript("OnEnterPressed", doLink)
  a.link = T.button(a, "Link", 100, 24, "primary", doLink)
  a.link:SetPoint("LEFT", a.code, "RIGHT", 6, 0)
  -- pending: the request to copy
  a.request = copyBox(a, cw)
  a.request:SetPoint("TOPLEFT", L, -186)
  a.step2 = T.text(a, SZ.small, C.body); a.step2:SetPoint("TOPLEFT", L, -220); a.step2:SetWidth(cw); a.step2:SetJustifyH("LEFT")
  -- pending / linked: paste a snapshot
  a.paste = editBox(a, cw - 106, "Paste the SRP1... snapshot here", ns.AccountCodes.MAX_CODE)
  local function doImport()
    local okI, res = Acc.import(a.paste:GetText())
    if okI then
      a.paste:SetText("")
      UI.accountNote = (res == "linked") and "Linked. Your stackrivals.io profile is on the Profile tab." or "Profile updated."
      UI.accountNoteGood = true
    else
      UI.accountNote = Acc.ERRORS[res] or ("Can't import: " .. tostring(res)); UI.accountNoteGood = false
    end
    a.paste:ClearFocus()
    UI:RefreshAccount()
  end
  a.paste:SetScript("OnEnterPressed", doImport)
  a.import = T.button(a, "Import", 100, 24, "steel", doImport)
  a.import:SetPoint("LEFT", a.paste, "RIGHT", 6, 0)
  a.cancel = T.button(a, "Cancel linking", 130, 26, "frame", function() Acc.cancelLink(); UI.accountNote = nil; UI:RefreshAccount() end)
  a.unlink = T.button(a, "Unlink", 130, 26, "frame", function(b)
    if not b.armed then b.armed = true; b:SetLabel("Click to confirm"); return end
    b.armed = false
    Acc.unlink()
    UI.accountNote = "Unlinked on this PC. Unlink on stackrivals.io too to remove it from your account."
    UI.accountNoteGood = true
    UI:RefreshAccount()
  end)
  a.unlink.tip = "Forgets the link and profile for this character on this PC. Your website account is not changed."
  a.expiry = T.text(a, SZ.label, C.label)
  a.note = T.text(a, SZ.small, C.gold); a.note:SetPoint("TOPLEFT", L, -320); a.note:SetWidth(cw - 150); a.note:SetJustifyH("LEFT")

  ------------------------------------------------------------------ Profile tab
  local p = T.panel(s, C.steel)
  p:SetSize(cw, 268); p:SetPoint("TOPLEFT", L, -92)
  s.prof = p
  p.empty = T.text(p, SZ.body, C.body); p.empty:SetPoint("TOPLEFT", 14, -16); p.empty:SetWidth(cw - 28); p.empty:SetJustifyH("LEFT")
  p.empty:SetSpacing(3)
  p.name = T.display(p, SZ.title, C.paper); p.name:SetPoint("TOPLEFT", 14, -12)
  p.rank = T.display(p, SZ.small, C.gold); p.rank:SetPoint("TOPRIGHT", -14, -16); p.rank:SetJustifyH("RIGHT")
  local function bar(y, label)
    local l = T.text(p, SZ.label, C.label); l:SetPoint("TOPLEFT", 14, y); l:SetText(label)
    local v = T.text(p, SZ.label, C.body); v:SetPoint("TOPRIGHT", -14, y); v:SetJustifyH("RIGHT")
    local track = T.tex(p, "ARTWORK", C.line, 1); track:SetPoint("TOPLEFT", 14, y - 16); track:SetSize(cw - 28, 4)
    local fill = T.tex(p, "OVERLAY", C.red, 1); fill:SetPoint("TOPLEFT", track, "TOPLEFT"); fill:SetSize(1, 4)
    return { l = l, v = v, track = track, fill = fill }
  end
  p.xp = bar(-42, "LEVEL")
  p.season = bar(-70, "SEASON")
  p.stats = T.text(p, SZ.small, C.body); p.stats:SetPoint("TOPLEFT", 14, -98); p.stats:SetWidth(cw - 28); p.stats:SetJustifyH("LEFT")
  p.extra = T.text(p, SZ.label, C.label); p.extra:SetPoint("TOPLEFT", 14, -116); p.extra:SetWidth(cw - 28); p.extra:SetJustifyH("LEFT")
  p.histHead = T.label(p, "RECENT MATCHES (STACKRIVALS.IO)"); p.histHead:SetPoint("TOPLEFT", 14, -138)
  p.hist = {}
  for i = 1, 5 do
    local row = {}
    row.mode = T.text(p, SZ.small, C.body); row.mode:SetPoint("TOPLEFT", 14, -154 - (i - 1) * 16)
    row.res = T.display(p, SZ.small, C.paper); row.res:SetPoint("TOPLEFT", 140, -154 - (i - 1) * 16)
    row.score = T.text(p, SZ.small, C.body); row.score:SetPoint("TOPLEFT", 168, -154 - (i - 1) * 16)
    row.at = T.text(p, SZ.label, C.label); row.at:SetPoint("TOPRIGHT", -14, -155 - (i - 1) * 16); row.at:SetJustifyH("RIGHT")
    p.hist[i] = row
  end
  p.foot = T.text(p, SZ.label, C.label); p.foot:SetPoint("BOTTOMLEFT", 14, 10); p.foot:SetWidth(cw - 28); p.foot:SetJustifyH("LEFT")

  local close = T.button(s, "Close", 130, 32, "frame", function() s:Hide(); UI:RefreshPhase() end)
  close:SetPoint("BOTTOMRIGHT", -20, 16)
  s:SetScript("OnShow", function() UI.accountNote = nil; a.unlink.armed = false; UI:RefreshAccount() end)
  -- the pending countdown (once a second, only while the sheet is open)
  local acc = 0
  s:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc >= 1 then acc = 0; if UI.accountTab == "account" then UI:RefreshAccount() end end
  end)
  if self.CreateSync then self:CreateSync(s) end
end

function UI:RefreshAccount()
  local s = self.accountSheet
  if not s or not s:IsShown() then return end
  local Acc = ns.Account
  local tab = self.accountTab or "account"
  for k, b in pairs(s.tabs) do setSegment(b, k == tab) end
  s.acc:SetShown(tab == "account")
  s.prof:SetShown(tab == "profile")
  if s.sync then s.sync:SetShown(tab == "sync") end
  local state, r = Acc.state()
  if tab == "account" then
    local a = s.acc
    local st = STATE[state]
    a.status.chip:SetText(st[1]); a.status.chip:SetTextColor(st[2][1], st[2][2], st[2][3])
    a.status.who:SetText("This character: " .. (ns.Duel and ns.Duel.short(Acc.me() or "?") or (Acc.me() or "?")))
    local pr = r and r.profile
    if state == "linked" then
      a.status.line:SetText("Account " .. safe(pr.name) .. "  -  last synced " .. when(r.lastSync) .. " (snapshot " .. ago(pr.issued) .. ")")
    elseif state == "not_synced" then
      a.status.line:SetText("Account " .. safe(pr.name) .. "  -  snapshot from " .. when(pr.issued) .. " is out of date. Import a fresh one.")
    elseif state == "pending" then
      a.status.line:SetText("Waiting for confirmation from stackrivals.io. Not linked yet.")
    else
      a.status.line:SetText((r and r.note == "unlinked") and "Unlinked on this PC." or "Last synced: never.")
    end
    local showCode, showReq, showPaste = state == "not_linked", state == "pending", state ~= "not_linked"
    a.code:SetShown(showCode); a.link:SetShown(showCode)
    a.request:SetShown(showReq); a.step2:SetShown(showReq)
    a.paste:SetShown(showPaste); a.import:SetShown(showPaste)
    a.cancel:SetShown(showReq); a.unlink:SetShown(state == "linked" or state == "not_synced")
    a.expiry:SetShown(showReq)
    a.cancel:ClearAllPoints(); a.unlink:ClearAllPoints(); a.paste:ClearAllPoints(); a.expiry:ClearAllPoints()
    if state == "not_linked" then
      a.steps:SetText("1. Log in on stackrivals.io with your e-mail (on the website, never in WoW).\n"
        .. "2. Account > Link WoW character: you get a one-time code.\n3. Type the code here:")
    elseif state == "pending" then
      a.steps:SetText("Copy this link request (click, Ctrl+C), paste it on stackrivals.io:")
      a.request:SetValue(Acc.requestCode())
      a.step2:SetText("Then paste the confirmation snapshot (SRP1...) the website shows you:")
      a.paste:SetPoint("TOPLEFT", 24, -240)
      a.cancel:SetPoint("TOPLEFT", 24, -276)
      a.expiry:SetPoint("LEFT", a.cancel, "RIGHT", 12, 0)
      local left = math.max(0, Acc.PENDING_TTL - (Acc.now() - r.pending.at))
      a.expiry:SetText(string.format("Code %s  -  this request expires in %d:%02d", ns.AccountCodes.prettyWebCode(r.pending.code), math.floor(left / 60), left % 60))
    else
      a.steps:SetText("To sync: stackrivals.io > Account > WoW > Export snapshot.\n"
        .. "Paste it here. It only shows your profile; the website decides.")
      a.paste:SetPoint("TOPLEFT", 24, -212)
      a.unlink:SetPoint("TOPLEFT", 24, -250)
      a.unlink:SetLabel(a.unlink.armed and "Click to confirm" or "Unlink")
    end
    a.note:SetText(self.accountNote or ((r and r.note == "pending_expired") and Acc.ERRORS.pending_expired) or "")
    local nc = (self.accountNoteGood and self.accountNote) and C.green or C.gold
    a.note:SetTextColor(nc[1], nc[2], nc[3])
  elseif tab == "profile" then
    self:RefreshProfile(s.prof, state, r)
  elseif tab == "sync" and self.RefreshSync then
    self:RefreshSync()
  end
end

function UI:RefreshProfile(p, state, r)
  local pr = r and r.profile
  local has = pr ~= nil
  p.empty:SetShown(not has)
  for _, k in ipairs({ "name", "rank", "stats", "extra", "histHead", "foot" }) do p[k]:SetShown(has) end
  for _, b in ipairs({ p.xp, p.season }) do for _, x in pairs(b) do x:SetShown(has) end end
  for _, row in ipairs(p.hist) do for _, x in pairs(row) do x:SetShown(has) end end
  if not has then
    p.empty:SetText(state == "pending" and "Linking is not finished: import the confirmation snapshot from stackrivals.io on the Account tab."
      or "No profile yet. Link your stackrivals.io account on the Account tab: your name, rank, level, XP, season and match history will show here.")
    return
  end
  p.name:SetText(safe(pr.name))
  p.rank:SetText(pr.rank and string.upper(safe(pr.rank)) or "UNRANKED")
  p.xp.v:SetText("Level " .. pr.level .. "  -  " .. (pr.xpNext > 0 and (T.commas(pr.xp) .. " / " .. T.commas(pr.xpNext) .. " XP") or (T.commas(pr.xp) .. " XP")))
  local w = p.xp.track:GetWidth()
  p.xp.fill:SetWidth(math.max(1, pr.xpNext > 0 and w * math.min(1, pr.xp / pr.xpNext) or 1))
  p.season.v:SetText((pr.season and safe(pr.season) or "No season") .. "  -  " .. pr.seasonPct .. "%")
  p.season.fill:SetWidth(math.max(1, w * pr.seasonPct / 100))
  local games = pr.wins + pr.losses + pr.draws
  p.stats:SetText(string.format("Wins %s  -  Losses %s  -  Draws %s%s", T.commas(pr.wins), T.commas(pr.losses), T.commas(pr.draws),
    games > 0 and string.format("  -  %d%% won", math.floor(100 * pr.wins / games + 0.5)) or ""))
  p.extra:SetText("Achievements " .. (pr.achUnlocked and (pr.achUnlocked .. " / " .. pr.achTotal) or "-")
    .. "  -  Cosmetics " .. (pr.cosOwned and (pr.cosOwned .. " owned" .. (pr.cosEquipped and (", wearing " .. safe(pr.cosEquipped)) or "")) or "-"))
  for i, row in ipairs(p.hist) do
    local h = pr.history[i]
    if h then
      row.mode:SetText(MODE_NAME[h.mode] or string.upper(h.mode))
      row.res:SetText(string.upper(h.res))
      local c = (h.res == "w") and C.green or (h.res == "l") and C.redLight or C.paper
      row.res:SetTextColor(c[1], c[2], c[3])
      row.score:SetText(T.commas(h.my) .. " - " .. T.commas(h.their))
      row.at:SetText(date("%d %b", h.at))
    else
      for _, x in pairs(row) do x:SetShown(false) end
    end
  end
  if #pr.history == 0 then p.hist[1].mode:SetShown(true); p.hist[1].mode:SetText("No matches yet.") end
  p.foot:SetText("From stackrivals.io, snapshot " .. when(pr.issued) .. (state == "not_synced" and " (out of date)" or "")
    .. ". Display only: the website is the authority." .. (pr.signed and " Signature not checked by this version." or ""))
end
