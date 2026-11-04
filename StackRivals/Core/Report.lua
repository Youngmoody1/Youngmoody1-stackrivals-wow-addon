--[[
  StackRivals - compatibility diagnostics a player can send us (/sr report, /sr commtest).

  /sr report
    One line of plain text (SRDIAG1;key=value;...) in a copy box: click it, Ctrl+C, paste it into a
    bug report (CurseForge comments, GitHub issue, Discord). It says which client this is and what
    it can do, so a problem on a client we don't run ourselves can be fixed from the report.
    What's in it: addon / engine version, client type, project ID, interface, build, Hardcore /
    Season of Discovery / trial flags, which APIs exist, WoW's addon chat lockdown right now (and
    why), instance type, group size and channel, loot method (read only), message counters and send
    result codes, the last /sr commtest, saved-data health, and errors StackRivals caught itself.
    NOT in it: no character, realm, guild or friend names, no chat, no account data. It is only
    text on your screen: nothing is sent anywhere unless you paste it somewhere yourself.
    tools/diag_report.py turns it into a readable table.

  /sr commtest  (in a party or raid)
    Proves addon messages really ARRIVE here, not just that the send call returned OK: one test
    ping (CTP) on PARTY / RAID / INSTANCE_CHAT; every StackRivals in the group answers on the same
    channel (CTA). The chat line lists who answered and how fast. Use it in the open world, in a
    dungeon between pulls and during a boss fight (docs/FOREVER.md F1-F5). Once per 15 s; each PC
    answers each ping once.
]]
local _, ns = ...
ns = ns or {}

local R = { GAP = 15, WAIT = 6 }
ns.Report = R

local function now() return GetTime and GetTime() or 0 end
local function P() return ns.Protocol end
local function b(v) return v and "1" or "0" end
local function clean(s) return (tostring(s or ""):gsub("[;=|\r\n]", " ")) end

