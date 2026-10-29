--[[
  StackRivals - addon bootstrap: SavedVariables, events, slash commands, run lifecycle.
]]
local ADDON, ns = ...
local DB, Session, E = ns.DB, ns.Session, ns.Engine

local function meta(field)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if get then
    local ok, v = pcall(get, ADDON, field)
    if ok then return v end
  end
  return nil
end
ns.VERSION = meta("Version") or "dev"

local App = { session = nil, inMenu = true, lastMode = "classic" }
ns.App = App

local PREFIX = "|cffff4d5aStack|r|cfff6f4f0Rivals|r: "
function App:Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

function App:Today() return date("!%Y-%m-%d") end

function App:BestFor(mode)
  local db = ns.db
  if not db then return 0 end
  if mode == "daily" then
    local d = db.records.dailyToday
    return (d.date == self:Today()) and d.best or 0
  end
  local r = db.records[mode]
  return r and r.best or 0
end

local function newSeed()
  return string.format("%06x%06x%04x", math.random(0, 0xffffff), math.random(0, 0xffffff), math.floor((GetTime() * 1000) % 0xffff))
end

--- Start a fresh run in `mode` (classic | blitz | daily).
function App:Start(mode)
  if ns.UI.inCombat() then self:Print("Can't start a run in combat."); return end
  ns.UI:Create()
  local seed = (mode == "daily") and Session.dailySeed(self:Today()) or newSeed()
  self.session = Session.new(mode, seed)
  self.lastMode = mode
  self.inMenu = false
  ns.db.suspended = nil
  if not ns.UI.frame:IsShown() then ns.UI.frame:Show() end
  ns.UI:RefreshPhase()
end

function App:ContinueSuspended()
  local su = ns.db.suspended
  if not su then return end
  local sess = Session.restore(su.mode, su.log, su.playSeconds)
  ns.db.suspended = nil
  if not sess then self:Print("That saved run could not be restored."); ns.UI:RefreshMenu(); return end
  self.session = sess
  self.lastMode = su.mode
  self.inMenu = false
  ns.UI:RefreshPhase()
end

function App:ShowMenu()
  self.inMenu = true
  if self.session and self.session:isActive() then self.session:pause("manual") end
  if ns.UI.frame then ns.UI:RefreshMenu(); ns.UI:RefreshPhase() end
end

function App:Quit()
  self.session = nil
  self:ShowMenu()
end

function App:Pause(reason)
  local s = self.session
  if s and s:pause(reason) and ns.UI.frame then ns.UI:RefreshPhase() end
end

function App:Resume()
  local s = self.session
  if not s then return end
  if ns.UI.inCombat() then self:Print("Finish the fight first."); return end
  if ns.UI.settings and ns.UI.settings:IsShown() then ns.UI:ShowSettings(false) end
  if s:resume() then ns.UI:RefreshPhase() end
end

--- Called once when a run ends (top-out or time up).
function App:OnRunOver(reason)
  local s = self.session
  if not s or s.recorded then return end
  s.recorded = true
  local mode = s.mode.key
  local res = DB.recordRun(ns.db, mode, s.state, s.playSeconds, self:Today(), E.serializeLog(s.state))
  if res.newBest then ns.Sound.play("record") else ns.Sound.play("gameover") end
  ns.UI:ShowOver({
    state = s.state, reason = reason, mode = mode, modeName = s.mode.name,
    newBest = res.newBest, prevBest = res.prevBest, newTodayBest = res.newTodayBest,
  })
  ns.UI:RefreshMenu()
end

--- Post the last result to guild or group chat (only when the player clicks the button).
function App:Share(where)
  local s = self.session
  if not s or s.phase ~= "over" then return end
  if ns.UI.inCombat() then return end
  local channel = where
  if where == "GROUP" then
    if IsInRaid and IsInRaid() then channel = "RAID" elseif IsInGroup and IsInGroup() then channel = "PARTY" else return end
  elseif not (IsInGuild and IsInGuild()) then return end
  local st = s.state
  local extra = (s.mode.key == "daily") and (" (Daily " .. self:Today() .. ")") or ""
  local msg = string.format("[StackRivals] %s points, %d lines in %s%s. Can you beat it?",
    ns.T.commas(st.score), st.lines, s.mode.name, extra)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local ok = pcall(send, msg, channel)
  if not ok then self:Print("Couldn't post to chat here.") end
end

