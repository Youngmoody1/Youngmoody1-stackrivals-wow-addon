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

--- What the Account tab says. A pasted snapshot links this character on this PC, but without a
--- signature it proves nothing about who owns the website account: "LINKED - UNVERIFIED", never a
--- plain green LINKED. VERIFIED (green) only once a signature scheme exists and the check passed.
local STATE = {
  not_linked = { "NOT LINKED", C.label },
  pending = { "PENDING CONFIRMATION", C.gold },
  linked = { "LINKED - UNVERIFIED", C.gold },
  verified = { "VERIFIED", C.green },
  not_synced = { "OUT OF DATE", C.redLight },
}
UI.ACCOUNT_STATE = STATE
--- The display state: Account.state() plus the profile's verification.
function UI.accountDisplayState()
  local st, r = ns.Account.state()
  if st == "linked" then
    local v = ns.Account.profileView()
    if v and v.verified then return "verified", r end
  end
  return st, r
end
local MODE_NAME = {
  b120 = "Duel 2:00", r180 = "Duel 3:00", s180 = "Spell Duel", classic = "Classic", blitz = "Time Trial",
  daily = "Daily Challenge", spellbot = "Spell Battle",
}
UI.ACCOUNT_MODE_NAME = MODE_NAME

--- One date format everywhere on the account screens: "26 Oct 2026, 08:36" (the PC's local time).
local function when(t)
  if not t then return "never" end
  return date("%d %b %Y, %H:%M", t)
end
--- Days since 1970-01-01 of the local calendar date of t (no time() needed; exact across months).
local function dayNumber(t)
  local d = date("*t", t)
  local y, m = d.year, d.month
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d.day - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end
UI.accountDayNumber = dayNumber
--- "just now" / "5 min ago" / "3 h ago" (same day) / "yesterday" / "12 days ago" (calendar days,
--- so a snapshot from 26 Oct read on 7 Nov is "12 days ago" whatever the hour).
local function ago(t)
  local now = ns.Account.now()
  local d = now - t
  if d < 120 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. " min ago" end
  local days = dayNumber(now) - dayNumber(t)
  if days <= 0 then return math.floor(d / 3600) .. " h ago" end
  if days == 1 then return "yesterday" end
  return days .. " days ago"
end
UI.accountAgo = ago
--- Text from the website, shown safely ("|" can't start a WoW escape code).
local function safe(s) return s and (s:gsub("|", "||")) or nil end

local function setSegment(b, on)
  b.onReEnable = function(x) setSegment(x, on) end -- keep the selection after hover / re-enable
  if b.greyed then -- disabled: grey, but the picked one keeps its border
    local e = on and C.steel or C.line
    b.border:SetColorTexture(e[1], e[2], e[3], 1)
    return
  end
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
  function eb:SetValue(v)
    if v ~= self.value then self.copied = false end
    self.value = v; self.locked = true
    -- only when the text really changes: SetText drops the selection, and the Account tab refreshes every
    -- second (the expiry countdown), which cleared "Select" before the player could press Ctrl+C
    if self:GetText() ~= (v or "") then self.setting = true; self:SetText(v or ""); self.setting = false end
  end
  -- WoW can't put text on the clipboard for an addon: the player presses Ctrl+C (Cmd+C on a Mac).
  -- We only say "Ctrl+C pressed" after seeing that key in the box, never "copied" before.
  if eb:HasScript("OnKeyDown") then
    eb:SetScript("OnKeyDown", function(self, key)
      local mod = (IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())
      if key == "C" and mod and self.value and self.value ~= "" then
        self.copied = true
        if self.onCopy then self:onCopy() end
      end
    end)
  end
  --- Focus it and select everything, ready for Ctrl+C.
  function eb:SelectAll() self:Show(); self:SetFocus(); self:HighlightText() end
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
  st:SetSize(cw, 76); st:SetPoint("TOPLEFT", L, -92)
  st.chip = T.display(st, SZ.heading, C.label); st.chip:SetPoint("TOPLEFT", 12, -10)
  st.who = T.text(st, SZ.small, C.body); st.who:SetPoint("TOPRIGHT", -12, -12); st.who:SetJustifyH("RIGHT")
  st.line = T.text(st, SZ.label, C.label); st.line:SetPoint("TOPLEFT", 12, -38); st.line:SetWidth(cw - 24); st.line:SetJustifyH("LEFT"); st.line:SetWordWrap(false)
  st.trust = T.text(st, SZ.label, C.label); st.trust:SetPoint("TOPLEFT", 12, -54); st.trust:SetWidth(cw - 24); st.trust:SetJustifyH("LEFT"); st.trust:SetWordWrap(false)
  a.status = st

  a.steps = T.text(a, SZ.small, C.body); a.steps:SetPoint("TOPLEFT", L, -180); a.steps:SetWidth(cw); a.steps:SetJustifyH("LEFT")
  a.steps:SetSpacing(3)
  -- not linked: type the web code
  a.code = editBox(a, 160, "A7K9-P2XM", 12)
  a.code:SetPoint("TOPLEFT", L, -248)
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
  a.request = copyBox(a, cw - 106)
  a.request:SetPoint("TOPLEFT", L, -200)
  a.request.onCopy = function() UI.accountNote = "Ctrl+C pressed. Now paste it on the website, then come back for step 3."; UI.accountNoteGood = true; UI:RefreshAccount() end
  a.select = T.button(a, "Select", 100, 24, "steel", function()
    a.request:SelectAll()
    UI.accountNote = "Selected. Press Ctrl+C (Cmd+C on a Mac) to copy it."; UI.accountNoteGood = false
    UI:RefreshAccount()
  end)
  a.select:SetPoint("LEFT", a.request, "RIGHT", 6, 0)
  a.select.tip = "WoW can't copy for an addon: this selects the whole request so Ctrl+C copies all of it."
  a.step2 = T.text(a, SZ.small, C.body); a.step2:SetPoint("TOPLEFT", L, -234); a.step2:SetWidth(cw); a.step2:SetJustifyH("LEFT")
  -- pending / linked: paste a snapshot
  a.paste = editBox(a, cw - 106, "Paste the SRP1... snapshot here", ns.AccountCodes.MAX_CODE)
  local function doImport()
    local okI, res = Acc.import(a.paste:GetText())
    if okI then
      a.paste:SetText("")
      UI.accountNote = (res == "linked") and "Linked. Your stackrivals.io profile is on the Profile tab." or "Profile updated."
      UI.accountNoteGood = true
    else
      -- the paste is refused and nothing changes: the profile you had stays as it was
      UI.accountNote = "REJECTED: " .. (Acc.ERRORS[res] or ("can't import (" .. tostring(res) .. ")")); UI.accountNoteGood = false
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
    UI.accountNote = "Unlinked on this PC. To remove it from your account too: " .. Acc.WEB.unlink .. "."
    UI.accountNoteGood = true
    UI:RefreshAccount()
  end)
  a.unlink.tip = "Forgets the link and profile for this character on this PC. Your website account is not changed."
  a.expiry = T.text(a, SZ.label, C.label)
  a.note = T.text(a, SZ.small, C.gold); a.note:SetPoint("TOPLEFT", L, -334); a.note:SetWidth(cw - 150); a.note:SetJustifyH("LEFT")

  ------------------------------------------------------------------ Profile tab
  -- Top: name (left, cut with "..." when long) and rank (right, bounded). Then level and season
  -- bars, record + Shards (only when the website delivers a balance), achievements and cosmetics,
  -- up to 5 recent matches. Bottom strip, under a divider: when the website made this snapshot,
  -- that it was pasted by hand, and whether it is verified (no signature check exists yet).
  local p = T.panel(s, C.steel)
  local PH = 278
  p:SetSize(cw, PH); p:SetPoint("TOPLEFT", L, -92)
  p.fullHeight = PH
  s.prof = p
  local inner = cw - 28
  local RANKW = 150
  p.tips = {}
  --- One-line text, cut with "..." when too long; hovering shows the whole text in a tooltip.
  local function line(fs, w)
    fs:SetWidth(w); fs:SetWordWrap(false); fs:SetJustifyH("LEFT")
    local hover = CreateFrame("Frame", nil, p)
    hover:SetAllPoints(fs); hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(self)
      local t = fs:GetText()
      if not t or t == "" or not (fs.IsTruncated and fs:IsTruncated()) then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(t, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hover.fs = fs
    p.tips[#p.tips + 1] = hover
    return fs
  end
  p.empty = T.text(p, SZ.body, C.body); p.empty:SetPoint("TOPLEFT", 14, -16); p.empty:SetWidth(inner); p.empty:SetJustifyH("LEFT")
  p.empty:SetSpacing(3)
  p.name = line(T.display(p, SZ.title, C.paper), inner - RANKW - 12); p.name:SetPoint("TOPLEFT", 14, -12)
  p.rank = line(T.display(p, SZ.small, C.gold), RANKW); p.rank:SetPoint("TOPRIGHT", -14, -16); p.rank:SetJustifyH("RIGHT")
  local function bar(y, label)
    local l = T.text(p, SZ.label, C.label); l:SetPoint("TOPLEFT", 14, y); l:SetText(label)
    local v = line(T.text(p, SZ.label, C.body), inner - 70); v:SetPoint("TOPRIGHT", -14, y); v:SetJustifyH("RIGHT")
    local track = T.tex(p, "ARTWORK", C.line, 1); track:SetPoint("TOPLEFT", 14, y - 16); track:SetSize(inner, 4)
    local fill = T.tex(p, "OVERLAY", C.red, 1); fill:SetPoint("TOPLEFT", track, "TOPLEFT"); fill:SetSize(1, 4)
    return { l = l, v = v, track = track, fill = fill }
  end
  p.xp = bar(-42, "LEVEL")
  p.season = bar(-70, "SEASON")
  p.stats = line(T.text(p, SZ.small, C.body), inner); p.stats:SetPoint("TOPLEFT", 14, -98)
  p.statsWidth = inner
  p.SHARDSW = 160 -- "999,999,999,999 SHARDS" (12 digits) fits; longer is cut, with the full text on hover
  p.shards = line(T.display(p, SZ.small, C.gold), p.SHARDSW); p.shards:SetPoint("TOPRIGHT", -14, -98); p.shards:SetJustifyH("RIGHT")
  p.extra = line(T.text(p, SZ.label, C.label), inner); p.extra:SetPoint("TOPLEFT", 14, -116)
  p.histHead = T.label(p, "RECENT MATCHES (STACKRIVALS.IO)"); p.histHead:SetPoint("TOPLEFT", 14, -138)
  p.hist = {}
  for i = 1, 5 do
    local row = {}
    row.mode = line(T.text(p, SZ.small, C.body), 120); row.mode:SetPoint("TOPLEFT", 14, -154 - (i - 1) * 16)
    row.res = T.display(p, SZ.small, C.paper); row.res:SetPoint("TOPLEFT", 140, -154 - (i - 1) * 16)
    row.score = line(T.text(p, SZ.small, C.body), inner - 154 - 60); row.score:SetPoint("TOPLEFT", 168, -154 - (i - 1) * 16)
    row.at = T.text(p, SZ.label, C.label); row.at:SetPoint("TOPRIGHT", -14, -155 - (i - 1) * 16); row.at:SetJustifyH("RIGHT")
    p.hist[i] = row
  end
  p.divider = T.tex(p, "ARTWORK", C.line, 1); p.divider:SetPoint("BOTTOMLEFT", 14, 40); p.divider:SetSize(inner, 1)
  p.trust = line(T.display(p, SZ.label, C.gold), 90); p.trust:SetPoint("BOTTOMRIGHT", -14, 22); p.trust:SetJustifyH("RIGHT")
  p.updated = line(T.text(p, SZ.label, C.body), inner - 100); p.updated:SetPoint("BOTTOMLEFT", 14, 22)
  p.foot = line(T.text(p, SZ.label, C.label), inner); p.foot:SetPoint("BOTTOMLEFT", 14, 8)
  -- no profile yet: a compact panel with one clear next step (no big empty area)
  p.go = T.button(p, "Link account", 130, 26, "primary", function() UI.accountTab = "account"; UI:RefreshAccount() end)
  p.go:SetPoint("BOTTOMLEFT", 14, 12)
  p.go.tip = "Link this character to your stackrivals.io account with a one-time code."

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
    local shown = UI.accountDisplayState()
    local st = STATE[shown]
    a.status.chip:SetText(st[1]); a.status.chip:SetTextColor(st[2][1], st[2][2], st[2][3])
    a.status.who:SetText("This character: " .. (ns.Duel and ns.Duel.short(Acc.me() or "?") or (Acc.me() or "?")))
    local pr = r and r.profile
    local line, trust
    if shown == "verified" then
      line = "Account " .. safe(pr.name) .. "  -  last update " .. when(pr.issued) .. " (" .. ago(pr.issued) .. ")"
      trust = "The website's signature on this profile checked out."
    elseif shown == "linked" then
      line = "Account " .. safe(pr.name) .. "  -  last update " .. when(pr.issued) .. " (" .. ago(pr.issued) .. ")"
      trust = "Linked from a pasted snapshot. Not checked: no signatures yet."
    elseif shown == "not_synced" then
      line = "Account " .. safe(pr.name) .. "  -  last update " .. when(pr.issued) .. " (" .. ago(pr.issued) .. ")"
      trust = "Older than 7 days or expired: paste a new snapshot below."
    elseif shown == "pending" then
      line = "Waiting for confirmation from stackrivals.io. Not linked yet."
      trust = "Nothing is linked until you import the website's snapshot (step 3)."
    else
      line = (r and r.note == "unlinked") and "Unlinked on this PC." or "This character isn't linked to a stackrivals.io account."
      trust = "Everything works without an account, Loot Duel included."
    end
    a.status.line:SetText(line)
    a.status.trust:SetText(trust)
    local tc = (shown == "not_synced") and C.gold or C.label
    a.status.trust:SetTextColor(tc[1], tc[2], tc[3])
    local showCode, showReq, showPaste = state == "not_linked", state == "pending", state ~= "not_linked"
    a.code:SetShown(showCode); a.link:SetShown(showCode)
    a.request:SetShown(showReq); a.select:SetShown(showReq); a.step2:SetShown(showReq)
    a.paste:SetShown(showPaste); a.import:SetShown(showPaste)
    a.cancel:SetShown(showReq); a.unlink:SetShown(state == "linked" or state == "not_synced")
    a.expiry:SetShown(showReq)
    a.cancel:ClearAllPoints(); a.unlink:ClearAllPoints(); a.paste:ClearAllPoints(); a.expiry:ClearAllPoints()
    if state == "not_linked" then
      a.steps:SetText("Step 1 of 3. Log in on stackrivals.io (on the website, never in WoW).\n"
        .. "Open " .. Acc.WEB.link:gsub("^stackrivals%.io > ", "") .. ": it shows a one-time code.\nType that code here and click Link:")
    elseif state == "pending" then
      a.steps:SetText("Step 2 of 3. Select, Ctrl+C, then paste it on that website page:")
      a.request:SetValue(Acc.requestCode())
      a.step2:SetText("Step 3 of 3. Paste the snapshot the website then shows (SRP1...):")
      a.paste:SetPoint("TOPLEFT", 24, -254)
      a.cancel:SetPoint("TOPLEFT", 24, -290)
      a.expiry:SetPoint("LEFT", a.cancel, "RIGHT", 12, 0)
      local left = math.max(0, Acc.PENDING_TTL - (Acc.now() - r.pending.at))
      a.expiry:SetText(string.format("Code %s  -  this request expires in %d:%02d", ns.AccountCodes.prettyWebCode(r.pending.code), math.floor(left / 60), left % 60))
    else
      a.steps:SetText("Update: open " .. Acc.WEB.export .. ",\n"
        .. "copy the snapshot (SRP1...), paste it here and click Import.")
      a.paste:SetPoint("TOPLEFT", 24, -226)
      a.unlink:SetPoint("TOPLEFT", 24, -264)
      a.unlink:SetLabel(a.unlink.armed and "Click to confirm" or "Unlink")
    end
    a.note:SetText(self.accountNote or ((r and r.note == "pending_expired") and Acc.ERRORS.pending_expired) or "")
    local note = self.accountNote
    local nc = (self.accountNoteGood and note) and C.green or (note and note:find("^REJECTED") and C.redLight) or C.gold
    a.note:SetTextColor(nc[1], nc[2], nc[3])
  elseif tab == "profile" then
    self:RefreshProfile(s.prof, state, r)
  elseif tab == "sync" and self.RefreshSync then
    self:RefreshSync()
  end
end

--- The bottom strip of the Profile tab: { updated = line 1, foot = line 2, trust = tag, stale }.
--- Line 1 says when stackrivals.io made the snapshot; line 2 that it was pasted by hand (or that it
--- is out of date); the tag says whether a signature was checked (none can be yet).
function UI.profileSyncText(v)
  local updated = "Last update " .. when(v.asOf) .. "  -  " .. ago(v.asOf)
  local foot = v.stale and "OUT OF DATE: paste a new snapshot from stackrivals.io."
    or "Pasted by hand, so it may be out of date. Nothing unlocks in WoW."
  return { updated = updated, foot = foot, trust = v.verified and "VERIFIED" or "UNVERIFIED", stale = v.stale }
end
--- Kept for callers and tests that want the whole strip as one text.
function UI.profileFootText(v)
  local t = UI.profileSyncText(v)
  return t.updated .. ". " .. t.foot .. " " .. t.trust .. "."
end

function UI:RefreshProfile(p, state, r)
  local pr = r and r.profile and ns.Account.profileView() -- the view, never the raw format
  local has = pr ~= nil
  p.empty:SetShown(not has)
  p.go:SetShown(not has and state ~= "pending")
  p:SetHeight(has and p.fullHeight or 104)
  for _, k in ipairs({ "name", "rank", "stats", "shards", "extra", "histHead", "foot", "updated", "trust", "divider" }) do p[k]:SetShown(has) end
  for _, b in ipairs({ p.xp, p.season }) do for _, x in pairs(b) do x:SetShown(has) end end
  for _, row in ipairs(p.hist) do for _, x in pairs(row) do x:SetShown(has) end end
  if not has then
    for _, h in ipairs(p.tips) do h:Hide() end
    p.empty:SetText(state == "pending" and "Linking is not finished: import the confirmation snapshot from stackrivals.io on the Account tab."
      or "No profile yet. Link your stackrivals.io account on the Account tab: your name, rank, level, XP, season and match history will show here.")
    return
  end
  p.name:SetText(safe(pr.name))
  p.rank:SetText(pr.rank and string.upper(safe(pr.rank)) or "UNRANKED")
  local rc = pr.rank and C.gold or C.label
  p.rank:SetTextColor(rc[1], rc[2], rc[3])
  p.xp.v:SetText("Level " .. pr.level .. "  -  " .. (pr.xpNext > 0 and (T.commas(pr.xp) .. " / " .. T.commas(pr.xpNext) .. " XP") or (T.commas(pr.xp) .. " XP")))
  local w = p.xp.track:GetWidth()
  p.xp.fill:SetWidth(math.max(1, pr.xpNext > 0 and w * math.min(1, pr.xp / pr.xpNext) or 1))
  p.season.v:SetText((pr.season and safe(pr.season) or "No season") .. "  -  " .. pr.seasonPct .. "%")
  p.season.fill:SetWidth(math.max(1, w * pr.seasonPct / 100))
  local games = pr.wins + pr.losses + pr.draws
  p.stats:SetText(string.format("Wins %s  -  Losses %s  -  Draws %s%s", T.commas(pr.wins), T.commas(pr.losses), T.commas(pr.draws),
    games > 0 and string.format("  -  %d%% won", math.floor(100 * pr.wins / games + 0.5)) or ""))
  -- the website's balance, only when an approved format delivers one (SRP1 never does)
  p.shards:SetText(pr.shards and (T.commas(pr.shards) .. " SHARDS") or "")
  p.stats:SetWidth(pr.shards and (p.statsWidth - p.SHARDSW - 6) or p.statsWidth) -- the record gets the whole line without Shards
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
  p.histHead:SetText(#pr.history > #p.hist and ("RECENT MATCHES (" .. #p.hist .. " OF " .. #pr.history .. ", MORE ON STACKRIVALS.IO)") or "RECENT MATCHES (STACKRIVALS.IO)")
  -- a tooltip only where there is text to show (and none over the "Link account" button)
  for _, h in ipairs(p.tips) do h:SetShown(h.fs:IsShown()) end
  local t = UI.profileSyncText(pr)
  p.updated:SetText(t.updated)
  p.foot:SetText(t.foot)
  p.trust:SetText(t.trust)
  local uc = t.stale and C.gold or C.body
  p.updated:SetTextColor(uc[1], uc[2], uc[3])
  local fc = t.stale and C.gold or C.label
  p.foot:SetTextColor(fc[1], fc[2], fc[3])
  local tc = pr.verified and C.green or C.gold
  p.trust:SetTextColor(tc[1], tc[2], tc[3])
end
