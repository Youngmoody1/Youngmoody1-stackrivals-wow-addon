--[[
  StackRivals - match chat panel: a compact panel on the right edge of the StackRivals window while
  you are in a duel (lobby, match, result). Text + Send, quick messages (GL, GG, WP, Rematch?),
  Mute, chat on/off, and a close button that folds it into a small "Chat" tab.
  The panel only shows what Core/Chat.lua allows: free text between the same faction when both
  have chat on, quick messages otherwise, nothing when off. Nothing is ever posted to a WoW channel.
]]
local _, ns = ...
local T = ns.T
local C = T.C
local UI = ns.UI
local SZ = T.SIZE

local PW, PH = 196, 352
local SLOTS, STEP = 12, 15
local WRAP = 30 -- characters per visual line at this width (estimate; long words are cut)

--- Split a line into visual lines of at most `n` characters (by words).
local function wrap(text, n)
  local out, cur = {}, ""
  for word in text:gmatch("%S+") do
    while #word > n do
      if cur ~= "" then out[#out + 1] = cur; cur = "" end
      local cut = n
      while cut > 1 and (word:byte(cut + 1) or 0) >= 128 and (word:byte(cut + 1) or 0) < 192 do cut = cut - 1 end -- not inside a UTF-8 character
      out[#out + 1] = word:sub(1, cut); word = word:sub(cut + 1)
    end
    if cur == "" then cur = word
    elseif #cur + 1 + #word <= n then cur = cur .. " " .. word
    else out[#out + 1] = cur; cur = word end
  end
  if cur ~= "" then out[#out + 1] = cur end
  return out
end
UI.chatWrap = wrap

local function short(n) return ns.Duel.short(n) or "?" end

--- The match the chat belongs to (lobby, playing, waiting, result).
local function chatMatch()
  local m = ns.Duel and ns.Duel.current
  if m and m.state ~= "invited" and m.state ~= "inviting" then return m end
end
UI.chatMatch = chatMatch

local function sendText(p)
  local m = chatMatch()
  local text = p.input:GetText()
  local okS, why = ns.Chat.send(m, text)
  if okS then p.input:SetText(""); UI.chatNote = nil else UI.chatNote = why end
  UI:RefreshChat()
end

function UI:CreateMatchChat()
  local F = self.frame
  local p = T.panel(F, C.steel)
  p._layoutRoot = true -- sits outside the window: checked as its own screen (tests/layout.lua)
  p:SetSize(PW, PH)
  p:SetPoint("TOPLEFT", F, "TOPRIGHT", 6, 0)
  p:SetFrameLevel(F:GetFrameLevel() + 50)
  p:EnableMouse(true)
  local cw = PW - 20
  p.title = T.label(p, "MATCH CHAT"); p.title:SetPoint("TOPLEFT", 10, -10); p.title:SetWidth(cw - 26); p.title:SetJustifyH("LEFT")
  p.close = T.button(p, "x", 20, 20, "frame", function()
    local m = chatMatch()
    if m then m.chatFolded = true; m.chatSeen = #(m.chat or {}) end
    UI:RefreshChat()
  end)
  p.close:SetPoint("TOPRIGHT", -6, -6)
  p.close.tip = "Fold the chat into a small tab (it keeps working)."
  p.status = T.text(p, SZ.label, C.label); p.status:SetPoint("TOPLEFT", 10, -30); p.status:SetWidth(cw); p.status:SetJustifyH("LEFT")
  p.lines = {}
  for i = 1, SLOTS do
    local fs = T.text(p, SZ.small, C.body); fs:SetPoint("TOPLEFT", 10, -60 - (i - 1) * STEP); fs:SetWidth(cw); fs:SetJustifyH("LEFT")
    p.lines[i] = fs
  end
  -- quick messages: always allowed when chat is on (also across factions)
  p.quick = {}
  local qw = { 32, 32, 32, 68 }
  local ql = { "GL", "GG", "WP", "Rematch?" }
  local x = 10
  for i = 1, 4 do
    local b = T.button(p, ql[i], qw[i], 22, "frame", function()
      local okQ, why = ns.Chat.quick(chatMatch(), i)
      UI.chatNote = (not okQ) and why or nil
      UI:RefreshChat()
    end)
    b:SetPoint("TOPLEFT", x, -246)
    b.tip = ns.Protocol.QUICK[i]
    x = x + qw[i] + 4
    p.quick[i] = b
  end
  -- text input + Send
  local eb = CreateFrame("EditBox", nil, p)
  eb:SetSize(cw - 56, 24); eb:SetPoint("TOPLEFT", 10, -274)
  eb:SetAutoFocus(false); eb:SetMaxLetters(ns.Protocol.CHAT_MAX)
  eb:SetFont(T.FONT, SZ.small, ""); eb:SetTextInsets(6, 6, 0, 0)
  local ebg = T.tex(eb, "BACKGROUND", C.ink, 1); ebg:SetAllPoints()
  local ebo = T.tex(eb, "BORDER", C.line, 1); ebo:SetPoint("BOTTOMLEFT"); ebo:SetPoint("BOTTOMRIGHT"); ebo:SetHeight(1)
  eb.hint = T.text(eb, SZ.label, C.label); eb.hint:SetPoint("LEFT", 6, 0); eb.hint:SetText("Type a message...")
  eb:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
  eb:SetScript("OnEnterPressed", function(self) sendText(p); self:ClearFocus() end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  p.input = eb
  p.send = T.button(p, "Send", 52, 24, "steel", function() sendText(p) end)
  p.send:SetPoint("LEFT", eb, "RIGHT", 4, 0)
  -- mute this rival / match chat on-off (remembered)
  p.mute = T.button(p, "Mute", 84, 22, "frame", function()
    local m = chatMatch()
    if m then ns.Chat.mute(m, not ns.Chat.muted(m.rival)) end
    UI:RefreshChat()
  end)
  p.mute:SetPoint("TOPLEFT", 10, -306)
  p.mute.tip = "Stop seeing this player's messages (remembered). They are not told."
  p.onoff = T.button(p, "Chat: on", 88, 22, "frame", function()
    local d = ns.db.chat
    d.enabled = not d.enabled
    local m = chatMatch()
    if m and ns.Card then ns.Card.send(m) end -- tell the rival (their card shows chat on/off)
    UI:RefreshChat()
  end)
  p.onoff:SetPoint("LEFT", p.mute, "RIGHT", 4, 0)
  p.onoff.tip = "Match chat for every duel (remembered). Off: you neither send nor see messages."
  p.note = T.text(p, SZ.label, C.gold); p.note:SetPoint("TOPLEFT", 10, -334); p.note:SetWidth(cw); p.note:SetJustifyH("LEFT")
  p:Hide()
  self.chat = p

  -- folded: a small tab with the number of unread lines
  local tab = T.button(F, "Chat", 64, 24, "steel", function()
    local m = chatMatch()
    if m then m.chatFolded = false end
    UI:RefreshChat()
  end)
  tab._layoutRoot = true
  tab:SetPoint("TOPLEFT", F, "TOPRIGHT", 6, 0)
  tab:SetFrameLevel(F:GetFrameLevel() + 50)
  tab:Hide()
  self.chatTab = tab
end

local LINE_COLOR = { me = C.paper, them = C.body, quick = C.gold, sys = C.label }

function UI:RefreshChat()
  local p = self.chat
  if not p then return end
  local m = chatMatch()
  if not m or (ns.BUILD and not ns.BUILD.duels) then p:Hide(); self.chatTab:Hide(); return end
  local Chat = ns.Chat
  local lines = m.chat or {}
  if m.chatFolded then
    p:Hide()
    local unread = #lines - (m.chatSeen or 0)
    self.chatTab:SetLabel(unread > 0 and ("Chat (" .. unread .. ")") or "Chat")
    self.chatTab:Show()
    return
  end
  self.chatTab:Hide()
  p:Show()
  m.chatSeen = #lines
  local mode, why = Chat.mode(m)
  local muted = Chat.muted(m.rival)
  p.title:SetText("MATCH CHAT  -  " .. string.upper(short(m.rival)))
  local status
  if mode == "free" then status = "Only you two see this. Never posted to WoW chat."
  elseif mode == "quick" then
    local rc = m.rivalCard
    status = (rc and rc.faction and rc.faction ~= (ns.Card.mine().faction or "")) and "Different factions: quick messages only." or ("Quick messages only: " .. (why or ""))
  else status = "Chat is off: " .. (why or "") .. "." end
  if muted then status = "You muted " .. short(m.rival) .. ". " .. status end
  p.status:SetText(status)
  -- newest at the bottom; long lines wrap onto more slots
  local vis = {}
  if #lines == 0 then vis[1] = { "No messages yet.", "sys" } end
  -- the rival's name in WoW's class colour (from their card; steel when unknown)
  local rc = m.rivalCard
  local rivalTag = rc and rc.class and T.classText(rc.class, short(m.rival)) or ("|cff4fa8ff" .. short(m.rival) .. "|r")
  for _, l in ipairs(lines) do
    local who = l.me and "You" or short(m.rival)
    local kind = l.quick and "quick" or (l.me and "me" or "them")
    -- wrap the plain text, THEN escape each piece: a cut can never split an escaped "||"
    local raw = who .. ": " .. (l.text:gsub("||", "|"))
    for i, part in ipairs(wrap(raw, WRAP)) do
      part = part:gsub("|", "||")
      if i == 1 and not l.me then part = rivalTag .. part:sub(#who + 1) end
      vis[#vis + 1] = { i == 1 and part or ("  " .. part), kind }
    end
  end
  local first = math.max(1, #vis - SLOTS + 1)
  for i, fs in ipairs(p.lines) do
    local v = vis[first + i - 1]
    if v then
      fs:SetText(v[1])
      local c = LINE_COLOR[v[2]]
      fs:SetTextColor(c[1], c[2], c[3])
      fs:Show()
    else
      fs:SetText(""); fs:Hide()
    end
  end
  local canQuick, canText = mode ~= "off", mode == "free"
  for _, b in ipairs(p.quick) do if canQuick then b:Enable() else b:Disable() end end
  if canText then p.send:Enable(); p.input:Show() else p.send:Disable(); p.input:Hide(); p.input:ClearFocus() end
  p.mute:SetLabel(muted and "Unmute" or "Mute")
  p.onoff:SetLabel(ns.db.chat.enabled == false and "Chat: off" or "Chat: on")
  p.note:SetText(self.chatNote and ("Not sent: " .. self.chatNote .. ".") or "")
end