--- Errors StackRivals itself caught (pcall'd code paths report here): the last 5, short.
R.errors = {}
function R.noteError(where, err)
  local e = R.errors
  e[#e + 1] = clean(where) .. ": " .. clean(err):sub(1, 90)
  while #e > 5 do table.remove(e, 1) end
end

--- The report text (one line). `extra` adds key/value pairs (tests).
function R.text(extra)
  local C = ns.Client and ns.Client.get() or {}
  local f = ns.Client and ns.Client.features() or {}
  local comm = ns.Comm or {}
  local st = comm.stats or {}
  local codes = {}
  for code, n in pairs(st.codes or {}) do codes[#codes + 1] = code .. "x" .. n end
  table.sort(codes)
  local locked = ns.Client and ns.Client.messagingLocked() or false
  local why = ns.Client and ns.Client.lockdownReason() or nil
  local ch = ns.LootDuel and ns.LootDuel.channel and ns.LootDuel.channel() or nil
  local size = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local db = ns.db or {}
  local rec = db.records or {}
  local ct = R.last
  local parts = {
    "SRDIAG1",
    "v=" .. clean(ns.VERSION), "engine=" .. clean(ns.Engine and ns.Engine.ENGINE_VERSION),
    "build=" .. clean(ns.BUILD and ns.BUILD.flavour or "full"),
    "client=" .. clean(C.key), "project=" .. clean(C.project), "iface=" .. clean(C.interface), "wow=" .. clean(C.version) .. "." .. clean(C.build),
    "byIface=" .. b(C.byInterface), "hc=" .. b(C.hardcore), "sod=" .. b(C.sod), "trial=" .. b(C.trial),
    "api=am" .. b(f.addonMessages) .. ",bn" .. b(f.bnetGameData) .. ",lk" .. b(f.chatLockdownApi) .. ",ra" .. b(f.restrictionApi)
      .. ",lm" .. b(f.lootMethodApi) .. ",sv" .. b(f.secretValues) .. ",cp" .. b(f.compartment) .. ",ii" .. b(f.itemInfo),
    "locked=" .. b(locked), "why=" .. clean(why or "-"),
    "inst=" .. clean(ns.Client and ns.Client.instanceType() or "none"),
    "group=" .. clean(ch or "none") .. ":" .. size,
    "loot=" .. clean(ns.Client and ns.Client.lootMethod() or "-"),
    "comm=en" .. b(comm.enabled) .. ",un" .. b(comm.unavailable) .. ",reg" .. clean(comm.registerResult) .. ",s" .. (st.sent or 0)
      .. ",r" .. (st.received or 0) .. ",d" .. (st.dropped or 0) .. ",x" .. (st.rejected or 0) .. ",lk" .. (st.lockdowns or 0)
      .. ",q" .. (comm.queue and #comm.queue or 0) .. ",max" .. (st.maxQueue or 0),
    "codes=" .. (#codes > 0 and table.concat(codes, ",") or "-"),
    "ct=" .. (ct and (clean(ct.channel) .. ",code" .. clean(ct.code) .. ",ans" .. ct.answers .. "/" .. ct.size .. ",ms" .. ct.ms .. ",lk" .. b(ct.locked) .. ",in" .. clean(ct.inst)) or "-"),
    "db=classic" .. ((rec.classic and rec.classic.games) or 0) .. ",loads" .. ((db.diag and db.diag.loads) or 0),
    "err=" .. (#R.errors > 0 and table.concat(R.errors, " / ") or "-"),
    "utc=" .. (date and date("!%Y-%m-%d %H:%M") or "?"),
  }
  for k, v in pairs(extra or {}) do parts[#parts + 1] = clean(k) .. "=" .. clean(v) end
  return table.concat(parts, ";")
end

------------------------------------------------------------------------------------------------
-- /sr commtest: a ping on the group channel; every StackRivals in the group answers once
------------------------------------------------------------------------------------------------
function R.commTest()
  local ch = ns.LootDuel and ns.LootDuel.channel and ns.LootDuel.channel()
  if not ch then return false, "not_in_group" end
  if not (ns.Comm and ns.Comm.enabled) then return false, "unavailable" end
  local t = now()
  if R.cur and t - R.cur.at < R.GAP then return false, "cooldown" end
  local id = P().token(6, math.random)
  local size = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  R.cur = { id = id, at = t, channel = ch, size = math.max(0, size - 1), answers = 0, names = {}, ms = 0,
    locked = ns.Client and ns.Client.messagingLocked() or false, inst = ns.Client and ns.Client.instanceType() or "none" }
  -- straight to the API once (the result code is part of the answer), then nothing else
  local api = C_ChatInfo
  local code = api and api.SendAddonMessage and ns.Comm.result(pcall(api.SendAddonMessage, P().PREFIX, P().encode("CTP", id), ch)) or 9
  R.cur.code = code
  R.last = R.cur
  return true, code
end

--- Answers seen so far; the summary is printed when the wait is over (R.update).
function R.update(t)
  local c = R.cur
  if c and not c.printed and t - c.at >= R.WAIT then
    c.printed = true
    if ns.App then
      local who = #c.names > 0 and (": " .. table.concat(c.names, ", ")) or ""
      ns.App:Print(string.format("comm test on %s: send result %s, %d of %d group members' StackRivals answered%s%s",
        c.channel, tostring(c.code), c.answers, c.size, who, c.locked and " (WoW reported addon chat lockdown)" or ""))
    end
  end
end

local answered = {}
local function onPing(m, sender, channel)
  if answered[m.id] then return end
  answered[m.id] = true
  local ch = ns.LootDuel and ns.LootDuel.channel and ns.LootDuel.channel()
  if ch and ns.Comm then ns.Comm.send(P().encode("CTA", m.id, ns.VERSION or "?"), ch, nil, nil, { key = "CTA:" .. m.id }) end
end
local function onAnswer(m, sender)
  local c = R.cur
  if not (c and c.id == m.id) then return end
  for _, n in ipairs(c.names) do if n == sender then return end end
  c.answers = c.answers + 1
  c.names[#c.names + 1] = (sender or "?"):match("^[^-]+") .. " " .. tostring(m.version)
  c.ms = math.floor((now() - c.at) * 1000)
end

function R.init()
  if ns.Comm and ns.Comm.on then
    ns.Comm.on("CTP", onPing)
    ns.Comm.on("CTA", onAnswer)
  end
end

------------------------------------------------------------------------------------------------
-- The report window (/sr report): a copy box, built the first time it is needed
------------------------------------------------------------------------------------------------
local UI = ns.UI or {}
ns.UI = UI
function UI:ShowReport()
  local T = ns.T
  if not (T and CreateFrame and UIParent) then return end
  local w = self.reportFrame
  if not w then
    w = T.panel(UIParent, T.C.red)
    w:SetSize(560, 170)
    w:SetPoint("CENTER", 0, 120)
    w:SetFrameStrata("DIALOG")
    w:EnableMouse(true)
    local title = T.display(w, T.SIZE.title, T.C.gold); title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("STACKRIVALS REPORT")
    local sub = T.text(w, T.SIZE.label, T.C.label); sub:SetPoint("TOPLEFT", 16, -40); sub:SetWidth(528); sub:SetJustifyH("LEFT")
    sub:SetText("Click the box, press Ctrl+C, and paste it into your bug report. It has no character, realm or chat data, and nothing is sent anywhere.")
    w.box = UI.accountCopyBox(w, 528, 4000)
    w.box:SetPoint("TOPLEFT", 16, -80)
    w.close = T.button(w, "Close", 110, 26, "frame", function() w:Hide() end)
    w.close:SetPoint("BOTTOMRIGHT", -16, 14)
    w.refresh = T.button(w, "Refresh", 110, 26, "frame", function() w.box:SetValue(R.text()) end)
    w.refresh:SetPoint("RIGHT", w.close, "LEFT", -8, 0)
    local hint = T.text(w, T.SIZE.label, T.C.label); hint:SetPoint("BOTTOMLEFT", 16, 20)
    hint:SetText("/sr commtest first, in a group, adds a delivery check.")
    self.reportFrame = w
    StackRivalsReport = w -- the one global name Esc needs (UISpecialFrames lists frames by name)
    if UISpecialFrames then tinsert(UISpecialFrames, "StackRivalsReport") end
  end
  w.box:SetValue(R.text())
  w:Show()
  w.box:SetFocus()
  w.box:HighlightText()
end