------------------------------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------------------------------
local function slash(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, arg = msg:match("^(%S*)%s*(.*)$")
  if cmd == "" or cmd == "toggle" then
    ns.UI:Toggle()
  elseif cmd == "classic" or cmd == "blitz" or cmd == "daily" then
    App:Start(cmd)
  elseif cmd == "pause" then
    App:Pause("manual")
  elseif cmd == "settings" or cmd == "options" or cmd == "config" then
    ns.UI:Create(); ns.UI.frame:Show(); ns.UI:ShowSettings(true)
  elseif cmd == "minimap" then
    ns.db.settings.minimapHide = not ns.db.settings.minimapHide
    ns.Minimap:Update()
    App:Print("Minimap button " .. (ns.db.settings.minimapHide and "hidden" or "shown") .. ".")
  elseif cmd == "scale" and tonumber(arg) then
    ns.UI:Create(); ns.UI:SetScale(tonumber(arg))
    App:Print(string.format("Window size %d%%.", ns.db.settings.scale * 100))
  elseif cmd == "reset" then
    ns.UI:Create(); ns.UI:ResetPosition(); ns.UI:SetScale(1)
    App:Print("Window position and size reset.")
  elseif cmd == "sound" then
    ns.db.settings.sound = not ns.db.settings.sound
    ns.Sound.enabled = ns.db.settings.sound
    App:Print("Sound " .. (ns.db.settings.sound and "on" or "off") .. ".")
  elseif cmd == "stats" then
    for _, k in ipairs(Session.MODE_ORDER) do
      local r = ns.db.records[k]
      App:Print(string.format("%s: best %s, %d runs, %d lines, %d quads", Session.MODES[k].name,
        ns.T.commas(r.best), r.games, r.totalLines, r.quads))
    end
  elseif cmd == "version" then
    App:Print("version " .. ns.VERSION .. ", engine v" .. E.ENGINE_VERSION .. ", interface " .. tostring(select(4, GetBuildInfo())))
  else
    App:Print("commands: /sr (open), /sr blitz | classic | daily, /sr pause, /sr settings, /sr minimap, /sr scale 0.8, /sr reset, /sr sound, /sr stats, /sr version")
  end
end

SLASH_STACKRIVALS1 = "/sr"
SLASH_STACKRIVALS2 = "/stackrivals"
SlashCmdList.STACKRIVALS = slash

-- Addon compartment (the addon menu next to the minimap in modern clients). Named in the TOC.
function StackRivals_OnAddonCompartmentClick() ns.UI:Toggle() end

------------------------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function reg(name) pcall(ev.RegisterEvent, ev, name) end -- unknown events must not error

reg("ADDON_LOADED")
reg("PLAYER_LOGIN")
reg("PLAYER_LOGOUT")
reg("PLAYER_REGEN_DISABLED")
reg("PLAYER_REGEN_ENABLED")
reg("LOADING_SCREEN_ENABLED")
reg("PLAYER_LEAVING_WORLD")
reg("PLAYER_DEAD")

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    ns.db = DB.sanitize(StackRivalsDB)
    StackRivalsDB = ns.db
    ns.Sound.enabled = ns.db.settings.sound
    local su = ns.db.suspended
    if su and su.mode == "daily" and su.date and su.date ~= App:Today() then ns.db.suspended = nil end
  elseif event == "PLAYER_LOGIN" then
    ns.Minimap:Create()
    if not ns.db.seenIntro then
      ns.db.seenIntro = true
      App:Print("loaded. Type |cffff4d5a/sr|r or click the minimap button to play.")
    end
  elseif event == "PLAYER_LOGOUT" then
    -- keep an unfinished run so /reload or logout never loses it
    local s = App.session
    if s then
      local data = s:suspendData()
      if data then data.date = App:Today(); ns.db.suspended = data end
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- Fires before combat lockdown starts: pause and hand every key back to WoW now.
    local s = App.session
    if s and s:isActive() then App:Pause("combat") end
    if ns.UI.binding then ns.UI:EndBind() end
    if ns.UI.keys then ns.UI:SetKeyboard(false) end
    local F = ns.UI.frame
    if F and F:IsShown() and ns.db.settings.hideInCombat then
      App.reopenAfterCombat = true
      F:Hide()
    end
    if ns.UI.frame then ns.UI:RefreshMenu() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if App.reopenAfterCombat then
      App.reopenAfterCombat = false
      if ns.UI.frame then ns.UI.frame:Show() end
    end
    if ns.UI.frame then ns.UI:RefreshMenu(); ns.UI:RefreshPhase() end
  elseif event == "LOADING_SCREEN_ENABLED" or event == "PLAYER_LEAVING_WORLD" then
    App:Pause("loading")
  elseif event == "PLAYER_DEAD" then
    App:Pause("manual")
  end
end)
